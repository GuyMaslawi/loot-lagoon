-- =============================================================================
--  Loot Lagoon -- a clan you can talk in, ask in, and be asked to earn
-- =============================================================================
--
-- Guy, 2026-09-14, five notes about the clan page. Four of them are layout and
-- live in main.gd. These are the ones that need the server to hold something
-- it does not hold yet:
--
--   * A SEARCH FIELD over clans, beside CREATE, for a player who has none.
--     -> find_clans.
--   * A CLAN'S STAR REQUIREMENT, shown to somebody looking at it from outside
--     before they knock. -> clans.min_stars, set_clan_min_stars, and the check
--     inside join_clan / request_join_clan.
--   * A CLAN CHAT. -> clan_messages, say_clan, clan_chat.
--   * ASKING THE CLAN FOR SPINS: a line in the chat with a bar on it, up to ten
--     clanmates may each drop three spins into it, one ask per player per five
--     hours. -> ask_clan_help('spins') + donate_clan_help + spin_gifts.
--   * ASKING FOR A CARD, and only for a 1-, 2- or 3-star one.
--     -> ask_clan_help('cards'), which routes its donations through the same
--     rules send_card already enforces.
--
-- THE CHAT IS USER-GENERATED CONTENT, WHICH IS A STORE QUESTION, NOT A FEATURE
-- QUESTION. 20260904170000 said so at length and declined to build it for that
-- reason; Guy has now asked for it, so it is built with the four things
-- guideline 1.2 actually requires around it rather than without them:
--
--   1. FILTERING. say_clan runs the same banned_words list display names go
--      through (20260824161500) and refuses the message rather than starring it
--      out -- a masked word is still the message being delivered.
--   2. REPORTING. report_player already exists and the chat row carries the
--      author's id, so every line in the chat is one tap from it.
--   3. BLOCKING. blocks already exists, and clan_chat drops both directions of
--      it -- somebody you blocked does not get to talk to you by joining your
--      clan.
--   4. AN EULA. This is the half that is still MISSING and no SQL can supply
--      it: the terms page has to name the no-objectionable-content rule and the
--      App Store's standard licence terms have to be accepted. See the note in
--      the client's chat composer.
--
-- Everything follows the house rules the clan migrations set: no RLS policies,
-- every read and write through a SECURITY DEFINER function, and a refusal is a
-- jsonb {"ok": false, "reason": ...} rather than an exception.

-- -----------------------------------------------------------------------------
--  the numbers, as functions
-- -----------------------------------------------------------------------------
--
-- Same reasoning as clan_max_members: a number the client mirrors so it can
-- refuse politely, and the server holds so a modified client cannot.

-- What one clanmate drops into somebody's spin ask. Guy's figure.
create or replace function public.clan_help_spins() returns integer
language sql immutable as $$ select 3 $$;

-- How many clanmates may answer ONE ask. Guy's figure, and it is the whole
-- bound on this feature: 10 x 3 = 30 spins is what an ask is worth, at most.
create or replace function public.clan_help_donors() returns integer
language sql immutable as $$ select 10 $$;

-- How often one player may ask. Guy's figure. It is PER KIND: a spin ask and a
-- card ask are different favours, and one shared clock would mean asking for a
-- card costs you your spins for five hours.
--
-- THE WHOLE INFLOW IS THIS TIMES THAT: 30 spins every five hours is 144 a day
-- if every ask fills and nobody ever sleeps, against a daily bonus that is 19.
-- It is bounded, it is not small, and it is deliberately one function to turn
-- down -- see the note Guy was given when this shipped.
create or replace function public.clan_ask_cooldown() returns interval
language sql immutable as $$ select interval '5 hours' $$;

-- How much chat is kept, and how much of it one call hands back. A clan page
-- draws one un-virtualised row per message, same as the roster does per member.
create or replace function public.clan_chat_keep() returns interval
language sql immutable as $$ select interval '3 days' $$;

-- -----------------------------------------------------------------------------
--  a clan may now ask for something before it opens its door
-- -----------------------------------------------------------------------------
--
-- Defaulting to 0 is the compatible answer: every clan that exists when this
-- lands keeps taking anyone, and a build that has never heard of the column
-- keeps working against it.
--
-- IT IS CHECKED ON join_clan AND request_join_clan, AND DELIBERATELY NOT ON
-- accept_clan_invite. Being invited by a member IS the approval -- that is the
-- rule the closed door already follows, and a threshold that overrode a named
-- invitation would mean a clan could not choose to make an exception for
-- somebody it actually wanted.
alter table public.clans
    add column if not exists min_stars integer not null default 0;

