#!/usr/bin/env python3
"""
Loot Lagoon -- backend load and stress test.

Runs the REAL migrations against a throwaway local Postgres, then drives the
same RPCs the game calls, from many concurrent connections, as the roles and
under the RLS policies a real client has.

Why local rather than against the live project: this hammers the part we own
and can fix -- the schema, the indexes and the query plans. Running the same
thing at the live project would create tens of thousands of real rows in the
players table, burn the free tier's quota, and measure Supabase's shared
PostgREST pool rather than the game's own SQL. What it does NOT cover is
GoTrue, PostgREST and the network in front of them; those are Supabase's to
scale and are noted as such in the report.

Phases:
  A  signup storm      -- launch day: N clients calling claim_player at once
  B  steady state      -- the real RPC mix, at rising concurrency
  C  contention        -- races the schema is supposed to settle
  D  scale             -- the same reads against a table with many islands

Usage: tools/loadtest_db.py [--players N] [--seconds S] [--levels 1,8,32,...]
"""

import argparse
import json
import os
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

import psycopg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PG = os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")

STUB = """
create role anon           nologin;
create role authenticated  nologin;
create role service_role   nologin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
create table auth.identities (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    provider text not null
);
create or replace function auth.uid() returns uuid
language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
"""


class Pg:
    """A throwaway Postgres that cleans itself up."""

    def __init__(self):
        self.work = tempfile.mkdtemp(prefix="lootlagoon-load-")
        self.data = os.path.join(self.work, "data")

    def start(self):
        run([os.path.join(PG, "initdb"), "-D", self.data, "-U", "postgres",
             "--auth=trust"])
        # Tuned like a small managed instance rather than a laptop default, so
        # the numbers mean something: Supabase's free tier is 60 connections
        # and shared buffers in the same order.
        run([os.path.join(PG, "pg_ctl"), "-D", self.data,
             "-o", f"-k {self.work} -c listen_addresses='' "
                   f"-c max_connections=200 -c shared_buffers=256MB "
                   f"-c work_mem=8MB -c track_io_timing=on "
                   f"-c log_min_duration_statement=2000",
             "-l", os.path.join(self.work, "log"), "-w", "start"])

    def stop(self):
        subprocess.run([os.path.join(PG, "pg_ctl"), "-D", self.data, "-s",
                        "-m", "immediate", "stop"],
                       capture_output=True)
        shutil.rmtree(self.work, ignore_errors=True)

    def dsn(self):
        return f"host={self.work} user=postgres dbname=postgres"


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"command failed: {' '.join(cmd)}\n{p.stdout}\n{p.stderr}")
    return p.stdout


def apply_schema(dsn):
    with psycopg.connect(dsn, autocommit=True) as c:
        c.execute(STUB)
    files = sorted(os.listdir(os.path.join(ROOT, "supabase", "migrations")))
    for f in files:
        path = os.path.join(ROOT, "supabase", "migrations", f)
        p = subprocess.run(
            [os.path.join(PG, "psql"), "-v", "ON_ERROR_STOP=1", "-q",
             "--no-psqlrc", "-f", path],
            capture_output=True, text=True,
            env={**os.environ, "PGHOST": dsn.split("host=")[1].split()[0],
                 "PGUSER": "postgres", "PGDATABASE": "postgres"})
        if p.returncode != 0:
            sys.exit(f"migration {f} failed:\n{p.stderr}")
    print(f"   {len(files)} migrations applied")


# --- one virtual player ------------------------------------------------------

SAVE = json.dumps({"coins": 123456, "spins": 30, "buildings": [3, 3, 3, 3, 3],
                   "island_level": 4, "rank_stars": 120,
                   "filler": "x" * 1200})   # a real save is a few KB


class Client:
    """One signed-in device, on its own connection, as `authenticated`."""

    def __init__(self, dsn, uid):
        self.uid = uid
        self.conn = psycopg.connect(dsn, autocommit=True)
        with self.conn.cursor() as cur:
            cur.execute("select set_config('request.jwt.claim.sub', %s, false)",
                        (str(uid),))
            cur.execute("set role authenticated")

    def call(self, sql, args=()):
        with self.conn.cursor() as cur:
            cur.execute(sql, args)
            try:
                return cur.fetchone()
            except psycopg.ProgrammingError:
                return None

    def close(self):
        try:
            self.conn.close()
        except Exception:
            pass


