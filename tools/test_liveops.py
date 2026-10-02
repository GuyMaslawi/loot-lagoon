"""Exercises tools/liveops.py against a stub that speaks the slice of PostgREST
the CLI uses.

    python3 tools/test_liveops.py

What this covers that test_migrations.sql cannot: the HTTP shape, WHICH KEY goes
on which request, the value grammar, and the guards -- the timezone refusal and
the warnings in front of a write. The SQL resolution rules are tested properly
against a real Postgres over there; the stub here reimplements only enough of
them to tell one row from another.

Never touches the live project: `project` and `service_key` are replaced before
anything runs, so there is no path from this file to a real key.
"""
import importlib.util, io, json, sys, threading, contextlib
from http.server import BaseHTTPRequestHandler, HTTPServer

spec = importlib.util.spec_from_file_location(
    "liveops", "/Users/guymaslawi/Documents/my_apps/steam-game/tools/liveops.py")
lo = importlib.util.module_from_spec(spec); spec.loader.exec_module(lo)

ROWS = []
NEXT_ID = 1
SEEN = []          # (method, path, apikey)

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n)) if n else None
    def _send(self, obj, code=200):
        raw = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw))); self.end_headers()
        self.wfile.write(raw)
    def do_POST(self):
        SEEN.append(("POST", self.path, self.headers.get("apikey")))
        b = self._body()
        if self.path.endswith("/rpc/app_events"):
            # The window arithmetic the real function does in SQL: absolute
            # timestamps in the table, SECONDS on the wire. Reimplemented here
            # only far enough to tell a running row from a future one.
            import datetime as _dt
            now = _dt.datetime.now(_dt.timezone.utc)
            out = []
            for r in ROWS:
                if r.get("app") != b["p_app"] or "starts_at" not in r:
                    continue
                st = _dt.datetime.fromisoformat(r["starts_at"])
                en = _dt.datetime.fromisoformat(r["ends_at"])
                if en <= now:
                    continue
                if (st - now).total_seconds() > b["p_horizon_hours"] * 3600:
                    continue
                out.append({"kind": r["kind"], "payload": r["payload"],
                            "starts_in": round((st - now).total_seconds()),
                            "ends_in": round((en - now).total_seconds())})
            out.sort(key=lambda e: e["starts_in"])
            return self._send(out)
        if self.path.endswith("/rpc/app_config"):
            # The resolution the real function does, narrowed to what we assert.
            out = {}
            for r in sorted(ROWS, key=lambda r: (r["platform"] == "", -r["min_build"])):
                if r["app"] != b["p_app"]: continue
                bd = b["p_build"]
                if bd and not (bd >= r["min_build"] and (not r["max_build"] or bd <= r["max_build"])):
                    continue
                if r["platform"] and r["platform"] != b["p_platform"]: continue
                out.setdefault(r["key"], r["value"])
            return self._send(out)
        # The real table hands out an id from a bigserial; a stub that did not
        # would let a KeyError in the CLI pass as a stub bug.
        global NEXT_ID
        b.setdefault("id", NEXT_ID); NEXT_ID += 1
        if "/rpc/" in self.path:
            return self._send({}, 200)
        ROWS.append(b); self._send(None, 201)
    def _match(self):
        """The `col=eq.value` filters PostgREST takes, applied to ROWS."""
        want = {}
        for part in self.path.split("?", 1)[-1].split("&"):
            if "=eq." in part:
                k, v = part.split("=eq.", 1)
                want[k] = v
        return [r for r in ROWS if all(str(r.get(k, "")) == v
                                       for k, v in want.items())]

    def do_GET(self):
        SEEN.append(("GET", self.path, self.headers.get("apikey")))
        self._send(self._match())
    def do_PATCH(self):
        SEEN.append(("PATCH", self.path, self.headers.get("apikey")))
        b = self._body()
        for r in ROWS:
            if r["key"] == b["key"] and r["app"] == b["app"]: r.update(b)
        self._send(None, 204)
    def do_DELETE(self):
        SEEN.append(("DELETE", self.path, self.headers.get("apikey")))
        doomed = [id(r) for r in self._match()]
        ROWS[:] = [r for r in ROWS if id(r) not in doomed]
        self._send(None, 204)

srv = HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d" % srv.server_port
lo.project = lambda: (URL, "PUBLISHABLE")
lo.service_key = lambda: "SERVICE"

fails = []
def ck(name, ok, detail=""):
    print("  [%s] %s %s" % ("ok" if ok else "FAIL", name, detail))
    if not ok: fails.append(name)

def run(fn, **kw):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fn(lo.argparse.Namespace(**kw))
    return buf.getvalue()

print("-- show, on an empty table --")
out = run(lo.cmd_show, app="loot-lagoon", build=147, platform="ios")
ck("an empty project reports the compiled defaults", "compiled into the build" in out, out.strip())
ck("and the read used the PUBLISHABLE key, as a phone does",
   SEEN[-1][2] == "PUBLISHABLE", str(SEEN[-1]))

print("-- set --")
out = run(lo.cmd_set, app="loot-lagoon", key="clan_chat", value="false",
          platform="", min_build=0, max_build=0, note="abuse", yes=True)
ck("a write lands", len(ROWS) == 1 and ROWS[0]["value"] is False, str(ROWS))
ck("the value was parsed as JSON, not as the string 'false'",
   ROWS[0]["value"] is False, repr(ROWS[0]["value"]))
ck("a write that turns a feature off says so out loud",
   "TURNS A FEATURE OFF" in out, out.strip()[:120])
ck("and the write used the SERVICE key",
   any(s[0] == "POST" and s[2] == "SERVICE" for s in SEEN), str(SEEN[-2:]))