create or replace function public.set_clan_min_stars(p_stars integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_clan uuid := public.my_clan_id();
    v_want integer := least(greatest(coalesce(p_stars, 0), 0), 1000000);
begin
    if v_me is null or v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'no_clan');
    end if;
    if not exists (select 1 from public.clans where id = v_clan and owner = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'not_owner');
    end if;
    update public.clans set min_stars = v_want where id = v_clan;
    -- Raising the bar answers every request standing under it, for the same
    -- reason opening the door answers every request standing at it: the owner's
    -- badge must not stay lit for approvals that can no longer be granted.
    delete from public.clan_requests r
     using public.players p
     where r.clan_id = v_clan and p.id = r.player_id and p.rank_stars < v_want;
    return jsonb_build_object('ok', true, 'clan', public.clan_view(v_clan));
end;
$$;

-- join_clan is REPLACED so an older build cannot walk past a bar it has never
-- heard of, exactly as 20260904170000 replaced it so an older build could not
-- walk through a closed door. An old client gets {"ok": false, "reason":
-- "stars"}, which its existing refusal handler renders as a sentence.
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
    v_bar   integer;
    v_mine  integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if exists (select 1 from public.clan_members where player_id = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;
    select c.open, c.members, c.min_stars into v_open, v_count, v_bar
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
    select rank_stars into v_mine from public.players where id = v_me;
    if coalesce(v_bar, 0) > 0 and coalesce(v_mine, 0) < v_bar then
        return jsonb_build_object('ok', false, 'reason', 'stars', 'need', v_bar);
    end if;
    insert into public.clan_members (player_id, clan_id) values (v_me, p_clan);
    update public.clans set members = members + 1 where id = p_clan;
    delete from public.clan_invites  where to_player = v_me;
    delete from public.clan_requests where player_id = v_me;
    return jsonb_build_object('ok', true, 'clan', public.clan_view(p_clan));
end;
$$;

-- Knocking on a door you could not walk through even if it opened is the same
-- wait-for-an-answer-that-is-not-coming that request_join_clan already refuses
-- for an OPEN clan. Same shape, one more reason.
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
    v_bar   integer;
    v_mine  integer;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if exists (select 1 from public.clan_members where player_id = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already_in_clan');
    end if;
    select c.open, c.members, c.min_stars into v_open, v_count, v_bar
      from public.clans c where c.id = p_clan;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    if v_count >= public.clan_max_members() then
        return jsonb_build_object('ok', false, 'reason', 'full');
    end if;
    if v_open then
        return jsonb_build_object('ok', false, 'reason', 'open');
    end if;
    select rank_stars into v_mine from public.players where id = v_me;
    if coalesce(v_bar, 0) > 0 and coalesce(v_mine, 0) < v_bar then
        return jsonb_build_object('ok', false, 'reason', 'stars', 'need', v_bar);
    end if;
    insert into public.clan_requests (clan_id, player_id) values (p_clan, v_me)
        on conflict (clan_id, player_id) do nothing;
    return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
--  the two readers, carrying the bar
-- -----------------------------------------------------------------------------
--
-- `min_stars` is additive in exactly the way `stars` and `open` were before it:
-- a client that has not been updated draws the rows it already knew how to
-- draw. `max` goes out too, so the detail dialog can say "8 / 30" without
-- mirroring clan_max_members() a second time in a second language.
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
                   'min_stars', x.min_stars,
                   'max', public.clan_max_members(),
                   'full', x.members >= public.clan_max_members())
               order by x.rank)
          from (select c.id, c.name, c.emoji, c.members, c.open, c.min_stars,
                       st.stars, st.rank
                  from public.clans c
                  join public.clan_standings() st on st.clan_id = c.id
                 order by st.rank
                 limit least(greatest(coalesce(p_limit, 30), 1), 50)) x), '[]'::jsonb)
$$;

