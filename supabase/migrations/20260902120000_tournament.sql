-- =============================================================================
--  The tournament board
-- =============================================================================
--
-- The trophy used to open a table of `rank_stars`, which is a WORLD ranking of
-- everything the player has ever built. That table has no end and no rungs: a
-- three-week-old island can read it every day and never move on it, because the
-- people above it have been playing for a month and the gap only widens.
--
-- What the trophy is supposed to be is a 72-hour competition among a few dozen
-- islands at roughly the same stage, scored on what you did THIS cycle. Every
-- part of that -- "this cycle", "roughly the same stage", "what you did" -- is
-- new state, and none of it could be answered from `players` as it stood.
--
-- THE INVARIANT THIS FILE MUST NOT BREAK. Tournament points are not stars.
-- `rank_stars` is the cloud-save merge key and push_save trusts it *because* it
-- only ever rises; tournament points go to zero every 72 hours. They are
-- separate columns here for exactly the reason they are separate keys in the
-- save, and merging them would tell the reconciler that every device on earth
-- had gone backwards at once. See the note in main.gd above TOURNEY_SECONDS.
--
-- The cycle id is computed the same way on both sides -- floor(epoch / 259200)
-- -- so a phone that has been in a tunnel for an hour and the server agree on
-- which tournament it is without anybody being asked.

-- -----------------------------------------------------------------------------
--  Columns
-- -----------------------------------------------------------------------------
--
-- Four rather than two, and the extra pair is what makes the end-of-tournament
-- prize payable. A player who opens the game after a rollover reports the NEW
-- cycle immediately, which would overwrite the score the prize is owed on
-- before the client has had a chance to ask where it placed. So the rollover
-- shifts the finished cycle sideways into `tourney_prev_*` instead of dropping
-- it, and the result query reads whichever of the two pairs carries the cycle
-- it was asked about.
alter table public.players
    add column if not exists tourney_id          integer not null default 0,
    add column if not exists tourney_points      integer not null default 0,
    add column if not exists tourney_prev_id     integer not null default 0,
    add column if not exists tourney_prev_points integer not null default 0;

-- -----------------------------------------------------------------------------
--  Which tournament it is, and which bracket you are in
-- -----------------------------------------------------------------------------
create or replace function public.tourney_now_id()
returns integer
language sql
stable
set search_path = ''
as $$ select floor(extract(epoch from now()) / 259200.0)::integer $$;

-- Three islands to a league, ten leagues, everything past island 30 in the top
-- one -- which is also where the economy curve flattens, so the last league is
-- the only one whose members are genuinely interchangeable.
--
-- Level rather than stars, and that is a design choice worth writing down.
-- Stars are a lifetime total, so bracketing on them puts a returning player who
-- has 4,000 stars and no time to play against people currently grinding; the
-- island number is how far along the game somebody is, which is what "roughly
-- the same level in seniority" means. Immutable so it can be indexed.
create or replace function public.tourney_league(p_level integer)
returns integer
language sql
immutable
set search_path = ''
as $$
    select greatest(1, least(10, ((greatest(coalesce(p_level, 1), 1) - 1) / 3) + 1))
$$;

-- The board's real query: one league, one cycle, ordered by points.
--
-- Leading on the league because that is the equality filter -- the same lesson
-- as players_mm_seek_idx, from the other side. There the index had to lead on
-- the random key so the walk crossed the whole band; here the walk must stay
-- INSIDE one band, so the band comes first and the sort key second, and the
-- top of a league is one index range scan rather than a sort of the world.
create index if not exists players_tourney_idx
    on public.players (public.tourney_league(island_level), tourney_id, tourney_points desc)
    where deleted_at is null;

