-- =============================================================================
--  diagnostics -- what the game has no way of telling anyone right now
-- =============================================================================
--
-- There is no crash reporting in this game. None. Twenty-five paid strangers
-- are about to play it for fourteen days and the only thing that comes back is
-- a number in Play Console, so a crash on a device nobody here owns is
-- indistinguishable from a tester who lost interest -- and the production
-- access questionnaire asks, in so many words, whether testers used all
-- available features. Right now the honest answer is "no idea".
--
-- WHY THIS IS NOT SENTRY OR CRASHLYTICS. Either would be a plugin build on two
-- platforms, and -- the part that actually decides it -- either would make the
-- Data Safety answer "Data shared with third parties: YES". That answer was
-- deliberately NO: Supabase is a processor acting on instructions, a crash
-- vendor is a recipient. The badge it puts on the store listing is not worth a
-- stack trace. This writes to the database the app already talks to.
--
-- WHAT IT DOES NOT DO. It cannot catch a native segfault -- nothing written in
-- GDScript can, because the process is gone. What it can see is that the
-- PREVIOUS session never shut down cleanly, which on a phone is a narrower
-- claim than it sounds: the OS kills backgrounded apps constantly and that is
-- not a crash, so the marker is cleared on the way to the background by
-- _go_away(). A marker still standing at launch means the app died while the
-- player was looking at it. That is the event worth a row.

-- -----------------------------------------------------------------------------
--  The table
-- -----------------------------------------------------------------------------
--
-- No RLS policies are written for it on purpose. RLS is enabled and nothing is
-- granted to anon or authenticated, so the only way in is report_diagnostics()
-- below, which is security definer. A client that could insert here directly
-- could also write a thousand rows a second.
create table if not exists public.diagnostics (
    id          bigint generated always as identity primary key,

    -- Cascades: a deleted account under guideline 5.1.1(v) takes its
    -- diagnostics with it. There is no reason for a crash report to outlive
    -- the person who hit the crash.
    player      uuid not null references public.players (id) on delete cascade,

    -- Random per install, made on the client, reset by a reinstall. NOT a
    -- person and not a device id: it exists so two reports from one phone can
    -- be told apart from two phones, which is the whole question when six of
    -- twelve testers report nothing.
    install_id  text not null,

    -- 'crash' -- the previous foreground session did not shut down cleanly
    -- 'error' -- the game noticed something wrong and kept going
    -- 'usage' -- a counter batch: which features were actually touched
    kind        text not null,

    -- The commit count, same integer ship_android.sh and ship.sh use as the
    -- version code, so a report can be pinned to a build without guessing.
    build       integer not null default 0,

    platform    text not null default '',
    os_version  text not null default '',
    model       text not null default '',

    -- Whatever the event carries: the last screen before a crash, the counter
    -- names and totals for a usage batch, a message for an error. Bounded
    -- below rather than by a column type -- see the size check in the RPC.
    detail      jsonb not null default '{}'::jsonb,

    created_at  timestamptz not null default now(),

    constraint diagnostics_kind_ck check (kind in ('crash', 'error', 'usage'))
);

alter table public.diagnostics enable row level security;

-- Reading is "show me this build's crashes, newest first" and "how many rows
-- has this player filed in the last hour" -- the rate limit below is the hot
-- one, and it runs on every single call.
create index if not exists diagnostics_player_recent
    on public.diagnostics (player, created_at desc);

create index if not exists diagnostics_kind_recent
    on public.diagnostics (kind, created_at desc);

