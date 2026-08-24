-- =============================================================================
--  Reporting and blocking
-- =============================================================================
--
-- App Store Guideline 1.2 asks for three things once players can see content
-- other players made, and a display name is content other players made: a way
-- to filter objectionable material, a way to report it, and a way to block the
-- person responsible. The filter went in with the name rules. This is the other
-- two.
--
-- It is not paperwork. A player who meets a name aimed at them has no recourse
-- at all right now, and "email the developer" is exactly the answer the
-- guideline exists to rule out.

-- -----------------------------------------------------------------------------
--  reports
-- -----------------------------------------------------------------------------
create table if not exists public.reports (
    id          uuid primary key default gen_random_uuid(),
    reporter    uuid not null references public.players (id) on delete cascade,
    reported    uuid not null references public.players (id) on delete cascade,
    reason      text not null,
    created_at  timestamptz not null default now(),
    -- Null until somebody looks. There is no moderation console yet and there
    -- does not need to be one on day one -- what there needs to be is the
    -- record, so the queue exists the moment it is worth reading.
    reviewed_at timestamptz,
    unique (reporter, reported)
);

create index if not exists reports_open_idx
    on public.reports (created_at desc) where reviewed_at is null;
-- Answers "who is being reported by many different people", which is the only
-- signal worth acting on -- one report is an argument, twenty is a pattern.
create index if not exists reports_reported_idx on public.reports (reported);

-- -----------------------------------------------------------------------------
--  blocks
-- -----------------------------------------------------------------------------
--
-- Blocking here means one thing: never put us in front of each other again.
-- There is no chat to mute and no profile to hide, so matchmaking is the whole
-- surface, and that is where it has to bite.
create table if not exists public.blocks (
    blocker     uuid not null references public.players (id) on delete cascade,
    blocked     uuid not null references public.players (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (blocker, blocked)
);

alter table public.reports enable row level security;
alter table public.blocks  enable row level security;
-- No policies. Both are written through the functions below and read by nobody:
-- a client that could read `blocks` could work out who has blocked them, and a
-- client that could read `reports` could see who reported it.

-- -----------------------------------------------------------------------------
--  report_player
-- -----------------------------------------------------------------------------
--
-- Reporting blocks as well, deliberately. Someone upset enough to report a name
-- wants it gone now, not after a review; asking them to press two buttons in
-- sequence to achieve that is a design that protects the wrong person.
create or replace function public.report_player(p_player uuid, p_reason text default 'name')
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
    if p_player = v_me then
        raise exception 'cannot report your own island';
    end if;
    if not exists (select 1 from public.players where id = p_player and deleted_at is null) then
        raise exception 'no such island';
    end if;

    insert into public.reports (reporter, reported, reason)
    values (v_me, p_player, left(coalesce(p_reason, 'name'), 200))
    on conflict (reporter, reported) do nothing;

    insert into public.blocks (blocker, blocked)
    values (v_me, p_player)
    on conflict do nothing;

    return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.block_player(p_player uuid)
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
    if p_player = v_me then
        raise exception 'cannot block your own island';
    end if;
    insert into public.blocks (blocker, blocked) values (v_me, p_player)
    on conflict do nothing;
    return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
--  find_target respects it
-- -----------------------------------------------------------------------------
--
-- Rewritten only to add the block clause. Everything else is as it was in 0002,
-- including the comment about why bots come back through the same shape.
--
-- The check runs in BOTH directions. Blocking is not only "I do not want to see
-- them" -- it is also "they do not get to come back at me", and a block that
-- only worked one way would leave the person who was reported still raiding the
-- player who reported them.
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
       and p.last_seen > now() - interval '30 days'
       and p.island_level between v_level - p_band and v_level + p_band
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
     order by random()
     limit 1;

    if v_pick is not null then
        return public.public_player(v_pick);
    end if;

    select p.id into v_pick
      from public.players p
     where p.is_bot = true
       and p.deleted_at is null
       and p.island_level between v_level - p_band and v_level + p_band
       and ((p_mode = 'steal'  and p.vault_coins > 0)
         or (p_mode = 'attack' and p.shields = 0
             and exists (select 1 from unnest(p.buildings) b where b > 0)))
       -- Bots are reportable too. A seeded name that upsets somebody should
       -- stop appearing for them, and there is no reason to make that a
       -- special case.
       and not exists (select 1 from public.blocks bl
                        where bl.blocker = v_me and bl.blocked = p.id)
     order by random()
     limit 1;

    if v_pick is null then
        return null;
    end if;
    return public.public_player(v_pick);
end;
$$;

do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('report_player','block_player','find_target')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;

-- -----------------------------------------------------------------------------
--  set_emoji
-- -----------------------------------------------------------------------------
--
-- A face, chosen from a fixed set the game draws. Not an upload: an uploaded
-- image is the hardest kind of user content to moderate, one bad picture in
-- front of other players is a removal-level problem, and a curated set removes
-- the question instead of managing it.
--
-- The list is checked here anyway, because "the client only offers these
-- twelve" stops being true the moment somebody edits the client.
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
    if p_emoji is null or p_emoji not in
        ('😎','🧑‍🚀','🏴‍☠️','🦜','🐙','🦈','🐢','🦀','🌴','⛵','🗺️','💎') then
        return jsonb_build_object('ok', false, 'reason', 'Pick one of the faces');
    end if;
    update public.players set emoji = p_emoji where id = v_me;
    return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.set_emoji(text) from public, anon;
grant execute on function public.set_emoji(text) to authenticated;
