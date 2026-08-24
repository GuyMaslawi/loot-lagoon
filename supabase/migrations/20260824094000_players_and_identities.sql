-- =============================================================================
--  Loot Lagoon -- players, identities, and the save blob
-- =============================================================================
--
-- The island moves off the device.
--
-- Until now the whole game lived in user://coinvillage_save.json: 2.8 KB of
-- JSON on the player's phone and nowhere else. Delete the app and an island is
-- gone, and because every product in the store is a consumable there is no
-- Restore Purchases that brings the money back either -- iap.gd says so itself
-- ("Consumables are never restored"). A player two years in has two years in
-- one place, and that is the hole this closes.
--
-- Two things are deliberately NOT in here:
--
--   * Token verification. Supabase Auth already takes a native Sign in with
--     Apple / Google ID token, checks it against the provider's rotating JWKS
--     and gives back a session. Hand-rolling that is how you ship an auth bug,
--     so auth.users is the source of truth for "who signed in".
--
--   * A one-to-one link between an account and an island. See below.

-- -----------------------------------------------------------------------------
--  players -- the island. One row per human being.
-- -----------------------------------------------------------------------------
create table if not exists public.players (
    id            uuid primary key default gen_random_uuid(),

    -- What other players see on the leaderboard and on the raid card.
    display_name  text not null default 'Islander',
    emoji         text not null default '🙂',

    -- The save. The entire dictionary _flush_save() builds in main.gd, stored
    -- whole rather than split into columns: the game owns that shape, it has
    -- already changed twice (see the two migrations in _load_game), and a
    -- schema that mirrors it would need a migration every time a counter is
    -- added. The server does not read the game's rules out of this -- it only
    -- ever hands it back to the client that owns it.
    save_blob     jsonb,

    -- Denormalised out of save_blob because matchmaking and the leaderboard
    -- sort and filter on them, and you cannot index your way out of doing that
    -- inside a jsonb on every row. Written by push_save from the same payload,
    -- so they cannot drift from the blob they came out of.
    rank_stars    integer not null default 0,
    island_level  integer not null default 1,

    -- Bots live in this table, as real rows, with this flag set. That is the
    -- whole trick: matchmaking is one query, and "prefer a human, fall back to
    -- a bot" is one relaxed filter rather than a second code path. A separate
    -- bots table would mean two queries whose results have to be made
    -- indistinguishable by hand, and the day they differ is the day players
    -- work out which opponents are fake.
    is_bot        boolean not null default false,

    -- Matchmaking will not offer an island nobody has visited in a while: a
    -- raid is only interesting if the victim comes back and sees it happened.
    last_seen     timestamptz not null default now(),

    -- Soft delete, for two cases that both need an undo: the losing island in
    -- a merge conflict, and account deletion under App Store guideline
    -- 5.1.1(v). Someone will pick wrong and email Guy about it, and "it is
    -- gone" is a worse answer than "it is gone in thirty days".
    deleted_at    timestamptz,

    -- Optimistic concurrency. Two devices signed into the same island both
    -- pushing is normal, not exceptional; this is what lets push_save tell a
    -- stale write from a fresh one instead of last-writer-wins.
    save_version  bigint not null default 0,

    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
--  player_identities -- which sign-ins open which island
-- -----------------------------------------------------------------------------
--
-- This is the table that answers "he was on Android with Google, now he is on
-- an iPhone with Apple -- is it the same person?"
--
-- Not by matching email. Sign in with Apple offers Hide My Email, so the Apple
-- identity of a player often carries a @privaterelay.appleid.com address that
-- matches nothing, and even without hiding it, a person's Apple ID is usually
-- not their Gmail. Matching on email fails in both directions at once: it
-- misses the players it is supposed to save (they lose the island), and if it
-- ever trusted an unverified address it would hand an account to whoever
-- claimed it.
--
-- So identity is many-to-one and it is explicit. Each Supabase auth user --
-- one per provider per person -- points at an island. Two rows pointing at the
-- same player_id IS the cross-device link, and it gets written when the player
-- deliberately connects the second provider, not guessed afterwards.
--
-- Which is why the game has to ask for it BEFORE the phone is lost. Connecting
-- Apple while still on Android is the whole point, and Sign in with Apple's
-- web flow works on Android, so it is possible.
create table if not exists public.player_identities (
    auth_uid    uuid primary key references auth.users (id) on delete cascade,
    player_id   uuid not null references public.players (id) on delete cascade,
    -- 'apple' | 'google'. Copied off the JWT for display ("Connected: Apple"),
    -- never used to decide anything.
    provider    text not null,
    linked_at   timestamptz not null default now()
);

create index if not exists player_identities_player_idx
    on public.player_identities (player_id);

-- Matchmaking's real query: eligible opponents in a level band. Partial, so
-- deleted islands are not in the index at all rather than filtered out of it.
create index if not exists players_matchmaking_idx
    on public.players (island_level, last_seen desc)
    where deleted_at is null;

create index if not exists players_leaderboard_idx
    on public.players (rank_stars desc)
    where deleted_at is null;

-- -----------------------------------------------------------------------------
--  Row level security
-- -----------------------------------------------------------------------------
--
-- Default deny on both tables. A player reads and writes exactly one island --
-- their own -- and everything that needs to see somebody else's (matchmaking,
-- the leaderboard, a raid) goes through a security definer function that
-- returns only the public columns. Without that split, "show me the
-- leaderboard" is also "show me everyone's save_blob", and a save_blob is the
-- one thing an attacker would most like to be able to write.
alter table public.players            enable row level security;
alter table public.player_identities  enable row level security;

