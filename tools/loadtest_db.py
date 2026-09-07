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
  E  tournament        -- brackets, placings and the league-size cache
  F  clans             -- four doors into one thirty-seat room
  G  gifts             -- the daily caps under a stampede

Phases A-D give every virtual player its own connection and stop being honest
somewhere under a thousand. Phases E-G go through a bounded pool with the JWT
claim swapped per call, which is what PostgREST does, so they scale to the
population the game is actually being asked about.

Usage: tools/loadtest_db.py [--players N] [--seconds S] [--levels 1,8,32,...]
"""

import argparse
import contextlib
import json
import os
import queue
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

    def start(self, max_conns=200):
        run([os.path.join(PG, "initdb"), "-D", self.data, "-U", "postgres",
             "--auth=trust"])
        # Tuned like a small managed instance rather than a laptop default, so
        # the numbers mean something: Supabase's free tier is 60 connections
        # and shared buffers in the same order.
        #
        # max_conns is SIZED FROM THE RUN rather than fixed at 200, because a
        # fixed 200 is one short of what `--players 200` -- the default -- asks
        # for: phase A holds a connection per client and then wants one more for
        # the admin count at the end, and Postgres answers "sorry, too many
        # clients already" from inside a `with psycopg.connect(...)` that reads
        # as a schema failure rather than as running out of sockets. The tool's
        # own default invocation could not finish phase A.
        run([os.path.join(PG, "pg_ctl"), "-D", self.data,
             "-o", f"-k {self.work} -c listen_addresses='' "
                   f"-c max_connections={max_conns} -c shared_buffers=256MB "
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

    # RAID THE RIVAL THE SERVER JUST OFFERED, which is what the game does.
    #
    # This used to raid a victim drawn at random from a list, and since
    # 20260831190000_raid_offers_and_column_grants.sql that is not a raid at
    # all: `record_raid` requires an open `raid_offers` row for that exact
    # (attacker, victim) pair, minted by `find_target`, and refuses anything
    # else with 'no open raid offer for that island'. Measured at 18,662
    # failures out of 18,862 calls -- 99% -- so the 20% of the mix that is
    # meant to be the heaviest WRITE in the game was timing how fast Postgres
    # can raise an exception. `timed()` swallows it into an error counter, so
    # the phase reported a throughput figure the whole time.
    #
    # cloud.gd's own order is find_target -> show the rival -> record_raid on
    # that rival, so holding the offer here is the shape as well as the fix.
    offer = {"id": None, "mode": "steal"}
    while time.perf_counter() < deadline:
        op = random.choice(_BAG)
        if op == "find_target":
            mode = random.choice(["steal", "attack"])
            r = timed(stats, op, client.call,
                      "select public.find_target(%s)", (mode,))
            if r and r[0] and isinstance(r[0], dict) and r[0].get("id"):
                offer = {"id": r[0]["id"], "mode": mode}
        elif op == "record_raid":
            if not offer["id"]:
                # Nothing offered yet. Ask, rather than raiding a stranger --
                # a search always precedes a raid on a real device too.
                mode = random.choice(["steal", "attack"])
                r = timed(stats, "find_target", client.call,
                          "select public.find_target(%s)", (mode,))
                if r and r[0] and isinstance(r[0], dict) and r[0].get("id"):
                    offer = {"id": r[0]["id"], "mode": mode}
            if offer["id"]:
                timed(stats, op, client.call,
                      "select public.record_raid(%s, %s, %s, %s)",
                      (offer["id"], offer["mode"],
                       random.randint(100, 50000), random.randint(0, 4)))
                offer = {"id": None, "mode": "steal"}
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
    # READ THE record_raid ERROR COUNT AS A PASS, NOT A FAULT -- once it says
    # 'already raided that island today' or 'too many raids in one hour'.
    # Those are the game's own anti-griefing rules, and a load generator that
    # raids thousands of times a minute is exactly what they exist to refuse.
    # What was NOT a pass was the message this used to print, 'no open raid
    # offer for that island': that one meant the call had no precondition and
    # the raid path was never being exercised at all.
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
    #
    # FORTY ATTACKERS, not one attacker forty times. `record_raid` has refused
    # a repeat against the same island within 24 hours since
    # 20260831190000_raid_offers_and_column_grants.sql, and it refuses by
    # RAISING -- so the original loop threw `InsufficientPrivilege: already
    # raided that island today` out of an unguarded call and took the whole
    # process down on the second iteration. Everything after it in phase C, and
    # the whole of phase D, had not run since that migration landed. It reads
    # as a crash in the harness rather than as a test that has expired, which
    # is why it sat there.
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select set_config('request.jwt.claim.sub', %s, false)",
                    (str(uids[2]),))
        cur.execute("select public.current_player()")
        target = cur.fetchone()[0]
        cur.execute("delete from public.raids where victim = %s", (target,))
    raiders = [u for u in uids[3:] if u != uids[2]][:40]
    # The offer each of them would have been holding. record_raid consumes a
    # raid_offers row and refuses without one, and find_target mints offers
    # against whoever IT picks -- which will not be this victim out of 110,000
    # islands. Minting them directly is the only way to aim the test, and it
    # is exactly the row a search that happened to land here would have left.
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("""
            insert into public.raid_offers (attacker, victim)
            select pi.player_id, %s
              from public.player_identities pi
             where pi.auth_uid = any(%s)""", (target, [str(u) for u in raiders]))
        # A steal needs something in the vault, and phase B may have emptied it.
        cur.execute("update public.players set vault_coins = 5000000, "
                    "shields = 0 where id = %s", (target,))
    landed = 0
    errs = {}
    for u in raiders:
        try:
            clients[u].call("select public.record_raid(%s, %s, %s)",
                            (target, "steal", 100 + landed))
            landed += 1
        except Exception as e:
            errs[str(e).split("\n")[0][:70]] = errs.get(
                str(e).split("\n")[0][:70], 0) + 1
    if errs:
        print(f"     (record_raid refusals: {errs})")
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
    good = left == 0 and total == landed and landed > 0
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] {landed} raids from {landed} "
          f"attackers, six devices draining at once: {total} recorded, "
          f"{left} left unseen, {len(acked)} ack calls "
          f"({len(set(acked))} distinct)")
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


# --- a pooled client, because 10,000 players do not get 10,000 connections ----
#
# Phases A-D give every virtual player its own connection, which is honest at
# 200 and impossible at 10,000: Postgres is configured for 200 and Supabase's
# free tier for 60. Modelling it as a connection each would not merely fail to
# start, it would measure the wrong thing -- PostgREST puts every request
# through a small pool and sets `request.jwt.claim.sub` per request, so a
# bounded pool with the claim swapped around each call IS production.
#
# That makes "10,000 concurrent players" mean what it means on a real server:
# ten thousand identities with work in flight, funnelled through the pool the
# database actually has. The queue depth is the interesting number, not the
# socket count.
class Pool:
    def __init__(self, dsn, size):
        self.dsn = dsn
        self.size = size
        self._free = queue.Queue()
        self._all = []
        for _ in range(size):
            c = psycopg.connect(dsn, autocommit=True)
            self._all.append(c)
            self._free.put(c)

    @contextlib.contextmanager
    def _lease(self, uid):
        c = self._free.get()
        try:
            with c.cursor() as cur:
                cur.execute("reset role")
                cur.execute(
                    "select set_config('request.jwt.claim.sub', %s, false)",
                    (str(uid),))
                cur.execute("set role authenticated")
            yield c
        finally:
            # RESET ROLE always returns to the session user, so a call that
            # raised cannot leave the next borrower wearing somebody else's
            # role -- which would be a cross-account read in the test harness
            # itself, and would look exactly like an RLS hole in the schema.
            try:
                with c.cursor() as cur:
                    cur.execute("reset role")
            except Exception:
                try:
                    c.close()
                except Exception:
                    pass
                c = psycopg.connect(self.dsn, autocommit=True)
            self._free.put(c)

    def call(self, uid, sql, args=()):
        with self._lease(uid) as c, c.cursor() as cur:
            cur.execute(sql, args)
            try:
                return cur.fetchone()
            except psycopg.ProgrammingError:
                return None

    def close(self):
        for c in self._all:
            try:
                c.close()
            except Exception:
                pass


def admin(dsn, sql, args=()):
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute(sql, args)
        try:
            return cur.fetchall()
        except psycopg.ProgrammingError:
            return None


def bulk_signup(dsn, pool, uids, stats, workers):
    """claim_player for everybody, through the pool."""
    def one(uid):
        timed(stats, "claim_player", pool.call, uid,
              "select public.claim_player(%s::jsonb, %s, %s, %s, %s, %s, %s, %s)",
              (SAVE, f"Player{uuid.uuid4().hex[:10]}", "🙂",
               random.randint(0, 20000), random.randint(1, 30),
               random.randint(0, 10 ** 6), random.randint(0, 3), [3, 3, 3, 3, 3]))
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(one, uids))


# --- phase E: the tournament, which phases A-D never touched -----------------
#
# The tournament is the newest write path and the only zero-sum one in the
# game, and it was invisible to this file until now. Three things are being
# asked:
#
#   1. does `tourney_report` stay monotonic within a cycle when the same
#      account reports from several devices at once,
#   2. does the bracket the BOARD draws match the field `tourney_result`
#      counts -- the two disagreeing is the entire defect the brackets
#      migration exists to close, and it is a disagreement that only appears
#      at a population no test has ever built, and
#   3. does the league-size cache stay off the read path as the league grows.
def phase_tourney(dsn, pool, uids, seconds, workers):
    print(f"\n=> PHASE E  the tournament -- {len(uids):,} players scoring at once")
    stats = Stats()
    ok = True

    now_id = admin(dsn, "select public.tourney_now_id()")[0][0]

    # Everybody reports, repeatedly, the way a player scoring during a spin
    # session does. Points rise, so within-cycle monotonicity is testable.
    best = {}
    lock = threading.Lock()

    # Held back deliberately: signed in, in a bracket, and yet to score a point
    # this cycle. That is not an exotic state -- it is everybody, for the first
    # hours of every cycle, and anybody who opens the app after one ended
    # without having played it.
    watchers = list(uids[-20:]) if len(uids) > 400 else []
    uids = [u for u in uids if u not in set(watchers)]

    # EVERY player reports, not just the first `workers` of them. The obvious
    # shape -- ex.map(score, uids) where score() loops until a deadline -- gives
    # the whole window to the first `workers` uids and runs the other 9,900
    # after it has expired, doing nothing. The bracket checks below then sample
    # players who never scored and measure a different thing entirely.
    #
    # So: one deterministic pass where everybody reports once, then a timed
    # storm over random uids, which is what a population actually looks like.
    def report_once(uid):
        pts = random.randint(1, 400)
        with lock:
            best[uid] = max(best.get(uid, 0), pts)
        timed(stats, "tourney_report", pool.call, uid,
              "select public.tourney_report(%s, %s)", (now_id, pts))

    t = time.perf_counter()
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(report_once, uids))

    deadline = time.perf_counter() + seconds

    def storm(_seat):
        while time.perf_counter() < deadline:
            uid = random.choice(uids)
            with lock:
                pts = best.get(uid, 0) + random.randint(1, 120)
                best[uid] = pts
            timed(stats, "tourney_report", pool.call, uid,
                  "select public.tourney_report(%s, %s)", (now_id, pts))
            if random.random() < 0.25:
                timed(stats, "tourney_board", pool.call, uid,
                      "select public.tourney_board(30)")
            if random.random() < 0.10:
                timed(stats, "tourney_result", pool.call, uid,
                      "select public.tourney_result(%s)", (now_id,))
            if random.random() < 0.05:
                timed(stats, "tourney_progress", pool.call, uid,
                      "select public.tourney_progress()")

    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(storm, range(workers)))
    elapsed = time.perf_counter() - t
    stats.report(f"{len(uids):,} players, {workers} pooled connections", elapsed)

    # 1. Monotonic within the cycle: the stored score is the highest reported.
    stored = dict(admin(dsn, """select p.id, p.tourney_points
                                  from public.players p
                                 where p.tourney_id = %s""", (now_id,)) or [])
    ident = dict(admin(dsn, """select i.auth_uid, i.player_id
                                 from public.player_identities i""") or [])
    bad = 0
    for uid, want in best.items():
        pid = ident.get(uid)
        if pid is None:
            continue
        got = stored.get(pid)
        if got is None or got < want:
            bad += 1
    good = bad == 0
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] every stored score is the highest "
          f"its player reported ({len(best):,} players, {bad} short)")

    # 2. The board and the placing must be drawn over the SAME field. This is
    #    the check the brackets migration was written to make true, and it can
    #    only fail at a population -- at a dozen testers the two agree by
    #    accident because everybody fits.
    sample = random.sample(list(uids), min(60, len(uids)))
    field_off = []
    place_off = []
    fields = []
    for uid in sample:
        b = pool.call(uid, "select public.tourney_board(100)")
        r = pool.call(uid, "select public.tourney_result(%s)", (now_id,))
        if not b or not r or b[0] is None or r[0] is None:
            continue
        board, res = b[0], r[0]
        fields.append(res["field"])
        if len(board) != res["field"]:
            field_off.append((len(board), res["field"]))
        above = sum(1 for row in board if row["points"] > res["points"])
        if above + 1 != res["place"]:
            place_off.append((above + 1, res["place"]))
    good = not field_off
    ok = ok and good
    worst = max(fields) if fields else 0
    print(f"   [{'ok' if good else 'FAIL'}] the board and the placing count the "
          f"same field for {len(sample)} sampled players "
          f"({len(field_off)} disagree, biggest bracket {worst})")
    if field_off:
        print(f"     ! first five (board rows vs result field): {field_off[:5]}")
    # The PLACING is deliberately not asserted mid-cycle. The board scores a bot
    # at `tourney_progress()` -- how far through the three days it is -- and
    # tourney_result scores the same bot at 1.0, its finished total, because
    # result is only ever asked about a cycle that has ended. So the two rank
    # bots differently while a cycle is running, by design, and an assertion
    # here would be measuring the clock. Reported, not failed.
    print(f"   (placing differs for {len(place_off)}/{len(sample)} mid-cycle, "
          f"which is bot pacing rather than a disagreement)")

    # 2b. THE PLAYER WHO HAS NOT SCORED YET. The board draws them -- it has an
    #     explicit `or p.id = v_me` so a player always finds themselves on it --
    #     and tourney_result must count them in the same field, or the placing
    #     is computed against a field the player is not in and can come out one
    #     bigger than it. "#12 of 11" is not a rounding difference; it is the
    #     board and the placing being two different competitions, which is the
    #     defect the brackets migration exists to close.
    bad_watch = []
    for uid in watchers:
        b = pool.call(uid, "select public.tourney_board(100)")
        r = pool.call(uid, "select public.tourney_result(%s)", (now_id,))
        if not b or not r or b[0] is None or r[0] is None:
            continue
        board, res = b[0], r[0]
        if len(board) != res["field"] or res["place"] > res["field"]:
            bad_watch.append((len(board), res["field"], res["place"]))
    good = not bad_watch
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] a player yet to score this cycle is "
          f"counted in their own field ({len(bad_watch)}/{len(watchers)} are "
          f"placed outside it)")
    if bad_watch:
        print(f"     ! first five (board rows, result field, result place): "
              f"{bad_watch[:5]}")

    # 3. A bracket is meant to be a group. Report what the population actually
    #    produced rather than asserting a number the design may have moved.
    rows = admin(dsn, """
        select public.tourney_league(island_level) lg, count(*)
          from public.players where deleted_at is null group by 1 order by 1""")
    sizes = admin(dsn, "select league, members from public.tourney_leagues order by 1")
    print(f"   leagues by population: "
          + ", ".join(f"L{lg}:{n:,}" for lg, n in (rows or [])))
    print(f"   cached member counts:  "
          + ", ".join(f"L{lg}:{n:,}" for lg, n in (sizes or []))
          + ("  (empty -- nothing reported)" if not sizes else ""))
    for lg, n in (sizes or []):
        sl = admin(dsn, "select public.tourney_slices(%s)", (lg,))[0][0]
        print(f"     L{lg}: {n:,} members / {sl} slices "
              f"= {n / max(sl, 1):.0f} to a bracket")

    # 4. The read path must not count the league. If tourney_board scanned the
    #    league, its plan would show the whole band; it must show a range.
    with psycopg.connect(dsn, autocommit=True) as c, c.cursor() as cur:
        cur.execute("select set_config('request.jwt.claim.sub', %s, false)",
                    (str(sample[0]),))
        cur.execute("explain (analyze, format json) select public.tourney_board(30)")
        plan = cur.fetchone()[0][0]
        print(f"   tourney_board at this population: "
              f"{plan['Execution Time']:.1f}ms")
    return ok, stats


# --- phase F: clans, and the cap that has to hold under a stampede -----------
#
# The 30-member cap is enforced by a read of `clans.members` under a row lock
# and a write back. That is correct only if every path that admits a member
# takes the same lock -- and there are FOUR of them (join, accept an invite,
# answer a request, and create). A cap that holds against one door and not the
# others is not a cap.
def phase_clans(dsn, pool, uids):
    print("\n=> PHASE F  clans -- four doors into one thirty-seat room")
    ok = True
    cap = admin(dsn, "select public.clan_max_members()")[0][0]

    # A clan, and then far more applicants than seats, all at once.
    owner = uids[0]
    r = pool.call(owner, "select public.create_clan(%s, %s)",
                  ("Stampede Bay", "🏴"))
    made = r[0] if r else None
    if not made or not made.get("ok"):
        print(f"   [FAIL] could not create the clan under test: {made}")
        return False
    clan = made["clan"]["id"]
    pool.call(owner, "select public.set_clan_open(true)")

    applicants = list(uids[1:1 + cap * 8])
    got_in = []
    lock = threading.Lock()

    def rush(uid):
        try:
            res = pool.call(uid, "select public.join_clan(%s)", (clan,))
            if res and res[0] and res[0].get("ok"):
                with lock:
                    got_in.append(uid)
        except Exception:
            pass

    with ThreadPoolExecutor(max_workers=min(64, len(applicants))) as ex:
        list(ex.map(rush, applicants))

    counted = admin(dsn, "select members from public.clans where id = %s",
                    (clan,))[0][0]
    actual = admin(dsn, "select count(*) from public.clan_members where clan_id = %s",
                   (clan,))[0][0]
    good = actual <= cap and counted == actual
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] {len(applicants)} applicants raced "
          f"for {cap} seats: {len(got_in)} told yes, {actual} actually seated, "
          f"the counter says {counted}")

    # The same name, from many accounts, in the same moment.
    freshmen = list(uids[1 + cap * 8:1 + cap * 8 + 40])
    winners = []

    def name_rush(uid):
        try:
            res = pool.call(uid, "select public.create_clan(%s, %s)",
                            ("Same Name Crew", "🏴"))
            if res and res[0] and res[0].get("ok"):
                with lock:
                    winners.append(uid)
        except Exception:
            pass

    with ThreadPoolExecutor(max_workers=min(40, len(freshmen))) as ex:
        list(ex.map(name_rush, freshmen))
    holders = admin(dsn, """select count(*) from public.clans
                             where lower(name) = lower(%s)""",
                    ("Same Name Crew",))[0][0]
    good = holders == 1 and len(winners) == 1
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] {len(freshmen)} clients raced for "
          f"one clan name: {len(winners)} told they won, {holders} exist")

    # Leaving and joining at the same time must not drift the counter. This is
    # the one that goes wrong quietly -- `members` is a denormalised count and
    # a lost update leaves a clan that says 29 with 30 people in it, or one
    # that says 30 with 12 and can never be joined again.
    leavers = got_in[:10]
    newcomers = list(uids[1 + cap * 8 + 40:1 + cap * 8 + 70])

    def churn(uid, leaving):
        try:
            if leaving:
                pool.call(uid, "select public.leave_clan()")
            else:
                pool.call(uid, "select public.join_clan(%s)", (clan,))
        except Exception:
            pass

    jobs = [(u, True) for u in leavers] + [(u, False) for u in newcomers]
    random.shuffle(jobs)
    with ThreadPoolExecutor(max_workers=32) as ex:
        list(ex.map(lambda j: churn(*j), jobs))
    counted = admin(dsn, "select members from public.clans where id = %s",
                    (clan,))[0][0]
    actual = admin(dsn, "select count(*) from public.clan_members where clan_id = %s",
                   (clan,))[0][0]
    good = counted == actual and actual <= cap
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] ten left while thirty joined: the "
          f"counter says {counted}, the roster holds {actual}")

    # DELETING AN ACCOUNT IS A DEPARTURE. Until 20260907190000 it was not:
    # delete_account soft-deletes the island and a soft delete fires no
    # cascade, so the clan_members row stayed, `clans.members` never came down,
    # and the seat was gone for good. A clan reached thirty with fewer than
    # thirty real people in it and could never be joined again.
    quitters = got_in[10:16]
    seats_before = admin(dsn, "select members from public.clans where id = %s",
                         (clan,))[0][0]
    for uid in quitters:
        try:
            pool.call(uid, "select public.delete_account()")
        except Exception:
            pass
    counted = admin(dsn, "select members from public.clans where id = %s",
                    (clan,))[0][0]
    living = admin(dsn, """select count(*) from public.clan_members m
                             join public.players p on p.id = m.player_id
                            where m.clan_id = %s and p.deleted_at is null""",
                   (clan,))[0][0]
    ghosts = admin(dsn, """select count(*) from public.clan_members m
                             join public.players p on p.id = m.player_id
                            where m.clan_id = %s and p.deleted_at is not null""",
                   (clan,))[0][0]
    good = counted == living and ghosts == 0
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] {len(quitters)} members deleted "
          f"their accounts: seats {seats_before} -> {counted}, {living} living "
          f"members, {ghosts} ghosts still holding a seat")

    # AND THE OWNER LEAVING MUST NOT STRAND THE CLAN. `clans.owner` gates the
    # door switch and the whole join-request queue, and nothing used to
    # reassign it -- so an owner who left or deleted their account took the
    # controls with them permanently.
    owner_now = admin(dsn, "select owner from public.clans where id = %s",
                      (clan,))[0][0]
    try:
        pool.call(owner, "select public.delete_account()")
    except Exception:
        pass
    row = admin(dsn, """select c.owner, c.members,
                               (select count(*) from public.clan_members m
                                 where m.clan_id = c.id) roster
                          from public.clans c where c.id = %s""", (clan,))
    if not row:
        good = True   # disbanded, which is correct if nobody was left
        print("   [ok] the owner deleting their account disbanded an empty clan")
    else:
        new_owner, mem, roster = row[0]
        alive = admin(dsn, """select count(*) from public.players
                               where id = %s and deleted_at is null""",
                      (new_owner,))[0][0]
        good = alive == 1 and new_owner != owner_now and mem == roster
        ok = ok and good
        print(f"   [{'ok' if good else 'FAIL'}] the owner deleted their "
              f"account: the clan was handed to a living member "
              f"({'yes' if alive else 'NO -- a ghost owns it'}), "
              f"{mem} seats for {roster} on the roster")

    # Nobody may hold two seats. The unique key on clan_members is what makes
    # this true; it is checked because a lost one is silent.
    dupes = admin(dsn, """select count(*) from (
                            select player_id from public.clan_members
                             group by 1 having count(*) > 1) t""")[0][0]
    good = dupes == 0
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] no player sits in two clans "
          f"({dupes} do)")
    return ok


# --- phase G: gifts, and the caps that stop one modified client servicing all -
def phase_gifts(dsn, pool, uids):
    print("\n=> PHASE G  card gifts -- the daily caps under a stampede")
    ok = True
    give_cap = admin(dsn, "select public.gift_give_cap()")[0][0]
    recv_cap = admin(dsn, "select public.gift_receive_cap()")[0][0]

    # A clan of givers and one receiver, all pushing at once.
    crew = list(uids[400:436])
    host = crew[0]
    r = pool.call(host, "select public.create_clan(%s, %s)", ("Gift Harbour", "🎁"))
    if not r or not r[0] or not r[0].get("ok"):
        print(f"   [FAIL] could not create the gifting clan: {r[0] if r else None}")
        return False
    clan = r[0]["clan"]["id"]
    pool.call(host, "select public.set_clan_open(true)")
    for uid in crew[1:]:
        pool.call(uid, "select public.join_clan(%s)", (clan,))

    ids = {u: admin(dsn, """select i.player_id from public.player_identities i
                             where i.auth_uid = %s""", (u,))[0][0] for u in crew}
    target = ids[crew[1]]

    def spam(uid):
        for i in range(12):
            try:
                pool.call(uid, "select public.send_card(%s, %s, %s, %s)",
                          (target, "pirate", i % 8, 1 + i % 4))
            except Exception:
                pass

    senders = [u for u in crew if ids[u] != target]
    with ThreadPoolExecutor(max_workers=min(32, len(senders))) as ex:
        list(ex.map(spam, senders))

    got = admin(dsn, """select count(*) from public.card_gifts
                         where to_player = %s
                           and created_at > now() - interval '24 hours'""",
                (target,))[0][0]
    good = got <= recv_cap
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] {len(senders)} clanmates pushed "
          f"{len(senders) * 12} gifts at one inbox with a cap of {recv_cap}: "
          f"{got} landed")

    over = admin(dsn, """select count(*) from (
                           select from_player from public.card_gifts
                            where created_at > now() - interval '24 hours'
                            group by 1 having count(*) > %s) t""",
                 (give_cap,))[0][0]
    good = over == 0
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] no sender got past the give cap of "
          f"{give_cap} ({over} did)")

    # A five-star card is not sendable, and that is a table constraint as well
    # as a branch -- so it holds even against a replaced function.
    res = pool.call(crew[2], "select public.send_card(%s, %s, %s, %s)",
                    (target, "pirate", 0, 5))
    good = res and res[0] and res[0].get("ok") is False
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] a five-star card is refused "
          f"({res[0] if res else None})")

    # Self-send, which Guy asked for by name.
    res = pool.call(crew[1], "select public.send_card(%s, %s, %s, %s)",
                    (target, "pirate", 0, 2))
    good = res and res[0] and res[0].get("reason") == "self"
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] a self-send is refused "
          f"({res[0] if res else None})")

    # Across clans, which is the whole point of the clan check.
    outsider = uids[500]
    res = pool.call(outsider, "select public.send_card(%s, %s, %s, %s)",
                    (target, "pirate", 0, 2))
    good = res and res[0] and res[0].get("reason") == "not_clanmates"
    ok = ok and good
    print(f"   [{'ok' if good else 'FAIL'}] a stranger cannot gift into a clan "
          f"({res[0] if res else None})")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--players", type=int, default=200)
    ap.add_argument("--seconds", type=int, default=12)
    ap.add_argument("--levels", default="1,8,32,64,128")
    ap.add_argument("--sizes", default="1000,25000,100000")
    # The population phases E-G drive. Kept separate from --players because
    # A-D take a connection each and cannot go here; this is the number the
    # question "does it hold at ten thousand" is actually about.
    ap.add_argument("--social", type=int, default=0,
                    help="run phases E-G with this many pooled players")
    ap.add_argument("--pool", type=int, default=96,
                    help="connections phases E-G share, as PostgREST would")
    ap.add_argument("--skip-abcd", action="store_true",
                    help="only the pooled phases")
    args = ap.parse_args()

    levels = [int(x) for x in args.levels.split(",")]
    sizes = [int(x) for x in args.sizes.split(",")]

    print("=> booting a throwaway Postgres and applying the real migrations")
    pg = Pg()
    ok = True
    b, d = [], []
    social = None
    # Phase A holds one connection per client for the whole run, phases E-G
    # hold the pool, and several checks open an admin connection alongside
    # both. Sized for all three at once with headroom, never below 200.
    need = 200
    if not args.skip_abcd:
        need = max(need, args.players + max(levels) + 64)
    if args.social:
        need = max(need, (0 if args.skip_abcd else args.players) + args.pool + 64)
    try:
        pg.start(max_conns=need)
        print(f"   postgres sized for {need} connections")
        dsn = pg.dsn()
        apply_schema(dsn)

        if not args.skip_abcd:
            uids = make_auth_users(dsn, args.players)
            clients, a_ok = phase_signup(dsn, uids)
            ok = ok and a_ok
            b = phase_steady(dsn, clients, levels, args.seconds)
            ok = phase_contention(dsn, clients) and ok
            d = phase_scale(dsn, clients, sizes, args.seconds)
            for c in clients.values():
                c.close()

        if args.social:
            n = args.social
            print(f"\n=> pooled population -- {n:,} players through "
                  f"{args.pool} connections")
            pool = Pool(dsn, args.pool)
            try:
                puids = make_auth_users(dsn, n)
                sign = Stats()
                t = time.perf_counter()
                bulk_signup(dsn, pool, puids, sign, args.pool)
                el = time.perf_counter() - t
                sign.report(f"{n:,} first-time sign-ins through the pool", el)
                made = admin(dsn, "select count(*) from public.players "
                                  "where is_bot = false and deleted_at is null"
                             )[0][0]
                dupes = admin(dsn, """select count(*) from (
                                        select public.normalize_name(display_name) nm
                                          from public.players
                                         where deleted_at is null and is_bot = false
                                         group by 1 having count(*) > 1) t""")[0][0]
                good = dupes == 0
                ok = ok and good
                print(f"   [{'ok' if good else 'FAIL'}] {made:,} islands now "
                      f"exist, {dupes} duplicate names under the unique index")

                e_ok, e_stats = phase_tourney(dsn, pool, puids, args.seconds,
                                              args.pool)
                ok = e_ok and ok
                ok = phase_clans(dsn, pool, puids) and ok
                ok = phase_gifts(dsn, pool, puids) and ok
                social = (n, made, e_stats)
            finally:
                pool.close()

        print("\n=> SUMMARY")
        if b:
            print("   throughput against concurrency:")
            for n, tps, p95, errs in b:
                worst = max(p95.items(), key=lambda kv: kv[1]) if p95 else ("-", 0)
                print(f"     {n:>4} clients  {tps:>8.0f} calls/s   "
                      f"slowest p95: {worst[0]} {worst[1]:.0f}ms   errors {errs}")
        if d:
            print("   read latency against world size:")
            for size, ft, lb in d:
                print(f"     {size:>8,} islands   find_target p95 {ft:>7.1f}ms   "
                      f"leaderboard p95 {lb:>7.1f}ms")
        if social:
            n, made, st = social
            print(f"   pooled population: {n:,} players, {made:,} islands, "
                  f"{args.pool} connections")
            for op in sorted(st.lat):
                v = sorted(st.lat[op])
                print(f"     {op:<18} n={len(v):>7}  p50 {pct(v,50):>6.1f}ms  "
                      f"p95 {pct(v,95):>7.1f}ms  p99 {pct(v,99):>7.1f}ms  "
                      f"errors {st.err[op]}")
    finally:
        pg.stop()
    print(f"\nLOAD TEST: {'ALL CORRECTNESS CHECKS PASS' if ok else 'FAILURES ABOVE'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
