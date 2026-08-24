-- =============================================================================
--  Loot Lagoon -- the save round trip, account linking, and finding a rival
-- =============================================================================
--
-- 0001 built the tables. This is everything the game actually calls, and all of
-- it goes through security definer functions rather than the tables directly:
-- 0001 grants no insert and no delete to anybody, on purpose, because creating
-- an island, attaching a second sign-in to one, raiding somebody and deleting an
-- account are all transactions with rules attached, and a client that could
-- write those rows itself could give itself an island with a billion coins or
-- staple its identity onto somebody else's.
--
-- The rule every function here keeps: THE SERVER DOES NOT UNDERSTAND THE SAVE.
-- save_blob goes in and comes out whole. main.gd owns the game's rules, it has
-- already changed that dictionary's shape twice (see the two migrations in
-- _load_game), and a server that parsed it would be a second, stale copy of
-- those rules that has to be redeployed every time a counter is added. The few
-- figures the server does sort and filter on are passed in explicitly by the
-- client, next to the blob they were taken from.

-- -----------------------------------------------------------------------------
--  Columns matchmaking needs to see without opening the save
-- -----------------------------------------------------------------------------
alter table public.players
    add column if not exists vault_coins bigint      not null default 0,
    add column if not exists shields     smallint    not null default 0,
    -- What is standing on the island. An attack needs to know there is
    -- something left to knock down; quoting a raid at a flattened island is the
    -- soft-lock qa_soak.gd already has a test for.
    add column if not exists buildings   smallint[]  not null default '{0,0,0,0,0}';

-- -----------------------------------------------------------------------------
--  raids -- what happened to whom
-- -----------------------------------------------------------------------------
--
-- A raid is recorded here and applied by the VICTIM's client, not by the server.
--
-- The alternative -- the server deducting coins from the victim's save_blob --
-- would mean the server knowing which key holds coins, how the island curve
-- scales them, what a shield blocks and what a hammer hits. That is the whole
-- economy, living in two places, drifting apart. Here the server only records
-- that a raid happened and what was claimed; the victim's game reads its unseen
-- raids on the next load and applies them under its own rules, which are the
-- only rules there are.
--
-- It also happens to be how a game like this has to work anyway: the victim is
-- asleep with the app closed when they are robbed.
create table if not exists public.raids (
    id          uuid primary key default gen_random_uuid(),
    attacker    uuid not null references public.players (id) on delete cascade,
    victim      uuid not null references public.players (id) on delete cascade,
    -- 'steal' | 'attack'
    mode        text not null,
    -- What the attacker's client says it took. Trusted only as far as it has to
    -- be: see the clamp in record_raid.
    coins       bigint not null default 0,
    -- Which hut an attack hit, 0-4, or null for a steal.
    hut         smallint,
    created_at  timestamptz not null default now(),
    -- Null until the victim's client has read and applied it.
    seen_at     timestamptz
);

create index if not exists raids_victim_unseen_idx
    on public.raids (victim, created_at desc) where seen_at is null;
create index if not exists raids_attacker_recent_idx
    on public.raids (attacker, victim, created_at desc);
-- Matchmaking asks "has anybody hit this island lately"; without this it is a
-- sequential scan of every raid ever recorded, on every spin.
create index if not exists raids_victim_recent_idx
    on public.raids (victim, created_at desc);

alter table public.raids enable row level security;
-- No policy at all: raids are read and written only through the functions
-- below. A player may see raids against themselves, which unseen_raids()
-- returns, and nothing else -- the full table would tell an attacker exactly
-- which islands are being farmed.

grant select on public.raids to authenticated;