-- The islands this signed-in user may touch. A function rather than a repeated
-- subquery so the rule exists in one place.
create or replace function public.my_player_ids()
returns setof uuid
language sql
stable
security invoker
set search_path = ''
as $$
    select player_id
      from public.player_identities
     where auth_uid = auth.uid()
$$;

drop policy if exists players_select_own on public.players;
create policy players_select_own on public.players
    for select to authenticated
    using (id in (select public.my_player_ids()));

drop policy if exists players_update_own on public.players;
create policy players_update_own on public.players
    for update to authenticated
    using (id in (select public.my_player_ids()))
    with check (id in (select public.my_player_ids()));

drop policy if exists identities_select_own on public.player_identities;
create policy identities_select_own on public.player_identities
    for select to authenticated
    using (auth_uid = auth.uid());

-- No insert or delete policy on either table, for anybody. Creating an island,
-- linking a provider to one and deleting an account are all transactions with
-- rules attached -- see 0002 -- and a client that could insert its own rows
-- could give itself an island with a billion coins, or attach its identity to
-- somebody else's island. Those all go through security definer functions.

-- -----------------------------------------------------------------------------
--  updated_at
-- -----------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists players_touch_updated_at on public.players;
create trigger players_touch_updated_at
    before update on public.players
    for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
--  Privileges
-- -----------------------------------------------------------------------------
--
-- Spelled out because the project is created with "Automatically expose new
-- tables" turned OFF. That setting hands every future table in this schema to
-- the API the moment it is created, which is the opposite of how these two are
-- designed -- a table nobody remembered to write a policy for would be readable
-- by anyone holding the anon key, and the anon key ships inside the app.
--
-- So privileges are granted here, per table, next to the policies that bound
-- them. Two locks rather than one: a role has to hold the privilege AND satisfy
-- the policy. Missing either is a 403, and forgetting to write a policy fails
-- closed instead of open.
--
-- Note what is NOT granted: nothing at all to `anon`. Every path into this data
-- requires a signed-in user, and matchmaking -- the one thing that legitimately
-- reads other people's rows -- goes through a security definer function that
-- returns public columns only.
grant select, update on public.players           to authenticated;
grant select          on public.player_identities to authenticated;

-- The functions in 0002 are the only way to create an island, link a provider
-- to one, raid somebody or delete an account, so `insert` and `delete` are
-- granted to nobody. See the note above the policies.
