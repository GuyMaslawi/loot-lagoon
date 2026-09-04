-- =============================================================================
--  Loot Lagoon -- clan invites, join requests, and the badge that counts them
-- =============================================================================
--
-- WHY THIS EXISTS AT ALL, since 20260904120000 shipped clans two hours ago.
--
-- Guy, 2026-09-04, looking at the clan button on a real phone: "make sure that
-- if there is an invitation from a user, or a join request when you are the
-- clan leader, there is a notification with numbers on that icon."
--
-- There was no such number to show, and no amount of client work could invent
-- one: clans as shipped are open doors. Every clan is public, `join_clan` puts
-- you straight in, and nobody ever has to be asked or told anything. A badge
-- needs something PENDING to count, so this migration is what gives a clan two
-- kinds of pending thing.
--
--   * AN INVITE is addressed to one player. Any member may send one; only the
--     player it names can accept it. It is the half that makes a clan
--     recruitable rather than only browsable.
--   * A REQUEST is addressed to a clan. It only exists for a clan whose owner
--     has closed the door (`clans.open = false`), and only the owner may
--     answer it.
--
-- WHAT IS DELIBERATELY NOT HERE, so it is not rediscovered as an omission:
-- there is no clan chat. Guy's note made it conditional ("if a clan chat is
-- needed, add it"), and it is the one feature on the list that changes what
-- this app IS to a store reviewer -- free-text player-to-player messaging is
-- user-generated content, which brings a filtering obligation, a reporting
-- path, a blocking path and an EULA with it under App Store guideline 1.2.
-- The reporting and blocking halves already exist (20260824174500); the rest
-- does not, and shipping the message box before the moderation around it is
-- how a review rejection happens two days before a launch window.
--
-- Everything below follows the house rules the clan migration set: no RLS
-- policies, every read and write through a SECURITY DEFINER function, and a
-- refusal is a jsonb `{"ok": false, "reason": ...}` rather than an exception,
-- so a client that is out of date gets a sentence rather than a 500.

-- -----------------------------------------------------------------------------
--  the door
-- -----------------------------------------------------------------------------
--
-- Defaulting to TRUE is the compatible answer: every clan that exists when
-- this lands keeps behaving exactly as it did, and a build that has never
-- heard of requests keeps working against it.
alter table public.clans
    add column if not exists open boolean not null default true;

-- A CAP, WHICH THE FIRST MIGRATION DID NOT HAVE.
--
-- It matters more now than it did. The roster page draws one row per member
-- with no virtualisation, `clan_view` aggregates every member into a single
-- jsonb payload on every read, and the receive cap that bounds the card economy
-- is per PLAYER -- so a thousand-member clan is a thousand-row page, a fat
-- payload on every open, and a thousand people who may each be sent to. Thirty
-- is a screen and a half of roster and is well above what a clan of friends
-- ever reaches.
create or replace function public.clan_max_members() returns integer
language sql immutable as $$ select 30 $$;

-- How many invites one clan may have in flight. Not a rule anybody will meet
-- honestly -- it exists so a modified client cannot write invite rows at every
-- account in the table and turn the badge into spam for the whole game.
create or replace function public.clan_invite_cap() returns integer
language sql immutable as $$ select 40 $$;

-- -----------------------------------------------------------------------------
--  the two pending things
-- -----------------------------------------------------------------------------

create table if not exists public.clan_invites (
    id          uuid primary key default gen_random_uuid(),
    clan_id     uuid not null references public.clans(id) on delete cascade,
    from_player uuid not null references public.players(id) on delete cascade,
    to_player   uuid not null references public.players(id) on delete cascade,
    created_at  timestamptz not null default now(),
    -- Cheap, and it is the rule the accept path would otherwise have to trust
    -- a function to have checked.
    constraint clan_invites_not_self check (from_player <> to_player)
);

-- ONE PENDING INVITE PER CLAN PER PLAYER, said by an index rather than by a
-- check inside invite_to_clan. Five members of one clan all inviting the same
-- person in the same minute is the normal case, not an attack, and without
-- this that person's badge reads "5" for one invitation.
create unique index if not exists clan_invites_uidx
    on public.clan_invites (clan_id, to_player);

create index if not exists clan_invites_to_idx
    on public.clan_invites (to_player, created_at desc);

create index if not exists clan_invites_clan_idx
    on public.clan_invites (clan_id);

create table if not exists public.clan_requests (
    id         uuid primary key default gen_random_uuid(),
    clan_id    uuid not null references public.clans(id) on delete cascade,
    player_id  uuid not null references public.players(id) on delete cascade,
    created_at timestamptz not null default now()
);

create unique index if not exists clan_requests_uidx
    on public.clan_requests (clan_id, player_id);

create index if not exists clan_requests_clan_idx
    on public.clan_requests (clan_id, created_at);

