-- =============================================================================
--  Loot Lagoon -- clans, and giving a spare card to somebody in yours
-- =============================================================================
--
-- WHAT THIS CAN AND CANNOT PROMISE, because the honest answer is not "nothing
-- can be cheated" and pretending otherwise is how a hole ships.
--
-- The card collection is CLIENT-AUTHORITATIVE. `col_owned` and `col_dupes`
-- live inside `players.save_blob`, which this server stores whole and never
-- inspects -- migration 20260824094000 says so in its own comment. So the
-- server cannot know whether a sender really held the spare they claim to have
-- given, and no amount of clan membership changes that: membership gates WHO
-- may send, never WHETHER the thing sent existed.
--
-- What the server CAN do is bound the damage, and that is what everything
-- below is for:
--
--   * the RECEIVER's gain is issued here, from a row this server wrote, and is
--     capped per day. That cap is the ceiling on how much any collection can
--     be inflated, by anyone, cheating or not.
--   * the SENDER is capped per day too, so a modified client cannot become an
--     unlimited fountain even for accounts that have receive budget left.
--   * FIVE-STAR CARDS CANNOT BE SENT AT ALL. Guy's rule, 2026-09-04, and it is
--     enforced here rather than in the client because the client is the thing
--     we are defending against. The season length is measured off the 5-star
--     rate; two co-operating accounts must not be able to touch it.
--   * NOBODY CAN SEND TO THEMSELVES. Pointless when honest, and an unbounded
--     duplicate-to-star laundry when not: a spare melts for its own star
--     rating, and 110 stars buy a Treasure Vault with a guaranteed 5-star.
--     Self-sending would be a loop from nothing to gold.
--
-- The residual hole, stated plainly so nobody rediscovers it as news: a
-- modified client can give without ever debiting itself. It cannot exceed its
-- own daily give cap, cannot send golds, and cannot push any receiver past
-- their daily receive cap. That is a bounded leak, not an open one.

-- -----------------------------------------------------------------------------
--  clans
-- -----------------------------------------------------------------------------

create table if not exists public.clans (
    id          uuid primary key default gen_random_uuid(),
    name        text not null,
    emoji       text not null default '🏴',
    owner       uuid not null references public.players(id) on delete cascade,
    created_at  timestamptz not null default now(),
    -- Denormalised for the browse list, which sorts and filters on it and
    -- cannot count members per row. Maintained by the join/leave functions.
    members     integer not null default 0
);

-- One clan per name, case- and space-insensitively, reusing the same folding
-- the display-name uniqueness index uses so "Sea Dogs" and "seadogs" cannot
-- both exist and be told apart only by a human squinting.
create unique index if not exists clans_name_uidx
    on public.clans (public.normalize_name(name));

create index if not exists clans_browse_idx
    on public.clans (members desc, created_at desc);

-- ONE CLAN PER PLAYER, and it is the primary key that says so rather than a
-- check somewhere in a function. A player in two clans could receive from both
-- pools and the receive cap would stop meaning anything.
create table if not exists public.clan_members (
    player_id  uuid primary key references public.players(id) on delete cascade,
    clan_id    uuid not null references public.clans(id) on delete cascade,
    joined_at  timestamptz not null default now()
);

create index if not exists clan_members_clan_idx on public.clan_members (clan_id);

-- -----------------------------------------------------------------------------
--  card gifts
-- -----------------------------------------------------------------------------
--
-- Shaped deliberately like `raids`: the sender writes a row, the receiver's
-- client reads its unseen ones on the next launch and applies them, then acks.
-- That path is already proven, already has a replay guard on the client
-- (`applied_raids`), and already survives an ack that never lands.

create table if not exists public.card_gifts (
    id          uuid primary key default gen_random_uuid(),
    from_player uuid not null references public.players(id) on delete cascade,
    to_player   uuid not null references public.players(id) on delete cascade,
    -- The card, in the client's own coordinates. The server does not own the
    -- card tables and deliberately does not try to: it validates the STAR
    -- RATING, which is the only property any rule here depends on.
    set_id      text not null,
    card_idx    integer not null,
    stars       integer not null,
    created_at  timestamptz not null default now(),
    seen_at     timestamptz,

    -- The two rules that must hold even if every function above is bypassed.
    constraint card_gifts_no_self  check (from_player <> to_player),
    constraint card_gifts_no_golds check (stars between 1 and 4)
);

create index if not exists card_gifts_unseen_idx
    on public.card_gifts (to_player, created_at)
    where seen_at is null;

-- The two windows the caps are counted over.
create index if not exists card_gifts_from_recent_idx
    on public.card_gifts (from_player, created_at);
create index if not exists card_gifts_to_recent_idx
    on public.card_gifts (to_player, created_at);

alter table public.clans        enable row level security;
alter table public.clan_members enable row level security;
alter table public.card_gifts   enable row level security;
-- No policies, exactly like `raids`: every read and write goes through the
-- SECURITY DEFINER functions below, so PostgREST cannot be pointed at these
-- tables directly.