-- -----------------------------------------------------------------------------
--  link_tokens -- connecting a second sign-in to the same island
-- -----------------------------------------------------------------------------
--
-- The problem this solves is narrow and easy to miss: a player cannot be signed
-- in as two providers at once. Signing in with Apple REPLACES the Google
-- session, so "while signed in with Google, also connect Apple" cannot be one
-- continuous transaction -- by the time Apple answers, the session that knew
-- which island to attach it to is gone.
--
-- So the island hands out a token before the switch, and the new session
-- redeems it after. Ten minutes, one use. The player never sees it; it is not a
-- password and it does not need to be typed. It is a note the game leaves in
-- its own pocket while it changes hats.
create table if not exists public.link_tokens (
    token       text primary key,
    player_id   uuid not null references public.players (id) on delete cascade,
    created_at  timestamptz not null default now(),
    expires_at  timestamptz not null default now() + interval '10 minutes',
    used_at     timestamptz
);

create index if not exists link_tokens_player_idx on public.link_tokens (player_id);

alter table public.link_tokens enable row level security;
-- Again no policy. Handed out and redeemed by the functions only; a client that
-- could read this table could read somebody else's token and take their island.

-- -----------------------------------------------------------------------------
--  Who is calling
-- -----------------------------------------------------------------------------
create or replace function public.current_player()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select pi.player_id
      from public.player_identities pi
      join public.players p on p.id = pi.player_id
     where pi.auth_uid = auth.uid()
       and p.deleted_at is null
     limit 1
$$;

-- The columns it is safe for anybody to see about anybody: what the leaderboard
-- shows and what the raid card shows. Never save_blob.
create or replace function public.public_player(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
               'id',           p.id,
               'name',         p.display_name,
               'emoji',        p.emoji,
               'island_level', p.island_level,
               'rank_stars',   p.rank_stars,
               'coins',        p.vault_coins,
               'shields',      p.shields,
               'buildings',    p.buildings)
      from public.players p
     where p.id = p_id and p.deleted_at is null
$$;