alter table public.clan_invites  enable row level security;
alter table public.clan_requests enable row level security;
-- No policies, exactly like clans and card_gifts.

-- -----------------------------------------------------------------------------
--  helpers
-- -----------------------------------------------------------------------------

-- The clan I am in, or null. Used by nearly everything below, and worth having
-- once rather than as six copies of the same select.
create or replace function public.my_clan_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select clan_id from public.clan_members
     where player_id = public.current_player()
$$;

-- -----------------------------------------------------------------------------
--  joining, now that a clan can say no
-- -----------------------------------------------------------------------------
--
-- join_clan is REPLACED rather than left alone, because a closed clan whose
-- door can still be walked through by an older build is not closed. An old
-- client calling this against a closed clan now gets `{"ok": false, "reason":
-- "closed"}`, which its existing refusal handler already renders as a sentence.
create or replace function public.join_clan(p_clan uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me    uuid := public.current_player();
    v_open  boolean;
    v_count integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if exists (select 1 from public.clan_members where player_id = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;
    -- The row is locked before the count moves, so two people joining the same
    -- clan in the same moment cannot both read `members` and write it back.
    select c.open, c.members into v_open, v_count
      from public.clans c where c.id = p_clan for update;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    if not v_open then
        return jsonb_build_object('ok', false, 'reason', 'closed');
    end if;
    if v_count >= public.clan_max_members() then
        return jsonb_build_object('ok', false, 'reason', 'full');
    end if;
    insert into public.clan_members (player_id, clan_id) values (v_me, p_clan);
    update public.clans set members = members + 1 where id = p_clan;
    -- Whatever else was pending for this player is now moot. Left behind, an
    -- invite accepted after the fact would try to move somebody who is already
    -- somewhere, and a stale request keeps a badge lit for a clan owner about
    -- a player who has since joined a different one.
    delete from public.clan_invites  where to_player = v_me;
    delete from public.clan_requests where player_id = v_me;
    return jsonb_build_object('ok', true, 'clan', public.clan_view(p_clan));
end;
$$;

-- The browse list, now carrying whether each clan takes walk-ins. The client
-- needs it to decide whether a row's button says JOIN or REQUEST -- offering
-- JOIN and then refusing it is exactly the "broken feature" read the clans-not-
-- ready card exists to avoid.
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
                   'full', x.members >= public.clan_max_members())
               order by x.members desc, x.created_at desc)
          from (select c.id, c.name, c.emoji, c.members, c.open, c.created_at
                  from public.clans c
                 order by c.members desc, c.created_at desc
                 limit least(greatest(coalesce(p_limit, 30), 1), 50)) x), '[]'::jsonb)
$$;

-- clan_view gains `open` for the same reason: the roster page has to be able to
-- draw the owner's own door switch in the position it is actually in.
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
               'members', coalesce((
                   select jsonb_agg(public.public_player(m.player_id)
                                    order by m.joined_at)
                     from public.clan_members m
                    where m.clan_id = c.id), '[]'::jsonb))
      from public.clans c
     where c.id = p_clan
$$;

-- Owner only, and it is the owner rather than any member on purpose: the door
-- decides who the roster is, and a roster every member can rewrite the terms of
-- is one nobody owns.
create or replace function public.set_clan_open(p_open boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_clan uuid := public.my_clan_id();
begin
    if v_me is null or v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'no_clan');
    end if;
    if not exists (select 1 from public.clans where id = v_clan and owner = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'not_owner');
    end if;
    update public.clans set open = coalesce(p_open, true) where id = v_clan;
    -- Opening the door answers every request standing at it. Leaving them
    -- pending would keep the owner's badge lit for approvals that no longer
    -- have to happen, and the player can simply walk in now.
    if coalesce(p_open, true) then
        delete from public.clan_requests where clan_id = v_clan;
    end if;
    return jsonb_build_object('ok', true, 'clan', public.clan_view(v_clan));
end;
$$;

-- =============================================================================
--  requests -- a player knocking on a closed clan
-- =============================================================================

