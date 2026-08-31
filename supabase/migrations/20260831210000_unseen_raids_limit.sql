-- =============================================================================
--  The limit on unseen_raids has never limited anything
-- =============================================================================
--
-- Written as:
--
--     select jsonb_agg(jsonb_build_object(...) order by r.created_at)
--       from public.raids r
--      where r.victim = v_me and r.seen_at is null
--      limit 50
--
-- There is no GROUP BY, so the aggregate collapses every matching row into ONE
-- result row, and LIMIT 50 then limits the number of RESULT rows -- which was
-- already one. It is not a smaller answer; it is the same answer with a clause
-- attached that does nothing. Measured rather than reasoned about: 300 raids in
-- the table, 300 in the response.
--
-- The correct shape is four lines below it in the same file. `leaderboard`
-- takes its LIMIT inside the subquery, where it bounds the rows being fed to
-- jsonb_agg, and that is what this copies.
--
-- WHY IT IS WORTH A MIGRATION rather than a note. main.gd remembers the raid
-- ids it has applied in `applied_raids`, capped at APPLIED_RAIDS_KEEP = 200,
-- and _on_cloud_raids applies anything whose id is not in that list. The cap is
-- sized against a response that was believed to hold at most 50. With the limit
-- doing nothing, a player who comes back to more than 200 unseen raids gets all
-- of them at once, the oldest ids fall off the end of the dedupe list, and if
-- ack_raids does not land -- it retries three times and then stops, because the
-- radio is the usual reason it fails -- the server sends the same raids again
-- on the next launch and the ones that fell off are applied A SECOND TIME. The
-- coins come out twice. That is the exact failure the applied_raids list was
-- added to close, reopened by an arithmetic assumption underneath it.
--
-- It is also just a large response to send to a phone: every unseen raid this
-- player has ever accumulated, each carrying a public_player() blob.
--
-- Fifty is kept as the number rather than raised. Anything left over is still
-- unseen on the server and arrives on the next fetch, so nothing is lost -- and
-- fifty against a 200-entry dedupe list leaves three whole fetches of headroom.

create or replace function public.unseen_raids()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'id',    x.id,
                   'mode',  x.mode,
                   'coins', x.coins,
                   'hut',   x.hut,
                   'at',    extract(epoch from x.created_at),
                   'by',    public.public_player(x.attacker))
               order by x.created_at)
          from (select r.id, r.mode, r.coins, r.hut, r.created_at, r.attacker
                  from public.raids r
                 where r.victim = v_me and r.seen_at is null
                 order by r.created_at
                 limit 50) x), '[]'::jsonb);
end;
$$;

-- Recreating a function resets its privileges to the default, which for a
-- SECURITY DEFINER function that reads another player's row is not something to
-- leave to the default. Same three lines migration 190000 ends with, and for
-- the same reason.
revoke all on function public.unseen_raids() from public, anon;
grant execute on function public.unseen_raids() to authenticated;