create or replace function public.clan_view(p_clan uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
               'id',        c.id,
               'name',      c.name,
               'emoji',     c.emoji,
               'owner',     c.owner,
               'open',      c.open,
               'min_stars', c.min_stars,
               'max',       public.clan_max_members(),
               'full',      c.members >= public.clan_max_members(),
               'stars',     coalesce(st.stars, 0),
               'rank',      coalesce(st.rank, 0),
               -- A soft-deleted island answers NULL out of public_player, and a
               -- JSON null in this array is the hole 20260907200000 describes.
               -- The departures migration evicts them; this is the belt to that
               -- migration's braces, since the roster is drawn from here.
               'members', coalesce((
                   select jsonb_agg(public.public_player(m.player_id)
                                    order by m.joined_at)
                     from public.clan_members m
                     join public.players p on p.id = m.player_id
                    where m.clan_id = c.id and p.deleted_at is null), '[]'::jsonb))
      from public.clans c
      left join public.clan_standings() st on st.clan_id = c.id
     where c.id = p_clan
$$;

-- -----------------------------------------------------------------------------
--  finding a clan by name
-- -----------------------------------------------------------------------------
--
-- A PREFIX MATCH, LIKE find_players, AND FOR A WEAKER REASON. A clan list is
-- already public and already enumerable thirty rows at a time through
-- clan_list, so this is not defending anything the league table does not give
-- away -- it is a prefix so that `like` can use an index if this table ever
-- grows one, and so the behaviour is the one players have already met on the
-- invite screen.
--
-- Two characters, not three: clan names start at three characters and "Kr" is
-- a reasonable thing to type at one.
create or replace function public.find_clans(p_query text, p_limit integer default 20)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_q    text := public.normalize_name(coalesce(p_query, ''));
    v_like text;
begin
    if length(v_q) < 2 then
        return '[]'::jsonb;
    end if;
    -- THE LIKE METACHARACTERS ARE ESCAPED, WHICH IS NOT OPTIONAL. This is the
    -- find_players hole from 20260909120000, one feature later: normalize_name
    -- does not touch % or _, so `%%` sails past the length guard and becomes
    -- `like '%%%'` -- every clan in the table, in one call, ordered by rank.
    -- Backslash first, then % and _, so the default LIKE escape applies and the
    -- caller's text can only ever anchor a prefix. Caught by the test, not by
    -- reading it.
    v_like := replace(replace(replace(v_q, '\\', '\\\\'), '%', '\\%'), '_', '\\_');
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'id', x.id, 'name', x.name, 'emoji', x.emoji,
                   'members', x.members, 'open', x.open,
                   'stars', x.stars, 'rank', x.rank,
                   'min_stars', x.min_stars,
                   'max', public.clan_max_members(),
                   'full', x.members >= public.clan_max_members())
               order by x.rank)
          from (select c.id, c.name, c.emoji, c.members, c.open, c.min_stars,
                       st.stars, st.rank
                  from public.clans c
                  join public.clan_standings() st on st.clan_id = c.id
                 where public.normalize_name(c.name) like v_like || '%'
                 order by st.rank
                 limit least(greatest(coalesce(p_limit, 20), 1), 30)) x), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
--  the chat, and the two things you can ask it for
-- -----------------------------------------------------------------------------
--
-- ONE TABLE FOR ALL THREE KINDS, because all three are lines in the same
-- scroll and the only thing the reader does differently with them is what it
-- draws on the right-hand end. A separate requests table would mean merging two
-- streams by timestamp on every read, in two places, for no gain.
create table if not exists public.clan_messages (
    id         uuid primary key default gen_random_uuid(),
    clan_id    uuid not null references public.clans(id)   on delete cascade,
    player_id  uuid not null references public.players(id) on delete cascade,
    kind       text not null check (kind in ('say', 'spins', 'cards')),
    -- 'say' only. Held as typed; the filtering happens before the insert.
    body       text,
    -- 'cards' only: which card is being asked for, and how good it is.
    set_id     text,
    card_idx   integer,
    stars      integer,
    created_at timestamptz not null default now(),
    -- THE STAR CEILING ON AN ASK, AS A CONSTRAINT AND NOT ONLY AS A CHECK IN A
    -- FUNCTION. Guy: "only cards that are one, two or three stars". Same
    -- belt-and-braces as card_gifts' own no-golds constraint, and for the same
    -- reason -- a later rewrite of the function cannot lose it.
    constraint clan_messages_ask_stars check (
        kind <> 'cards' or (stars between 1 and 3 and set_id is not null
                            and card_idx is not null and card_idx >= 0)),
    constraint clan_messages_say_body check (
        kind <> 'say' or (body is not null and length(body) between 1 and 140))
);

