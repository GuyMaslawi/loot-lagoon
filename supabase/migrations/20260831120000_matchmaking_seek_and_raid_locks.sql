-- =============================================================================
--  Two fixes found by load-testing the schema, 2026-08-31
-- =============================================================================
--
--  1. find_target read the whole level band to return one row.
--  2. record_raid deadlocked when two players raided each other.
--
-- Both were invisible at the player counts this project has seen and both get
-- worse in exactly the situation a successful launch produces.

-- -----------------------------------------------------------------------------
--  1. Matchmaking: stop sorting the haystack to pull out one straw
-- -----------------------------------------------------------------------------
--
-- find_target ended in `order by random() limit 1`, which no index can serve.
-- Postgres pulled every row matching the band off the heap, sorted them all,
-- and threw away everything but one. Measured against 100,000 islands with
-- 24,015 matching the band: the filter on its own answered in 0.03ms, and the
-- ordering took it to 11.29ms while touching 14,972 buffers. Under 24
-- concurrent readers, p95 went from 4.6ms at a thousand islands to 361.7ms at
-- twenty-five thousand. This runs on every raid triple, so it is the hottest
-- call the game makes.
--
-- The fix gives every island a fixed random coordinate and seeks to a random
-- point in that space, taking the first eligible row at or after it. That is an
-- index scan that stops on the first match instead of a sort of everything.
--
-- WHY A COLUMN RATHER THAN A CLEVERER ORDER BY. The key has to be stable and
-- indexable; anything computed per-query is back to sorting. It is deliberately
-- NOT re-rolled per raid -- a fixed key means the scan can stop early, and the
-- randomness comes from where each *search* starts, not from where the rows sit.
alter table public.players
    add column if not exists mm_key double precision;

-- Backfill, then make it mandatory. Split in two so re-running this file on a
-- populated database does not leave rows without a coordinate.
update public.players set mm_key = random() where mm_key is null;

alter table public.players
    alter column mm_key set default random();

do $$
begin
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'players'
                  and column_name = 'mm_key' and is_nullable = 'YES')
       and not exists (select 1 from public.players where mm_key is null) then
        alter table public.players alter column mm_key set not null;
    end if;
end;
$$;

-- Leading on mm_key rather than on (island_level, mm_key), which is the
-- mistake this replaced on the way to being written: an index led by the level
-- makes the scan land in the lowest level of the band every single time. Fast,
-- and not matchmaking -- 3,000 draws returned 201 distinct rivals instead of
-- 2,669. Led by mm_key, the walk crosses the whole band in key order and the
-- level is a filter, so the draw stays even across it.
create index if not exists players_mm_seek_idx
    on public.players (mm_key)
    where deleted_at is null;

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

    -- A human first. Two passes: from a random point in the key space, then --
    -- if that fell past the last eligible row -- from the start, so the space
    -- wraps and the tail is reachable.
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
        v_k := -1.0;   -- wrap: everything is >= this
    end loop;

    if v_pick is not null then
        return public.public_player(v_pick);
    end if;

    -- Then a bot, on the same seek. Bots are reportable too, so a blocked one
    -- stays blocked.
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
                            where bl.blocker = v_me and bl.blocked = p.id)
         order by p.mm_key
         limit 1;
        exit when v_pick is not null;
        v_k := -1.0;
    end loop;

    if v_pick is null then
        return null;
    end if;
    return public.public_player(v_pick);
end;
$$;

-- -----------------------------------------------------------------------------
--  2. record_raid: two players raiding each other deadlocked
-- -----------------------------------------------------------------------------
--
-- The function took `select ... for update` on the victim and then inserted
-- into raids -- and that insert needs a foreign-key lock on BOTH referenced
-- player rows, attacker as well as victim. So A-raids-B running against
-- B-raids-A is a lock cycle: each holds the row the other is about to need.
--
-- Reproduced at 98% of rounds with the transaction held open across the insert,
-- and seen once in 16,832 calls in the ordinary mix at 128 concurrent clients.
-- It matters more than that rate suggests, because cloud.gd hands record_raid an
-- empty callback: the attacker's device applies the raid, the insert dies, and
-- the victim is never told and never debited.
--
-- Locking both rows up front in a fixed order -- lowest uuid first -- means two
-- transactions touching the same pair always take them in the same sequence, so
-- one simply waits instead of both dying. Measured on the same harness:
-- 37 deadlocks in 80 mutual raids became 0, and all 80 raids were recorded
-- instead of 43.
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

    -- Both rows, lowest id first, before anything else touches either. This is
    -- the whole fix; everything below is unchanged.
    perform 1
       from public.players
      where id in (v_me, p_victim)
      order by id
        for update;

    select vault_coins into v_vault
      from public.players where id = p_victim and deleted_at is null;
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

-- Both functions were re-created, so their grants were re-created with the
-- default of executable-by-anyone. Put them back.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('find_target', 'record_raid')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
