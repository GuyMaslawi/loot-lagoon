-- =============================================================================
--  The support desk
-- =============================================================================
--
-- The game has had a report button since 20260824 and nothing on the other end
-- of it. That migration's own comment says so plainly: "There is no moderation
-- console yet and there does not need to be one on day one -- what there needs
-- to be is the record, so the queue exists the moment it is worth reading."
--
-- Publishing to a store is that moment, and it brings a second one with it. The
-- week a game goes live is the week the mail starts: "I paid and got nothing",
-- "I lost my island", "somebody in my clan is abusive". Answering any of those
-- means finding one player among many, and today that cannot be done at all --
-- not by the game, not by the ops tool, not even by the service role, which has
-- no privilege on `players` whatsoever.
--
-- THREE FUNCTIONS, AND WHO MAY CALL THEM IS THE WHOLE SECURITY STORY.
--
-- Everything here is granted to `service_role` ONLY. Not anon, not
-- authenticated -- and that is the opposite of every other function this
-- project has added, which makes it the thing to get right rather than the
-- thing to copy. app_config and app_events answer questions about the GAME and
-- a guest is entitled to ask them. These answer questions about PEOPLE: a
-- client that could call support_find_player could enumerate every player and
-- read their coin balance, and one that could call support_reports could find
-- out who reported it. The grant block at the bottom revokes from public first
-- for exactly that reason.
--
-- THE SAVE BLOB IS NEVER RETURNED. `players.save_blob` is the entire game state
-- and is both enormous and none of a support answer's business. What comes back
-- is the shape a person needs to answer an email: who, how far along, how much
-- they hold, when they were last seen, and what they have paid.

-- -----------------------------------------------------------------------------
--  Finding one player
-- -----------------------------------------------------------------------------
--
-- THE QUERY IS WHATEVER THE PLAYER SENT YOU, which is the point. Somebody
-- writing for help will quote the support id off their Options page, and that
-- is a uuid when they are signed in and an install id when they are not -- so
-- both have to work, and so does a display name, because plenty of people will
-- just write "my name is Crabby" and nothing else.
--
-- A GUEST WHO PAID HAS NO PLAYER ROW AT ALL, and that is the case most likely
-- to arrive as an angry email. Their receipt carries the install id and a null
-- player, so the receipt search below is not a nicety -- it is the only way
-- that person can be answered.
create or replace function public.support_find_player(
        p_query text,
        p_limit integer default 10)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    with q as (
        select trim(coalesce(p_query, '')) as raw,
               -- Postgres has no "try cast", and a malformed uuid raises rather
               -- than returning null -- so the shape is tested first.
               case when trim(coalesce(p_query, ''))
                         ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                    then trim(p_query)::uuid end as as_uuid
    ),
    hits as (
        select p.*
          from public.players p, q
         where q.raw <> ''
           and (p.id = q.as_uuid
                -- An install id, through whatever that install has paid for.
                or p.id in (select r.player
                              from public.iap_receipts r
                             where r.install_id = q.raw
                               and r.player is not null)
                -- ...or a name. Bots are excluded here rather than filtered
                -- after: there are nine seeded crews and a name search that
                -- returned them would bury the person who wrote in.
                or (not p.is_bot and p.display_name ilike '%' || q.raw || '%'))
         order by p.last_seen desc nulls last
         limit greatest(1, least(coalesce(p_limit, 10), 50))
    )
    select coalesce(jsonb_agg(to_jsonb(h) order by h.last_seen desc nulls last),
                    '[]'::jsonb)
      from (select p.id,
                   p.display_name,
                   p.emoji,
                   p.island_level,
                   p.rank_stars,
                   p.vault_coins,
                   p.shields,
                   p.is_bot,
                   p.created_at,
                   p.last_seen,
                   -- A deleted account still answers, and says so. Somebody who
                   -- deleted by accident is a support case, and a lookup that
                   -- returned nothing would read as "never existed".
                   p.deleted_at,
                   -- WHICH SIGN-INS ARE BEHIND THIS, if any. "Restore my
                   -- account" is answerable only when there is one, and WHICH
                   -- one decides what to tell them to press -- so the provider
                   -- list is the answer rather than a yes/no.
                   (select coalesce(jsonb_agg(distinct i.provider), '[]'::jsonb)
                      from public.player_identities i
                     where i.player_id = p.id) as sign_ins,
                   (select count(*) from public.reports r
                     where r.reported = p.id) as reports_against,
                   -- WHAT THEY HAVE PAID, which is the question behind most of
                   -- the mail. Rolled up by verdict so "I was charged and got
                   -- nothing" can be answered in one glance, with the last few
                   -- rows for the detail.
                   (select coalesce(jsonb_object_agg(v.verdict, v.n), '{}'::jsonb)
                      from (select r.verdict, count(*) as n
                              from public.iap_receipts r
                             where r.player = p.id
                             group by r.verdict) v) as receipts_by_verdict,
                   (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                      from (select r.created_at, r.platform, r.product_id,
                                   r.verdict, r.detail
                              from public.iap_receipts r
                             where r.player = p.id
                             order by r.created_at desc
                             limit 5) x) as recent_receipts
              from hits p) h