-- -----------------------------------------------------------------------------
--  report_diagnostics -- the only door
-- -----------------------------------------------------------------------------
--
-- Batched, because the client holds events until it has a reason to send and
-- one radio wake-up carrying eight rows costs less than eight carrying one.
--
-- Returns the number of rows actually written, which is not always the number
-- offered: over the hourly ceiling it returns 0 and the client is expected to
-- drop them rather than retry. A diagnostics pipeline that retries forever
-- becomes the outage it was installed to observe.
--
-- GRANTED TO authenticated ONLY, like every other function in this schema. A
-- guest has no session and therefore files nothing -- a real gap, and the
-- reason the testers were told to sign in with Google rather than play as
-- guest. Opening this to anon would put the first unauthenticated write
-- endpoint in the schema, rate limited by a value the client itself supplies.
create or replace function public.report_diagnostics(
    p_install   text,
    p_platform  text,
    p_os        text,
    p_model     text,
    p_build     integer,
    p_events    jsonb
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    -- Per player per hour. Sized against the client's own behaviour: it flushes
    -- a usage batch every few minutes and files at most one crash per launch,
    -- so a well-behaved install lands nowhere near this. It is here for the
    -- one that is not well-behaved.
    c_hourly_cap constant integer := 120;

    -- One flush should never carry more than a handful. Anything larger is a
    -- bug in the client or somebody exploring the API.
    c_batch_cap  constant integer := 25;

    -- Bytes, per event. A breadcrumb and a dozen counters; not a log file.
    c_detail_cap constant integer := 4000;

    v_me     uuid := public.current_player();
    v_recent integer;
    v_wrote  integer := 0;
    v_event  jsonb;
    v_kind   text;
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;

    if p_events is null or jsonb_typeof(p_events) <> 'array' then
        return 0;
    end if;

    select count(*) into v_recent
      from public.diagnostics
     where player = v_me
       and created_at > now() - interval '1 hour';

    if v_recent >= c_hourly_cap then
        return 0;
    end if;

    for v_event in
        select value from jsonb_array_elements(p_events) limit c_batch_cap
    loop
        -- Skip rather than fail the batch. One malformed event should not cost
        -- the seven good ones next to it, and the client cannot fix what it
        -- cannot see the error for anyway.
        v_kind := v_event ->> 'kind';
        if v_kind is null or v_kind not in ('crash', 'error', 'usage') then
            continue;
        end if;
        if length(coalesce(v_event ->> 'detail', '')) > c_detail_cap then
            continue;
        end if;
        exit when v_recent + v_wrote >= c_hourly_cap;

        insert into public.diagnostics
            (player, install_id, kind, build, platform, os_version, model, detail)
        values (
            v_me,
            left(coalesce(p_install,  ''), 64),
            v_kind,
            coalesce(p_build, 0),
            left(coalesce(p_platform, ''), 32),
            left(coalesce(p_os,       ''), 64),
            left(coalesce(p_model,    ''), 64),
            coalesce(v_event -> 'detail', '{}'::jsonb)
        );
        v_wrote := v_wrote + 1;
    end loop;

    return v_wrote;
end;
$$;

revoke all on function public.report_diagnostics(text, text, text, text, integer, jsonb)
    from public, anon;
grant execute on function public.report_diagnostics(text, text, text, text, integer, jsonb)
    to authenticated;

-- -----------------------------------------------------------------------------
--  prune_diagnostics -- because nothing else deletes from this table
-- -----------------------------------------------------------------------------
--
-- Usage rows arrive every few minutes per install and are worthless a fortnight
-- later; crashes and errors are worth keeping longer because they are rare and
-- because "did this stop happening after build 63" is the question they exist
-- to answer. Not scheduled -- there is no pg_cron here -- so it is a button to
-- press from the SQL editor, and it says how many it took.
create or replace function public.prune_diagnostics(
    p_usage_days integer default 14,
    p_fault_days integer default 90
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_gone integer;
begin
    delete from public.diagnostics
     where (kind = 'usage' and created_at < now() - make_interval(days => p_usage_days))
        or (kind <> 'usage' and created_at < now() - make_interval(days => p_fault_days));
    get diagnostics v_gone = row_count;
    return v_gone;
end;
$$;

revoke all on function public.prune_diagnostics(integer, integer)
    from public, anon, authenticated;