-- The chat's only read pattern: this clan, newest first.
create index if not exists clan_messages_clan_idx
    on public.clan_messages (clan_id, created_at desc);

-- The cooldown's only read pattern: my last ask of this kind.
create index if not exists clan_messages_ask_idx
    on public.clan_messages (player_id, kind, created_at desc)
    where kind <> 'say';

-- WHO ANSWERED AN ASK. The primary key IS the "one clanmate, one donation"
-- rule -- said by the index rather than by a count inside the function, for
-- the same reason clan_invites_uidx says one invite per clan per player.
create table if not exists public.clan_help (
    message_id uuid not null references public.clan_messages(id) on delete cascade,
    donor      uuid not null references public.players(id)       on delete cascade,
    created_at timestamptz not null default now(),
    primary key (message_id, donor)
);

-- SPINS THAT HAVE BEEN GIVEN BUT NOT YET LANDED, which is the same shape
-- card_gifts has and for the same reason: the receiver may be asleep, and a
-- counter moves on the device it belongs to, when the thing arrives.
-- (See the held-counter rule in main.gd: the number moves when the thing lands.)
create table if not exists public.spin_gifts (
    id          uuid primary key default gen_random_uuid(),
    to_player   uuid not null references public.players(id) on delete cascade,
    from_player uuid not null references public.players(id) on delete cascade,
    spins       integer not null check (spins > 0 and spins <= 50),
    created_at  timestamptz not null default now(),
    seen_at     timestamptz,
    constraint spin_gifts_not_self check (to_player <> from_player)
);

create index if not exists spin_gifts_unseen_idx
    on public.spin_gifts (to_player, created_at) where seen_at is null;

alter table public.clan_messages enable row level security;
alter table public.clan_help     enable row level security;
alter table public.spin_gifts    enable row level security;
-- No policies, exactly like clans, card_gifts, clan_invites and clan_requests.

-- -----------------------------------------------------------------------------
--  saying something
-- -----------------------------------------------------------------------------
--
-- THE WORD FILTER REFUSES THE MESSAGE RATHER THAN MASKING IT. A starred-out
-- word is the message being delivered with a costume on, and the player learns
-- the shape of the filter rather than that the rule exists. Same list the
-- display names go through, so it is one list to maintain.
--
-- THE RATE LIMIT IS TWO COUNTS, not one. The short one stops a jammed finger
-- and an autoclicker; the hourly one stops somebody settling in to fill a
-- clan's scroll with one line a minute for an afternoon. Neither is reachable
-- by a person typing.
create or replace function public.say_clan(p_body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me    uuid := public.current_player();
    v_clan  uuid := public.my_clan_id();
    v_text  text;
    v_norm  text;
    v_last  timestamptz;
    v_hour  integer;
    v_id    uuid;
begin
    if v_me is null or v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'no_clan');
    end if;
    -- Control characters out first, then collapse whitespace: a message that is
    -- forty newlines is a message that owns the whole scroll.
    v_text := btrim(regexp_replace(
                  regexp_replace(coalesce(p_body, ''), '[[:cntrl:]]+', ' ', 'g'),
                  '\s+', ' ', 'g'));
    if length(v_text) < 1 then
        return jsonb_build_object('ok', false, 'reason', 'empty');
    end if;
    if length(v_text) > 140 then
        return jsonb_build_object('ok', false, 'reason', 'long');
    end if;

    -- normalize_name lowercases and strips the decoration people hide words
    -- behind; it is the same normalisation the name filter matches on.
    v_norm := public.normalize_name(v_text);
    if exists (select 1 from public.banned_words b
                where v_norm like '%' || b.word || '%') then
        return jsonb_build_object('ok', false, 'reason', 'language');
    end if;

    select max(created_at) into v_last from public.clan_messages
     where player_id = v_me;
    if v_last is not null and v_last > now() - interval '2 seconds' then
        return jsonb_build_object('ok', false, 'reason', 'too_fast');
    end if;
    select count(*) into v_hour from public.clan_messages
     where player_id = v_me and kind = 'say'
       and created_at > now() - interval '1 hour';
    if v_hour >= 30 then
        return jsonb_build_object('ok', false, 'reason', 'too_many');
    end if;

    insert into public.clan_messages (clan_id, player_id, kind, body)
         values (v_clan, v_me, 'say', v_text)
      returning id into v_id;

    -- Swept here rather than on a schedule, because there is no scheduler on
    -- this project and a clan's scroll is only ever too long for the clan that
    -- is actively filling it. Bounded by the clan index above.
    delete from public.clan_messages
     where clan_id = v_clan and created_at < now() - public.clan_chat_keep();

    return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- -----------------------------------------------------------------------------