$$;

-- -----------------------------------------------------------------------------
--  Finding a receipt with no player behind it
-- -----------------------------------------------------------------------------
--
-- The other half of the same question. A guest pays, gets nothing, and writes
-- in quoting the install id from their Options page -- there is no player row
-- to find, and the receipt is the only record that they are owed anything.
create or replace function public.support_find_receipts(
        p_query text,
        p_limit integer default 20)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
      from (select r.created_at, r.verified_at, r.platform, r.product_id,
                   r.verdict, r.detail, r.install_id, r.player,
                   -- Deliberately not store_payload: it is kept for reading an
                   -- incident, not for answering a mail, and the less of it
                   -- that moves around the better.
                   r.receipt_id
              from public.iap_receipts r
             where trim(coalesce(p_query, '')) <> ''
               and (r.install_id = trim(p_query)
                    or r.receipt_id = trim(p_query)
                    or (trim(p_query) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                        and r.player = trim(p_query)::uuid))
             order by r.created_at desc
             limit greatest(1, least(coalesce(p_limit, 20), 100))) x
$$;

-- -----------------------------------------------------------------------------
--  The report queue
-- -----------------------------------------------------------------------------
--
-- Apple's guideline 1.2 requires acting on reports about user content, and the
-- clan chat is user content. The button has existed for months; this is the
-- inbox behind it.
--
-- `reporters` IS THE NUMBER TO LOOK AT, not the row count. The original
-- migration's index comment already said it: "one report is an argument, twenty
-- is a pattern". The queue is therefore ordered by how many DISTINCT people
-- have reported the same person, so the pattern floats whatever the dates say.
create or replace function public.support_reports(
        p_open_only boolean default true,
        p_limit     integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(to_jsonb(x) order by x.reporters desc,
                                                   x.created_at desc),
                    '[]'::jsonb)
      from (select r.id,
                   r.reason,
                   r.created_at,
                   r.reviewed_at,
                   rp.display_name as reported_name,
                   rp.emoji        as reported_emoji,
                   r.reported      as reported_id,
                   rp.deleted_at   as reported_deleted_at,
                   who.display_name as reporter_name,
                   r.reporter       as reporter_id,
                   (select count(distinct r2.reporter)
                      from public.reports r2
                     where r2.reported = r.reported) as reporters
              from public.reports r
              join public.players rp  on rp.id  = r.reported
              left join public.players who on who.id = r.reporter
             where (not coalesce(p_open_only, true) or r.reviewed_at is null)
             order by r.created_at desc
             limit greatest(1, least(coalesce(p_limit, 50), 500))) x
$$;

-- -----------------------------------------------------------------------------
--  Marking one seen
-- -----------------------------------------------------------------------------
--
-- Stamping rather than deleting. The row is the evidence that a report was
-- received and looked at, which is the thing a store asks about -- deleting it
-- would answer "did you act on reports" with an empty table.
create or replace function public.support_review_report(p_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
    with done as (
        update public.reports
           set reviewed_at = now()
         where id = p_id and reviewed_at is null
        returning id, reviewed_at)
    select case when exists (select 1 from done)
                then (select jsonb_build_object('ok', true, 'id', d.id,
                                                'reviewed_at', d.reviewed_at)
                        from done d)
                when exists (select 1 from public.reports where id = p_id)
                then jsonb_build_object('ok', true, 'already', true)
                else jsonb_build_object('ok', false, 'error', 'no such report')
           end
$$;

-- -----------------------------------------------------------------------------
--  THE GRANT, WHICH IS THE POINT OF THE FILE
-- -----------------------------------------------------------------------------
--
-- service_role and nobody else. Every other function this project exposes is
-- granted to anon and authenticated because it answers a question about the
-- game; these answer questions about people, and a phone must never be able to
-- ask them. `revoke from public` first, because EXECUTE on a new function is
-- granted to PUBLIC by default -- leaving that in place would make the whole
-- file readable by every guest, which is the exact failure it exists to avoid.
--
-- The tables stay unreachable: nothing below grants SELECT on players or
-- reports to anybody. These functions are security definer, so they read on
-- their own authority and the shape they return is the only shape that exists.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('support_find_player', 'support_find_receipts',
                             'support_reports', 'support_review_report')
    loop
        execute format('revoke all on function %s from public', fn);
        execute format('revoke all on function %s from anon, authenticated', fn);
        execute format('grant execute on function %s to service_role', fn);
    end loop;
end;
$$;