def make_auth_users(dsn, n):
    """Auth rows only -- the islands are created by claim_player under load."""
    uids = [uuid.uuid4() for _ in range(n)]
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.executemany("insert into auth.users (id, email) values (%s, %s)",
                        [(u, f"{u}@example.test") for u in uids])
        cur.executemany(
            "insert into auth.identities (user_id, provider) values (%s, 'apple')",
            [(u,) for u in uids])
    return uids


# --- measurement -------------------------------------------------------------

class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.lat = defaultdict(list)
        self.err = defaultdict(int)
        self.errmsg = defaultdict(str)

    def record(self, op, secs):
        with self.lock:
            self.lat[op].append(secs * 1000.0)

    def fail(self, op, msg):
        with self.lock:
            self.err[op] += 1
            if not self.errmsg[op]:
                self.errmsg[op] = str(msg)[:200]

    def report(self, title, elapsed):
        print(f"\n   {title}")
        print(f"   {'op':<22}{'n':>8}{'ok/s':>9}{'p50':>9}{'p95':>9}"
              f"{'p99':>9}{'max':>9}{'err':>7}")
        total = 0
        for op in sorted(self.lat):
            v = sorted(self.lat[op])
            total += len(v)
            if not v:
                continue
            print(f"   {op:<22}{len(v):>8}{len(v)/elapsed:>9.0f}"
                  f"{pct(v,50):>9.1f}{pct(v,95):>9.1f}{pct(v,99):>9.1f}"
                  f"{v[-1]:>9.1f}{self.err[op]:>7}")
        for op in sorted(self.err):
            if self.err[op]:
                print(f"     ! {op}: {self.err[op]} errors -- {self.errmsg[op]}")
        print(f"   {'':<22}{total:>8} calls, {total/elapsed:>.0f}/s overall")
        return total


def pct(sorted_vals, p):
    if not sorted_vals:
        return 0.0
    k = (len(sorted_vals) - 1) * p / 100.0
    lo, hi = int(k), min(int(k) + 1, len(sorted_vals) - 1)
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (k - lo)


def timed(stats, op, fn, *a):
    t = time.perf_counter()
    try:
        r = fn(*a)
        stats.record(op, time.perf_counter() - t)
        return r
    except Exception as e:
        stats.record(op, time.perf_counter() - t)
        stats.fail(op, e)
        return None


# --- phase A: the signup storm ----------------------------------------------

def phase_signup(dsn, uids):
    print(f"\n=> PHASE A  signup storm -- {len(uids)} first-time sign-ins at once")
    stats = Stats()
    clients = {}

    def signup(uid):
        c = Client(dsn, uid)
        clients[uid] = c
        timed(stats, "claim_player", c.call,
              "select public.claim_player(%s::jsonb, %s, %s, %s, %s, %s, %s, %s)",
              (SAVE, f"Player{random.randint(1, 10**9)}", "🙂",
               random.randint(0, 500), random.randint(1, 12),
               random.randint(0, 10**6), random.randint(0, 3), [3, 3, 3, 3, 3]))

    t = time.perf_counter()
    with ThreadPoolExecutor(max_workers=min(64, len(uids))) as ex:
        list(ex.map(signup, uids))
    elapsed = time.perf_counter() - t
    stats.report(f"signup storm, {len(uids)} accounts in {elapsed:.1f}s", elapsed)

    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select count(*) from public.players where is_bot = false")
        made = cur.fetchone()[0]
        cur.execute("""select count(*) from (
                         select public.normalize_name(display_name) n
                           from public.players
                          where deleted_at is null and is_bot = false
                          group by 1 having count(*) > 1) t""")
        dupes = cur.fetchone()[0]
    ok = made == len(uids) and dupes == 0
    print(f"   [{'ok' if ok else 'FAIL'}] {made}/{len(uids)} islands created, "
          f"{dupes} duplicate names under a concurrent unique index")
    return clients, ok


# --- phase B: steady state ---------------------------------------------------

# What a client actually does, weighted the way the game does it. cloud.gd
# pushes at most once every 30s per device, polls raids on resume, and reads
# the board only when the player opens it -- but a raid lookup happens on every
# raid triple, which is the hot one.
MIX = [
    ("find_target",   34),
    ("record_raid",   17),
    ("push_save",     20),
    ("unseen_raids",  14),
    ("ack_raids",      6),
    ("pull_save",      5),
    ("leaderboard",    4),
]
_BAG = [op for op, w in MIX for _ in range(w)]