create or replace function public.request_join_clan(p_clan uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me    uuid := public.current_player();
    v_open  boolean;
    v_count integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if exists (select 1 from public.clan_members where player_id = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;
    select c.open, c.members into v_open, v_count from public.clans c where c.id = p_clan;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    if v_count >= public.clan_max_members() then
        return jsonb_build_object('ok', false, 'reason', 'full');
    end if;
    -- An open clan does not take requests: there is nothing to grant. Saying so
    -- rather than filing a row nobody will ever look at is what stops a player
    -- waiting on an approval that is not coming.
    if v_open then
        return jsonb_build_object('ok', false, 'reason', 'open');
    end if;
    insert into public.clan_requests (clan_id, player_id) values (p_clan, v_me)
        on conflict (clan_id, player_id) do nothing;
    return jsonb_build_object('ok', true);
end;
$$;

-- Withdrawing. A player who has knocked on four doors and got into a fifth is
-- handled by join_clan's sweep; this is for the one who changed their mind.
create or replace function public.cancel_clan_request(p_clan uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
begin
    if v_me is null then
        return jsonb_build_object('ok', true);
    end if;
    delete from public.clan_requests where player_id = v_me and clan_id = p_clan;
    return jsonb_build_object('ok', true);
end;
$$;

-- What the owner has waiting. Reused `public_player` again, so a knock at the
-- door reveals no more about somebody than the leaderboard already does.
create or replace function public.clan_join_requests()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_clan uuid := public.my_clan_id();
begin
    if v_me is null or v_clan is null then
        return '[]'::jsonb;
    end if;
    if not exists (select 1 from public.clans where id = v_clan and owner = v_me) then
        return '[]'::jsonb;
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'id', r.id, 'player', public.public_player(r.player_id))
               order by r.created_at)
          from (select id, player_id, created_at
                  from public.clan_requests
                 where clan_id = v_clan
                 order by created_at
                 limit 50) r), '[]'::jsonb);
end;
$$;

create or replace function public.answer_clan_request(p_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me    uuid := public.current_player();
    v_clan  uuid := public.my_clan_id();
    v_who   uuid;
    v_count integer;
begin
    if v_me is null or v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'no_clan');
    end if;
    if not exists (select 1 from public.clans where id = v_clan and owner = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'not_owner');
    end if;
    -- Scoped to MY clan in the delete itself. An id is a guess away from being
    -- another clan's request, and an owner answering somebody else's door is
    -- the one thing an id-addressed call has to be unable to do.
    delete from public.clan_requests
     where id = p_id and clan_id = v_clan
 returning player_id into v_who;
    if v_who is null then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    if not coalesce(p_accept, false) then
        return jsonb_build_object('ok', true, 'joined', false);
    end if;
    -- The applicant may have joined somewhere else while this sat in the
    -- owner's list, which is not an error -- it is simply late.
    if exists (select 1 from public.clan_members where player_id = v_who) then
        return jsonb_build_object('ok', true, 'joined', false, 'reason', 'already_in_clan');
    end if;
    select members into v_count from public.clans where id = v_clan for update;
    if v_count >= public.clan_max_members() then
        return jsonb_build_object('ok', false, 'reason', 'full');
    end if;
    insert into public.clan_members (player_id, clan_id) values (v_who, v_clan);
    update public.clans set members = members + 1 where id = v_clan;
    delete from public.clan_invites  where to_player = v_who;
    delete from public.clan_requests where player_id = v_who;
    return jsonb_build_object('ok', true, 'joined', true,
                              'clan', public.clan_view(v_clan));
end;
$$;

-- =============================================================================
--  invites -- a clan asking for one player
-- =============================================================================
--
-- ANY MEMBER MAY INVITE, not only the owner. A clan of friends recruits by
-- everybody bringing somebody, and routing that through one person makes the
-- owner a bottleneck on the only thing that grows a clan. The owner keeps the
-- powers that are about the clan's shape -- the door, and who gets in through
-- it -- and an invite is answered by the person it names anyway, so the worst
-- a bad member can do is send a notification somebody declines.
create or replace function public.invite_to_clan(p_to uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me      uuid := public.current_player();
    v_clan    uuid := public.my_clan_id();
    v_count   integer;
    v_pending integer;
begin
    if v_me is null or v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'no_clan');
    end if;
    if p_to is null or p_to = v_me then
        return jsonb_build_object('ok', false, 'reason', 'self');
    end if;
    if not exists (select 1 from public.players where id = p_to) then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    if exists (select 1 from public.clan_members where player_id = p_to) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;
    select members into v_count from public.clans where id = v_clan;
    if v_count >= public.clan_max_members() then
        return jsonb_build_object('ok', false, 'reason', 'full');
    end if;
    select count(*) into v_pending from public.clan_invites where clan_id = v_clan;
    if v_pending >= public.clan_invite_cap() then
        return jsonb_build_object('ok', false, 'reason', 'too_many');
    end if;
    insert into public.clan_invites (clan_id, from_player, to_player)
         values (v_clan, v_me, p_to)
    on conflict (clan_id, to_player) do nothing;
    return jsonb_build_object('ok', true);
end;
$$;

-- Mine, waiting. Each carries who sent it and how big the clan is, because
-- "Rex invited you to Sea Dogs (7)" is the whole of what the decision needs.
create or replace function public.my_clan_invites()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
begin
    if v_me is null then
        return '[]'::jsonb;
    end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'id',      i.id,
                   'clan_id', c.id,
                   'name',    c.name,
                   'emoji',   c.emoji,
                   'members', c.members,
                   'from',    public.public_player(i.from_player))
               order by i.created_at desc)
          from (select id, clan_id, from_player, created_at
                  from public.clan_invites
                 where to_player = v_me
                 order by created_at desc
                 limit 30) i
          join public.clans c on c.id = i.clan_id), '[]'::jsonb);
