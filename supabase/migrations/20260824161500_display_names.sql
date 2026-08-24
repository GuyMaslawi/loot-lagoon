-- =============================================================================
--  Display names: unique, filtered, and the player's own choice
-- =============================================================================
--
-- Until now the name on an island came straight from the provider profile and
-- went to the server unexamined. That is two problems at once.
--
-- The privacy one is the worse of the two: somebody who signs in with Google
-- gets their real, full name shown on a leaderboard and on a raid card to
-- strangers, without ever being asked. That is not a setting anyone chose, and
-- it is exactly the kind of thing App Review stops.
--
-- The other is collisions. Names arrive from providers, so two players called
-- Guy are ordinary, and both of them can also collide with the 46 seeded bots
-- -- which would let anyone call themselves Maya and pose as a rival other
-- players already recognise.
--
-- Everything here is enforced on the SERVER. A client can be edited, so a check
-- that only runs in GDScript is a suggestion.

-- -----------------------------------------------------------------------------
--  Normalisation
-- -----------------------------------------------------------------------------
--
-- `Maya`, `maya` and `maya   ` are three strings and one name. Uniqueness has
-- to be decided on what the eye sees, or the rule is trivially sidestepped by
-- pressing the space bar.
create or replace function public.normalize_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
    select lower(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'))
$$;

-- Humans only, and that exclusion is load-bearing rather than a shortcut.
--
-- The seeded bots deliberately share 46 names across 120 rows: no name repeats
-- inside a seven-island window, which is the widest lineup a player can ever
-- see, but distant islands reuse them. A blanket unique index would forbid that
-- and force either 120 invented names or suffixes like "Maya 2", which reads as
-- a machine the moment anyone notices.
--
-- So the index enforces uniqueness where it matters -- between people -- while
-- name_available and unique_name below check against EVERY undeleted row, bots
-- included. Two bots may share a name; no player can take a name any bot holds.
-- That is exactly the rule that was asked for.
--
-- Partial on deleted_at too, so a soft-deleted island does not hold its name
-- hostage: after delete_account or a losing merge it returns to circulation.
create unique index if not exists players_name_unique_idx
    on public.players (public.normalize_name(display_name))
    where deleted_at is null and is_bot = false;

-- -----------------------------------------------------------------------------
--  The word filter
-- -----------------------------------------------------------------------------
--
-- A table rather than a constant, so the list can grow without a migration --
-- it will need to, because this kind of list is never finished. Substring
-- matching on the normalised name, which over-blocks a little; that is the
-- right direction to err for something shown to strangers.
create table if not exists public.banned_words (
    word text primary key
);

alter table public.banned_words enable row level security;
-- No policy and no grant: read only through name_available / set_display_name.
-- A readable blocklist is a readable list of exactly what to try.

insert into public.banned_words (word) values
    ('fuck'), ('shit'), ('cunt'), ('nigger'), ('nigga'), ('faggot'), ('rape'),
    ('nazi'), ('hitler'), ('slut'), ('whore'), ('bitch'), ('penis'), ('vagina'),
    ('admin'), ('moderator'), ('support'), ('lootlagoon'), ('official')
on conflict (word) do nothing;

-- The last few are not profanity. A player calling themselves "Support" or
-- "Official" is impersonating the game to other players, which does the same
-- damage as an insult and is easier to miss.

-- -----------------------------------------------------------------------------
--  Validation
-- -----------------------------------------------------------------------------
--
-- Returns null when the name is fine, or a short reason the game can show.
create or replace function public.name_problem(p_name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_norm text := public.normalize_name(p_name);
begin
    if length(v_norm) < 2 then
        return 'Too short';
    end if;
    if length(v_norm) > 16 then
        return 'Too long';
    end if;
    -- Letters, digits, spaces and a couple of joiners. Deliberately allows
    -- non-Latin scripts: `\w` with the `u` flag covers Hebrew, Arabic, Cyrillic
    -- and the rest, and a game sold in 175 countries has no business insisting
    -- on A-Z. What it excludes is punctuation soup and control characters.
    if v_norm !~ '^[[:alnum:] ''._-]+$' and v_norm !~ '^[\w ''._-]+$' then
        return 'Letters and numbers only';
    end if;
    if exists (select 1 from public.banned_words b where v_norm like '%' || b.word || '%') then
        return 'Please pick another name';
    end if;
    return null;
end;
$$;

-- Free, and allowed. Answers the linking screen's "is this taken" without
-- writing anything.
create or replace function public.name_available(p_name text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_problem text := public.name_problem(p_name);
    v_me uuid := public.current_player();
begin
    if v_problem is not null then
        return jsonb_build_object('ok', false, 'reason', v_problem);
    end if;
    if exists (select 1 from public.players p
                where public.normalize_name(p.display_name) = public.normalize_name(p_name)
                  and p.deleted_at is null
                  and (v_me is null or p.id <> v_me)) then
        return jsonb_build_object('ok', false, 'reason', 'That name is taken');
    end if;
    return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
--  A name nobody else has
-- -----------------------------------------------------------------------------
--
-- Used when a name has to be produced rather than chosen: the provider gave one
-- that is taken, or gave nothing at all. Appends a number, which is what every
-- service does because it is the only approach that always terminates.
--
-- The bots are in this table too, so "Maya" being one of the 46 seeded faces is
-- handled by the same query that handles another player having it -- there is
-- no separate reserved list to keep in step.
create or replace function public.unique_name(p_base text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_base text := btrim(coalesce(p_base, ''));
    v_try  text;
    n      integer := 1;
begin
    if public.name_problem(v_base) is not null then
        v_base := 'Islander';
    end if;
    v_try := v_base;
    -- Bounded. A thousand collisions on one base means something is very wrong,
    -- and looping forever inside a transaction is worse than an ugly name.
    while n < 1000 loop
        if not exists (select 1 from public.players p
                        where public.normalize_name(p.display_name) = public.normalize_name(v_try)
                          and p.deleted_at is null) then
            return v_try;
        end if;
        n := n + 1;
        -- Trimmed so base + suffix still fits the 16-character ceiling.
        v_try := left(v_base, 16 - length(n::text) - 1) || ' ' || n::text;
    end loop;
    return 'Islander ' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
end;
$$;

-- -----------------------------------------------------------------------------
--  Setting it
-- -----------------------------------------------------------------------------
create or replace function public.set_display_name(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me      uuid := public.current_player();
    v_check   jsonb;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    v_check := public.name_available(p_name);
    if not (v_check->>'ok')::boolean then
        return v_check;
    end if;
    update public.players
       set display_name = btrim(regexp_replace(p_name, '\s+', ' ', 'g'))
     where id = v_me;
    return jsonb_build_object('ok', true, 'name',
        (select display_name from public.players where id = v_me));
end;
$$;

-- -----------------------------------------------------------------------------
--  claim_player takes the same road
-- -----------------------------------------------------------------------------
--
-- The provider's name is now a SUGGESTION, not the name. It is filtered and
-- de-duplicated on the way in, so an island can never be created holding a name
-- that is taken, reserved by a bot, or unrepeatable in front of other players.
create or replace function public.claim_player(
    p_save          jsonb   default null,
    p_display_name  text    default null,
    p_emoji         text    default null,
    p_rank_stars    integer default 0,
    p_island_level  integer default 1,
    p_vault_coins   bigint  default 0,
    p_shields       integer default 0,
    p_buildings     integer[] default '{0,0,0,0,0}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid       uuid := auth.uid();
    v_player    uuid;
    v_provider  text;
begin
    if v_uid is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    v_player := public.current_player();
    if v_player is not null then
        update public.players set last_seen = now() where id = v_player;
        return jsonb_build_object(
            'is_new', false,
            'player', public.public_player(v_player),
            'save',   (select save_blob from public.players where id = v_player));
    end if;

    select coalesce(
               (select i.provider from auth.identities i where i.user_id = v_uid limit 1),
               'unknown')
      into v_provider;

    insert into public.players (display_name, emoji, save_blob, rank_stars,
                                island_level, vault_coins, shields, buildings)
    values (public.unique_name(p_display_name),
            coalesce(nullif(p_emoji, ''), '🙂'),
            p_save,
            greatest(p_rank_stars, 0),
            greatest(p_island_level, 1),
            greatest(p_vault_coins, 0),
            greatest(p_shields, 0)::smallint,
            p_buildings::smallint[])
    returning id into v_player;

    insert into public.player_identities (auth_uid, player_id, provider)
    values (v_uid, v_player, v_provider);

    return jsonb_build_object(
        'is_new', true,
        'player', public.public_player(v_player),
        'save',   p_save);
end;
$$;

do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('normalize_name','name_problem','name_available',
                             'unique_name','set_display_name','claim_player')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
