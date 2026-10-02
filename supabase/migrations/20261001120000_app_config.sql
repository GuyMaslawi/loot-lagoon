-- =============================================================================
--  Remote config: the knobs that do not need a binary
-- =============================================================================
--
-- Until now exactly five things in this game could be changed without shipping
-- a build, and all five are in client_gate_rules: a build floor, a build
-- ceiling, a sentence, and two store links. Everything else -- every event, the
-- 151 constants at the top of main.gd, the deal chains, the island curve -- is
-- compiled in. So "turn that off" and "run the event on Saturday" both mean a
-- new binary, which means Apple review, which means three days with the problem
-- still live on every phone.
--
-- This is the other half of client_gate, built to the same doctrine, and the
-- doctrine is the whole file:
-- 
--   THE EMPTY ANSWER IS TODAY'S BEHAVIOUR. No rows, no migration, no network,
--   a malformed reply, a key the running build has never heard of -- every one
--   of those paths ends with the client using the constant it shipped with.
--   Nothing here can turn a feature off by accident; it takes somebody writing
--   a row that says so.
--
-- That is not caution for its own sake. A config service that fails closed is
-- a game that breaks itself the afternoon the server has a bad hour, and the
-- blast radius of that is larger than every outage this table exists to shorten.
--
-- WHY A KEY/VALUE TABLE RATHER THAN COLUMNS. client_gate_rules is one row of
-- typed columns and that is right for it: it answers one question with a fixed
-- shape, forever. This answers "what should this build believe", and the set of
-- things worth believing grows every release. Columns would mean a migration
-- per knob, and a migration per knob means the knob arrives at the same speed
-- as the binary it was supposed to outrun.
--
-- WHY `app` IS IN THE PRIMARY KEY ON DAY ONE. There is one game today. The
-- reason this column exists before there are two is that the alternative is
-- discovered rather than chosen: a table without it gets read by game two,
-- answers with game one's rows, and the fix is a migration against live data
-- plus a client change in a build that is already in review. One text column
-- now costs nothing and makes the second game a row rather than a rewrite.

create table if not exists public.app_config (
    -- Surrogate, because the natural key is "the most specific row that matches
    -- this client" and that is a resolution rule, not a uniqueness constraint.
    -- Two rows for the same key are not a mistake here -- they are how a knob
    -- gets targeted at one platform or one build range.
    id         bigserial primary key,
    -- Which game. 'loot-lagoon' is this one; the client sends its own name and
    -- never reads a row it did not ask for.
    app        text    not null,
    -- What the client calls this knob. Free text on purpose: a build that has
    -- never heard of a key ignores it, so a key can ship here BEFORE the build
    -- that reads it, which is the whole point -- the row can be in place and
    -- proven before the binary that depends on it reaches a phone.
    key        text    not null,
    -- Whatever the knob is. jsonb rather than text because half of these are
    -- booleans, half are numbers, and the ones that are neither are objects.
    -- The client coerces, and coerces defensively: see flags.gd.
    value      jsonb   not null,
    -- WHICH BUILDS THIS ROW IS FOR, and this pair is the most important thing
    -- in the table.
    --
    -- Builds in this project ship AHEAD of the schema -- a binary sits in
    -- TestFlight for weeks while migrations land underneath it, which is the
    -- same fact that check_client_rpcs.sh exists for. So every row written here
    -- WILL be read by builds that predate it. A knob whose meaning changed
    -- between build 140 and build 150 must be able to say so, or the row that
    -- fixes the new build breaks the old one.
    --
    -- min_build 0 and max_build 0 mean "every build", which is what an ordinary
    -- kill switch wants.
    min_build  integer not null default 0 check (min_build >= 0),
    max_build  integer not null default 0 check (max_build >= 0),
    -- '' for both, or 'ios' / 'android'. The game branches in five places and
    -- two of them are store rules rather than code, so a knob that can only be
    -- set for everybody is a knob that cannot answer a platform's reviewer.
    platform   text    not null default ''
                   check (platform in ('', 'ios', 'android')),
    -- Why this row exists, for the person reading the table in six months.
    -- Never sent to a client.
    note       text    not null default '',
    updated_at timestamptz not null default now()
);

-- The resolution order below reads these two; without the index it reads them
-- off a sequential scan on every boot of every install.
create index if not exists app_config_lookup
    on public.app_config (app, key);

-- Nobody reaches the table. The function below is the contract, for the same
-- reason client_gate_rules gives: a client that could SELECT this could also be
-- handed a column it does not understand by a future migration, and a function
-- is a shape that can be kept stable while the storage underneath it moves.
alter table public.app_config enable row level security;

-- -----------------------------------------------------------------------------
--  The answer
-- -----------------------------------------------------------------------------
--
-- One flat object: {"clan_chat": false, "chain_hours": 18}. Flat because the
-- client merges it over its own compiled defaults key by key, and a nested
-- answer would make "the server did not mention this knob" and "the server set
-- this knob to an empty object" the same reply.
--
-- MOST SPECIFIC ROW WINS, and the order is fixed here rather than left to
-- whatever the planner returns: a platform-specific row beats a generic one,
-- then a higher floor beats a lower one, then the newest row beats an older
-- one. Deterministic matters more than clever -- an ops table whose answer
-- depends on physical row order is one VACUUM away from a different game.
--
-- BUILD 0 MATCHES EVERY ROW, which is deliberately the opposite of what
-- client_gate does with the same number, and the reason is symmetric. Build 0
-- is the editor or a desktop run; `BuildID.label()` calls it "dev". The version
-- gate exists to protect players, and a dev build is not a player, so it is
-- exempt. This exists to be tested, and a dev build is where testing happens,
-- so it sees everything -- including rows aimed at a build that does not exist
-- yet, which is the only way to prove a row before it ships. A harness that
-- needs to see what build 140 would see sets LL_FAKE_BUILD and passes it.
create or replace function public.app_config(
        p_app      text    default 'loot-lagoon',
        p_build    integer default 0,
        p_platform text    default '')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_object_agg(r.key, r.value), '{}'::jsonb)
      from (select distinct on (c.key) c.key, c.value
              from public.app_config c
             where c.app = coalesce(p_app, '')
               -- The dev exemption, and both halves of the range.
               and (coalesce(p_build, 0) = 0
                    or (coalesce(p_build, 0) >= c.min_build
                        and (c.max_build = 0
                             or coalesce(p_build, 0) <= c.max_build)))
               and (c.platform = ''
                    or c.platform = lower(coalesce(p_platform, '')))
             order by c.key,
                      (c.platform <> '') desc,
                      c.min_build desc,
                      c.id desc) r
$$;

-- ANON AS WELL AS AUTHENTICATED, for the reason client_gate takes the same
-- grant: a kill switch that only reaches signed-in players is not a kill
-- switch. Every feature this can turn off is reachable by a guest.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'app_config'
    loop
        execute format('revoke all on function %s from public', fn);
        execute format('grant execute on function %s to anon, authenticated', fn);
    end loop;
end;
$$;

-- NO SEED ROWS, and that is the migration's last statement on purpose.
--
-- An empty table is a working game. Every knob the client knows about has a
-- constant behind it that is already correct, and the first row anybody writes
-- here should be written because something is wrong in production -- not
-- because the table looked bare.
