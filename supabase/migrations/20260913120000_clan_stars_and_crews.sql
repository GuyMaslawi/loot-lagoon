-- =============================================================================
--  Loot Lagoon -- what a clan is WORTH, and a world with clans already in it
-- =============================================================================
--
-- Two things Guy asked for on 2026-09-13, and they are one migration because
-- the second is pointless without the first:
--
--   1. "every clan shows its star count, all its members together, and that is
--      what ranks them" -- a clan had no score at all. The browse list sorted
--      on `members`, which measures how many people are in a room and nothing
--      about what they have done; two clans of eight were indistinguishable.
--   2. "create a few clans, put some bots in them so there is something going
--      on" -- the clan page opened on "No clans yet" for every player who was
--      not the first to press CREATE. A social feature whose list is empty
--      reads as a broken one, and the first real tester is always alone.
--
-- STARS ARE SUMMED LIVE, NOT DENORMALISED like `members` is. A clan's members
-- change a few times in its life and are counted by the two functions that
-- change them; a member's `rank_stars` changes every time they build anything,
-- through push_save, which knows nothing about clans. A cached total would be
-- wrong within one spin of one member's phone, and the trigger that would keep
-- it right fires on the hottest write in the schema.
--
-- The cost is one hash aggregate over clan_members joined to players per call,
-- which is the whole table in a single pass rather than a subquery per clan.
-- With the population this game has that is nothing. If clans ever run to tens
-- of thousands, the answer is a materialised view refreshed on a schedule --
-- not a trigger on push_save.

-- -----------------------------------------------------------------------------
--  The standings. ONE definition of the order, used by both readers.
-- -----------------------------------------------------------------------------
--
-- clan_list draws the league table and clan_view tells one clan where it
-- stands in it. If those two computed the order separately they would
-- eventually disagree, and a clan whose own page says #3 while the table above
-- it says #4 is a bug nobody can explain. Same reasoning as _tourney_rank in
-- the client, which the board and the prize both go through.
--
-- Ties are broken by roster size and then by age, so the order is total and
-- stable -- row_number() over a partial order would shuffle equal clans
-- between two calls a second apart.
--
-- NOT GRANTED TO ANYBODY. It is called from inside two security definer
-- functions, which run as the owner.
create or replace function public.clan_standings()
returns table (clan_id uuid, stars bigint, rank bigint)
language sql
stable
security definer
set search_path = ''
as $$
    select c.id,
           coalesce(s.stars, 0)::bigint,
           row_number() over (order by coalesce(s.stars, 0) desc,
                                       c.members desc, c.created_at desc)
      from public.clans c
      left join (
            select m.clan_id, sum(p.rank_stars)::bigint as stars
              from public.clan_members m
              join public.players p on p.id = m.player_id
             where p.deleted_at is null
             group by m.clan_id) s on s.clan_id = c.id
$$;

-- -----------------------------------------------------------------------------
--  The browse list, as a league table
-- -----------------------------------------------------------------------------
--
-- `stars` and `rank` are new; everything else is exactly what the previous
-- version answered, and in the same shape, so a client that has not been
-- updated keeps drawing the rows it already knew how to draw.
--
-- THE ORDER CHANGED and that is the point: biggest crew first became strongest
-- crew first. A clan of thirty players on island 2 is not the clan a new
-- player should be shown at the top of the list.
create or replace function public.clan_list(p_limit integer default 30)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((
        select jsonb_agg(jsonb_build_object(
                   'id', x.id, 'name', x.name, 'emoji', x.emoji,
                   'members', x.members, 'open', x.open,
                   'stars', x.stars, 'rank', x.rank,
                   'full', x.members >= public.clan_max_members())
               order by x.rank)
          from (select c.id, c.name, c.emoji, c.members, c.open,
                       st.stars, st.rank
                  from public.clans c
                  join public.clan_standings() st on st.clan_id = c.id
                 order by st.rank
                 limit least(greatest(coalesce(p_limit, 30), 1), 50)) x), '[]'::jsonb)
$$;

-- One clan, now carrying its own total and its place in the table. The roster
-- already answers each member's `rank_stars` through public_player, so the
-- page can show who is carrying the clan without a second round trip.
create or replace function public.clan_view(p_clan uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
               'id',      c.id,
               'name',    c.name,
               'emoji',   c.emoji,
               'owner',   c.owner,
               'open',    c.open,
               'stars',   coalesce(st.stars, 0),
               'rank',    coalesce(st.rank, 0),
               'members', coalesce((
                   select jsonb_agg(public.public_player(m.player_id)
                                    order by m.joined_at)
                     from public.clan_members m
                    where m.clan_id = c.id), '[]'::jsonb))
      from public.clans c
      left join public.clan_standings() st on st.clan_id = c.id
     where c.id = p_clan
$$;

-- -----------------------------------------------------------------------------
--  A world with crews already in it
-- -----------------------------------------------------------------------------
--
-- WHY THE FLAG AND NOT A NAME LIST. The seed has to be re-runnable -- it is
-- regenerated whenever the bot population is -- and re-running means clearing
-- what it made last time. Matching on names would mean a player who founds
-- "First Wave" before this runs loses their clan to a housekeeping delete.
-- A column says exactly which rows this function owns and nothing else is in
-- reach of it.
alter table public.clans
    add column if not exists seeded boolean not null default false;