ck("set echoes back what a build now sees", "clan_chat" in out, out.strip()[-200:])

print("-- the value grammar --")
run(lo.cmd_set, app="loot-lagoon", key="chain_hours", value="18", platform="",
    min_build=150, max_build=0, note="", yes=True)
ck("a bare number is a number", any(r["key"] == "chain_hours" and r["value"] == 18 for r in ROWS))
run(lo.cmd_set, app="loot-lagoon", key="banner", value='{"text":"back soon"}',
    platform="", min_build=0, max_build=0, note="", yes=True)
ck("an object survives", any(r["key"] == "banner" and r["value"] == {"text": "back soon"} for r in ROWS))
run(lo.cmd_set, app="loot-lagoon", key="motd", value="back soon", platform="",
    min_build=0, max_build=0, note="", yes=True)
ck("and a bare word becomes a string rather than an error",
   any(r["key"] == "motd" and r["value"] == "back soon" for r in ROWS))

print("-- show, with rows, and the build range --")
out = run(lo.cmd_show, app="loot-lagoon", build=149, platform="ios")
ck("build 149 is below the chain_hours floor and does not see it",
   "chain_hours" not in out, out.strip())
out = run(lo.cmd_show, app="loot-lagoon", build=150, platform="ios")
ck("build 150 sees it", "chain_hours" in out, out.strip())
out = run(lo.cmd_show, app="loot-lagoon", build=0, platform="")
ck("a dev build is told it sees everything", "dev build" in out, out.strip()[:80])

print("-- list --")
out = run(lo.cmd_list, app="loot-lagoon")
ck("every row is listed", all(k in out for k in ["clan_chat", "chain_hours", "banner", "motd"]))
ck("and the targeting is shown", "150.." in out, out.strip())
out = run(lo.cmd_list, app="game-two")
ck("another game's listing is empty", "no rows" in out, out.strip())

print("-- rm --")
out = run(lo.cmd_rm, app="loot-lagoon", key="clan_chat", yes=True)
ck("the row goes", not any(r["key"] == "clan_chat" for r in ROWS), str([r["key"] for r in ROWS]))
ck("removing a live kill switch warns that a cached phone keeps it",
   "LIVE KILL SWITCH" in out, out.strip()[:200])
out = run(lo.cmd_rm, app="loot-lagoon", key="nothing_here", yes=True)
ck("removing what is not there is not an error", "Nothing to remove" in out, out.strip())

# --------------------------------------------------------------------------- #
#  the calendar
# --------------------------------------------------------------------------- #

print("-- the timezone guard --")
import datetime
for bad in ["2026-10-31T18:00", "2026-10-31", "next tuesday"]:
    try:
        lo.when(bad); ck("a time without an offset is refused: %r" % bad, False)
    except SystemExit as e:
        ck("a time without an offset is refused: %r" % bad,
           "offset" in str(e) or "cannot read" in str(e))
ck("and one with an offset is taken", lo.when("2026-10-31T18:00+03:00").startswith("2026-10-31T18:00"))
ck("Z is an offset too", lo.when("2026-10-31T15:00Z").endswith("+00:00"))
ck("the two above are the SAME instant",
   datetime.datetime.fromisoformat(lo.when("2026-10-31T18:00+03:00"))
   == datetime.datetime.fromisoformat(lo.when("2026-10-31T15:00Z")))

print("-- scheduling --")
ROWS[:] = []
out = run(lo.cmd_schedule, app="loot-lagoon", kind="deal_chain",
          payload='{"id":"tide_hunt"}', start="2026-10-31T18:00+03:00",
          end="2026-11-01T18:00+03:00", platform="", min_build=0, max_build=0,
          note="halloween", yes=True)
ck("the event lands", any(r.get("kind") == "deal_chain" for r in ROWS), str(ROWS))
ck("with its window as unambiguous instants",
   any("+03:00" in str(r.get("starts_at", "")) for r in ROWS), str(ROWS))
ck("and scheduling says out loud that it runs for everybody",
   "RUNS AN EVENT FOR EVERY PLAYER" in out, out.strip()[:160])

out = run(lo.cmd_schedule, app="loot-lagoon", kind="deal_chain",
          payload='{"id":"not_a_real_chain"}', start="2026-12-01T00:00Z",
          end="2026-12-02T00:00Z", platform="", min_build=0, max_build=0,
          note="", yes=True)
ck("a chain id that is not in deals.gd is warned about, not silently accepted",
   "not a chain in deals.gd" in out, out.strip()[:200])
ck("and the real chain ids were read out of the source",
   "tide_hunt" in lo.known_chain_ids(), str(sorted(lo.known_chain_ids()))[:120])

print("-- reading the calendar back --")
out = run(lo.cmd_events, app="loot-lagoon", build=150, platform="ios", horizon=72)
ck("the planned rows are listed", "deal_chain" in out and "halloween" in out)
ck("and what a phone is handed is shown separately", "is handed" in out, out.strip()[-200:])

print("-- unscheduling --")
rid = [r for r in ROWS if r.get("kind") == "deal_chain"][0]["id"]
out = run(lo.cmd_unschedule, app="loot-lagoon", id=rid, yes=True)
ck("the row goes", not any(r.get("id") == rid for r in ROWS), str(len(ROWS)))
ck("and cancelling explains that a ladder in progress is never taken away",
   "never takes a ladder away" in out, out.strip()[:240])
out = run(lo.cmd_unschedule, app="loot-lagoon", id=9999, yes=True)
ck("unscheduling what is not there is not an error", "no event 9999" in out)

print("\nLIVEOPS: %s" % ("ALL PASS" if not fails else "%d FAILURES: %s" % (len(fails), fails)))
sys.exit(1 if fails else 0)
