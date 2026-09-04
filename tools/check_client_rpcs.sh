#!/usr/bin/env bash
# Does the shipped client still fit the schema? Every RPC cloud.gd calls, with
# the exact argument names it sends, resolved against the migrations as they
# stand.
#
# This exists because of the shape of this project rather than out of caution.
# The client ships AHEAD of the schema -- a build sits in TestFlight for weeks
# while migrations land underneath it -- so "the migration is valid" and "the
# phones in people's pockets still work" are different questions, and
# validate_migrations.sh only answers the first. An argument renamed in SQL is
# not a compile error anywhere; it is a PGRST202 on a real player's phone, and
# the first sign of it is a support email.
#
# The list below is maintained by hand against cloud.gd. Adding an RPC there
# means adding a line here.
set -euo pipefail
ROOT="/Users/guymaslawi/Documents/my_apps/steam-game"
PG="/opt/homebrew/opt/postgresql@17/bin"
S="$(dirname "$0")"
WORK="$(mktemp -d)"
cleanup(){ "$PG/pg_ctl" -D "$WORK/data" -s -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
"$PG/initdb" -D "$WORK/data" -U postgres --auth=trust >/dev/null
"$PG/pg_ctl" -D "$WORK/data" -o "-k $WORK -c listen_addresses=''" -l "$WORK/log" -w start >/dev/null
export PGHOST="$WORK" PGUSER=postgres PGDATABASE=postgres
PSQL=("$PG/psql" -v ON_ERROR_STOP=1 -q --no-psqlrc)
sed -n "/create role anon/,/^STUB$/p" "$ROOT/tools/validate_migrations.sh" | sed '$d' | "${PSQL[@]}" >/dev/null
for f in "$ROOT"/supabase/migrations/*.sql; do "${PSQL[@]}" -f "$f" >/dev/null; done

fails=0
# fn:arg,arg,...  exactly as cloud.gd builds each body.
while IFS=: read -r fn args; do
  [ -z "$fn" ] && continue
  n=$("${PSQL[@]}" -tAc "
    select count(*) from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='public' and p.proname='$fn'
       and (select coalesce(bool_and(a = any(coalesce(p.proargnames,'{}'))), true)
              from unnest(string_to_array(nullif('$args',''), ',')) a)")
  if [ "$n" = "0" ]; then echo "    MISMATCH $fn($args)"; fails=$((fails+1))
  else echo "    ok $fn($args)"; fi
done <<'RPC'
claim_player:p_save,p_display_name,p_emoji,p_rank_stars,p_island_level,p_vault_coins,p_shields,p_buildings
push_save:p_save,p_rank_stars,p_island_level,p_vault_coins,p_shields,p_buildings,p_force
find_target:p_mode
record_raid:p_victim,p_mode,p_coins,p_hut
unseen_raids:
ack_raids:p_ids
set_display_name:p_name
set_emoji:p_emoji
report_diagnostics:p_install,p_platform,p_os,p_model,p_build,p_events
report_player:p_player,p_reason
leaderboard:p_limit
tourney_report:p_tourney_id,p_points
tourney_board:p_limit
tourney_result:p_tourney_id
create_link_token:
my_identities:
redeem_link_token:p_token
delete_account:
server_time:
my_clan:
clan_list:p_limit
create_clan:p_name,p_emoji
join_clan:p_clan
leave_clan:
gift_budget:
send_card:p_to,p_set,p_idx,p_stars
unseen_gifts:
ack_gifts:p_ids
clan_news:
my_clan_invites:
accept_clan_invite:p_id
decline_clan_invite:p_id
invite_to_clan:p_to
request_join_clan:p_clan
clan_join_requests:
answer_clan_request:p_id,p_accept
set_clan_open:p_open
find_players:p_query,p_limit
RPC
echo
[ "$fails" -eq 0 ] && echo "every RPC the client calls still resolves" || echo "$fails MISMATCH(ES)"
exit "$fails"