-- EVERY SEEDED CLAN LEAVES ITS DOOR OPEN, and that is a rule rather than a
-- setting. A closed clan's join request goes to its owner -- who here is a bot,
-- and a bot answers nothing, ever. Offering a door that can never open is
-- worse than offering no door: the player waits for an answer that is not
-- coming. The ASK path is exercised by real clans, where somebody is home.
--
-- SIZES ARE 6 TO 8 OF THE 30 SEATS. Enough that the roster looks like a crew
-- rather than a placeholder, and far enough from the cap that a real player
-- can always walk into any of them -- including the one at the top of the
-- table, which is the one they will want.
--
-- The bands are contiguous islands, so a clan's members look like people who
-- play together rather than a random draw off the whole population, and the
-- star totals come out as a ladder with real gaps in it. That ladder is the
-- entire content of the league table on day one.
create or replace function public.seed_clans()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_specs jsonb := '[
        {"name": "Deepwater Kings",  "emoji": "🦈", "lo": 27, "hi": 30, "take": 8},
        {"name": "Kraken Deep",      "emoji": "🐙", "lo": 23, "hi": 26, "take": 8},
        {"name": "Coral Crown",      "emoji": "👑", "lo": 19, "hi": 22, "take": 8},
        {"name": "Saltwind Sailors", "emoji": "⛵",  "lo": 15, "hi": 18, "take": 8},
        {"name": "Lantern Bay",      "emoji": "🏮", "lo": 11, "hi": 14, "take": 7},
        {"name": "Anchor Point",     "emoji": "⚓",  "lo": 8,  "hi": 11, "take": 7},
        {"name": "Driftwood Crew",   "emoji": "🪵", "lo": 5,  "hi": 8,  "take": 6},
        {"name": "Tidepool Scouts",  "emoji": "🐚", "lo": 3,  "hi": 6,  "take": 6},
        {"name": "First Wave",       "emoji": "🌊", "lo": 1,  "hi": 4,  "take": 6}
    ]'::jsonb;
    v_spec  jsonb;
    v_clan  uuid;
    v_crew  uuid[];
    v_made  integer := 0;
    v_evict integer := 0;
begin
    -- Cleared first, and the count of real players caught in it is reported
    -- rather than hidden: re-seeding puts anybody who had joined one of these
    -- back on the clan browser, and whoever runs this should know how many.
    select count(*) into v_evict
      from public.clan_members m
      join public.clans c on c.id = m.clan_id
      join public.players p on p.id = m.player_id
     where c.seeded and not p.is_bot;
    delete from public.clan_members m
     using public.clans c
     where c.id = m.clan_id and c.seeded;
    delete from public.clans where seeded;
    if v_evict > 0 then
        raise notice 'seed_clans: % real player(s) were in a seeded clan and are now clanless', v_evict;
    end if;

    for v_spec in select * from jsonb_array_elements(v_specs)
    loop
        -- Strongest islands in the band first, so the owner -- which every
        -- other function treats as the clan's standing authority -- is the
        -- longest-serving-looking member rather than an arbitrary one.
        select array_agg(p.id order by p.island_level desc, p.rank_stars desc, p.id)
          into v_crew
          from (select p2.id, p2.island_level, p2.rank_stars
                  from public.players p2
                 where p2.is_bot
                   and p2.deleted_at is null
                   and p2.island_level between (v_spec->>'lo')::integer
                                           and (v_spec->>'hi')::integer
                   and not exists (select 1 from public.clan_members m
                                    where m.player_id = p2.id)
                 order by p2.island_level desc, p2.rank_stars desc, p2.id
                 limit (v_spec->>'take')::integer) p;
        -- A project whose bot population has not been seeded yet gets no
        -- clans rather than a row of empty ones. seed_bots.sql first, then
        -- this -- and that order is why this is a function and not a block of
        -- inserts: it can simply be run again afterwards.
        if v_crew is null or array_length(v_crew, 1) is null then
            continue;
        end if;

        insert into public.clans (name, emoji, owner, members, open, seeded)
        values (v_spec->>'name', v_spec->>'emoji', v_crew[1],
                array_length(v_crew, 1), true, true)
        returning id into v_clan;

        -- joined_at is spread so the roster has an order with a story in it --
        -- clan_view sorts on it, and every member joining in the same
        -- microsecond makes that sort arbitrary. It also decides who inherits
        -- an orphaned clan, so it must not be a tie.
        insert into public.clan_members (player_id, clan_id, joined_at)
        select v_crew[i], v_clan, now() - make_interval(days => 40 - i * 3)
          from generate_series(1, array_length(v_crew, 1)) i;

        v_made := v_made + 1;
    end loop;

    return v_made;
end;
$$;

-- Run once here, so applying this migration is the whole job on a project that
-- already has its bots. Safe on one that does not: seed_clans() makes nothing
-- when there is nobody to put in a clan, and can be run again after
-- 20260824143000_seed_bots.sql -- which deletes and re-inserts the whole bot
-- population, taking every seeded membership down with it.
select public.seed_clans();

-- -----------------------------------------------------------------------------
--  privileges
-- -----------------------------------------------------------------------------
--
-- clan_list and clan_view were recreated above, and recreating a function
-- resets its privileges -- so they are re-granted here or the clan page stops
-- working for the only role that calls it. clan_standings and seed_clans are
-- deliberately absent: the first runs inside the two above, as the owner, and
-- the second is housekeeping that no client has any business calling.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('clan_list', 'clan_view')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('clan_standings', 'seed_clans')
    loop
        execute format('revoke all on function %s from public, anon, authenticated', fn);
    end loop;
end;
$$;
