-- =============================================================================
--  Bots have to arrive over the three days, not be waiting at the finish line
-- =============================================================================
--
-- THE BUG THIS FIXES, and it is a design bug rather than a broken query.
--
-- `tourney_bot_points` returned one number per (bot, cycle): the score that bot
-- would end the tournament on. It was correct at the buzzer and wrong for the
-- other seventy-one hours. A player opening the board fifteen hours into a
-- cycle -- which is the ordinary case, because the cycle turns while the game is
-- shut -- had a few hundred points of their own against a field already sitting
-- on its final totals. The board said "everyone is finished and you have not
-- started", on the morning of day one, to every player at once.
--
-- A leaderboard's whole job is to be climbable. This one was showing a race
-- that had already been run.
--
-- So the score is now the final total scaled by how much of the cycle has
-- elapsed, and every bot climbs on its own curve: a pace exponent from a second
-- slice of the same md5 puts some of them out fast and leaves others finishing
-- strong. At the buzzer the totals are exactly what they always were -- progress
-- reaches 1 and the exponent stops mattering -- so nothing about the standings
-- a cycle ends on changes.

-- The signature gains a parameter, so the three-argument version has to go
-- rather than be replaced: Postgres overloads on the argument list, and
-- PostgREST resolving a call against two candidates is a 300 that only shows up
-- on a real phone.
drop function if exists public.tourney_bot_points(uuid, integer, integer);

-- `p_progress` is 0 at the start of a cycle and 1 at its end. Passed in rather
-- than read off now() so this stays IMMUTABLE -- the board and the result query
-- want different values for it (the live fraction, and 1 for a cycle that has
-- already finished), and a function that reads the clock could not answer the
-- second one at all.
create or replace function public.tourney_bot_points(
        p_id uuid, p_cycle integer, p_level integer, p_progress double precision)
returns integer
language sql
immutable
set search_path = ''
as $$
    select round(
        -- the final total, unchanged from the previous migration
        (('x' || substr(md5(p_id::text || ':' || p_cycle::text), 1, 8))::bit(32)::bigint
         % (700 + 60 * least(greatest(coalesce(p_level, 1), 1), 30)))
        -- ...times where this bot is on its own curve. Exponent 0.55 is a bot
        -- that front-loads, 1.75 is one that leaves it late; a second slice of
        -- the same hash keeps it stable for the whole cycle.
        * power(
            least(greatest(coalesce(p_progress, 1.0), 0.0), 1.0),
            0.55 + 1.2 * (('x' || substr(md5(p_id::text || ':pace'), 1, 4))::bit(16)::bigint / 65535.0)
          )
    )::integer
$$;

-- How far through the current cycle we are. Stable, not immutable: it reads the
-- clock, and it is the server's clock deliberately -- the same one that decides
-- which cycle it is.
create or replace function public.tourney_progress()
returns double precision
language sql
stable
set search_path = ''
as $$
    select least(greatest(
        (extract(epoch from now()) - public.tourney_now_id()::double precision * 259200.0) / 259200.0,
        0.0), 1.0)
$$;

-- -----------------------------------------------------------------------------
--  The two readers, pointed at the new signature
-- -----------------------------------------------------------------------------
create or replace function public.tourney_board(p_limit integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_me     uuid := public.current_player();
    v_now    integer := public.tourney_now_id();
    v_prog   double precision := public.tourney_progress();
    v_league integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select public.tourney_league(island_level) into v_league
      from public.players where id = v_me;

    return (
        select coalesce(jsonb_agg(jsonb_set(row, '{points}', to_jsonb(pts)) order by pts desc), '[]'::jsonb)
          from (select public.public_player(p.id) as row,
                       case when p.is_bot
                            then public.tourney_bot_points(p.id, v_now, p.island_level, v_prog)
                            when p.tourney_id = v_now then p.tourney_points
                            else 0 end as pts
                  from public.players p
                 where p.deleted_at is null
                   and public.tourney_league(p.island_level) = v_league
                   and (p.is_bot or p.tourney_id = v_now or p.id = v_me)
                 order by pts desc
                 limit least(greatest(coalesce(p_limit, 30), 1), 100)) t
    );
end;
$$;

-- A finished cycle is scored at progress 1: the bots ran their whole race.
create or replace function public.tourney_result(p_tourney_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_me     uuid := public.current_player();
    v_league integer;
    v_mine   integer;
    v_above  integer;
    v_field  integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select public.tourney_league(island_level),
           case when tourney_id = p_tourney_id then tourney_points
                when tourney_prev_id = p_tourney_id then tourney_prev_points
                else 0 end
      into v_league, v_mine
      from public.players where id = v_me;

    -- Ties go to the player; see the note in 20260902120000_tournament.sql.
    select count(*), count(*) filter (where pts > v_mine)
      into v_field, v_above
      from (select case when p.is_bot
                        then public.tourney_bot_points(p.id, p_tourney_id, p.island_level, 1.0)
                        when p.tourney_id = p_tourney_id then p.tourney_points
                        when p.tourney_prev_id = p_tourney_id then p.tourney_prev_points
                        else 0 end as pts
              from public.players p
             where p.deleted_at is null
               and public.tourney_league(p.island_level) = v_league
               and (p.is_bot
                    or p.tourney_id = p_tourney_id
                    or p.tourney_prev_id = p_tourney_id)) t;

    return jsonb_build_object(
        'tourney_id', p_tourney_id,
        'points',     v_mine,
        'place',      v_above + 1,
        'field',      greatest(v_field, 1),
        'league',     v_league);
end;
$$;

-- -----------------------------------------------------------------------------
--  Grants, again, because the drop took the old function's with it
-- -----------------------------------------------------------------------------
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('tourney_bot_points','tourney_progress',
                             'tourney_board','tourney_result')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