--  asking the clan for something
-- -----------------------------------------------------------------------------
--
-- An ask IS a chat line. It is not a separate object with its own list, because
-- the thing Guy described is a bar sitting in the conversation next to the name
-- of whoever wants it.
create or replace function public.ask_clan_help(
    p_kind  text,
    p_set   text default null,
    p_idx   integer default null,
    p_stars integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_clan uuid := public.my_clan_id();
    v_kind text := lower(btrim(coalesce(p_kind, '')));
    v_last timestamptz;
    v_id   uuid;
begin
    if v_me is null or v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'no_clan');
    end if;
    if v_kind not in ('spins', 'cards') then
        return jsonb_build_object('ok', false, 'reason', 'kind');
    end if;
    if v_kind = 'cards' then
        -- GOLDS AND FOUR-STARS ARE NOT ASKABLE. Guy named one, two and three.
        -- The constraint on the table says it too.
        if p_stars is null or p_stars < 1 or p_stars > 3 then
            return jsonb_build_object('ok', false, 'reason', 'stars');
        end if;
        if p_set is null or btrim(p_set) = '' or p_idx is null or p_idx < 0 then
            return jsonb_build_object('ok', false, 'reason', 'card');
        end if;
    end if;

    -- THE COOLDOWN IS PER KIND, and the wait is answered in seconds rather than
    -- as a refusal on its own: a button that says "in 3h 40m" is a button that
    -- was worth pressing once.
    select max(created_at) into v_last from public.clan_messages
     where player_id = v_me and kind = v_kind;
    if v_last is not null and v_last > now() - public.clan_ask_cooldown() then
        return jsonb_build_object('ok', false, 'reason', 'too_soon',
            'wait', ceil(extract(epoch from
                (v_last + public.clan_ask_cooldown()) - now()))::integer);
    end if;

    insert into public.clan_messages (clan_id, player_id, kind, set_id, card_idx, stars)
         values (v_clan, v_me, v_kind,
                 case when v_kind = 'cards' then btrim(p_set) end,
                 case when v_kind = 'cards' then p_idx end,
                 case when v_kind = 'cards' then p_stars end)
      returning id into v_id;

    delete from public.clan_messages
     where clan_id = v_clan and created_at < now() - public.clan_chat_keep();

    return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- -----------------------------------------------------------------------------
