-- =============================================================================
--  Brackets -- a league is a few dozen rivals again, at any population
-- =============================================================================
--
-- THE DEFECT THIS CLOSES, found 2026-09-02 and left as a design call until Guy
-- made it on 2026-09-07.
--
-- A league is three islands wide and everything past island 30 shares the top
-- one, so a league is a POPULATION, not a group. `tourney_board` returns at
-- most 40 rows and the client writes "#N of M" from what came back, while
-- `tourney_result` counts the whole league with no cap. At today's numbers --
-- twelve bots and a handful of testers -- the two agree. At a thousand players
-- in islands 1-3 the screen says "#1 of 40" for three days and then the
-- end-of-tournament dialog says "#3,412 of 50,000", which is not a rounding
-- difference, it is two different competitions.
--
-- It is also the fairness half of the same problem. The reward track is
-- personal -- a player clearing it takes nothing from anybody -- but the top
-- five placing prizes are the one zero-sum thing in the game, and in a league
-- of fifty thousand they are decided by whoever is at the extreme tail. Guy's
-- original brief was "a group of players at the same level", and a group is
-- thirty people, not a census.
--
-- FIXED RIVALS, NOT RESHUFFLED -- Guy's call between the two shapes. The same
-- faces every cycle is what makes a board worth climbing; a field redrawn every
-- 72 hours is a fresh set of strangers each time and nobody to actually beat.
--
-- =============================================================================
--  How a bracket is decided without counting the league on every read
-- =============================================================================
--
-- The obvious implementation -- ntile over the league -- needs the league's
-- size in the query, which is the whole-table read this is supposed to remove.
-- The one below never counts anything on the read path.
--
--   * Every player gets a permanent SLOT, 0..1023, derived from `mm_key`. It
--     is stored, so it is indexable, and it never moves.
--   * A league is cut into `slices` contiguous runs of slots. A bracket is one
--     run, so the board's filter is a RANGE on an indexed column.
--   * `slices` comes from a cached member count refreshed by `tourney_report`,
--     which is already a write and is called by every active player.
--
-- Contiguous runs rather than `slot % slices` is the load-bearing detail. When
-- a league grows past its next multiple of thirty the slice count rises and
-- brackets SPLIT -- and a split of a contiguous run leaves each player with
-- half of the rivals they had, in the same competition, instead of scattering
-- everybody to a new set of strangers. Modulo would reshuffle the entire league
-- on every resize, which is the shape Guy did not pick.
--
-- With no cache row -- a fresh database, or a league nobody has reported in --
-- `slices` is 1, one bracket, the whole league. That is exactly the behaviour
-- this file replaces, so the failure mode of every new part here is "the way it
-- was yesterday".

-- -----------------------------------------------------------------------------
--  The slot
-- -----------------------------------------------------------------------------
--
-- Derived from mm_key rather than rolled fresh, and that is not laziness: two
-- independent random coordinates on the same row would let a determined player
-- work out that raid selection and bracket selection are unrelated, and one
-- number that already exists is one fewer thing to backfill and keep not-null.
--
-- 1024 slots because the bracket boundaries have to divide cleanly enough that
-- a slice is even: at 64 slices -- a league of ~1,900 -- a slice is 16 slots,
-- and the count per slot is large enough by then that the edges do not matter.
alter table public.players
    add column if not exists tourney_slot smallint;

update public.players
   set tourney_slot = least(1023, floor(coalesce(mm_key, random()) * 1024.0)::integer)
 where tourney_slot is null;

alter table public.players
    alter column tourney_slot set default least(1023, floor(random() * 1024.0)::integer);

do $$
begin
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'players'
                  and column_name = 'tourney_slot' and is_nullable = 'YES')
       and not exists (select 1 from public.players where tourney_slot is null) then
        alter table public.players alter column tourney_slot set not null;
    end if;
end;
$$;