-- -----------------------------------------------------------------------------
--  claim_player -- the first thing the game calls after any sign-in
-- -----------------------------------------------------------------------------
--
-- Either this identity already opens an island, or it does not and one is
-- created for it, seeded from whatever was on the device.
--
-- That seeding matters more than it looks. Everybody arriving here for the
-- first time has already been playing -- the title screen says "START PLAYING"
-- and nothing else, because main.gd draws no sign-in buttons on an Apple
-- platform until Sign in with Apple exists. So the common case is a player with
-- a real island in user:// signing in for the first time, and dropping that on
-- the floor in favour of a fresh row would be the exact loss this whole system
-- was built to prevent.
create or replace function public.claim_player(
    p_save          jsonb   default null,
    p_display_name  text    default null,
    p_emoji         text    default null,
    p_rank_stars    integer default 0,
    p_island_level  integer default 1,
    -- integer, not smallint, even though the columns are: Postgres will not
    -- implicitly narrow an integer literal when resolving an overload, so a
    -- smallint parameter makes the function unfindable to any caller that
    -- writes a plain number. Narrowed at the point of use instead.
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
        -- Known identity. Hand back what is stored; the client decides whether
        -- to adopt it or push over it -- see push_save's conflict rule.
        update public.players set last_seen = now() where id = v_player;
        return jsonb_build_object(
            'is_new', false,
            'player', public.public_player(v_player),
            'save',   (select save_blob from public.players where id = v_player));
    end if;

    -- Which provider this session came in on, for "Connected: Apple" in the
    -- settings screen. Display only.
    select coalesce(
               (select i.provider from auth.identities i where i.user_id = v_uid limit 1),
               'unknown')
      into v_provider;

    insert into public.players (display_name, emoji, save_blob, rank_stars,
                                island_level, vault_coins, shields, buildings)
    values (coalesce(nullif(trim(p_display_name), ''), 'Islander'),
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

-- -----------------------------------------------------------------------------
--  pull_save / push_save
-- -----------------------------------------------------------------------------
create or replace function public.pull_save()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_player uuid := public.current_player();
begin
    if v_player is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    update public.players set last_seen = now() where id = v_player;
    return (select jsonb_build_object(
                       'save',         p.save_blob,
                       'rank_stars',   p.rank_stars,
                       'save_version', p.save_version,
                       'player',       public.public_player(p.id))
              from public.players p where p.id = v_player);
end;
$$;

-- Writes the island. Returns 'ok', or 'stale' with the stored save attached.
--
-- The conflict rule is rank_stars, and it works because of something main.gd
-- already guarantees: rank_stars only ever goes up. Its own comment says so --
-- "nothing in the game subtracts from it" -- because a standing you can lose by
-- playing is not a standing. That makes it a monotonic clock for free, and a
-- push carrying LESS of it than the server holds is not a newer save, it is an
-- older device catching up. Accepting it would hand the player back an island
-- they had already grown out of.
--
-- p_force exists for the one legitimate way rank goes down: the player wiping
-- their own island, which main.gd does by deleting the save files outright.
create or replace function public.push_save(
    p_save          jsonb,
    p_rank_stars    integer,
    p_island_level  integer,
    p_vault_coins   bigint   default 0,
    p_shields       integer default 0,
    p_buildings     integer[] default '{0,0,0,0,0}',
    p_force         boolean  default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_player uuid := public.current_player();
    v_stored integer;
begin
    if v_player is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if p_save is null then
        raise exception 'refusing to store a null save';
    end if;

    select rank_stars into v_stored from public.players where id = v_player for update;

    if not p_force and p_rank_stars < v_stored then
        return jsonb_build_object(
            'status',       'stale',
            'stored_rank',  v_stored,
            'pushed_rank',  p_rank_stars,
            'save',         (select save_blob from public.players where id = v_player));
    end if;

    update public.players
       set save_blob    = p_save,
           rank_stars   = greatest(p_rank_stars, 0),
           island_level = greatest(p_island_level, 1),
           vault_coins  = greatest(p_vault_coins, 0),
           shields      = greatest(p_shields, 0)::smallint,
           buildings    = p_buildings::smallint[],
           save_version = save_version + 1,
           last_seen    = now()
     where id = v_player;

    return jsonb_build_object(
        'status',       'ok',
        'save_version', (select save_version from public.players where id = v_player));
end;
$$;

-- -----------------------------------------------------------------------------
--  Linking a second provider
-- -----------------------------------------------------------------------------
create or replace function public.create_link_token()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_player uuid := public.current_player();
    v_token  text;
begin
    if v_player is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    v_token := encode(extensions.gen_random_bytes(24), 'base64');
    insert into public.link_tokens (token, player_id) values (v_token, v_player);
    return v_token;
end;
$$;

-- Attaches the CURRENT session's identity to the island the token names.
--
-- Three outcomes:
--   'linked'   -- this sign-in had no island; it now opens the token's island
--   'conflict' -- this sign-in already has its own island with progress on it,
--                 and merging silently would destroy one. Both are described so
--                 the player can be asked, and nothing is written.
--   'expired'  -- token unknown, used, or older than ten minutes
--
-- p_keep resolves a conflict: pass the id of the island to keep. The other is
-- soft-deleted, not dropped, because somebody will choose wrong and write in.
create or replace function public.redeem_link_token(
    p_token text,
    p_keep  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid    uuid := auth.uid();
    v_target uuid;
    v_mine   uuid;
begin
    if v_uid is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    select player_id into v_target
      from public.link_tokens
     where token = p_token and used_at is null and expires_at > now()
     for update;

    if v_target is null then
        return jsonb_build_object('status', 'expired');
    end if;

    v_mine := public.current_player();

    -- Already the same island: the player connected a provider that was
    -- connected before. Nothing to do, and saying so is not an error.
    if v_mine = v_target then
        update public.link_tokens set used_at = now() where token = p_token;
        return jsonb_build_object('status', 'linked',
                                  'player', public.public_player(v_target));
    end if;

    if v_mine is not null and p_keep is null then
        return jsonb_build_object(
            'status', 'conflict',
            'mine',   public.public_player(v_mine),
            'theirs', public.public_player(v_target));
    end if;

    if v_mine is not null then
        if p_keep not in (v_mine, v_target) then
            raise exception 'p_keep must be one of the two islands';
        end if;
        -- Every identity that pointed at the losing island now points at the
        -- winner, so the player cannot sign in through a door that opens onto
        -- the island they just discarded.
        update public.player_identities
           set player_id = p_keep
         where player_id in (v_mine, v_target);
        update public.players
           set deleted_at = now()
         where id in (v_mine, v_target) and id <> p_keep;
        update public.link_tokens set used_at = now() where token = p_token;
        return jsonb_build_object('status', 'linked',
                                  'player', public.public_player(p_keep));
    end if;

    insert into public.player_identities (auth_uid, player_id, provider)
    values (v_uid,
            v_target,
            coalesce((select i.provider from auth.identities i
                       where i.user_id = v_uid limit 1), 'unknown'))
    on conflict (auth_uid) do update set player_id = excluded.player_id;

    update public.link_tokens set used_at = now() where token = p_token;
    return jsonb_build_object('status', 'linked',
                              'player', public.public_player(v_target));
end;
$$;

-- -----------------------------------------------------------------------------
--  find_target -- a human if there is one, a bot if there is not
-- -----------------------------------------------------------------------------
--
-- The request Guy actually made, and the order is the whole point: real players
-- first, a bot only when the query comes back empty.
--
-- It will come back empty a lot, and that is expected rather than a failure. On
-- launch day there are no other players at all, so every raid is against a bot;
-- months in, a player at level 22 at four in the morning still may not have a
-- human in band. The bot path is not a fallback that rarely fires, it is the
-- common case for a long time, which is why bots are rows in `players` and come
-- back through this same function shaped identically.
--
-- What the caller gets back never says which it got. The moment that flag
-- exists somebody dumps the traffic, posts "here is how to tell", and every
-- raid in the game feels fake -- including the real ones.
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
    v_pick  uuid;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select island_level into v_level from public.players where id = v_me;

    select p.id into v_pick
      from public.players p
     where p.id <> v_me
       and p.is_bot = false
       and p.deleted_at is null
       -- A raid is only worth anything if the victim comes back and sees it.
       and p.last_seen > now() - interval '30 days'
       and p.island_level between v_level - p_band and v_level + p_band
       -- A steal wants a vault worth opening; an attack wants something still
       -- standing. Offering either of the opposite is the raid that hands back
       -- nothing, which qa_soak.gd's flattened-rival test exists for.
       and ((p_mode = 'steal'  and p.vault_coins > 0)
         or (p_mode = 'attack' and p.shields = 0
             and exists (select 1 from unnest(p.buildings) b where b > 0)))
       -- Not one this player has already had lately, and not one somebody else
       -- is in the middle of farming. Without the second clause a rich island
       -- becomes everyone's target at once and its owner never keeps anything.
       and not exists (select 1 from public.raids r
                        where r.attacker = v_me and r.victim = p.id
                          and r.created_at > now() - interval '24 hours')
       and not exists (select 1 from public.raids r
                        where r.victim = p.id
                          and r.created_at > now() - interval '10 minutes')
     order by random()
     limit 1;

    if v_pick is not null then
        return public.public_player(v_pick);
    end if;

    -- Nobody. Take a bot, on the same terms minus the ones that only make sense
    -- for a person: a bot is never asleep and cannot be farmed.
    select p.id into v_pick
      from public.players p
     where p.is_bot = true
       and p.deleted_at is null
       and p.island_level between v_level - p_band and v_level + p_band
       and ((p_mode = 'steal'  and p.vault_coins > 0)
         or (p_mode = 'attack' and p.shields = 0
             and exists (select 1 from unnest(p.buildings) b where b > 0)))
     order by random()
     limit 1;

    -- Still nothing means the bot pool has no one at this level, which is a
    -- gap in the seeded population rather than something the player did. The
    -- client falls back to its own local rivals so the spin still resolves.
    if v_pick is null then
        return null;
    end if;
    return public.public_player(v_pick);
end;
$$;

-- -----------------------------------------------------------------------------
--  record_raid / unseen_raids
-- -----------------------------------------------------------------------------
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
    v_me    uuid := public.current_player();
    v_vault bigint;
    v_take  bigint;
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

    select vault_coins into v_vault
      from public.players where id = p_victim and deleted_at is null for update;
    if v_vault is null then
        raise exception 'no such island';
    end if;

    -- The attacker's client computed the payout, because the payout is the
    -- game's economy and the economy lives in main.gd. What the server will not
    -- do is take the number on faith: an edited save could claim to have lifted
    -- a billion coins out of an island that held nine hundred. Clamping to what
    -- the victim actually has is the one rule the server can enforce without
    -- knowing anything about how the figure was arrived at.
    v_take := least(greatest(p_coins, 0), case when p_mode = 'steal' then v_vault else 0 end);

    update public.players
       set vault_coins = vault_coins - v_take
     where id = p_victim;

    insert into public.raids (attacker, victim, mode, coins, hut)
    values (v_me, p_victim, p_mode, v_take, p_hut::smallint);

    return jsonb_build_object('coins', v_take);
end;
$$;

-- What happened while the player was away, for the victim's client to apply
-- under its own rules and then acknowledge.
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
                   'id',    r.id,
                   'mode',  r.mode,
                   'coins', r.coins,
                   'hut',   r.hut,
                   'at',    extract(epoch from r.created_at),
                   'by',    public.public_player(r.attacker))
               order by r.created_at)
          from public.raids r
         where r.victim = v_me and r.seen_at is null
         limit 50), '[]'::jsonb);