def worker(client, stats, deadline, victims, rank):
    mine = client.call("select public.current_player()")
    mine = str(mine[0]) if mine else None
    targets = [v for v in victims if str(v) != mine] or victims
    while time.perf_counter() < deadline:
        op = random.choice(_BAG)
        if op == "find_target":
            timed(stats, op, client.call,
                  "select public.find_target(%s)",
                  (random.choice(["steal", "attack"]),))
        elif op == "record_raid":
            v = random.choice(targets)
            timed(stats, op, client.call,
                  "select public.record_raid(%s, %s, %s, %s)",
                  (v, random.choice(["steal", "attack"]),
                   random.randint(100, 50000), random.randint(0, 4)))
        elif op == "push_save":
            # rank_stars only ever rises -- that is the merge rule the server
            # trusts, so the load has to respect it or every push is 'stale'.
            rank[0] += random.randint(1, 5)
            timed(stats, op, client.call,
                  "select public.push_save(%s::jsonb, %s, %s, %s, %s, %s)",
                  (SAVE, rank[0], random.randint(1, 30),
                   random.randint(0, 10**7), random.randint(0, 3),
                   [3, 3, 3, 3, 3]))
        elif op == "unseen_raids":
            timed(stats, op, client.call, "select public.unseen_raids()")
        elif op == "ack_raids":
            rows = client.call("select public.unseen_raids()")
            ids = []
            if rows and rows[0]:
                ids = [r["id"] for r in rows[0]][:20]
            if ids:
                timed(stats, op, client.call,
                      "select public.ack_raids(%s::uuid[])", (ids,))
        elif op == "pull_save":
            timed(stats, op, client.call, "select public.pull_save()")
        elif op == "leaderboard":
            timed(stats, op, client.call, "select public.leaderboard(50)")


def phase_steady(dsn, clients, levels, seconds):
    print(f"\n=> PHASE B  steady state -- the real RPC mix, {seconds}s a level")
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select id from public.players where deleted_at is null "
                    "limit 500")
        victims = [r[0] for r in cur.fetchall()]

    uids = list(clients)
    results = []
    for n in levels:
        n = min(n, len(uids))
        stats = Stats()
        ranks = {u: [10000] for u in uids[:n]}
        deadline = time.perf_counter() + seconds
        t = time.perf_counter()
        with ThreadPoolExecutor(max_workers=n) as ex:
            for u in uids[:n]:
                ex.submit(worker, clients[u], stats, deadline, victims, ranks[u])
        elapsed = time.perf_counter() - t
        total = stats.report(f"{n} concurrent clients", elapsed)
        errs = sum(stats.err.values())
        p95 = {op: pct(sorted(v), 95) for op, v in stats.lat.items()}
        results.append((n, total / elapsed, p95, errs))
    return results


# --- phase C: the races ------------------------------------------------------

DELETED = set()