-- Leading on the league because it is an equality filter, then the slot because
-- it is a range, then the cycle and the score.
--
-- This is the OPPOSITE shape to players_mm_seek_idx, deliberately, and the note
-- there explains why: matchmaking must lead on the random key so the walk
-- crosses the whole band, because a walk that starts inside one level lands in
-- the same level every time. Here the walk must stay INSIDE one band -- that is
-- what a bracket is -- so the band leads and the random key is the range within
-- it. Same two columns, opposite order, for opposite reasons.
create index if not exists players_tourney_bracket_idx
    on public.players (public.tourney_league(island_level), tourney_slot,
                       tourney_id, tourney_points desc)
    where deleted_at is null;

-- -----------------------------------------------------------------------------
--  The cached league size
-- -----------------------------------------------------------------------------
--
-- Ten rows, one per league. Refreshed by tourney_report when it is more than an
-- hour stale, so the cost is one count per league per hour across the whole
-- player base rather than one per board open.
--
-- An hour is chosen against what it controls: the slice count, which changes
-- only when a league crosses a multiple of thirty members. Being an hour behind
-- on that means a handful of players sit in a bracket of 31 for an hour, which
-- nobody can perceive.
create table if not exists public.tourney_leagues (
    league       integer primary key,
    members      integer not null default 0,
    refreshed_at timestamptz not null default now()
);

alter table public.tourney_leagues enable row level security;

-- No policy, deliberately. Everything that reads this goes through a security
-- definer function; RLS on with no policy means a direct PostgREST select
-- returns nothing at all rather than the league sizes, which are exactly the
-- kind of population figure a scraper would like to have.
revoke all on table public.tourney_leagues from public, anon, authenticated;

-- Thirty to a bracket, and the ceiling is what keeps this honest at the top.
-- 64 slices against 1024 slots is 16 slots a slice; below that the runs stop
-- dividing evenly and a bracket's size starts depending on where its edges
-- fall. A league of 1,900+ therefore gets brackets that grow slowly rather than
-- brackets that are ragged -- the right trade, because a bracket of 40 is still
-- a group and a bracket of 8 next to a bracket of 52 is not.
create or replace function public.tourney_slices(p_league integer)
returns integer
language sql
stable
set search_path = ''
as $$
    -- (n + 29) / 30 is ceil(n/30) on non-negative integers, which is the whole
    -- of the rule: enough brackets that none of them holds more than thirty.
    select greatest(1, least(64,
        (coalesce((select members from public.tourney_leagues
                    where league = p_league), 0) + 29) / 30))
$$;

-- The half-open slot range of the bracket a slot falls in, as [lo, hi).
--
-- Immutable and pure arithmetic so both readers below can call it and agree.
-- The two of them disagreeing is the entire defect this file exists to close,
-- so they share one function rather than each computing it.
create or replace function public.tourney_bracket_range(p_slot integer, p_slices integer)
returns integer[]
language sql
immutable
set search_path = ''
as $$
    select array[
        (((least(greatest(coalesce(p_slot, 0), 0), 1023) * greatest(coalesce(p_slices, 1), 1)) / 1024)
            * 1024 + greatest(coalesce(p_slices, 1), 1) - 1) / greatest(coalesce(p_slices, 1), 1),
        ((((least(greatest(coalesce(p_slot, 0), 0), 1023) * greatest(coalesce(p_slices, 1), 1)) / 1024) + 1)
            * 1024 + greatest(coalesce(p_slices, 1), 1) - 1) / greatest(coalesce(p_slices, 1), 1)]
$$;

