#!/usr/bin/env python3
"""Read and write the remote config, without opening the dashboard.

    tools/liveops.py show 147 ios        what build 147 on iOS is actually served
    tools/liveops.py list                every row, with its targeting
    tools/liveops.py set clan_chat false --note "abuse report"
    tools/liveops.py set chain_hours 18 --min-build 150
    tools/liveops.py rm clan_chat        back to the compiled default

    tools/liveops.py events               the calendar, and what is running now
    tools/liveops.py schedule deal_chain '{"id":"tide_hunt"}' \\
        --from 2026-10-31T18:00+03:00 --to 2026-11-01T18:00+03:00
    tools/liveops.py unschedule 7         drop one row off the calendar

WHY A CLI AND NOT A DASHBOARD. A dashboard earns its keep when a team runs
live-ops and the calendar has to be legible to somebody who does not write SQL.
There is one person here, and the thing that person actually needs is for the
dangerous command to be hard to get wrong -- which is `show`, below. Every other
subcommand is a row; `show` is the only one that answers the question worth
asking before walking away from the keyboard, and it answers it by asking the
server the same way a phone does.

THE SERVICE ROLE KEY BYPASSES RLS ENTIRELY. It is the highest-value secret in
this project -- higher than the keystore password, because it reads and writes
every player's save. So it is pulled from the login Keychain the way
ship_android.sh pulls the keystore password, and never from a file in the repo
and never from a flag:

    security add-generic-password -a "$USER" -s LOOTLAGOON_SERVICE_KEY -w

An env var is accepted as a fallback for a CI run that has no Keychain, but it
is the worse door: `env` dumps it, shell history may hold the assignment, and a
crash reporter in the same shell can ship it somewhere.

READS USE THE PUBLISHABLE KEY ON PURPOSE. `show` calls the app_config function
with the key that ships inside the app, so what it prints is what a real client
is served -- including whether the anon grant is still in place. Calling it as
service_role would answer even if the grant had been dropped by a later
migration, which is the one failure `show` most needs to catch.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = "loot-lagoon"
KEYCHAIN_ITEM = "LOOTLAGOON_SERVICE_KEY"
TABLE = "app_config"
EVENTS = "app_events"


def die(msg):
    sys.exit("liveops: " + msg)


def project():
    """URL and publishable key, from the file the app itself reads."""
    path = os.path.join(ROOT, "supabase.json")
    if not os.path.exists(path):
        die("no supabase.json at the repo root -- see supabase.example.json")
    with open(path) as f:
        cfg = json.load(f)
    url = cfg.get("url", "").rstrip("/")
    key = cfg.get("publishable_key", "")
    if not url or not key:
        die("supabase.json is missing url or publishable_key")
    return url, key


def service_key():
    out = subprocess.run(
        ["security", "find-generic-password", "-a", os.environ.get("USER", ""),
         "-s", KEYCHAIN_ITEM, "-w"],
        capture_output=True, text=True)
    if out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    env = os.environ.get("SUPABASE_SERVICE_KEY", "").strip()
    if env:
        sys.stderr.write(
            "liveops: using SUPABASE_SERVICE_KEY from the environment. The "
            "Keychain is the better door:\n"
            "    security add-generic-password -a \"$USER\" -s %s -w\n"
            % KEYCHAIN_ITEM)
        return env
    die("no service key. Put it in the login Keychain:\n"
        "    security add-generic-password -a \"$USER\" -s %s -w" % KEYCHAIN_ITEM)


def call(path, key, method="GET", body=None, extra=None):
    url, _ = project()
    req = urllib.request.Request(url + path, method=method)
    req.add_header("apikey", key)
    req.add_header("Authorization", "Bearer " + key)
    req.add_header("Content-Type", "application/json")
    for k, v in (extra or {}).items():
        req.add_header(k, v)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data, timeout=30) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:400]
        die("%s %s -> %s %s\n%s" % (method, path, e.code, e.reason, detail))
    except urllib.error.URLError as e:
        die("cannot reach the project: %s" % e.reason)


# --------------------------------------------------------------------------- #
#  show -- the one that matters
# --------------------------------------------------------------------------- #

def cmd_show(a):
    _, pub = project()
    got = call("/rest/v1/rpc/" + TABLE, pub, "POST",
               {"p_app": a.app, "p_build": a.build, "p_platform": a.platform})
    label = "build %d" % a.build if a.build else "a dev build (sees every row)"
    print("%s, platform %r, app %r is served:" %
          (label, a.platform or "(none)", a.app))
    if not got:
        print("    nothing -- every knob is the one compiled into the build")
        return
    for k in sorted(got):
        print("    %-26s %s" % (k, json.dumps(got[k])))


# --------------------------------------------------------------------------- #
#  list / set / rm
# --------------------------------------------------------------------------- #

def cmd_list(a):
    rows = call("/rest/v1/%s?app=eq.%s&order=key,id" % (TABLE, a.app),
                service_key()) or []
    if not rows:
        print("no rows for %r. Every knob is its compiled default." % a.app)
        return
    print("%-24s %-14s %-9s %-11s %s" %
          ("key", "value", "platform", "builds", "note"))
    for r in rows:
        lo, hi = r["min_build"], r["max_build"]
        builds = "all" if not lo and not hi else "%s..%s" % (lo or 0, hi or "")
        print("%-24s %-14s %-9s %-11s %s" %
              (r["key"], json.dumps(r["value"]), r["platform"] or "-",
               builds, r.get("note", "")))


def cmd_set(a):
    # Parsed as JSON so `false`, `18` and `{"text":"..."}` all mean what they
    # look like -- and a bare word that is not valid JSON becomes a string
    # rather than an error, because `set banner_text back soon` is a reasonable
    # thing to type and `"back soon"` is a reasonable thing to mean.
    try:
        value = json.loads(a.value)
    except json.JSONDecodeError:
        value = a.value

    # WHAT THIS IS ABOUT TO CHANGE, BEFORE IT CHANGES IT. A kill switch is an
    # outward-facing action against every install at once, and the row that was
    # already there is the thing a mistake is measured against.
    key = service_key()
    q = "/rest/v1/%s?app=eq.%s&key=eq.%s&platform=eq.%s&min_build=eq.%d" % (
        TABLE, a.app, a.key, a.platform, a.min_build)
    existing = call(q, key) or []
    print("app       %s" % a.app)
    print("key       %s" % a.key)
    print("value     %s   (was: %s)" % (
        json.dumps(value),
        json.dumps(existing[0]["value"]) if existing else "no row -- compiled default"))
    print("platform  %s" % (a.platform or "every platform"))
    print("builds    %s" % ("every build" if not a.min_build and not a.max_build
                            else "%d..%s" % (a.min_build, a.max_build or "")))
    if isinstance(value, bool) and value is False:
        print("\nThis TURNS A FEATURE OFF for every install it reaches.")
    if not a.yes:
        try:
            if input("\nWrite it? [y/N] ").strip().lower() not in ("y", "yes"):
                die("nothing written")
        except (EOFError, KeyboardInterrupt):
            die("nothing written")

    row = {"app": a.app, "key": a.key, "value": value,
           "platform": a.platform, "min_build": a.min_build,
           "max_build": a.max_build, "note": a.note}
    if existing:
        call(q, key, "PATCH", row)
    else:
        call("/rest/v1/" + TABLE, key, "POST", row)
    print("written. What a build %s sees now:" % (a.min_build or 1))
    cmd_show(argparse.Namespace(app=a.app, build=a.min_build or 1,
                                platform=a.platform))


def cmd_rm(a):
    # DELETING IS NOT HOW A SWITCH IS TAKEN BACK, and the warning says so
    # because the client cannot tell an empty answer from a failed request --
    # it keeps its cached value through both. A phone that cached `false`
    # yesterday and cannot reach the server today still has the feature off,
    # and removing the row does not reach that phone. Setting it to `true` does.
    key = service_key()
    q = "/rest/v1/%s?app=eq.%s&key=eq.%s" % (TABLE, a.app, a.key)
    rows = call(q, key) or []
    if not rows:
        print("no rows for %r in %r. Nothing to remove." % (a.key, a.app))
        return
    for r in rows:
        print("  %s = %s  platform=%s  builds=%s..%s" %
              (r["key"], json.dumps(r["value"]), r["platform"] or "-",
               r["min_build"], r["max_build"] or ""))
    if any(r["value"] is False for r in rows):
        print("\nONE OF THESE IS A LIVE KILL SWITCH. Removing the row stops the"
              "\nSERVER saying 'off', but a phone that already cached 'off' and"
              "\ncannot reach the network keeps it. To actually turn a feature"
              "\nback on for everybody, set it to true instead of removing it.")
    if not a.yes:
        try:
            if input("\nRemove %d row(s)? [y/N] " % len(rows)
                     ).strip().lower() not in ("y", "yes"):
                die("nothing removed")
        except (EOFError, KeyboardInterrupt):
            die("nothing removed")
    call(q, key, "DELETE")
    print("removed %d row(s)." % len(rows))


# --------------------------------------------------------------------------- #
#  the calendar
# --------------------------------------------------------------------------- #

def when(text):
    """An instant, and only ever an unambiguous one.

    AN OFFSET IS REQUIRED and a bare local time is refused. "2026-10-31T18:00"
    means a different moment in every timezone the person typing it might be
    sitting in, and the failure it produces -- an event that runs an hour off,
    or on the wrong side of midnight for half the players -- is invisible until
    it has already happened to everybody. One extra token of typing removes the
    entire class.
    """
    try:
        at = datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        die("cannot read %r as a time. Use ISO 8601 with an offset, e.g.\n"
            "    2026-10-31T18:00+03:00    (Israel winter)\n"
            "    2026-10-31T15:00Z         (the same instant, in UTC)" % text)
    if at.tzinfo is None:
        die("%r has no timezone offset, so it names a different instant in\n"
            "every timezone. Add one: %s+03:00 for Israel winter, or Z for UTC."
            % (text, text))
    return at.isoformat()


def human(seconds):
    """'in 3h 20m' / 'running, 2d 4h left' -- the sanity check before walking away."""
    s = abs(int(seconds))
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    mi = s // 60
    parts = ([("%dd" % d)] if d else []) + ([("%dh" % h)] if h else []) + \
            ([("%dm" % mi)] if mi and not d else [])
    return " ".join(parts) or "under a minute"


def cmd_events(a):
    # BOTH HALVES, because they answer different questions. The table says what
    # was planned; the function says what a phone is actually handed, and the
    # two differ whenever a row is targeted at a build or a platform -- which is
    # exactly when a mistake is hardest to see.
    rows = call("/rest/v1/%s?app=eq.%s&order=starts_at&select=*"
                % (EVENTS, a.app), service_key()) or []
    if not rows:
        print("nothing on the calendar for %r. The rotation runs on its own clock."
              % a.app)
    else:
        print("%-4s %-12s %-22s %-26s %-26s %s" %
              ("id", "kind", "payload", "from", "to", "note"))
        for r in rows:
            print("%-4s %-12s %-22s %-26s %-26s %s" %
                  (r["id"], r["kind"], json.dumps(r["payload"])[:22],
                   r["starts_at"], r["ends_at"], r.get("note", "")))
    _, pub = project()
    got = call("/rest/v1/rpc/" + EVENTS, pub, "POST",
               {"p_app": a.app, "p_build": a.build, "p_platform": a.platform,
                "p_horizon_hours": a.horizon}) or []
    label = "build %d" % a.build if a.build else "a dev build"
    print("\nwhat %s on %r is handed, over the next %dh:"
          % (label, a.platform or "(no platform)", a.horizon))
    if not got:
        print("    nothing -- the rotation runs on its own clock")
        return
    for e in got:
        starts, ends = e["starts_in"], e["ends_in"]
        state = ("RUNNING, %s left" % human(ends)) if starts <= 0 \
            else ("starts in %s, runs %s" % (human(starts), human(ends - starts)))
        print("    %-12s %-24s %s" % (e["kind"], json.dumps(e["payload"]), state))


def cmd_schedule(a):
    try:
        payload = json.loads(a.payload)
    except json.JSONDecodeError:
        die("payload must be JSON, e.g. '{\"id\":\"tide_hunt\"}'")
    if not isinstance(payload, dict):
        die("payload must be a JSON object, not %s" % type(payload).__name__)
    starts, ends = when(a.start), when(a.end)
    if ends <= starts:
        die("the window ends before it starts")

    # A deal_chain row naming a chain the build does not have is not an error
    # -- the client falls back to its rotation -- but it is almost always a typo,
    # and the one place to catch it is before it is written.
    if a.kind == "deal_chain":
        known = known_chain_ids()
        if known and payload.get("id") not in known:
            print("WARNING: %r is not a chain in deals.gd. Known: %s"
                  % (payload.get("id"), ", ".join(sorted(known))))
            print("The client would fall back to its rotation for this window.")

    print("app       %s" % a.app)
    print("kind      %s" % a.kind)
    print("payload   %s" % json.dumps(payload))
    print("from      %s" % starts)
    print("to        %s" % ends)
    print("platform  %s" % (a.platform or "every platform"))
    print("builds    %s" % ("every build" if not a.min_build and not a.max_build
                            else "%d..%s" % (a.min_build, a.max_build or "")))
    print("\nThis RUNS AN EVENT FOR EVERY PLAYER it reaches, on those dates.")
    if not a.yes:
        try:
            if input("\nSchedule it? [y/N] ").strip().lower() not in ("y", "yes"):
                die("nothing scheduled")
        except (EOFError, KeyboardInterrupt):
            die("nothing scheduled")
    call("/rest/v1/" + EVENTS, service_key(), "POST",
         {"app": a.app, "kind": a.kind, "payload": payload,
          "starts_at": starts, "ends_at": ends, "platform": a.platform,
          "min_build": a.min_build, "max_build": a.max_build, "note": a.note})
    print("scheduled.")
    cmd_events(argparse.Namespace(app=a.app, build=a.min_build or 0,
                                  platform=a.platform, horizon=24 * 90))


def known_chain_ids():
    """Every `"id"` in deals.gd, which is a SUPERSET of the deal chains.

    It also picks up the powerups, the fairs and the mission keys, so the check
    in front of a schedule is permissive: it catches `tide_hnut` and would let
    `pu_deckhand` through. That is the right direction for a warning -- a false
    alarm on a legitimate id would teach somebody to stop reading them, and the
    client already treats an id it does not have as "run the rotation" rather
    than as an error. Parsing the CHAINS block specifically would be a stricter
    check and a more fragile one.
    """
    path = os.path.join(ROOT, "scripts", "deals.gd")
    if not os.path.exists(path):
        return set()
    with open(path) as f:
        return set(re.findall(r'"id"\s*:\s*"([a-z_]+)"', f.read()))


def cmd_unschedule(a):
    key = service_key()
    q = "/rest/v1/%s?app=eq.%s&id=eq.%d" % (EVENTS, a.app, a.id)
    rows = call(q, key) or []
    if not rows:
        print("no event %d in %r." % (a.id, a.app))
        return
    r = rows[0]
    print("  %s %s  %s -> %s" % (r["kind"], json.dumps(r["payload"]),
                                 r["starts_at"], r["ends_at"]))
    # Unlike a kill switch, removing this REACHES every phone that asks again:
    # the calendar is not cached to disk, so a cancelled event really does stop.
    # A phone mid-event keeps the chain it already started, which is the
    # no-rug-pull rule the client applies to every other way a chain can end.
    print("\nPhones pick this up on their next fetch. One that has ALREADY"
          "\nstarted the chain keeps it until its own deadline -- cancelling a"
          "\nwindow never takes a ladder away from somebody standing on it.")
    if not a.yes:
        try:
            if input("\nUnschedule it? [y/N] ").strip().lower() not in ("y", "yes"):
                die("nothing removed")
        except (EOFError, KeyboardInterrupt):
            die("nothing removed")
    call(q, key, "DELETE")
    print("unscheduled.")


def main():
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--app", default=APP, help="which game (default: %s)" % APP)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("show", help="what a given build is actually served")
    s.add_argument("build", type=int, nargs="?", default=0,
                   help="build number; 0 or omitted means a dev build")
    s.add_argument("platform", nargs="?", default="",
                   choices=["", "ios", "android"])
    s.set_defaults(fn=cmd_show)

    s = sub.add_parser("list", help="every row, with its targeting")
    s.set_defaults(fn=cmd_list)

    s = sub.add_parser("set", help="write a knob")
    s.add_argument("key")
    s.add_argument("value", help="JSON: false, true, 18, '{\"text\":\"hi\"}'")
    s.add_argument("--platform", default="", choices=["", "ios", "android"])
    s.add_argument("--min-build", type=int, default=0, dest="min_build")
    s.add_argument("--max-build", type=int, default=0, dest="max_build")
    s.add_argument("--note", default="", help="why, for whoever reads this later")
    s.add_argument("--yes", action="store_true", help="skip the confirmation")
    s.set_defaults(fn=cmd_set)

    s = sub.add_parser("rm", help="drop a knob back to its compiled default")
    s.add_argument("key")
    s.add_argument("--yes", action="store_true")
    s.set_defaults(fn=cmd_rm)

    s = sub.add_parser("events", help="the calendar, and what is running now")
    s.add_argument("build", type=int, nargs="?", default=0)
    s.add_argument("platform", nargs="?", default="", choices=["", "ios", "android"])
    s.add_argument("--horizon", type=int, default=72,
                   help="hours ahead to ask about (default 72)")
    s.set_defaults(fn=cmd_events)

    s = sub.add_parser("schedule", help="put an event on a date")
    s.add_argument("kind", help="deal_chain")
    s.add_argument("payload", help="JSON object, e.g. '{\"id\":\"tide_hunt\"}'")
    s.add_argument("--from", required=True, dest="start",
                   help="ISO 8601 WITH an offset: 2026-10-31T18:00+03:00")
    s.add_argument("--to", required=True, dest="end")
    s.add_argument("--platform", default="", choices=["", "ios", "android"])
    s.add_argument("--min-build", type=int, default=0, dest="min_build")
    s.add_argument("--max-build", type=int, default=0, dest="max_build")
    s.add_argument("--note", default="")
    s.add_argument("--yes", action="store_true")
    s.set_defaults(fn=cmd_schedule)

    s = sub.add_parser("unschedule", help="drop one row off the calendar")
    s.add_argument("id", type=int, help="the id from `events`")
    s.add_argument("--yes", action="store_true")
    s.set_defaults(fn=cmd_unschedule)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
