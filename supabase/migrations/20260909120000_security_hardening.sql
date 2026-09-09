-- Security hardening pass, 2026-09-09.
--
-- Five holes found by an adversarial review of the whole backend. None is a
-- privilege-escalation or a direct-table write (those were closed in the
-- earlier sieges) -- these are the residue: an enumeration bug hiding behind a
-- feature that never ran, two unbounded client inputs, and a one-row telemetry
-- poison. Each fix is a `create or replace` that keeps the function's contract
-- and touches only the guarded line, so nothing downstream changes.


-- 1. find_players: two bugs in one function.
--
--    (a) It selected `p.name`, but the column is `display_name` -- there is no
--        `name` column. The function has thrown `column p.name does not exist`
--        since it shipped (2026-09-04), so clan invite search has been dead.
--
--    (b) Its own comment promises a PREFIX search precisely so the table cannot
--        be enumerated three letters at a time. But normalize_name does not
--        escape LIKE metacharacters, so `%a%` (length 3, passes the guard)
--        becomes `like '%a%%'` -- a CONTAINS match over every name, and each
--        hit is a full public_player() blob (vault_coins, shields, buildings).
--        Fixing (a) without (b) would turn a dead feature into a live scraper.
--        Escape backslash first, then % and _, so the default LIKE escape
--        applies and the caller's text can only ever anchor a prefix.
create or replace function public.find_players(p_query text, p_limit integer default 12)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_q    text := public.normalize_name(coalesce(p_query, ''));
    v_like text;
begin
    if v_me is null or length(v_q) < 3 then
        return '[]'::jsonb;
    end if;
    v_like := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
    return coalesce((
        select jsonb_agg(public.public_player(x.id) order by x.display_name)
          from (select p.id, p.display_name
                  from public.players p
                 where p.id <> v_me
                   and public.normalize_name(p.display_name) like v_like || '%'
                   and not exists (select 1 from public.clan_members m
                                    where m.player_id = p.id)
                 order by p.display_name
                 limit least(greatest(coalesce(p_limit, 12), 1), 25)) x), '[]'::jsonb);
end;
$$;


-- 2. find_target: p_band flowed straight into `island_level between level-band
--    and level+band` with no clamp, and the scan is `order by random()`. A
--    client sending a huge band matches the whole table and forces a full
--    random sort every call. The real client only ever sends 3. Clamp to
--    [1,10] -- above the honest value, far below "the whole table".
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
    v_band  integer := least(greatest(coalesce(p_band, 3), 1), 10);
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    select island_level into v_level from public.players where id = v_me;
    v_lo := v_level - v_band;
    v_hi := v_level + v_band;

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
        v_k := -1.0;
    end loop;

    if v_pick is null then
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
                                where (bl.blocker = v_me and bl.blocked = p.id)
                                   or (bl.blocker = p.id and bl.blocked = v_me))
             order by p.mm_key
             limit 1;
            exit when v_pick is not null;
            v_k := -1.0;
        end loop;
    end if;

    if v_pick is null then
        return null;
    end if;

    insert into public.raid_offers (attacker, victim) values (v_me, v_pick);

    return public.public_player(v_pick);
end;
$$;