-- -----------------------------------------------------------------------------
--  The refresh, on the write path
-- -----------------------------------------------------------------------------
create or replace function public.tourney_touch_league(p_league integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_stale boolean;
begin
    select coalesce(max(refreshed_at) < now() - interval '1 hour', true) into v_stale
      from public.tourney_leagues where league = p_league;
    if not v_stale then
        return;
    end if;
    -- Bots count. They are permanent members of their league rather than
    -- filler -- the board carries them whether or not there are humans, so a
    -- player cannot work out which rows are real -- and a bracket sized on
    -- humans alone would hold twelve bots and one person.
    insert into public.tourney_leagues (league, members, refreshed_at)
    select p_league,
           count(*),
           now()
      from public.players p
     where p.deleted_at is null
       and public.tourney_league(p.island_level) = p_league
        on conflict (league) do update
       set members = excluded.members, refreshed_at = excluded.refreshed_at;
end;
$$;

-- -----------------------------------------------------------------------------
--  The two readers, now filtered to one bracket
-- -----------------------------------------------------------------------------
--
-- `create or replace` rather than drop-and-create: neither signature changes.
-- The note in 20260902160000_tourney_bot_pace.sql is about the other case --
-- an RPC whose PARAMETER LIST moves has to be dropped, because Postgres
-- overloads on the argument list and PostgREST resolving a call against two
-- candidates is a 300 that only shows up on a real phone.
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
    v_slot   integer;
    v_range  integer[];
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select public.tourney_league(island_level), tourney_slot
      into v_league, v_slot
      from public.players where id = v_me;
    v_range := public.tourney_bracket_range(v_slot, public.tourney_slices(v_league));

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
                   and p.tourney_slot >= v_range[1]
                   and p.tourney_slot <  v_range[2]
                   and (p.is_bot or p.tourney_id = v_now or p.id = v_me)
                 order by pts desc
                 limit least(greatest(coalesce(p_limit, 30), 1), 100)) t
    );
end;
$$;

-- The same bracket, and "the same" is the point of this function existing in
-- the shape it does. A placing computed over a different field to the one the
-- board drew for three days is the bug, whichever of the two is "correct".
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
    v_slot   integer;
    v_range  integer[];
    v_mine   integer;
    v_above  integer;
    v_field  integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select public.tourney_league(island_level),
           tourney_slot,
           case when tourney_id = p_tourney_id then tourney_points
                when tourney_prev_id = p_tourney_id then tourney_prev_points
                else 0 end
      into v_league, v_slot, v_mine
      from public.players where id = v_me;
    v_range := public.tourney_bracket_range(v_slot, public.tourney_slices(v_league));

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
               and p.tourney_slot >= v_range[1]
               and p.tourney_slot <  v_range[2]
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
--  tourney_report, which now also keeps the league sizes warm
-- -----------------------------------------------------------------------------
--
-- Replaced whole rather than wrapped, because the refresh has to run on the
-- path every active player already takes and this is the only such path. The
-- body below is the one from 20260902120000_tournament.sql with two lines
-- added at the end; everything else, including the 5,000,000 ceiling, the
-- stale-cycle refusal and the within-cycle monotonicity, is unchanged.
create or replace function public.tourney_report(p_tourney_id integer, p_points integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me     uuid := public.current_player();
    v_now    integer := public.tourney_now_id();
    v_points integer := least(greatest(coalesce(p_points, 0), 0), 5000000);
    v_row    public.players%rowtype;
    v_league integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if coalesce(p_tourney_id, 0) <> v_now then
        return jsonb_build_object('status', 'stale_cycle', 'tourney_id', v_now);
    end if;

    select * into v_row from public.players where id = v_me for update;

    if v_row.tourney_id = v_now then
        update public.players
           set tourney_points = greatest(tourney_points, v_points)
         where id = v_me;
    else
        update public.players
           set tourney_prev_id     = v_row.tourney_id,
               tourney_prev_points = v_row.tourney_points,
               tourney_id          = v_now,
               tourney_points      = v_points
         where id = v_me;
    end if;

    -- Kept warm here and nowhere else. tourney_board is `stable` and cannot
    -- write; this is already a write, and every player who is scoring calls it.
    v_league := public.tourney_league(v_row.island_level);
    perform public.tourney_touch_league(v_league);

    return jsonb_build_object('status', 'ok', 'tourney_id', v_now);
end;
$$;

-- -----------------------------------------------------------------------------
--  Grants
-- -----------------------------------------------------------------------------
--
-- tourney_touch_league and tourney_slices are NOT granted to authenticated:
-- they are called from inside security definer functions, which run as the
-- owner, so a grant would only add a way to ask the server how many people are
-- in a league. tourney_bracket_range is pure arithmetic on arguments and is
-- granted so validate_migrations can exercise it directly.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('tourney_board','tourney_result','tourney_report',
                             'tourney_bracket_range')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('tourney_slices','tourney_touch_league')
    loop
        execute format('revoke all on function %s from public, anon, authenticated', fn);
    end loop;
end;
$$;