end;
$$;

create or replace function public.ack_raids(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
    v_n  integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    update public.raids set seen_at = now()
     where victim = v_me and seen_at is null and id = any(p_ids);
    get diagnostics v_n = row_count;
    return v_n;
end;
$$;

-- -----------------------------------------------------------------------------
--  leaderboard
-- -----------------------------------------------------------------------------
create or replace function public.leaderboard(p_limit integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(row order by rank_stars desc), '[]'::jsonb)
      from (select public.public_player(p.id) as row, p.rank_stars
              from public.players p
             where p.deleted_at is null
             order by p.rank_stars desc
             limit least(greatest(p_limit, 1), 200)) t
$$;

-- -----------------------------------------------------------------------------
--  delete_account -- App Store guideline 5.1.1(v)
-- -----------------------------------------------------------------------------
--
-- Mandatory from the moment the game creates accounts, and it has to be doable
-- from inside the app rather than by emailing Guy.
--
-- Soft delete, then the auth users, in that order. Thirty days of recoverable
-- is not Apple stalling -- the guideline is about the player being able to
-- start the deletion themselves, which this does -- and it is the difference
-- between a support email that can be answered and one that cannot.
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

    update public.players set deleted_at = now() where id = v_me;
    delete from public.player_identities where player_id = v_me;
    delete from auth.users where id = any(v_uids);

    return jsonb_build_object('status', 'deleted', 'identities', coalesce(array_length(v_uids, 1), 0));
end;
$$;

-- -----------------------------------------------------------------------------
--  Who may call what
-- -----------------------------------------------------------------------------
-- Every one of these is security definer, so execute is the whole access
-- control. Revoke from public first: Postgres grants execute to public by
-- default, and "public" here includes the anon role that ships in the app.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('current_player','public_player','claim_player','pull_save',
                             'push_save','create_link_token','redeem_link_token','find_target',
                             'record_raid','unseen_raids','ack_raids','leaderboard',
                             'delete_account','my_player_ids','touch_updated_at')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
