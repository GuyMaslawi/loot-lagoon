-- =============================================================================
--  The bots were calibrated against a human score that does not exist
-- =============================================================================
--
-- Guy, 2026-09-07: "sort the tournament bots out so they are OK." He was right
-- to ask, and the reason is a consequence of the build fix in build 103 rather
-- than anything the bots themselves do wrong.
--
-- THE THING THAT WAS ASSUMED AND IS NOT TRUE: that a player's tournament score
-- grows with their island. It does not, and it never did. A raid scores
-- `TP_ATTACK x bet` / `TP_STEAL x bet`, the triple rate is the same on every
-- island in the game, and since build 103 the build term is a flat cap. So a
-- player's 72-hour total depends on ONE thing -- how many spins they played --
-- and is identical in league 1 and league 10:
--
--     casual  150 spins/day   ->  1,294 points
--     regular 350 spins/day   ->  2,620
--     heavy   800 spins/day   ->  5,604
--
-- The bot finish, meanwhile, was `700 + 60 x island_level`, which climbs from a
-- span of 880 in league 1 to 2,500 in league 10. Against a flat human score
-- that is a field which gets harder for no reason, and it broke the one
-- property the bots are FOR:
--
--   "They are the floor, not the ceiling -- somebody playing properly passes
--    all of them, which is deliberate."   (20260902120000_tournament.sql)
--
-- Measured against the expected top of twelve md5 draws, that sentence was true
-- in leagues 1, 2 and 3 and false in the other seven:
--
--     league    top bot    vs a casual player
--        1         812           63%
--        4       1,311          101%     <- the invariant breaks here
--        7       1,809          140%
--       10       2,308          178%
--
-- A casual player in the top league was finishing below eight of the twelve
-- bots on a board whose whole job is to be climbable.
--
-- WHY THE SLOPE SURVIVES AT ALL, rather than going flat. Nothing in the scoring
-- justifies it any more, but something outside the scoring does: a player who
-- has reached island 28 has been at this for weeks and probably plays more per
-- day than someone on island 2. That is an engagement proxy, not an economy
-- one, so it is worth a gentle tilt and not a steep one. The old slope was
-- steep because it was reasoning about the ECONOMY -- "a league's numbers grow
-- with it" -- and tournament points do not ride the economy curve.
--
-- 750 + 20, chosen so the low leagues do not move and the top ones come back:
--
--     league     was      now     vs a casual player
--        1        812      748          58%
--       10      2,308    1,246          96%
--
-- League 1 is where it was -- a first tournament should stay winnable -- and
-- the top bot in league 10 now lands just under a casual player's cycle, so the
-- invariant holds in ALL TEN leagues. A regular player clears the whole field
-- comfortably in every one of them, which is the point.
--
-- The pace curve, the md5 derivation, the immutability and the signature are
-- all untouched. `create or replace` is correct here BECAUSE the parameter list
-- does not move -- see the note in 20260902160000_tourney_bot_pace.sql, which
-- had to DROP instead: Postgres overloads on the argument list, and PostgREST
-- resolving a call against two candidates is a 300 that only appears on a real
-- phone. Changing constants inside a body has none of that hazard.
--
-- `_local_tourney_points` in scripts/main.gd carries the same two numbers for
-- the signed-out board and MUST move with this. They are named constants there
-- (TOURNEY_BOT_BASE / TOURNEY_BOT_SLOPE) so the pair is greppable.
create or replace function public.tourney_bot_points(
        p_id uuid, p_cycle integer, p_level integer, p_progress double precision)
returns integer
language sql
immutable
set search_path = ''
as $$
    select round(
        -- The final total. 750 + 20 x island, against 700 + 60 before.
        (('x' || substr(md5(p_id::text || ':' || p_cycle::text), 1, 8))::bit(32)::bigint
         % (750 + 20 * least(greatest(coalesce(p_level, 1), 1), 30)))
        -- ...times where this bot is on its own curve. Exponent 0.55 is a bot
        -- that front-loads, 1.75 is one that leaves it late; a second slice of
        -- the same hash keeps it stable for the whole cycle. Unchanged.
        * power(
            least(greatest(coalesce(p_progress, 1.0), 0.0), 1.0),
            0.55 + 1.2 * (('x' || substr(md5(p_id::text || ':pace'), 1, 4))::bit(16)::bigint / 65535.0)
          )
    )::integer
$$;

do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'tourney_bot_points'
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