-- -----------------------------------------------------------------------------
--  What a bot is holding this cycle
-- -----------------------------------------------------------------------------
--
-- Bots never call tourney_report, so their columns are zero for ever, and a
-- board where every seeded island sits on 0 pts is a board that says out loud
-- which of its rows are real. The rest of the game goes to some length to stop
-- that being visible -- bots are rows in `players` precisely so matchmaking
-- cannot tell them apart -- and this would have undone it on the one screen
-- players read most carefully.
--
-- So a bot's score is derived: md5 of (id, cycle) gives a number that is stable
-- for the whole 72 hours, different for every bot, and reshuffled when the
-- cycle turns. Scaled by island level so a league's numbers grow with it, and
-- capped under the top reward rung -- the bots are the field, not the ceiling,
-- and a real player who works for it should finish above all of them.
create or replace function public.tourney_bot_points(p_id uuid, p_cycle integer, p_level integer)
returns integer
language sql
immutable
set search_path = ''
as $$
    select (('x' || substr(md5(p_id::text || ':' || p_cycle::text), 1, 8))::bit(32)::bigint
            % (700 + 60 * least(greatest(coalesce(p_level, 1), 1), 30)))::integer
$$;

-- -----------------------------------------------------------------------------
--  tourney_report -- the client says what it has scored
-- -----------------------------------------------------------------------------
--
-- Client-declared, like rank_stars, and for the same reason: the server does
-- not simulate the game. It is bounded rather than trusted -- see the ceiling
-- below -- and the damage a liar can do is bounded with it, because the prize
-- for winning is spins and cards rather than anything another player loses.
--
-- Monotonic within a cycle. A device that has been offline pushes an older,
-- smaller total when it reconnects, and accepting it would undo the points
-- earned on the phone that was actually being played. Same rule as push_save,
-- for the same reason, on a number that resets instead of rising.
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
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    -- The server decides which tournament it is. A phone whose clock is wound
    -- forward would otherwise post into a cycle nobody else is playing yet and
    -- sit alone at the top of it until everyone arrived.
    if coalesce(p_tourney_id, 0) <> v_now then
        return jsonb_build_object('status', 'stale_cycle', 'tourney_id', v_now);
    end if;

    select * into v_row from public.players where id = v_me for update;

    if v_row.tourney_id = v_now then
        update public.players
           set tourney_points = greatest(tourney_points, v_points)
         where id = v_me;
    else
        -- The rollover. The cycle that just ended moves sideways so the prize
        -- it owes can still be worked out; see the column comment above.
        update public.players
           set tourney_prev_id     = v_row.tourney_id,
               tourney_prev_points = v_row.tourney_points,
               tourney_id          = v_now,
               tourney_points      = v_points
         where id = v_me;
    end if;
    return jsonb_build_object('status', 'ok', 'tourney_id', v_now);
end;
$$;

-- -----------------------------------------------------------------------------
--  tourney_board -- who else is in this league, and what they have
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
                            then public.tourney_bot_points(p.id, v_now, p.island_level)
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

-- -----------------------------------------------------------------------------
--  tourney_result -- where did I finish
-- -----------------------------------------------------------------------------
--
-- Asked once, after the client notices the cycle has turned. Returns a place
-- rather than a prize: what the placings are worth is the game's business and
-- changes with the island the player is on, and the server has no reason to
-- learn the reward table.
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

    -- Ties go to the player. Two islands on the same number both read as the
    -- higher place, which costs the game one duplicated prize in a rare case
    -- and avoids telling somebody they came sixth on a score that also came
    -- fifth -- an ordering they cannot see and would be right to dispute.
    select count(*), count(*) filter (where pts > v_mine)
      into v_field, v_above
      from (select case when p.is_bot
                        then public.tourney_bot_points(p.id, p_tourney_id, p.island_level)
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
--  Who may call what
-- -----------------------------------------------------------------------------
-- Same rule as every other function in this schema: security definer means the
-- grant is the entire access control, and Postgres hands execute to public --
-- which includes the anon role the app ships with -- unless it is taken away.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('tourney_now_id','tourney_league','tourney_bot_points',
                             'tourney_report','tourney_board','tourney_result')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;

-- The two new columns are readable through public_player only, which selects
-- an explicit column list -- so nothing here widens what one player can see of
-- another. The column-level grants added in 20260831190000 are a whitelist and
-- these are not on it, which is the behaviour we want: a direct PostgREST
-- select of players.tourney_points stays a permission error.