-- -----------------------------------------------------------------------------
--  the caps
-- -----------------------------------------------------------------------------
--
-- RECEIVE is the one that bounds the economy, so it is the tighter of the two.
-- Three a day is roughly a card every other set-gap, which speeds the middle of
-- a collection without touching how a set ends -- the last card of a set is
-- almost always the 5-star, and those cannot be sent at all.
--
-- GIVE is looser because giving is the social act and capping it hard makes
-- clan membership feel like a chore, but it exists so a single modified client
-- cannot service everybody.
create or replace function public.gift_receive_cap() returns integer
language sql immutable as $$ select 3 $$;

create or replace function public.gift_give_cap() returns integer
language sql immutable as $$ select 5 $$;

-- =============================================================================
--  clan membership
-- =============================================================================

create or replace function public.create_clan(p_name text, p_emoji text default '🏴')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
    v_id   uuid;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if length(v_name) < 3 or length(v_name) > 20 then
        return jsonb_build_object('ok', false, 'reason', 'length');
    end if;
    -- The same filter the display name goes through. A clan name is shown next
    -- to a player's own, so it is exactly as public and needs the same bar.
    if public.name_problem(v_name) is not null then
        return jsonb_build_object('ok', false, 'reason', 'name');
    end if;
    if exists (select 1 from public.clan_members where player_id = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;

    begin
        insert into public.clans (name, emoji, owner, members)
             values (v_name, coalesce(nullif(btrim(p_emoji), ''), '🏴'), v_me, 1)
          returning id into v_id;
    exception when unique_violation then
        return jsonb_build_object('ok', false, 'reason', 'taken');
    end;

    insert into public.clan_members (player_id, clan_id) values (v_me, v_id);
    return jsonb_build_object('ok', true, 'clan', public.clan_view(v_id));
end;
$$;

create or replace function public.join_clan(p_clan uuid)
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
    if exists (select 1 from public.clan_members where player_id = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;
    -- The row is locked before the count moves, so two people joining the same
    -- clan in the same moment cannot both read `members` and write it back.
    perform 1 from public.clans where id = p_clan for update;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    insert into public.clan_members (player_id, clan_id) values (v_me, p_clan);
    update public.clans set members = members + 1 where id = p_clan;
    return jsonb_build_object('ok', true, 'clan', public.clan_view(p_clan));
end;
$$;

create or replace function public.leave_clan()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_clan uuid;
    v_left integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select clan_id into v_clan from public.clan_members where player_id = v_me;
    if v_clan is null then
        return jsonb_build_object('ok', true);
    end if;
    perform 1 from public.clans where id = v_clan for update;
    delete from public.clan_members where player_id = v_me;
    update public.clans set members = greatest(0, members - 1)
     where id = v_clan
 returning members into v_left;
    -- The last member out takes the clan with them. A clan with nobody in it is
    -- a name held for ever against everybody else, and there is no ownership
    -- transfer flow to hand it to.
    if coalesce(v_left, 0) <= 0 then
        delete from public.clans where id = v_clan;
    end if;
    return jsonb_build_object('ok', true);
end;
$$;

-- One clan, with its members. `public_player` is reused rather than selecting
-- columns here, so a clan roster can never show more about somebody than the
-- leaderboard and the raid card already do.
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
               'members', coalesce((
                   select jsonb_agg(public.public_player(m.player_id)
                                    order by m.joined_at)
                     from public.clan_members m
                    where m.clan_id = c.id), '[]'::jsonb))
      from public.clans c
     where c.id = p_clan
$$;

create or replace function public.my_clan()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_clan uuid;
begin
    if v_me is null then
        return 'null'::jsonb;
    end if;
    select clan_id into v_clan from public.clan_members where player_id = v_me;
    if v_clan is null then
        return 'null'::jsonb;
    end if;
    return public.clan_view(v_clan);
end;
$$;

-- The browse list. Bounded inside the subquery, which is the shape migration
-- 20260831210000 exists to have taught: a LIMIT outside jsonb_agg limits the
-- number of result rows, and the aggregate has already collapsed them to one.
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
                   'members', x.members)
               order by x.members desc, x.created_at desc)
          from (select c.id, c.name, c.emoji, c.members, c.created_at
                  from public.clans c
                 order by c.members desc, c.created_at desc
                 limit least(greatest(coalesce(p_limit, 30), 1), 50)) x), '[]'::jsonb)
$$;

-- =============================================================================
--  giving a card
-- =============================================================================

