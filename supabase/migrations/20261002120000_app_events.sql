-- =============================================================================
--  The calendar: an event that happens on a DATE
-- =============================================================================
--
-- Every event in this game is a relative timer. `deal_until = now + 24h`, where
-- `now` is the moment that particular phone happened to roll one in, so no two
-- players are in the same event and no event can be aimed at a day. "The chain
-- starts on Saturday" is not a thing that can be expressed in main.gd at all --
-- not with a new binary, not with the config table added yesterday, because the
-- knob that table turns is "how long", never "when".
--
-- That is the gap this closes, and it is the one Guy asked about first.
--
-- SAME DOCTRINE AS app_config, AND IT MATTERS MORE HERE. An empty table is the
-- game exactly as it ships: the rotation keeps rolling chains in on its own
-- clock, as it has since the chain existed. A row does not replace that
-- machinery, it pre-empts it for a window and hands it back afterwards. No
-- network, no rows, an unapplied migration, a build that has never heard of
-- this -- every one of them is today's game.
--
-- WHY THE CLIENT IS NEVER SENT A TIMESTAMP. The obvious shape is `starts_at`
-- and `ends_at` on the wire and the phone comparing them against its own clock,
-- and it is wrong on this project for a reason already written down in main.gd:
-- `_now()` is a high-water mark precisely because a player can move the device
-- clock from the Settings app, and `_trusted_now()` falls back to it for anybody
-- who has not signed in. A calendar read against a clock the player owns is a
-- calendar the player owns.
--
-- So the arithmetic is done HERE, where the clock is not negotiable, and the
-- answer is in SECONDS FROM NOW. The phone needs no trusted clock at all -- only
-- the ability to count down, which is the same thing it already does for a
-- chain it rolled in itself. See the function below.

create table if not exists public.app_events (
    id         bigserial primary key,
    -- Which game. Same reasoning as app_config: present before there are two.
    app        text    not null,
    -- What kind of event this row schedules. 'deal_chain' is the only one the
    -- client understands today; a kind it has never heard of is ignored, which
    -- is what lets a row be written and proven before the build that reads it.
    kind       text    not null,
    -- What the kind needs to know. For 'deal_chain': {"id": "tide_hunt"} --
    -- which of the chains compiled into deals.gd to run. Naming one that does
    -- not exist is not an error here; the client falls back to its rotation.
    payload    jsonb   not null default '{}'::jsonb,
    starts_at  timestamptz not null,
    ends_at    timestamptz not null,
    -- The same targeting app_config carries, for the same reason: builds ship
    -- ahead of the schema, so every row here will be read by binaries that
    -- predate it.
    min_build  integer not null default 0 check (min_build >= 0),
    max_build  integer not null default 0 check (max_build >= 0),
    platform   text    not null default ''
                   check (platform in ('', 'ios', 'android')),
    note       text    not null default '',
    updated_at timestamptz not null default now(),
    -- A window that ends before it starts is a typo, and one that is caught
    -- here is one that never becomes a support thread. Equality is refused too:
    -- a zero-length event is a row somebody meant to fill in later.
    constraint app_events_window check (ends_at > starts_at)
);

create index if not exists app_events_window_lookup
    on public.app_events (app, kind, starts_at, ends_at);

alter table public.app_events enable row level security;
grant select, insert, update, delete on public.app_events to service_role;
grant usage, select on sequence public.app_events_id_seq to service_role;
-- The rows reach a client only through the function below, exactly as
-- app_config's do -- and the grant to the ops role is written in the same
-- migration as the table this time, because leaving it to a follow-up is what
-- shipped a table nobody could write on 2026-10-01.
revoke all on public.app_events from anon, authenticated;

-- -----------------------------------------------------------------------------
--  What is running, and what is about to
-- -----------------------------------------------------------------------------
--
-- An array, ordered by start, of everything live now or starting inside the
-- horizon. Each entry:
--
--     {"kind": "deal_chain", "payload": {"id": "tide_hunt"},
--      "starts_in": -1800, "ends_in": 84600}
--
-- `starts_in` IS NEGATIVE FOR AN EVENT ALREADY RUNNING, and that is the whole
-- interface: the client asks for the first entry of a kind whose `starts_in` is
-- at or below zero, and counts `ends_in` down from the moment it was told. No
-- timestamps, no timezone, no clock to trust and nothing to get wrong about
-- daylight saving -- which this project would otherwise meet twice a year with
-- an event that runs an hour long or an hour short.
--
-- THE HORIZON EXISTS SO THE ANSWER STAYS SMALL. A year of scheduled events is a
-- reasonable thing for somebody to plan, and none of it is any use to a phone
-- that is deciding what to run in the next few minutes. 72 hours by default,
-- which is comfortably longer than the gap between a boot and the next one.
create or replace function public.app_events(
        p_app           text    default 'loot-lagoon',
        p_build         integer default 0,
        p_platform      text    default '',
        p_horizon_hours integer default 72)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(e order by e.starts_in), '[]'::jsonb)
      from (select v.kind,
                   v.payload,
                   -- Rounded rather than truncated: a half-second either way is
                   -- nothing, and a float on the wire invites a client to parse
                   -- it as a string somewhere.
                   round(extract(epoch from (v.starts_at - now())))::bigint
                       as starts_in,
                   round(extract(epoch from (v.ends_at   - now())))::bigint
                       as ends_in
              from public.app_events v
             where v.app = coalesce(p_app, '')
               -- Already finished is simply not sent. The client has no use for
               -- it and a finished event in the list is one more thing for a
               -- future reader of this to handle wrongly.
               and v.ends_at > now()
               and v.starts_at < now()
                                 + make_interval(hours =>
                                     greatest(0, coalesce(p_horizon_hours, 72)))
               -- The dev exemption and the build range, identical to
               -- app_config's and for the same reasons. See that migration.
               and (coalesce(p_build, 0) = 0
                    or (coalesce(p_build, 0) >= v.min_build
                        and (v.max_build = 0
                             or coalesce(p_build, 0) <= v.max_build)))
               and (v.platform = ''
                    or v.platform = lower(coalesce(p_platform, '')))) e
$$;

-- ORDERED BY starts_in RATHER THAN starts_at, so the timestamp never has to
-- appear in the projection at all. Ordering by the column would have meant
-- selecting it, and jsonb_agg would then have put it on the wire -- a timestamp
-- sent to a client that the three paragraphs above say must never receive one.
-- The two orderings are identical: starts_in is starts_at minus a constant.
--
-- Anon for the same reason app_config is: an event is something a guest takes
-- part in, and a calendar that only reaches signed-in players is a calendar
-- with a hole in it the size of every guest.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'app_events'
    loop
        execute format('revoke all on function %s from public', fn);
        execute format('grant execute on function %s to anon, authenticated', fn);
    end loop;
end;
$$;
