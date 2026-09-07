-- =============================================================================
--  Diagnostics, part two -- the guests, and the funnel
-- =============================================================================
--
-- 20260901120000_diagnostics.sql built the pipeline and left one hole in it,
-- knowingly and in writing:
--
--     "GRANTED TO authenticated ONLY [...] A guest has no session and
--      therefore files nothing -- a real gap, and the reason the testers were
--      told to sign in with Google rather than play as guest."
--
-- That workaround cost real money. The closed-test order carries a written
-- Special Note telling 25 paid testers to use Google Sign-In, because a guest
-- creates no `players` row and therefore reports nothing. It works on 25 people
-- who were paid to follow instructions. It cannot work on the public, where
-- guest mode is the default path, is advertised as a full game, and is what
-- Google's own reviewer was told to use.
--
-- So the majority of the players this game is about to get would have been
-- invisible, and every retention number computed from this table would have
-- been computed over the self-selected minority who signed in -- which is a
-- worse failure than having no numbers, because it looks like having numbers.
--
-- This migration does three things:
--
--   1. lets a guest file, through a door that is deliberately NOT the one
--      signed-in players use
--   2. adds `milestone`, the event kind a funnel is made of
--   3. adds the read side, because a table nobody can ask questions of is
--      not measurement
--
-- -----------------------------------------------------------------------------
--  1. THE TRADE, WRITTEN DOWN, BECAUSE IT IS A REAL ONE
-- -----------------------------------------------------------------------------
--
-- This adds the first unauthenticated write endpoint in a schema that has been
-- through two adversarial passes. The original file's objection was exact:
-- an anon door here is "rate limited by a value the client itself supplies",
-- and a hostile client rotates `install_id` as fast as it likes.
--
-- That objection is correct and is NOT solved below. What is done instead is to
-- bound what it can cost, on the argument that the right question for a
-- diagnostics table is not "can this be abused" but "what does abuse buy, and
-- what does it break":
--
--   * The row it writes is inert. `player` is null, nothing joins to it, no
--     gameplay reads it, and no RLS policy anywhere grants on it. A flood
--     writes junk into a table whose only consumer is a human in the SQL
--     editor.
--   * There is a GLOBAL hourly ceiling as well as a per-install one, so a
--     rotating attacker exhausts a budget rather than a disk. When the global
--     ceiling is hit the function returns 0 and writes nothing, for an hour.
--   * The failure mode is the correct one. Guest telemetry stops; signed-in
--     reporting is on a different function with a different budget and does
--     not degrade. Losing an hour of guest telemetry is the cheapest thing in
--     this schema to lose.
--   * `prune_diagnostics` already exists and already deletes usage rows at 14
--     days, so a flood is not permanent even if nobody notices it.
--
-- The alternative considered and rejected was Supabase anonymous sign-in. It
-- would have given every guest a real JWT and closed the hole properly -- and
-- it also gives every guest an `auth.users` row that counts toward MAU, needs
-- its own cleanup, and needs a dashboard toggle that cannot be expressed in a
-- migration. Worse, the obvious version of it (an anonymous user with a
-- `players` row) would put guests into matchmaking, the leaderboard and cloud
-- save, which is a product change wearing a telemetry change's clothes. Not
-- for this.

-- -----------------------------------------------------------------------------
--  A guest row has no player
-- -----------------------------------------------------------------------------
--
-- The column stays a foreign key with its cascade intact, so a signed-in
-- player who deletes their account still takes their diagnostics with them
-- under guideline 5.1.1(v). It is only the NOT NULL that goes.
alter table public.diagnostics
    alter column player drop not null;

-- `milestone` -- fired at most once per install, ever, and the only kind that
-- is about a player reaching something rather than about the app misbehaving.
alter table public.diagnostics
    drop constraint if exists diagnostics_kind_ck;

alter table public.diagnostics
    add constraint diagnostics_kind_ck
    check (kind in ('crash', 'error', 'usage', 'milestone'));

-- The hot path of the guest rate limit: "how many rows has this install filed
-- in the last hour". The existing indexes lead on `player`, which is null for
-- every row this cares about.
create index if not exists diagnostics_install_recent
    on public.diagnostics (install_id, created_at desc);

-- The global circuit breaker's query, and the funnel's. Partial, because
-- milestones are a rounding error next to usage rows and this keeps the index
-- that size.
create index if not exists diagnostics_milestone_name
    on public.diagnostics ((detail ->> 'name'), created_at desc)
    where kind = 'milestone';

