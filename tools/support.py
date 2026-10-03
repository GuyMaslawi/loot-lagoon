#!/usr/bin/env python3
"""The support desk: find one player, read the report queue, answer the mail.

    tools/support.py who <id|name|install-id>   who is this, and what have they paid
    tools/support.py receipts <id|install-id>   every receipt, including guests'
    tools/support.py reports [--all]            the moderation queue
    tools/support.py seen <report-id>           mark one report reviewed

SEPARATE FROM liveops.py ON PURPOSE. That tool changes the GAME -- switches,
event windows, things with no personal data anywhere near them. This one reads
PEOPLE: names, balances, purchases, who reported whom. They happen to share a
key, and that is the only thing they share; keeping them in one file would mean
every "what's scheduled?" ran out of a tool that can also dump a player's
purchase history, and the habit of reaching for it would be the problem.

WHAT THIS CANNOT DO, and deliberately. There is no grant, no refund, no edit.
Every command here READS, except `seen`, which stamps a report as looked at.
Fixing a player's state means a deliberate SQL statement written for that player
after their case is understood -- not a flag on a support tool that gets reached
for at two in the morning. The read is the hard part and the part that was
missing; the write should stay hard.

Reads as the service role, out of the login Keychain -- see liveops.py for why
that door and not an environment variable.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import liveops  # noqa: E402  -- the key, the project and the HTTP shape


def rpc(fn, body):
    return liveops.call("/rest/v1/rpc/" + fn, liveops.service_key(), "POST", body)


def fmt_when(ts):
    return (ts or "")[:19].replace("T", " ") or "-"


# --------------------------------------------------------------------------- #
#  who
# --------------------------------------------------------------------------- #

def cmd_who(a):
    rows = rpc("support_find_player", {"p_query": a.query, "p_limit": a.limit}) or []
    if not rows:
        print("no player matches %r." % a.query)
        # The case most likely to be behind an angry email: a guest paid, so
        # there is no player row at all and only the receipt remembers them.
        rec = rpc("support_find_receipts", {"p_query": a.query, "p_limit": 20}) or []
        if rec:
            print("\nBUT %d RECEIPT(S) CARRY THAT ID. This is probably a guest who"
                  "\npaid without signing in -- there is no island to look at, and"
                  "\nthe purchase is real:" % len(rec))
            _print_receipts(rec)
        else:
            print("Nothing under that id in receipts either. If they quoted a"
                  "\nsupport id from the game, it is a guest install that has"
                  "\nnever reached the server -- their save is on their phone"
                  "\nonly, and nothing here can restore it.")
        return
    for r in rows:
        print("=" * 64)
        print("%s %s   island %s   %s stars" %
              (r.get("emoji", ""), r.get("display_name", "?"),
               r.get("island_level"), r.get("rank_stars")))
        print("  id          %s" % r.get("id"))
        print("  holds       %s coins, %s shields" %
              (f"{r.get('vault_coins', 0):,}", r.get("shields")))
        signs = r.get("sign_ins") or []
        print("  sign-in     %s" % (", ".join(signs) if signs else
              "NONE -- claim-only island, so there is nothing to restore it from"))
        print("  first seen  %s" % fmt_when(r.get("created_at")))
        print("  last seen   %s" % fmt_when(r.get("last_seen")))
        if r.get("deleted_at"):
            print("  DELETED     %s" % fmt_when(r["deleted_at"]))
        if r.get("is_bot"):
            print("  NOTE        this is a seeded bot, not a person")
        if r.get("reports_against"):
            print("  REPORTED    %s time(s) against them" % r["reports_against"])
        verdicts = r.get("receipts_by_verdict") or {}
        if verdicts:
            print("  paid        %s" % ", ".join(
                "%s x%d" % (k, v) for k, v in sorted(verdicts.items())))
            _print_receipts(r.get("recent_receipts") or [], indent="    ")
        else:
            print("  paid        nothing on record")


def _print_receipts(rows, indent="  "):
    for x in rows:
        line = "%s%s  %-10s %-14s %s" % (
            indent, fmt_when(x.get("created_at")), x.get("platform", ""),
            x.get("product_id", ""), x.get("verdict", ""))
        if x.get("detail"):
            line += "  (%s)" % x["detail"]
        print(line)


def cmd_receipts(a):
    rows = rpc("support_find_receipts", {"p_query": a.query, "p_limit": a.limit}) or []
    if not rows:
        print("no receipt carries %r." % a.query)
        return
    for x in rows:
        print("%s  %-8s %-14s %-9s install=%s player=%s" % (
            fmt_when(x.get("created_at")), x.get("platform"), x.get("product_id"),
            x.get("verdict"), x.get("install_id") or "-", x.get("player") or "-"))
        if x.get("detail"):
            print("    %s" % x["detail"])


# --------------------------------------------------------------------------- #
#  the queue
# --------------------------------------------------------------------------- #

def cmd_reports(a):
    rows = rpc("support_reports",
               {"p_open_only": not a.all, "p_limit": a.limit}) or []
    if not rows:
        print("nothing open in the queue." if not a.all else "no reports at all.")
        return
    # Ordered by how many DISTINCT people reported the same person: one report
    # is an argument, twenty is a pattern, and only the pattern is worth acting
    # on before reading anything.
    print("%-5s %-22s %-8s %-20s %s" %
          ("by", "reported", "reason", "when", "report id"))
    for r in rows:
        mark = "  <-- PATTERN" if r.get("reporters", 0) >= 3 else ""
        seen = "" if not r.get("reviewed_at") else "  [seen]"
        print("%-5s %-22s %-8s %-20s %s%s%s" % (
            r.get("reporters"),
            ("%s %s" % (r.get("reported_emoji", ""),
                        r.get("reported_name", "?")))[:22],
            r.get("reason", ""), fmt_when(r.get("created_at")),
            r.get("id"), mark, seen))
    print("\n`support.py who <reported id>` for the account, "
          "`support.py seen <report id>` once handled.")


def cmd_seen(a):
    res = rpc("support_review_report", {"p_id": a.id}) or {}
    if not res.get("ok"):
        liveops.die(res.get("error", "could not mark it"))
    # Stamped, never deleted: the row is the evidence that a report was received
    # and looked at, which is what a store asks about.
    print("marked reviewed." if not res.get("already") else "already reviewed.")


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("who", help="find a player by id, name or install id")
    s.add_argument("query")
    s.add_argument("--limit", type=int, default=10)
    s.set_defaults(fn=cmd_who)

    s = sub.add_parser("receipts", help="every receipt under an id")
    s.add_argument("query")
    s.add_argument("--limit", type=int, default=20)
    s.set_defaults(fn=cmd_receipts)

    s = sub.add_parser("reports", help="the moderation queue")
    s.add_argument("--all", action="store_true", help="include ones already seen")
    s.add_argument("--limit", type=int, default=50)
    s.set_defaults(fn=cmd_reports)

    s = sub.add_parser("seen", help="mark one report reviewed")
    s.add_argument("id")
    s.set_defaults(fn=cmd_seen)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