end;
$$;

-- An invite is a key to a door, so accepting it walks past `open` on purpose:
-- being asked by a member IS the approval a closed clan's request queue exists
-- to collect.
create or replace function public.accept_clan_invite(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me    uuid := public.current_player();
    v_clan  uuid;
    v_count integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if exists (select 1 from public.clan_members where player_id = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;
    -- Scoped to invites addressed to ME, so a guessed id is not a way in.
    select clan_id into v_clan from public.clan_invites
     where id = p_id and to_player = v_me;
    if v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    select members into v_count from public.clans where id = v_clan for update;
    if not found then
        delete from public.clan_invites where id = p_id;
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    if v_count >= public.clan_max_members() then
        return jsonb_build_object('ok', false, 'reason', 'full');
    end if;
    insert into public.clan_members (player_id, clan_id) values (v_me, v_clan);
    update public.clans set members = members + 1 where id = v_clan;
    delete from public.clan_invites  where to_player = v_me;
    delete from public.clan_requests where player_id = v_me;
    return jsonb_build_object('ok', true, 'clan', public.clan_view(v_clan));
end;
$$;

create or replace function public.decline_clan_invite(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
begin
    if v_me is null then
        return jsonb_build_object('ok', true);
    end if;
    delete from public.clan_invites where id = p_id and to_player = v_me;
    return jsonb_build_object('ok', true);
end;
$$;

-- =============================================================================
--  finding somebody to invite
-- =============================================================================
--
-- An invite needs a person, and until now the client had no way to name one:
-- the only players it ever learns the id of are the rivals matchmaking hands
-- it, which are mostly bots. So a search, deliberately narrow.
--
-- It matches on `normalize_name` -- the same folding the uniqueness index uses,
-- so a player typing "sea dogs" finds "SeaDogs" -- and it is a PREFIX match
-- rather than a contains. A contains search over a player table is a way to
-- enumerate it three letters at a time; a prefix search answers "I know who I
-- am looking for" and little else. It returns nothing for a query under three
-- characters for the same reason, and only players who are not already in a
-- clan, because everybody else is not invitable anyway.
create or replace function public.find_players(p_query text, p_limit integer default 12)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
    v_q  text := public.normalize_name(coalesce(p_query, ''));
begin
    if v_me is null or length(v_q) < 3 then
        return '[]'::jsonb;
    end if;
    return coalesce((
        select jsonb_agg(public.public_player(x.id) order by x.name)
          from (select p.id, p.name
                  from public.players p
                 where p.id <> v_me
                   and public.normalize_name(p.name) like v_q || '%'
                   and not exists (select 1 from public.clan_members m
                                    where m.player_id = p.id)
                 order by p.name
                 limit least(greatest(coalesce(p_limit, 12), 1), 25)) x), '[]'::jsonb);
end;
$$;

-- =============================================================================
--  the number on the button
-- =============================================================================
--
-- One call, two counts, because the badge is drawn on every page in the game
-- and must not cost two round trips to decide whether to be visible. Requests
-- come back zero for anybody who is not the owner of their clan, so the client
-- does not have to know the rule to render the right number.
create or replace function public.clan_news()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_clan uuid := public.my_clan_id();
    v_inv  integer := 0;
    v_req  integer := 0;
begin
    if v_me is null then
        return jsonb_build_object('invites', 0, 'requests', 0);
    end if;
    select count(*) into v_inv from public.clan_invites where to_player = v_me;
    if v_clan is not null then
        select count(*) into v_req
          from public.clan_requests r
          join public.clans c on c.id = r.clan_id
         where r.clan_id = v_clan and c.owner = v_me;
    end if;
    return jsonb_build_object('invites', v_inv, 'requests', v_req);
end;
$$;

-- -----------------------------------------------------------------------------
--  privileges
-- -----------------------------------------------------------------------------
--
-- Same block every migration in this project ends with, and it covers more than
-- the new functions: recreating a function resets its privileges to the
-- default, and join_clan, clan_list and clan_view were all replaced above. A
-- migration that grants only what it invented leaves three functions the whole
-- feature depends on revoked from the only role that calls them.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('join_clan', 'clan_list', 'clan_view',
                             'clan_max_members', 'clan_invite_cap', 'my_clan_id',
                             'set_clan_open', 'request_join_clan',
                             'cancel_clan_request', 'clan_join_requests',
                             'answer_clan_request', 'invite_to_clan',
                             'my_clan_invites', 'accept_clan_invite',
                             'decline_clan_invite', 'find_players', 'clan_news')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
