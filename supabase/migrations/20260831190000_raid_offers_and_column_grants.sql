-- =============================================================================
--  Closing the doors the red team walked through
-- =============================================================================
--
-- A twelve-angle adversarial pass on 2026-08-31 found two holes that four and
-- six of the twelve attackers respectively found independently, which is the
-- signal that they were not subtle. Both are here, plus the smaller ones that
-- live in the same files.
--
-- Neither needs a client change. Nothing in scripts/ calls a table directly or
-- raids anybody it was not handed by find_target, so a build already on
-- TestFlight keeps working against this schema.

-- -----------------------------------------------------------------------------
--  1. The UPDATE grant on players was column-blind
-- -----------------------------------------------------------------------------
--
-- `grant select, update on public.players to authenticated` (migration 0001)
-- read as "a player may write their own island", and the policy backing it does
-- check that: players_update_own tests `id in (select my_player_ids())` in both
-- USING and WITH CHECK. What neither the grant nor the policy says is WHICH
-- COLUMNS, because a table-wide UPDATE privilege has no column list and RLS has
-- no opinion about them.
--
-- So every rule the server enforces was one HTTP request away from irrelevant.
-- The anon key ships inside the app (supabase.json) and the bearer token sits
-- in user://cloud_session.json, so the request is a curl:
--
--   PATCH /rest/v1/players?id=eq.<my own island>
--   {"display_name": "<4KB of U+202E and slurs>", "rank_stars": 2000000000,
--    "island_level": 1, "deleted_at": null, "is_bot": true}
--
-- and it lands past set_display_name's length, charset, profanity and
-- impersonation rules, past set_emoji's twelve-face allowlist, and past
-- push_save's monotonic-rank conflict check. display_name and emoji are the
-- expensive ones: public_player hands them to every rival on the raid card and
-- to 200 rows of leaderboard, so one player's PATCH renders on everybody's
-- screen.
--
-- The fix is the grant, not the policy. cloud.gd reaches PostgREST at exactly
-- two kinds of path -- /auth/v1/token and /rest/v1/rpc/<fn> -- and never at
-- /rest/v1/players, so the write privilege was never used by the game at all.
-- Taking it away costs nothing and removes the whole class.
--
-- SELECT stays. It is genuinely bounded to the caller's own row by
-- players_select_own, and reading your own island back is not an attack.
revoke update on public.players from authenticated;

-- -----------------------------------------------------------------------------
--  2. record_raid trusted a victim id it never issued
-- -----------------------------------------------------------------------------
--
-- find_target is where every rule about who may be raided lives: the level
-- band, the block list in both directions, a 24-hour cooldown per attacker per
-- victim, a 10-minute lock so one island cannot be farmed by a crowd, and
-- `shields = 0` for an attack. All five are SELECT filters. record_raid
-- re-checked none of them -- it validated that the caller had an island, that
-- the victim was not the caller, and that the mode was one of two strings, and
-- then wrote.
--
-- Every victim uuid is public: public_player emits `'id', p.id` and leaderboard
-- returns up to 200 of those rows to any signed-in caller. So the attack was a
-- for-loop over the leaderboard calling record_raid twice per row -- one steal
-- to zero the vault, five attacks to level the huts -- with no cooldown, no
-- shield and no block able to stop it. A player who had bought shields was not
-- protected, and a player who had used the report-and-block button to get away
-- from a harasser was not protected either.
--
-- The clamp did hold: `least(greatest(p_coins,0), v_vault)` means nobody could
-- mint coins for themselves. The damage was purely destructive, which is what
-- makes it griefing rather than cheating, and worse rather than better.
--
-- The fix is to make a raid require something only the server can issue. Rather
-- than re-listing five filters in a second place and waiting for the two copies
-- to drift, find_target now records the offer it just made, and record_raid
-- spends it. The rules stay in one function; the second function only asks
-- whether this pairing came from it.

create table if not exists public.raid_offers (
    id          uuid primary key default gen_random_uuid(),
    attacker    uuid not null references public.players (id) on delete cascade,
    victim      uuid not null references public.players (id) on delete cascade,
    created_at  timestamptz not null default now(),
    -- A raid is the animation immediately after the search. Fifteen minutes is
    -- far longer than that and still short enough that offers cannot be
    -- stockpiled into a burst.
    expires_at  timestamptz not null default now() + interval '15 minutes',
    used_at     timestamptz
);

-- The lookup record_raid does: the caller's live offers against one victim.
create index if not exists raid_offers_open_idx
    on public.raid_offers (attacker, victim, expires_at desc)
    where used_at is null;

alter table public.raid_offers enable row level security;
-- No policy and no grant. Written by find_target and read by record_raid, both
-- security definer; a client that could read this table could enumerate who is
-- being matched against whom.