--  answering one
-- -----------------------------------------------------------------------------
--
-- ONE FUNCTION FOR BOTH KINDS, and that is not tidiness -- it is the only way
-- the donor row and the thing donated land in the SAME TRANSACTION. Two calls
-- (send the card, then mark the ask) leave a hole where the card has moved and
-- the bar has not, and the reverse hole where the bar has filled and nothing
-- was sent.
--
-- GIVING SPINS COSTS THE GIVER NOTHING. That is the model Guy described
-- ("whoever presses it, as it were, donates three spins") and the one every
-- game of this shape uses: the favour is free to do, which is what makes it
-- worth doing, and the ceiling on the whole thing is the ask's ten seats and
-- the asker's five-hour clock -- not the giver's purse.
--
-- GIVING A CARD COSTS THE GIVER THE CARD, through exactly the rules send_card
-- already enforces: no golds, clanmates only, and both daily caps. The ask
-- cannot be a way around any of them.
create or replace function public.donate_clan_help(p_message uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me     uuid := public.current_player();
    v_clan   uuid := public.my_clan_id();
    v_msg    public.clan_messages%rowtype;
    v_taken  integer;
    v_sent   integer;
    v_got    integer;
    v_spins  integer := public.clan_help_spins();
begin
    if v_me is null or v_clan is null then
        return jsonb_build_object('ok', false, 'reason', 'no_clan');
    end if;
    -- Locked before the seats are counted, so ten people pressing at once
    -- cannot all read nine and all write ten. Same lesson as join_clan's
    -- `for update` on the roster count.
    select * into v_msg from public.clan_messages
     where id = p_message for update;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;
    if v_msg.clan_id <> v_clan then
        return jsonb_build_object('ok', false, 'reason', 'not_clanmates');
    end if;
    if v_msg.kind = 'say' then
        return jsonb_build_object('ok', false, 'reason', 'kind');
    end if;
    if v_msg.player_id = v_me then
        return jsonb_build_object('ok', false, 'reason', 'self');
    end if;
    -- AN ASK GOES QUIET WHEN ITS CLOCK RUNS OUT, not when it scrolls away. A
    -- bar somebody can still fill six days later is a bar that pays a player
    -- for something they asked for last week and have long since bought.
    if v_msg.created_at < now() - public.clan_ask_cooldown() then
        return jsonb_build_object('ok', false, 'reason', 'expired');
    end if;
    select count(*) into v_taken from public.clan_help where message_id = p_message;
    if v_taken >= public.clan_help_donors() then
        return jsonb_build_object('ok', false, 'reason', 'filled');
    end if;
    if exists (select 1 from public.clan_help
                where message_id = p_message and donor = v_me) then
        return jsonb_build_object('ok', false, 'reason', 'already');
    end if;

    -- Both player rows locked in uuid order before anything is written, which
    -- is the record_raid deadlock lesson send_card already follows: A helping B
    -- against B helping A is a lock cycle unless the order is fixed.
    perform 1 from public.players
             where id in (v_me, v_msg.player_id) and deleted_at is null
             order by id for update;
    if not found then
        return jsonb_build_object('ok', false, 'reason', 'gone');
    end if;

    if v_msg.kind = 'cards' then
        -- The same two caps send_card counts, counted here for the same reason
        -- -- inside the transaction that writes the gift.
        select count(*) into v_sent from public.card_gifts
         where from_player = v_me and created_at > now() - interval '24 hours';
        if v_sent >= public.gift_give_cap() then
            return jsonb_build_object('ok', false, 'reason', 'give_cap',
                                      'cap', public.gift_give_cap());
        end if;
        select count(*) into v_got from public.card_gifts
         where to_player = v_msg.player_id and created_at > now() - interval '24 hours';
        if v_got >= public.gift_receive_cap() then
            return jsonb_build_object('ok', false, 'reason', 'their_cap',
                                      'cap', public.gift_receive_cap());
        end if;
        insert into public.card_gifts (from_player, to_player, set_id, card_idx, stars)
             values (v_me, v_msg.player_id, v_msg.set_id, v_msg.card_idx, v_msg.stars);
    else
        insert into public.spin_gifts (to_player, from_player, spins)
             values (v_msg.player_id, v_me, v_spins);
    end if;

    insert into public.clan_help (message_id, donor) values (p_message, v_me);

    return jsonb_build_object('ok', true,
        'filled', v_taken + 1,
        'cap', public.clan_help_donors(),
        'spins', case when v_msg.kind = 'spins' then v_spins else 0 end,
        'sent_today', case when v_msg.kind = 'cards' then v_sent + 1 else null end,
        'give_cap', public.gift_give_cap());
end;
$$;

-- -----------------------------------------------------------------------------
--  reading it
-- -----------------------------------------------------------------------------
--
-- OLDEST LAST, WHICH IS WHAT A CHAT IS. The limit is taken INSIDE the subquery
-- and the order flipped outside it -- that is the unseen_raids bug (a LIMIT
-- outside jsonb_agg limits rows the aggregate has already collapsed to one),
-- and the reason it is written this way rather than the obvious way.
--
-- BLOCKS ARE APPLIED IN BOTH DIRECTIONS. Somebody a player blocked does not get
-- to talk to them by joining their clan, and the block is not a signal the
-- blocked player gets to read either -- their own lines are still there for
-- them, they simply do not appear for the person who blocked them.
create or replace function public.clan_chat(p_limit integer default 60)
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
    return coalesce((
        select jsonb_agg(jsonb_build_object(
                   'id',     x.id,
                   'kind',   x.kind,
                   'body',   x.body,
                   'set',    x.set_id,
                   'idx',    x.card_idx,
                   'stars',  x.stars,
                   'at',     extract(epoch from x.created_at),
                   'by',     public.public_player(x.player_id),
                   'mine',   x.player_id = v_me,
                   'filled', x.filled,
                   'cap',    public.clan_help_donors(),
                   'gave',   x.gave,
                   -- Said by the server rather than worked out from `at` on a
                   -- phone whose clock is its own business.
                   'closed', x.kind <> 'say'
                             and (x.filled >= public.clan_help_donors()
                                  or x.created_at < now() - public.clan_ask_cooldown()))
               order by x.created_at)
          from (select m.id, m.kind, m.body, m.set_id, m.card_idx, m.stars,
                       m.created_at, m.player_id,
                       (select count(*) from public.clan_help h
                         where h.message_id = m.id)::integer as filled,
                       exists (select 1 from public.clan_help h
                                where h.message_id = m.id and h.donor = v_me) as gave
                  from public.clan_messages m
                  join public.players p on p.id = m.player_id
                 where m.clan_id = v_clan
                   and p.deleted_at is null
                   and not exists (select 1 from public.blocks bl
                                    where (bl.blocker = v_me and bl.blocked = m.player_id)
                                       or (bl.blocker = m.player_id and bl.blocked = v_me))
                 order by m.created_at desc
                 limit least(greatest(coalesce(p_limit, 60), 1), 100)) x), '[]'::jsonb);
end;
$$;

-- When I may next ask for each thing, so the two buttons in the composer can
-- say "in 3h 40m" instead of being pressed and refused. Rides along with the
-- chat read rather than costing its own round trip.
create or replace function public.clan_ask_state()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me    uuid := public.current_player();
    v_spins timestamptz;
    v_cards timestamptz;
begin
    if v_me is null then
        return '{}'::jsonb;
    end if;
    select max(created_at) into v_spins from public.clan_messages
     where player_id = v_me and kind = 'spins';
    select max(created_at) into v_cards from public.clan_messages
     where player_id = v_me and kind = 'cards';
    return jsonb_build_object(
        'spins_wait', greatest(0, ceil(extract(epoch from
            coalesce(v_spins, 'epoch'::timestamptz)
            + public.clan_ask_cooldown() - now()))::integer),
        'cards_wait', greatest(0, ceil(extract(epoch from
            coalesce(v_cards, 'epoch'::timestamptz)
            + public.clan_ask_cooldown() - now()))::integer),
        'give', public.clan_help_spins(),
        'seats', public.clan_help_donors());
end;
$$;

-- -----------------------------------------------------------------------------
--  spins that were given while the phone was off
-- -----------------------------------------------------------------------------
--
-- Exactly the shape unseen_gifts / ack_gifts has, which is the shape
-- unseen_raids / ack_raids has: the server keeps handing the thing over until
-- the client says it landed, and the client dedupes on the id as well so a
-- dropped ack cannot pay twice.
create or replace function public.unseen_spin_gifts()
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
                   'spins', x.spins,
                   'at',    extract(epoch from x.created_at),
                   'by',    public.public_player(x.from_player))
               order by x.created_at)
          from (select g.id, g.spins, g.created_at, g.from_player
                  from public.spin_gifts g
                 where g.to_player = v_me and g.seen_at is null
                 order by g.created_at
                 limit 50) x), '[]'::jsonb);