def phase_contention(dsn, clients):
    print("\n=> PHASE C  contention -- the races the schema has to settle")
    uids = list(clients)
    ok = True

    # 1. One player, two devices, pushing at once. rank_stars must never go
    #    backwards -- the whole save-merge rule rests on it.
    victim_uid = uids[0]
    devices = [Client(dsn, victim_uid) for _ in range(8)]
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select set_config('request.jwt.claim.sub', %s, false)",
                    (str(victim_uid),))
        cur.execute("select public.current_player()")
        pid = cur.fetchone()[0]
        cur.execute("update public.players set rank_stars = 1000 where id = %s",
                    (pid,))

    seen_backwards = threading.Event()

    def push_device(d, base):
        for i in range(60):
            try:
                d.call("select public.push_save(%s::jsonb, %s, %s)",
                       (SAVE, base + i, 5))
            except Exception:
                pass
            with psycopg.connect(dsn, autocommit=True) as c2, c2.cursor() as cur2:
                pass

    with ThreadPoolExecutor(max_workers=8) as ex:
        for i, d in enumerate(devices):
            ex.submit(push_device, d, 1000 + i * 100)

    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select rank_stars from public.players where id = %s", (pid,))
        final = cur.fetchone()[0]
    # Eight devices pushing 1000..1600; whatever wins, the stored rank must be
    # the highest anybody pushed, never a lower one that landed later.
    highest = 1000 + 7 * 100 + 59
    good = final == highest
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] eight devices pushing at once left "
          f"rank_stars at {final} (highest pushed {highest}) -- never goes backwards")
    for d in devices:
        d.close()

    # 2. Everybody grabs the same name at once. Exactly one may have it.
    wanted = "CaptainOne"
    winners = []
    lock = threading.Lock()

    def grab(uid):
        c = clients[uid]
        try:
            r = c.call("select public.set_display_name(%s)", (wanted,))
            if r and r[0] and r[0].get("ok") is True:
                with lock:
                    winners.append(uid)
        except Exception:
            pass

    contenders = uids[:min(48, len(uids))]
    with ThreadPoolExecutor(max_workers=len(contenders)) as ex:
        list(ex.map(grab, contenders))
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("""select count(*) from public.players
                        where deleted_at is null and is_bot = false
                          and public.normalize_name(display_name)
                              = public.normalize_name(%s)""", (wanted,))
        holders = cur.fetchone()[0]
    good = holders <= 1 and len(winners) <= 1
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] {len(contenders)} clients raced for "
          f"one name: {len(winners)} told they won, {holders} actually hold it")

    # 3. A raid must be delivered exactly once. Many acks, no loss, no replay.
    attacker = clients[uids[1]]
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select set_config('request.jwt.claim.sub', %s, false)",
                    (str(uids[2]),))
        cur.execute("select public.current_player()")
        target = cur.fetchone()[0]
        cur.execute("delete from public.raids where victim = %s", (target,))
    for i in range(40):
        attacker.call("select public.record_raid(%s, %s, %s)",
                      (target, "steal", 100 + i))
    victim_devices = [Client(dsn, uids[2]) for _ in range(6)]
    acked = []

    def drain(d):
        for _ in range(20):
            r = d.call("select public.unseen_raids()")
            rows = r[0] if r and r[0] else []
            ids = [x["id"] for x in rows]
            if not ids:
                return
            d.call("select public.ack_raids(%s::uuid[])", (ids,))
            with lock:
                acked.extend(ids)

    with ThreadPoolExecutor(max_workers=6) as ex:
        list(ex.map(drain, victim_devices))
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select count(*) from public.raids where victim = %s "
                    "and seen_at is null", (target,))
        left = cur.fetchone()[0]
        cur.execute("select count(*) from public.raids where victim = %s", (target,))
        total = cur.fetchone()[0]
    good = left == 0 and total == 40
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] 40 raids, six devices draining at "
          f"once: {total} recorded, {left} left unseen, "
          f"{len(acked)} ack calls ({len(set(acked))} distinct)")
    for d in victim_devices:
        d.close()

    # 4. A deleted account must stop appearing to anybody.
    doomed = uids[-1]
    c = clients[doomed]
    DELETED.add(doomed)
    try:
        c.call("select public.delete_account()")
        with psycopg.connect(dsn, autocommit=True) as c2, c2.cursor() as cur:
            cur.execute("""select count(*) from public.players
                            where deleted_at is not null and is_bot = false""")
            gone = cur.fetchone()[0]
            cur.execute("select public.leaderboard(200)")
            board = cur.fetchone()[0] or []
        good = gone >= 1
        ok = ok and good
        print(f"   [{'ok' if good else 'FAIL'}] delete_account soft-deleted the "
              f"island ({gone} deleted) and it is off the {len(board)}-row board")
    except Exception as e:
        ok = False
        print(f"   [FAIL] delete_account raised: {e}")

    return ok


# --- phase D: scale ----------------------------------------------------------