-- Deliberately NOT keyed by mode. main.gd:8275 asks find_target for a 'steal'
-- every time and then reports whichever raid the player actually performed --
-- island_visit can end in a hammer instead, and that arrives at record_raid as
-- mode 'attack'. An offer bound to the mode it was requested under would reject
-- every legitimate attack in the game.
--
-- Which also means find_target's `shields = 0` filter never ran for a real
-- attack: it is inside the `p_mode = 'attack'` branch, and the client never
-- asks for that mode. So the shield check has to be here, at the write, and
-- this is the only place it has ever actually been enforced.

create or replace function public.record_raid(
    p_victim uuid,
    p_mode   text,
    p_coins  bigint default 0,
    p_hut    integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me      uuid := public.current_player();
    v_vault   bigint;
    v_take    bigint;
    v_shields smallint;
    v_offer   uuid;
    v_hut     smallint;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if p_victim = v_me then
        raise exception 'cannot raid your own island';
    end if;
    if p_mode not in ('steal', 'attack') then
        raise exception 'unknown raid mode: %', p_mode;
    end if;

    -- Both rows, lowest id first, before anything else touches either. Two
    -- players raiding each other at once used to deadlock here; see the
    -- migration this one follows.
    perform 1
       from public.players
      where id in (v_me, p_victim)
      order by id
        for update;

    -- The offer. Spent under the same lock that guards the vault, so two
    -- concurrent calls cannot both consume it.
    select o.id into v_offer
      from public.raid_offers o
     where o.attacker = v_me
       and o.victim   = p_victim
       and o.used_at is null
       and o.expires_at > now()
     order by o.expires_at desc
     limit 1
       for update;
    if v_offer is null then
        raise exception 'no open raid offer for that island'
              using errcode = '42501';
    end if;

    select p.vault_coins, p.shields into v_vault, v_shields
      from public.players p
     where p.id = p_victim and p.deleted_at is null;
    if v_vault is null then
        raise exception 'no such island';
    end if;

    -- Re-asserted at the write rather than trusted from the read. An offer is
    -- fifteen minutes old at worst, and a shield bought or a block pressed
    -- inside that window has to count.
    if exists (select 1 from public.blocks bl
                where (bl.blocker = v_me     and bl.blocked = p_victim)
                   or (bl.blocker = p_victim and bl.blocked = v_me)) then
        raise exception 'that island is blocked' using errcode = '42501';
    end if;
    if p_mode = 'attack' and v_shields > 0 then
        raise exception 'that island is shielded' using errcode = '42501';
    end if;
    if exists (select 1 from public.raids r
                where r.attacker = v_me and r.victim = p_victim
                  and r.created_at > now() - interval '24 hours') then
        raise exception 'already raided that island today' using errcode = '42501';
    end if;

    -- 0-4 or null. The column is a smallint and the victim's client bounds-
    -- checks it again (main.gd:1353), so this was never a crash -- but a row
    -- carrying hut 9 is a row that means nothing, and storing it invites a
    -- future reader to trust it.
    v_hut := null;
    if p_hut is not null and p_hut between 0 and 4 then
        v_hut := p_hut::smallint;
    end if;

    update public.raid_offers set used_at = now() where id = v_offer;

    -- The attacker's client computed the payout, because the payout is the
    -- game's economy and the economy lives in main.gd. Clamping to what the
    -- victim actually has is the one rule the server can enforce without
    -- knowing how the figure was arrived at.
    v_take := least(greatest(p_coins, 0), case when p_mode = 'steal' then v_vault else 0 end);

    update public.players
       set vault_coins = vault_coins - v_take
     where id = p_victim;

    insert into public.raids (attacker, victim, mode, coins, hut)
    values (v_me, p_victim, p_mode, v_take, v_hut);

    return jsonb_build_object('coins', v_take);
end;
$$;

-- find_target, unchanged except that it now records what it offered. Same
-- seek, same filters, same two-pass wrap -- see the migration this one follows
-- for why the index leads on mm_key alone.
create or replace function public.find_target(
    p_mode  text default 'steal',
    p_band  integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me    uuid := public.current_player();
    v_level integer;
    v_lo    integer;
    v_hi    integer;
    v_pick  uuid;
    v_k     double precision;
    v_pass  integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select island_level into v_level from public.players where id = v_me;
    v_lo := v_level - p_band;
    v_hi := v_level + p_band;

    v_k := random();
    for v_pass in 1..2 loop
        select p.id into v_pick
          from public.players p
         where p.mm_key >= v_k
           and p.deleted_at is null
           and p.is_bot = false
           and p.id <> v_me
           and p.last_seen > now() - interval '30 days'
           and p.island_level between v_lo and v_hi
           and ((p_mode = 'steal'  and p.vault_coins > 0)
             or (p_mode = 'attack' and p.shields = 0
                 and exists (select 1 from unnest(p.buildings) b where b > 0)))
           and not exists (select 1 from public.blocks bl
                            where (bl.blocker = v_me and bl.blocked = p.id)
                               or (bl.blocker = p.id and bl.blocked = v_me))
           and not exists (select 1 from public.raids r
                            where r.attacker = v_me and r.victim = p.id
                              and r.created_at > now() - interval '24 hours')
           and not exists (select 1 from public.raids r
                            where r.victim = p.id
                              and r.created_at > now() - interval '10 minutes')
         order by p.mm_key
         limit 1;
        exit when v_pick is not null;
        v_k := -1.0;
    end loop;

    if v_pick is null then
        v_k := random();
        for v_pass in 1..2 loop
            select p.id into v_pick
              from public.players p
             where p.mm_key >= v_k
               and p.deleted_at is null
               and p.is_bot = true
               and p.island_level between v_lo and v_hi
               and ((p_mode = 'steal'  and p.vault_coins > 0)
                 or (p_mode = 'attack' and p.shields = 0
                     and exists (select 1 from unnest(p.buildings) b where b > 0)))
               and not exists (select 1 from public.blocks bl
                                where (bl.blocker = v_me and bl.blocked = p.id)
                                   or (bl.blocker = p.id and bl.blocked = v_me))
             order by p.mm_key
             limit 1;
            exit when v_pick is not null;
            v_k := -1.0;
        end loop;
    end if;

    if v_pick is null then
        return null;
    end if;

    -- The offer this call is making. Superseding rather than accumulating: a
    -- player who searches ten times has one live offer per rival the server
    -- actually showed them, which is exactly the number of raids they can
    -- perform.
    insert into public.raid_offers (attacker, victim) values (v_me, v_pick);

    return public.public_player(v_pick);
end;
$$;

-- Housekeeping. Spent and expired offers are of no interest to anything, and
-- the table would otherwise grow by one row per search forever.
create or replace function public.purge_raid_offers()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    n integer;
begin
    delete from public.raid_offers
     where expires_at < now() - interval '1 day';
    get diagnostics n = row_count;
    return n;
end;
$$;

-- -----------------------------------------------------------------------------
--  3. claim_player let an emoji be anything at all
-- -----------------------------------------------------------------------------
--
-- set_emoji checks against a twelve-face allowlist. claim_player, which is the
-- other way a row is created, took `coalesce(nullif(p_emoji, ''), '🙂')` and
-- stored whatever arrived. So the create path was an unfiltered second name
-- field: public_player emits `emoji` next to `name` on every raid card and
-- leaderboard row, and nothing downstream caps its length.
--
-- One allowlist, in one function, called from both places.
create or replace function public.emoji_ok(p_emoji text)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select p_emoji in
        ('😎','🧑‍🚀','🏴‍☠️','🦜','🐙','🦈','🐢','🦀','🌴','⛵','🗺️','💎','🙂')
$$;

create or replace function public.set_emoji(p_emoji text)
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
    -- '🙂' is the column default and a legal face to keep, but it is not one of
    -- the twelve the picker offers, so it is not selectable here.
    if p_emoji is null or p_emoji = '🙂' or not public.emoji_ok(p_emoji) then
        return jsonb_build_object('ok', false, 'reason', 'Pick one of the faces');
    end if;
    update public.players set emoji = p_emoji where id = v_me;
    return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
--  4. The banned-word check was a raw substring match
-- -----------------------------------------------------------------------------
--
-- normalize_name lowercases and collapses whitespace before the check, so case
-- and spacing were genuinely closed. What was not closed is that the charset
-- deliberately admits apostrophe, period, underscore and hyphen, and the full
-- Unicode alphanumeric range -- and the check is `v_norm like '%' || b.word ||
-- '%'`. So `f.u.c.k` contains no banned word, and neither does `Supp<U+03BF>rt`
-- with a Greek omicron.
--
-- The second one is the one that matters. Four of the seeded words --
-- 'admin', 'moderator', 'support', 'official' -- are there because a player
-- calling themselves Support is impersonating the game to other players, and a
-- homoglyph makes that impersonation free.
--
-- So the filter now runs against a second, tighter string: everything that is
-- not a letter or digit removed, and the common Cyrillic and Greek lookalikes
-- folded onto Latin. translate() rather than unaccent, because unaccent is an
-- extension this project does not install and a name filter should not be the
-- reason it starts needing one.
create or replace function public.fold_confusables(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
    select translate(
               regexp_replace(lower(coalesce(p_text, '')), '[^[:alnum:]]', '', 'g'),
               -- Cyrillic а в е к м н о р с т у х  Greek α β ε ι κ ν ο ρ τ υ χ
               'авекмнорстух' || 'αβειкμνορτυχ' || '0134578',
               'abekmhopctyx' || 'abeikmvoptyx' || 'oleastb')
$$;

create or replace function public.name_problem(p_name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_norm text := public.normalize_name(p_name);
    v_fold text := public.fold_confusables(v_norm);
begin
    if length(v_norm) < 2 then
        return 'Too short';
    end if;
    if length(v_norm) > 16 then
        return 'Too long';
    end if;
    -- Letters, digits, spaces and a couple of joiners. Deliberately allows
    -- non-Latin scripts: a game sold in 175 countries has no business
    -- insisting on A-Z. What it excludes is punctuation soup and control
    -- characters -- including the bidi overrides, which are neither alnum nor
    -- in the joiner list and so have never been permitted here.
    if v_norm !~ '^[[:alnum:] ''._-]+$' and v_norm !~ '^[\w ''._-]+$' then
        return 'Letters and numbers only';
    end if;
    -- Both forms. The raw one still catches a word spelled plainly; the folded
    -- one catches it spelled around.
    if exists (select 1 from public.banned_words b
                where v_norm like '%' || b.word || '%'
                   or v_fold like '%' || public.fold_confusables(b.word) || '%') then
        return 'Please pick another name';
    end if;
    return null;
end;
$$;

-- -----------------------------------------------------------------------------
--  5. A deleted account kept its name forever
-- -----------------------------------------------------------------------------
--
-- delete_account sets deleted_at and stops. The thirty-day undo that buys is
-- deliberate and stays -- someone will delete the wrong island and email Guy
-- about it. What cannot stay is the display name, because on a Google sign-in
-- that is very often the player's real full name, and "deleted" that leaves the
-- name in the table is not deletion under Apple 5.1.1(v) or GDPR erasure.
--
-- So the name goes now and the row goes later. The save blob is game state, not
-- PII, and it is the only thing an undo would have to restore, so it is what
-- the thirty days are actually for.
create or replace function public.delete_account()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_uids uuid[];
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;

    select array_agg(auth_uid) into v_uids
      from public.player_identities where player_id = v_me;

    -- The name goes now. Everything else is as it was.
    update public.players
       set deleted_at   = now(),
           -- Not the empty string: display_name is `not null`, and other
           -- players' devices may still hold a cached raid card naming this
           -- island. A placeholder is a name; a blank is a rendering bug.
           display_name = 'Former islander',
           emoji        = '🙂'
     where id = v_me;

    delete from public.player_identities where player_id = v_me;
    delete from auth.users where id = any(v_uids);

    return jsonb_build_object('status', 'deleted',
                              'identities', coalesce(array_length(v_uids, 1), 0));
end;
$$;

-- The other half of the thirty days. Nothing calls this on a schedule yet --
-- that is a pg_cron job somebody still has to add -- but the erasure promise
-- needs the function to exist and to be correct before it can be kept.
create or replace function public.purge_deleted_players()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    n integer;
begin
    delete from public.players
     where deleted_at is not null
       and deleted_at < now() - interval '30 days';
    get diagnostics n = row_count;
    return n;
end;
$$;


-- claim_player is the other create path, and it took the emoji on faith.
-- Otherwise identical to the version in the display-names migration: the name
-- still goes through unique_name, which runs name_problem -- and therefore now
-- runs the folded banned-word check too.
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
            case when public.emoji_ok(p_emoji) then p_emoji else '🙂' end,
            p_save,
            -- Rank is client-declared by design -- the economy lives in
            -- main.gd and the server cannot recompute it -- but "declared"
            -- does not have to mean "unbounded". A ceiling three orders of
            -- magnitude above any real island stops a fresh account from
            -- claiming the top of the leaderboard with 2,000,000,000 without
            -- coming anywhere near a player who has genuinely earned theirs.
            least(greatest(p_rank_stars, 0), 1000000),
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

-- -----------------------------------------------------------------------------
--  Privileges
-- -----------------------------------------------------------------------------
--
-- Every function re-created above came back with the default of
-- executable-by-anyone, PUBLIC included. Put them back the way the earlier
-- migrations set them, and keep the two housekeeping functions out of the API
-- entirely -- they are for a scheduled job, not a client.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('find_target', 'record_raid', 'set_emoji',
                             'name_problem', 'fold_confusables', 'emoji_ok',
                             'delete_account', 'claim_player')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;

    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('purge_raid_offers', 'purge_deleted_players')
    loop
        execute format('revoke all on function %s from public, anon, authenticated', fn);
    end loop;
end;
$$;