end;
$$;

create or replace function public.ack_spin_gifts(p_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
begin
    if v_me is null or p_ids is null then
        return;
    end if;
    update public.spin_gifts set seen_at = now()
     where to_player = v_me and seen_at is null and id = any(p_ids);
end;
$$;

-- -----------------------------------------------------------------------------
--  privileges
-- -----------------------------------------------------------------------------
--
-- join_clan, request_join_clan, clan_list and clan_view were all recreated
-- above, and recreating a function resets its privileges -- so they are
-- re-granted here or the clan page stops working for the only role that calls
-- it. The lesson 20260904170000 wrote down and 20260913120000 had to apply
-- again: a migration that grants only what it invented leaves what it replaced
-- revoked.
--
-- The four immutable numbers are granted too: the client mirrors them for
-- greying buttons out, but a QA harness and the migration test both call them.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('join_clan', 'request_join_clan', 'clan_list',
                             'clan_view', 'set_clan_min_stars', 'find_clans',
                             'say_clan', 'ask_clan_help', 'donate_clan_help',
                             'clan_chat', 'clan_ask_state',
                             'unseen_spin_gifts', 'ack_spin_gifts',
                             'clan_help_spins', 'clan_help_donors',
                             'clan_ask_cooldown', 'clan_chat_keep')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end;
$$;
