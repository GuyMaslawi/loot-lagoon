-- =============================================================================
--  The build floor
-- =============================================================================
--
-- Until now there was no version gate of any kind in this game, and for most of
-- what a release contains that is the right answer: a build that moves a button
-- has no business locking anybody out, and a forced update needs a network to
-- check for, so a gate on every release either blocks a working offline game or
-- opens itself and protects nothing.
--
-- What it is for is the one failure that is NOT survivable, and it is a real
-- one in this codebase. `_save_dict` in main.gd is a hand-written whitelist of
-- keys, and the collection normaliser deletes any set the running build does
-- not know about. So an island played once on an older build comes back with a
-- newer build's fields and card sets erased -- and `push_save`'s only check is
-- that `rank_stars` has not gone backwards, which a deletion like that does not
-- touch. The server takes the damaged save and the real one is gone.
--
-- main.gd now refuses to push once it has read a save stamped by a newer build,
-- which handles that on the device and needs nothing from here. This table is
-- the other hand: the ability to say "that build is not allowed on the island
-- any more" AFTER it has already shipped, without waiting for a new binary to
-- reach the phone that is doing the damage.
--
-- THE DEFAULT IS OFF. min_build 0 admits everything, which is what this row
-- ships as, and every client reads a missing row, an unapplied migration or a
-- dead network as "play on". Nothing here can lock a player out by accident;
-- it takes somebody deliberately raising a number.

create table if not exists public.client_gate_rules (
    -- One row, and the check is what keeps it that way. A second row would
    -- make "the floor" a question about ordering.
    id           boolean primary key default true check (id),
    -- Below this, the game shows a modal that cannot be dismissed. Raise it
    -- only for a build that damages something.
    min_build    integer not null default 0,
    -- The newest build in the stores. Below this the game mentions it once and
    -- lets the player carry on. Cosmetic, and safe to be wrong.
    latest_build integer not null default 0,
    -- Shown inside the blocking modal when set, so the reason can be specific
    -- ("builds before 96 lose card collections") without shipping a binary.
    note         text    not null default '',
    -- Where the update button goes. Empty means "use the one compiled into the
    -- build", which is the ordinary case -- this column exists because a store
    -- listing can move, and the one build that cannot be updated is the one
    -- whose update link is wrong.
    store_ios     text   not null default '',
    store_android text   not null default '',
    updated_at   timestamptz not null default now()
);

insert into public.client_gate_rules (id) values (true) on conflict (id) do nothing;

-- Readable through the function below and not otherwise. The table is two
-- integers and a sentence, none of it secret, but a client that could SELECT it
-- could also be pointed at the wrong row shape by a future column, and the
-- function is a stable contract in a way a table is not.
alter table public.client_gate_rules enable row level security;

-- -----------------------------------------------------------------------------
--  The answer
-- -----------------------------------------------------------------------------
--
-- `p_build` is taken and recorded nowhere. It is in the signature because the
-- client already knows its own number and passing it makes the call read as a
-- question rather than a fetch -- and because a future version of this may want
-- to answer differently per platform, which needs the argument to already be
-- there. Deliberately not logged: diagnostics already carries the build on rows
-- the player has consented to, and this call is made before sign-in.
create or replace function public.client_gate(p_build integer default 0)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'min_build',    coalesce(g.min_build, 0),
        'latest_build', coalesce(g.latest_build, 0),
        'note',         coalesce(g.note, ''),
        'store_ios',     coalesce(g.store_ios, ''),
        'store_android', coalesce(g.store_android, ''),
        -- Echoed back so the client can tell an answer about ITSELF from a
        -- cached or misrouted one. Costs nothing and makes the log readable.
        'your_build',   coalesce(p_build, 0))
      from public.client_gate_rules g
     where g.id
$$;

-- ANON, NOT JUST AUTHENTICATED, and that is the point of the whole file.
--
-- The damage this gate exists to stop is done to a save file on disk, which a
-- player who has never signed in has exactly as much of as anybody else. A
-- floor that only applies once you are logged in is a floor with a hole in it
-- the size of every guest.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'client_gate'
    loop
        execute format('revoke all on function %s from public', fn);
        execute format('grant execute on function %s to anon, authenticated', fn);
    end loop;
end;
$$;