create or replace function public.send_card(
    p_to      uuid,
    p_set     text,
    p_idx     integer,
    p_stars   integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me        uuid := public.current_player();
    v_my_clan   uuid;
    v_their_clan uuid;
    v_sent      integer;
    v_got       integer;
    v_id        uuid;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;

    -- SELF-SEND. Guy asked for this by name. It is refused here rather than
    -- hidden in the client, because the client is what we are defending
    -- against -- and a self-send is not merely pointless: a spare melts for
    -- its own star rating and 110 stars buy a guaranteed 5-star, so a loop
    -- back to yourself is a laundry from nothing into gold.
    if p_to = v_me then
        return jsonb_build_object('ok', false, 'reason', 'self');
    end if;

    -- FIVE STARS ARE NOT SENDABLE. Also a table constraint, so it holds even
    -- if this function is ever replaced by one that forgets.
    if p_stars is null or p_stars < 1 or p_stars > 4 then
        return jsonb_build_object('ok', false, 'reason', 'stars');
    end if;

    if p_set is null or btrim(p_set) = '' or p_idx is null or p_idx < 0 then
        return jsonb_build_object('ok', false, 'reason', 'card');
    end if;

    select clan_id into v_my_clan    from public.clan_members where player_id = v_me;
    select clan_id into v_their_clan from public.clan_members where player_id = p_to;
    if v_my_clan is null or v_their_clan is null or v_my_clan <> v_their_clan then
        return jsonb_build_object('ok', false, 'reason', 'not_clanmates');
    end if;

    -- Both rows locked in uuid order before anything is counted or written.
    -- This is the deadlock lesson from `record_raid`: the insert below needs an
    -- FK lock on both referenced players, so A-gives-B racing B-gives-A is a
    -- lock cycle unless the order is fixed. Same fix, same reason.
    perform 1 from public.players
             where id in (v_me, p_to) and deleted_at is null
             order by id for update;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;

    -- THE CAPS, counted inside the same locked transaction as the insert, so
    -- two concurrent gifts cannot both read a count of two and both write.
    select count(*) into v_sent
      from public.card_gifts
     where from_player = v_me and created_at > now() - interval '24 hours';
    if v_sent >= public.gift_give_cap() then
        return jsonb_build_object('ok', false, 'reason', 'give_cap',
                                  'cap', public.gift_give_cap());
    end if;

    select count(*) into v_got
      from public.card_gifts
     where to_player = p_to and created_at > now() - interval '24 hours';
    if v_got >= public.gift_receive_cap() then
        return jsonb_build_object('ok', false, 'reason', 'their_cap',
                                  'cap', public.gift_receive_cap());
    end if;

    insert into public.card_gifts (from_player, to_player, set_id, card_idx, stars)
         values (v_me, p_to, btrim(p_set), p_idx, p_stars)
      returning id into v_id;

    return jsonb_build_object('ok', true, 'id', v_id,
                              'sent_today', v_sent + 1,
                              'give_cap', public.gift_give_cap());
end;
$$;

-- How much of today's budget is left, so the client can grey a button out
-- rather than letting the player press it and be refused.
create or replace function public.gift_budget()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_sent integer := 0;
    v_got  integer := 0;
begin
    if v_me is null then
        return 'null'::jsonb;
    end if;
    select count(*) into v_sent from public.card_gifts
     where from_player = v_me and created_at > now() - interval '24 hours';
    select count(*) into v_got from public.card_gifts
     where to_player = v_me and created_at > now() - interval '24 hours';
    return jsonb_build_object(
        'sent', v_sent, 'give_cap', public.gift_give_cap(),
        'got',  v_got,  'receive_cap', public.gift_receive_cap());
end;
$$;

-- Everything given to me that my client has not applied yet. Same shape and
-- same bounded-inside-the-subquery LIMIT as `unseen_raids`.
create or replace function public.unseen_gifts()
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
                   'id',    x.id,
                   'set',   x.set_id,
                   'idx',   x.card_idx,
                   'stars', x.stars,
                   'at',    extract(epoch from x.created_at),
                   'by',    public.public_player(x.from_player))
               order by x.created_at)
          from (select g.id, g.set_id, g.card_idx, g.stars, g.created_at, g.from_player
                  from public.card_gifts g
                 where g.to_player = v_me and g.seen_at is null
                 order by g.created_at
                 limit 50) x), '[]'::jsonb);
end;
$$;

create or replace function public.ack_gifts(p_ids uuid[])
returns void
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
    update public.card_gifts
       set seen_at = now()
     where to_player = v_me and seen_at is null and id = any(p_ids);
end;
$$;

-- -----------------------------------------------------------------------------
--  privileges
-- -----------------------------------------------------------------------------
--
-- Recreating a function resets its privileges to the default, and the default
-- for a SECURITY DEFINER function that writes another player's inbox is not
-- something to leave to chance. Same block the previous two migrations end
-- with, for the same reason.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('create_clan', 'join_clan', 'leave_clan',
                             'my_clan', 'clan_view', 'clan_list',
                             'send_card', 'gift_budget', 'unseen_gifts',
                             'ack_gifts', 'gift_give_cap', 'gift_receive_cap')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