-- 3. push_save: the save blob and the buildings array were stored whole, with
--    no size bound anywhere. "The server does not understand the save" excuses
--    skipping STRUCTURE validation, not SIZE: an authenticated client can push
--    a multi-MB blob (or a million-element buildings array that matchmaking
--    then unnest()s) in a 30s loop, all storage/WAL/TOAST cost on us. The real
--    save is ~2.8KB and buildings is exactly five, so a 256KB blob cap and a
--    16-slot array slice never touch an honest save and cap the abuse hard.
--
--    Also: island_level is the tournament BRACKET key (tourney_league reads it)
--    and push_save let it move freely, so a cheat client could drop to level 1,
--    fall into the beginner league, and take its zero-sum top-five placing
--    prize from real new players. Honest level never goes down outside a wipe
--    (the rank_stars stale-gate already rejects an older device before we get
--    here), so make it monotonic except under p_force, mirroring rank_stars.
create or replace function public.push_save(
    p_save          jsonb,
    p_rank_stars    integer,
    p_island_level  integer,
    p_vault_coins   bigint   default 0,
    p_shields       integer default 0,
    p_buildings     integer[] default '{0,0,0,0,0}',
    p_force         boolean  default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_player  uuid := public.current_player();
    v_stored  integer;
    v_level   integer;
    v_seen    timestamptz;
    v_ceiling integer;
    v_rank    integer;
begin
    if v_player is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    if p_save is null then
        raise exception 'refusing to store a null save';
    end if;
    -- A real save is ~2.8KB; 256KB is ninety times that and still refuses the
    -- multi-megabyte blob a storage-abuse loop would push.
    if octet_length(p_save::text) > 262144 then
        raise exception 'save too large' using errcode = '54000';
    end if;

    select rank_stars, island_level, last_seen into v_stored, v_level, v_seen
      from public.players where id = v_player for update;

    -- The conflict rule, unchanged: rank_stars only ever goes up in main.gd
    -- ("nothing in the game subtracts from it"), which makes it a monotonic
    -- clock for free. A push carrying LESS of it than the server holds is not a
    -- newer save, it is an older device catching up. p_force is the one
    -- legitimate way it goes down -- the player wiping their own island.
    if not p_force and p_rank_stars < v_stored then
        return jsonb_build_object(
            'status',       'stale',
            'stored_rank',  v_stored,
            'pushed_rank',  p_rank_stars,
            'save',         (select save_blob from public.players where id = v_player));
    end if;

    v_ceiling := v_stored + 500
               + least(floor(extract(epoch from (now() - coalesce(v_seen, now()))) / 7.2), 1000000)::integer;
    v_rank := least(greatest(p_rank_stars, 0), greatest(v_ceiling, 0));
    -- A wipe is the player asking for a lower number, and there is nothing to
    -- bound about going down.
    if p_force then
        v_rank := greatest(p_rank_stars, 0);
    end if;

    update public.players
       set save_blob    = p_save,
           rank_stars   = least(v_rank, 1000000),
           -- Monotonic outside a wipe: the bracket key cannot be lowered to
           -- farm a weaker tournament league.
           island_level = case when p_force then greatest(p_island_level, 1)
                               else greatest(p_island_level, coalesce(v_level, 1)) end,
           vault_coins  = greatest(p_vault_coins, 0),
           shields      = greatest(p_shields, 0)::smallint,
           buildings    = (p_buildings)[1:16]::smallint[],
           save_version = save_version + 1,
           last_seen    = now()
     where id = v_player;

    return jsonb_build_object(
        'status',       'ok',
        'save_version', (select save_version from public.players where id = v_player),
        -- So a client that declared more than it was given can see that it was
        -- trimmed, rather than pushing the same rejected number for ever.
        'rank_stars',   (select rank_stars from public.players where id = v_player));
end;
$$;


-- 4. claim_player: the create path stores the same client save/buildings, so it
--    gets the same size bounds. (Its rank/level clamps already exist.)
create or replace function public.claim_player(
    p_save          jsonb   default null,
    p_display_name  text    default null,
    p_emoji         text    default null,
    p_rank_stars    integer default 0,
    p_island_level  integer default 1,
    p_vault_coins   bigint  default 0,
    p_shields       integer default 0,
    p_buildings     integer[] default '{0,0,0,0,0}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid       uuid := auth.uid();
    v_player    uuid;
    v_provider  text;
begin
    if v_uid is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    if p_save is not null and octet_length(p_save::text) > 262144 then
        raise exception 'save too large' using errcode = '54000';
    end if;

    v_player := public.current_player();
    if v_player is not null then
        update public.players set last_seen = now() where id = v_player;
        return jsonb_build_object(
            'is_new', false,
            'player', public.public_player(v_player),
            'save',   (select save_blob from public.players where id = v_player));
    end if;

    select coalesce(
               (select i.provider from auth.identities i where i.user_id = v_uid limit 1),
               'unknown')
      into v_provider;

    insert into public.players (display_name, emoji, save_blob, rank_stars,
                                island_level, vault_coins, shields, buildings)
    values (public.unique_name(p_display_name),
            case when public.emoji_ok(p_emoji) then p_emoji else '🙂' end,
            p_save,
            -- Rank is client-declared by design -- the economy lives in
            -- main.gd and the server cannot recompute it -- but "declared"
            -- does not have to mean "unbounded". A ceiling three orders of
            -- magnitude above any real island stops a fresh account from
            -- claiming the top of the leaderboard with 2,000,000,000 without
            -- coming anywhere near a player who has genuinely earned theirs.
            least(greatest(p_rank_stars, 0), 1000000),
            greatest(p_island_level, 1),
            greatest(p_vault_coins, 0),
            greatest(p_shields, 0)::smallint,
            (p_buildings)[1:16]::smallint[])
    returning id into v_player;

    insert into public.player_identities (auth_uid, player_id, provider)
    values (v_uid, v_player, v_provider);

    return jsonb_build_object(
        'is_new', true,
        'player', public.public_player(v_player),
        'save',   p_save);
end;
$$;


-- Re-grant execute on the four functions just replaced. create or replace
-- preserves grants, but the schema's own pattern re-asserts them after every
-- redefinition, so do the same rather than trust the difference.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('find_players', 'find_target', 'push_save', 'claim_player')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
end $$;


-- 5. The diagnostics analytics views cast client-supplied JSON to numeric with
--    no type guard, and report_diagnostics_guest is anon-callable and stores
--    arbitrary detail JSON. One anon row of {"secs":"x"} makes the whole view
--    throw `invalid input syntax for type numeric` the next time an analyst
--    queries it -- a one-row denial of the exact retention/funnel numbers the
--    Play production-access questionnaire needs. Guard every cast: filter to
--    numbers where a whole row is forged garbage, and null the cast inside the
--    aggregate where a real milestone row simply lacks the field (so the
--    install still counts, only its median contribution drops).

create or replace view public.diag_funnel as
    select d.detail ->> 'name'                                    as milestone,
           count(distinct d.install_id)                           as installs,
           round(100.0 * count(distinct d.install_id)
                 / nullif((select count(*) from public.diag_installs), 0), 1)
                                                                  as pct_of_installs,
           round(percentile_cont(0.5) within group (
                     order by (case when jsonb_typeof(d.detail -> 'since_install_s') = 'number'
                                    then (d.detail ->> 'since_install_s')::numeric end)
                 ))                                               as median_secs,
           min(d.created_at)                                      as first_reported
      from public.diagnostics d
     where d.kind = 'milestone'
       and d.detail ? 'name'
     group by d.detail ->> 'name'
     order by 2 desc;

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
       and jsonb_typeof(detail -> 'secs') = 'number'
     group by created_at::date
     order by 1 desc;

create or replace view public.diag_features_daily as
    select d.created_at::date                    as day,
           c.key                                 as feature,
           sum((c.value)::text::numeric)         as total,
           count(distinct d.install_id)          as installs
      from public.diagnostics d
      cross join lateral jsonb_each(coalesce(d.detail -> 'counters', '{}'::jsonb)) c
     where d.kind = 'usage'
       and jsonb_typeof(c.value) = 'number'
     group by d.created_at::date, c.key
     order by 1 desc, 3 desc;

-- Views inherit no grants, but the schema says so out loud rather than leave it
-- to be discovered; keep doing that for the three just replaced.
revoke all on public.diag_funnel         from public, anon, authenticated;
revoke all on public.diag_usage_daily    from public, anon, authenticated;
revoke all on public.diag_features_daily from public, anon, authenticated;