-- -----------------------------------------------------------------------------
--  report_diagnostics -- the signed-in door, which also has to learn the kind
-- -----------------------------------------------------------------------------
--
-- RECREATED ONLY TO WIDEN ITS KIND LIST, and it has to be: the table constraint
-- above accepts `milestone` now, but this function carries its OWN list and
-- skips anything not on it. Without this a signed-in player's milestones were
-- dropped silently, one event at a time, by the `continue` in the loop -- so the
-- funnel would have been built entirely out of guests while looking complete.
-- Caught by tools/test_migrations.sql, not by reading.
--
-- The body is otherwise byte-for-byte what 20260901120000 shipped. The grants
-- are repeated because CREATE OR REPLACE resets them, which is the trap
-- 20260904170000 documented the hard way.
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
    c_hourly_cap constant integer := 120;
    c_batch_cap  constant integer := 25;
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
        v_kind := v_event ->> 'kind';
        if v_kind is null or v_kind not in ('crash', 'error', 'usage', 'milestone') then
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
--  report_diagnostics_guest -- the other door
-- -----------------------------------------------------------------------------
--
-- A SEPARATE FUNCTION ON PURPOSE, rather than relaxing the null check in
-- report_diagnostics and granting that to anon. Two reasons, and the second is
-- the one that matters:
--
--   * The budgets are different and should be. A guest gets a smaller per-hour
--     allowance than a signed-in player, because a signed-in player is a known
--     row and a guest is a string.
--   * Granting the existing function to anon would mean any future edit to it
--     silently ships to anon as well. Two functions means the anon surface is
--     something somebody has to choose to widen.
create or replace function public.report_diagnostics_guest(
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
    -- Per install per hour. Lower than the signed-in cap of 120: the client
    -- flushes every three minutes and files one crash per launch, so a
    -- well-behaved guest lands around 20.
    c_hourly_cap constant integer := 40;

    -- ACROSS ALL GUESTS, PER HOUR. This is the circuit breaker and it is the
    -- whole reason the anon door is acceptable. Sized well above a real
    -- population: at 40 rows an hour it is 1,250 simultaneously-playing
    -- guests, which this game does not have and will notice happily if it ever
    -- does. Raise it when the real number gets close, not before.
    c_global_cap constant integer := 50000;

    c_batch_cap  constant integer := 25;
    c_detail_cap constant integer := 4000;

    v_install text := left(coalesce(p_install, ''), 64);
    v_recent  integer;
    v_global  integer;
    v_wrote   integer := 0;
    v_event   jsonb;
    v_kind    text;
begin
    -- An install id is the only thing tying a guest's rows together. Without
    -- one there is nothing to rate limit against and nothing to learn from the
    -- row, so it is refused rather than written unattributed.
    if v_install = '' then
        return 0;
    end if;

    if p_events is null or jsonb_typeof(p_events) <> 'array' then
        return 0;
    end if;

    -- The global check runs first and is deliberately the cheaper of the two
    -- to fail: under a flood this is the query that answers, and answering it
    -- must not require touching the per-install index for an id that is
    -- different every time.
    select count(*) into v_global
      from public.diagnostics
     where player is null
       and created_at > now() - interval '1 hour';

    if v_global >= c_global_cap then
        return 0;
    end if;

    select count(*) into v_recent
      from public.diagnostics
     where install_id = v_install
       and player is null
       and created_at > now() - interval '1 hour';

    if v_recent >= c_hourly_cap then
        return 0;
    end if;

    for v_event in
        select value from jsonb_array_elements(p_events) limit c_batch_cap
    loop
        v_kind := v_event ->> 'kind';
        if v_kind is null or v_kind not in ('crash', 'error', 'usage', 'milestone') then
            continue;
        end if;
        if length(coalesce(v_event ->> 'detail', '')) > c_detail_cap then
            continue;
        end if;
        exit when v_recent + v_wrote >= c_hourly_cap;
        exit when v_global + v_wrote >= c_global_cap;

        insert into public.diagnostics
            (player, install_id, kind, build, platform, os_version, model, detail)
        values (
            null,
            v_install,
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

revoke all on function public.report_diagnostics_guest(text, text, text, text, integer, jsonb)
    from public;
grant execute on function public.report_diagnostics_guest(text, text, text, text, integer, jsonb)
    to anon, authenticated;

-- -----------------------------------------------------------------------------
--  2. THE READ SIDE
-- -----------------------------------------------------------------------------
--
-- No grants, exactly like prune_diagnostics: these are for a human in the SQL
-- editor, and nothing in the game reads them. Views rather than functions
-- because the questions are "select * from" questions.
--
-- WHAT "RETENTION" MEANS HERE, and it is narrower than the word usually is.
-- A row only exists if the app reported, and diag.gd files nothing for a
-- session under ten seconds (MIN_SESSION). So an install "came back on day 3"
-- means it opened the game on day 3 AND stayed at least ten seconds. That is a
-- better definition than the usual one and it is not the usual one -- do not
-- compare these numbers to an industry chart without saying so.

-- Every install this table has ever heard from, and when it first spoke.
-- `install_id` is reset by a reinstall on purpose (see diag.gd), so this is
-- installs and not people.
create or replace view public.diag_installs as
    select install_id,
           min(created_at)                       as first_seen,
           max(created_at)                       as last_seen,
           min(platform) filter (where platform <> '') as platform,
           max(build)                            as build,
           bool_or(player is not null)           as ever_signed_in
      from public.diagnostics
     group by install_id;

-- The days an install was actually present, one row per install per day.
create or replace view public.diag_active_days as
    select d.install_id,
           i.first_seen::date                                     as cohort,
           d.created_at::date                                     as day,
           (d.created_at::date - i.first_seen::date)              as day_n
      from public.diagnostics d
      join public.diag_installs i using (install_id)
     group by d.install_id, i.first_seen, d.created_at::date;

-- Classic D1 / D7 / D30, by install cohort.
--
-- A cohort is only honest once it has had time to answer: a cohort that
-- installed yesterday cannot have a D7 yet, and its column reads 0 rather than
-- null, which is how a retention table gets misread. `mature_d7` /
-- `mature_d30` say whether the number means anything yet.
create or replace view public.diag_retention as
    select i.first_seen::date                             as cohort,
           count(*)                                       as installs,
           count(*) filter (
               where exists (select 1 from public.diag_active_days a
                              where a.install_id = i.install_id and a.day_n = 1)
           )                                              as d1,
           count(*) filter (
               where exists (select 1 from public.diag_active_days a
                              where a.install_id = i.install_id and a.day_n = 7)
           )                                              as d7,
           count(*) filter (
               where exists (select 1 from public.diag_active_days a
                              where a.install_id = i.install_id and a.day_n = 30)
           )                                              as d30,
           (i.first_seen::date <  current_date)           as mature_d1,
           (i.first_seen::date <= current_date - 7)       as mature_d7,
           (i.first_seen::date <= current_date - 30)      as mature_d30
      from public.diag_installs i
     group by i.first_seen::date
     order by 1 desc;

-- The funnel. One row per milestone, how many installs reached it, and how
-- long it took them -- the median rather than the mean, because a single
-- install that left the app open for a week would otherwise own the average.
create or replace view public.diag_funnel as
    select d.detail ->> 'name'                                    as milestone,
           count(distinct d.install_id)                           as installs,
           round(100.0 * count(distinct d.install_id)
                 / nullif((select count(*) from public.diag_installs), 0), 1)
                                                                  as pct_of_installs,
           round(percentile_cont(0.5) within group (
                     order by (d.detail ->> 'since_install_s')::numeric
                 ))                                               as median_secs,
           min(d.created_at)                                      as first_reported
      from public.diagnostics d
     where d.kind = 'milestone'
       and d.detail ? 'name'
     group by d.detail ->> 'name'
     order by 2 desc;

-- Sessions per day and how long they ran. `secs` is written by diag.gd's
-- _close_session, which also rolls a row every three minutes mid-session -- so
-- these are REPORTING WINDOWS, not whole sessions, and a long session appears
-- as several rows. Counting "how much time per day" is what this answers
-- honestly; "how long is a session" is not.
create or replace view public.diag_usage_daily as
    select created_at::date                                        as day,
           count(*)                                                as windows,
           count(distinct install_id)                              as installs,
           round(sum((detail ->> 'secs')::numeric) / 60.0)         as minutes_total,
           round(percentile_cont(0.5) within group (
                     order by (detail ->> 'secs')::numeric
                 ))                                                as median_window_secs
      from public.diagnostics
     where kind = 'usage'
       and detail ? 'secs'
     group by created_at::date
     order by 1 desc;

-- What the game is actually made of, per day: every counter name diag.gd was
-- handed, summed. This is the one that answers "did anybody open the card
-- shelf" -- the question the retention review said nothing could answer.
create or replace view public.diag_features_daily as
    select d.created_at::date                    as day,
           c.key                                 as feature,
           sum((c.value)::text::numeric)         as total,
           count(distinct d.install_id)          as installs
      from public.diagnostics d
      cross join lateral jsonb_each(coalesce(d.detail -> 'counters', '{}'::jsonb)) c
     where d.kind = 'usage'
     group by d.created_at::date, c.key
     order by 1 desc, 3 desc;

-- Crashes and faults, newest first, with the breadcrumb that says where.
create or replace view public.diag_faults as
    select created_at,
           kind,
           build,
           platform,
           os_version,
           model,
           detail ->> 'where'   as where_,
           detail ->> 'message' as message,
           detail ->> 'alive_s' as alive_s,
           install_id
      from public.diagnostics
     where kind in ('crash', 'error')
     order by created_at desc;

-- Views inherit no grants from the table, but say so rather than leave it to
-- be discovered: the SQL editor runs as the owner and sees them; anon and
-- authenticated cannot.
revoke all on public.diag_installs      from public, anon, authenticated;
revoke all on public.diag_active_days   from public, anon, authenticated;
revoke all on public.diag_retention     from public, anon, authenticated;
revoke all on public.diag_funnel        from public, anon, authenticated;
revoke all on public.diag_usage_daily   from public, anon, authenticated;
revoke all on public.diag_features_daily from public, anon, authenticated;
revoke all on public.diag_faults        from public, anon, authenticated;