def phase_scale(dsn, clients, sizes, seconds):
    print("\n=> PHASE D  scale -- the same reads against a bigger world")
    uids = [u for u in clients if u not in DELETED]
    grown = 0
    out = []
    for size in sizes:
        add = size - grown
        if add > 0:
            with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
                cur.execute("""
                    insert into public.players
                        (display_name, emoji, is_bot, rank_stars, island_level,
                         vault_coins, shields, buildings, last_seen, save_blob)
                    select 'Drifter' || g,
                           '🙂', false,
                           (random()*20000)::int,
                           1 + (random()*29)::int,
                           (random()*5000000)::bigint,
                           (random()*3)::smallint,
                           array[3,3,3,3,3]::smallint[],
                           now() - ((random()*20)::int * interval '1 day'),
                           %s::jsonb
                      from generate_series(%s::int, %s::int) g
                """, (SAVE, grown + 1, size))
                cur.execute("analyze public.players")
                cur.execute("analyze public.raids")
            grown = size

        stats = Stats()
        n = min(24, len(uids))
        deadline = time.perf_counter() + seconds
        t = time.perf_counter()

        def read_worker(cl):
            while time.perf_counter() < deadline:
                timed(stats, "find_target", cl.call,
                      "select public.find_target(%s)",
                      (random.choice(["steal", "attack"]),))
                timed(stats, "leaderboard", cl.call,
                      "select public.leaderboard(50)")

        with ThreadPoolExecutor(max_workers=n) as ex:
            for u in uids[:n]:
                ex.submit(read_worker, clients[u])
        elapsed = time.perf_counter() - t
        stats.report(f"{size:,} islands, {n} concurrent readers", elapsed)
        out.append((size,
                    pct(sorted(stats.lat.get("find_target", [])), 95),
                    pct(sorted(stats.lat.get("leaderboard", [])), 95)))

    # What the planner actually decided, which is the thing that will or will
    # not survive a hundred thousand players.
    print("\n   query plans at the largest size:")
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select set_config('request.jwt.claim.sub', %s, false)",
                    (str(uids[0]),))
        for label, sql in [
            ("leaderboard", "select public.leaderboard(50)"),
            ("find_target", "select public.find_target('steal')"),
        ]:
            cur.execute(f"explain (analyze, buffers, format json) {sql}")
            plan = cur.fetchone()[0][0]
            print(f"     {label}: {plan['Execution Time']:.1f}ms  "
                  f"(planning {plan['Planning Time']:.1f}ms)")
    # The scans that matter, measured directly rather than through the wrapper.
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("""explain (analyze, format json)
                       select p.id from public.players p
                        where p.deleted_at is null
                        order by p.rank_stars desc limit 50""")
        plan = cur.fetchone()[0][0]["Plan"]
        print(f"     leaderboard scan: {plan['Node Type']} "
              f"-> {'uses the index' if _has_index(plan) else 'SEQUENTIAL SCAN'}"
              f"  rows={plan.get('Actual Rows')}")
        # The matchmaking scan as find_target actually performs it since the
        # 2026-08-31 migration: a seek into the mm_key space that stops on the
        # first eligible row, rather than a sort of the whole band. `rows read`
        # is the number that must stay small as the world grows -- it was the
        # entire band (22k+) under the old ORDER BY random().
        cur.execute("""explain (analyze, format json)
                       select p.id from public.players p
                        where p.mm_key >= random()
                          and p.is_bot = false and p.deleted_at is null
                          and p.last_seen > now() - interval '30 days'
                          and p.island_level between 1 and 7
                          and p.vault_coins > 0
                        order by p.mm_key limit 1""")
        plan = cur.fetchone()[0][0]["Plan"]
        scanned = _rows_scanned(plan)
        print(f"     find_target scan: {plan['Node Type']} "
              f"-> {'uses the index' if _has_index(plan) else 'SEQUENTIAL SCAN'}"
              f"  rows read={scanned}")
    return out


def _has_index(plan):
    if "Index" in str(plan.get("Node Type", "")):
        return True
    return any(_has_index(sp) for sp in plan.get("Plans", []))


def _rows_scanned(plan):
    n = plan.get("Actual Rows", 0) or 0
    for sp in plan.get("Plans", []):
        n = max(n, _rows_scanned(sp))
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--players", type=int, default=200)
    ap.add_argument("--seconds", type=int, default=12)
    ap.add_argument("--levels", default="1,8,32,64,128")
    ap.add_argument("--sizes", default="1000,25000,100000")
    args = ap.parse_args()

    levels = [int(x) for x in args.levels.split(",")]
    sizes = [int(x) for x in args.sizes.split(",")]

    print("=> booting a throwaway Postgres and applying the real migrations")
    pg = Pg()
    ok = True
    try:
        pg.start()
        dsn = pg.dsn()
        apply_schema(dsn)
        uids = make_auth_users(dsn, args.players)
        clients, a_ok = phase_signup(dsn, uids)
        ok = ok and a_ok
        b = phase_steady(dsn, clients, levels, args.seconds)
        ok = phase_contention(dsn, clients) and ok
        d = phase_scale(dsn, clients, sizes, args.seconds)

        print("\n=> SUMMARY")
        print("   throughput against concurrency:")
        for n, tps, p95, errs in b:
            worst = max(p95.items(), key=lambda kv: kv[1]) if p95 else ("-", 0)
            print(f"     {n:>4} clients  {tps:>8.0f} calls/s   "
                  f"slowest p95: {worst[0]} {worst[1]:.0f}ms   errors {errs}")
        print("   read latency against world size:")
        for size, ft, lb in d:
            print(f"     {size:>8,} islands   find_target p95 {ft:>7.1f}ms   "
                  f"leaderboard p95 {lb:>7.1f}ms")
        for c in clients.values():
            c.close()
    finally:
        pg.stop()
    print(f"\nLOAD TEST: {'ALL CORRECTNESS CHECKS PASS' if ok else 'FAILURES ABOVE'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
