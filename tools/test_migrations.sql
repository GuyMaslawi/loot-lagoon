-- Functional tests for the Loot Lagoon schema. Run by tools/validate_migrations.sh
-- against a throwaway cluster, after the migrations have applied.
--
-- These exist because "the SQL compiles" and "the SQL does what the game needs"
-- are different claims, and the second one is the one that matters. Every check
-- below is a rule stated somewhere in a comment in the migrations; this is
-- where those claims get tested instead of believed.
\set ON_ERROR_STOP on

create or replace function pg_temp.be(p_uid uuid) returns void
language sql as $$ select set_config('request.jwt.claim.sub', p_uid::text, false)::void $$;

create or replace function pg_temp.ck(p_name text, p_ok boolean, p_detail text default '')
returns void language plpgsql as $$
begin
    if p_ok then
        raise notice '  [ok]   %', p_name;
    else
        raise exception '  [FAIL] % %', p_name, p_detail;
    end if;
end;
$$;

do $$
declare
    alice uuid := gen_random_uuid();
    bob   uuid := gen_random_uuid();
    carol uuid := gen_random_uuid();   -- alice's second provider
    p_alice uuid; p_bob uuid; p_bot uuid;
    r jsonb; tok text; n integer;
begin
    insert into auth.users (id, email) values
        (alice, 'alice@example.com'), (bob, 'bob@example.com'), (carol, null);
    insert into auth.identities (user_id, provider) values
        (alice, 'google'), (bob, 'apple'), (carol, 'apple');

    -- --- claim_player -------------------------------------------------------
    perform pg_temp.be(alice);
    r := public.claim_player('{"coins": 1500}'::jsonb, 'Alice', '😎', 120, 5, 9000, 0, '{2,1,0,0,0}');
    perform pg_temp.ck('claim_player creates an island on first sign-in', (r->>'is_new')::boolean);
    perform pg_temp.ck('it is seeded from the save that was on the device',
                       r->'save'->>'coins' = '1500', r::text);
    p_alice := (r->'player'->>'id')::uuid;

    r := public.claim_player('{"coins": 999}'::jsonb, 'Alice', '😎', 1, 1, 0, 0, '{0,0,0,0,0}');
    perform pg_temp.ck('a second sign-in finds the same island, not a new one',
                       (r->>'is_new')::boolean = false and (r->'player'->>'id')::uuid = p_alice);
    perform pg_temp.ck('and does NOT let a fresh device overwrite it on the way in',
                       r->'save'->>'coins' = '1500', r::text);

    -- --- push_save conflict rule -------------------------------------------
    r := public.push_save('{"coins": 4000}'::jsonb, 130, 6, 12000, 0, '{2,2,0,0,0}');
    perform pg_temp.ck('push_save accepts a save that moved forward', r->>'status' = 'ok');

    r := public.push_save('{"coins": 1}'::jsonb, 12, 1, 0, 0, '{0,0,0,0,0}');
    perform pg_temp.ck('push_save REJECTS a stale device pushing less rank',
                       r->>'status' = 'stale', r::text);
    perform pg_temp.ck('and hands back the stored island so the client can adopt it',
                       r->'save'->>'coins' = '4000', r::text);

    r := public.push_save('{"coins": 0}'::jsonb, 0, 1, 0, 0, '{0,0,0,0,0}', true);
    perform pg_temp.ck('p_force still allows a deliberate wipe', r->>'status' = 'ok');
    -- put alice back
    r := public.push_save('{"coins": 4000}'::jsonb, 130, 6, 12000, 0, '{2,2,0,0,0}', true);

    -- --- find_target: humans first -----------------------------------------
    insert into public.players (display_name, emoji, is_bot, island_level, rank_stars,
                                vault_coins, shields, buildings)
    values ('Bot Barnacle', '🤖', true, 6, 100, 5000, 0, '{1,1,1,0,0}')
    returning id into p_bot;

    perform pg_temp.be(bob);
    r := public.claim_player('{"coins": 7000}'::jsonb, 'Bob', '🧔', 110, 6, 7000, 0, '{1,1,0,0,0}');
    p_bob := (r->'player'->>'id')::uuid;

    perform pg_temp.be(alice);
    r := public.find_target('steal');
    perform pg_temp.ck('find_target prefers the human over the bot',
                       (r->>'id')::uuid = p_bob, r::text);

    -- --- find_target: the bot is the fallback, not the exception -----------
    -- Bob just got hit, so he is off the table for ten minutes.
    r := public.record_raid(p_bob, 'steal', 3000);
    perform pg_temp.ck('record_raid returns what was actually taken', (r->>'coins')::bigint = 3000);
    r := public.find_target('steal');
    -- "a bot", not "the bot this test made". Once the seeded population exists
    -- the fallback picks at random from it, and pinning the assertion to one
    -- row would fail for the right behaviour.
    perform pg_temp.ck('with no eligible human, find_target falls back to a bot',
                       (select is_bot from public.players where id = (r->>'id')::uuid),
                       coalesce(r::text, 'NULL'));
    perform pg_temp.ck('and the bot it found is in band, not just any bot',
                       abs((r->>'island_level')::int - 6) <= 3, coalesce(r::text, 'NULL'));

    -- --- a raid now needs an offer the server issued ------------------------
    --
    -- Bob was raided above, so the 24-hour rule has closed him and find_target
    -- will not offer him again. Reaching for him anyway is exactly the attack:
    -- his uuid is public, and before the offer table this call went through.
    begin
        r := public.record_raid(p_bob, 'steal', 999999999);
        perform pg_temp.ck('a raid against an island the server never offered is refused',
                           false, 'record_raid returned ' || coalesce(r::text, 'NULL'));
    exception when others then
        perform pg_temp.ck('a raid against an island the server never offered is refused',
                           sqlerrm like '%no open raid offer%'
                        or sqlerrm like '%already raided%', sqlerrm);
    end;

    -- --- the server clamps a lying client ----------------------------------
    -- Wind the clock back on the earlier raid so Bob is offerable again, then
    -- take the offer honestly. What is under test here is the coin clamp, not
    -- the cooldown that is under test just above.
    update public.raids set created_at = now() - interval '2 days'
     where attacker = p_alice and victim = p_bob;
    update public.players set vault_coins = 500 where id = p_bob;
    perform pg_temp.ck('find_target offers the reopened human again',
                       (public.find_target('steal')->>'id')::uuid = p_bob);
    r := public.record_raid(p_bob, 'steal', 999999999);
    perform pg_temp.ck('a raid cannot take more than the victim actually holds',
                       (r->>'coins')::bigint = 500, r::text);
    perform pg_temp.ck('and the victim is left at zero, never negative',
                       (select vault_coins from public.players where id = p_bob) = 0);

    -- --- the victim hears about it -----------------------------------------
    perform pg_temp.be(bob);
    r := public.unseen_raids();
    perform pg_temp.ck('the victim sees both raids waiting for them',
                       jsonb_array_length(r) = 2, r::text);
    select public.ack_raids(array(select (x->>'id')::uuid from jsonb_array_elements(r) x)) into n;
    perform pg_temp.ck('acknowledging clears them', n = 2);
    perform pg_temp.ck('and they do not come back',
                       jsonb_array_length(public.unseen_raids()) = 0);

    -- The fetch is bounded, and this is measured rather than read. `limit 50`
    -- sat on an aggregate query with no GROUP BY, where it limited the one
    -- result row the aggregate already produced and none of the rows going
    -- into it -- so the answer was every unseen raid this victim had ever
    -- accumulated. main.gd dedupes against a 200-entry list sized for a
    -- 50-row answer, so past that the oldest ids fall off and a failed ack
    -- means the coins come out twice. Sixty raids, so the bound has to bite.
    insert into public.raids (attacker, victim, mode, coins)
         select p_alice, p_bob, 'steal', 1 from generate_series(1, 60);
    perform pg_temp.ck('a big backlog is handed over in bounded batches',
                       jsonb_array_length(public.unseen_raids()) = 50,
                       jsonb_array_length(public.unseen_raids())::text);
    -- Nothing is dropped: what did not fit is still unseen and comes next time.
    select public.ack_raids(array(select (x->>'id')::uuid
                                    from jsonb_array_elements(public.unseen_raids()) x)) into n;
    perform pg_temp.ck('and the remainder is still waiting, not lost',
                       jsonb_array_length(public.unseen_raids()) = 10,
                       jsonb_array_length(public.unseen_raids())::text);
    select public.ack_raids(array(select (x->>'id')::uuid
                                    from jsonb_array_elements(public.unseen_raids()) x)) into n;
    perform pg_temp.ck('until the backlog is drained',
                       jsonb_array_length(public.unseen_raids()) = 0);

    -- --- linking a second provider -----------------------------------------
    perform pg_temp.be(alice);
    tok := public.create_link_token();

    -- Carol is Alice's Apple sign-in, on a new phone, already playing a bit.
    perform pg_temp.be(carol);
    r := public.claim_player('{"coins": 10}'::jsonb, 'Alice', '😎', 3, 1, 10, 0, '{0,0,0,0,0}');
    perform pg_temp.ck('the new phone started its own island', (r->>'is_new')::boolean);

    r := public.redeem_link_token(tok);
    perform pg_temp.ck('linking two islands with progress reports a conflict rather than merging',
                       r->>'status' = 'conflict', r::text);
    perform pg_temp.ck('and describes both so the player can be asked',
                       (r->'mine'->>'rank_stars')::int = 3
                   and (r->'theirs'->>'rank_stars')::int = 130, r::text);

    r := public.redeem_link_token(tok, p_alice);
    perform pg_temp.ck('resolving keeps the island the player chose', r->>'status' = 'linked'
                   and (r->'player'->>'id')::uuid = p_alice, r::text);
    perform pg_temp.ck('the Apple sign-in now opens the kept island',
                       public.current_player() = p_alice);
    perform pg_temp.ck('and the discarded island is soft-deleted, not destroyed',
                       (select count(*) from public.players
                         where deleted_at is not null and save_blob->>'coins' = '10') = 1);
    perform pg_temp.ck('a spent token cannot be spent twice',
                       public.redeem_link_token(tok)->>'status' = 'expired');

    -- --- the linking screen can tell what is already connected -------------
    perform pg_temp.ck('my_identities reports both providers after a link',
                       public.my_identities() @> '["apple","google"]'::jsonb,
                       public.my_identities()::text);

    -- --- Alice's original Google sign-in still opens the same island --------
    perform pg_temp.be(alice);
    perform pg_temp.ck('the first provider was not evicted by the link',
                       public.current_player() = p_alice);

    -- --- display names -----------------------------------------------------
    perform pg_temp.be(alice);

    -- The 46 seeded bot faces are in `players` like everyone else, so this is
    -- the same query that catches another human -- there is no second list.
    perform pg_temp.ck('a name held by a bot cannot be taken',
                       (public.name_available('Maya')->>'ok')::boolean = false,
                       public.name_available('Maya')::text);

    perform pg_temp.ck('nor a name held by another player',
                       (public.name_available('Bob')->>'ok')::boolean = false,
                       public.name_available('Bob')::text);

    -- Maya, maya and "maya   " are three strings and one name. Without
    -- normalisation the whole rule is sidestepped with the space bar.
    perform pg_temp.ck('case and spacing do not create a second name',
                       (public.name_available('  MAYA  ')->>'ok')::boolean = false);

    perform pg_temp.ck('profanity is refused', public.name_problem('shitlord') is not null);
    perform pg_temp.ck('so is posing as the game itself',
                       public.name_problem('Official Support') is not null);
    perform pg_temp.ck('a one-letter name is refused', public.name_problem('x') is not null);
    perform pg_temp.ck('and one longer than the card can show',
                       public.name_problem('Bartholomew Fitzgerald III') is not null);

    -- 175 countries. Insisting on A-Z would be its own kind of bug.
    perform pg_temp.ck('a Hebrew name is accepted', public.name_problem('גיא') is null,
                       coalesce(public.name_problem('גיא'), 'null'));

    perform pg_temp.ck('a free name is free', (public.name_available('Seashell')->>'ok')::boolean);
    r := public.set_display_name('Seashell');
    perform pg_temp.ck('and setting it works', (r->>'ok')::boolean, r::text);
    perform pg_temp.ck('the island now wears it',
                       public.public_player(p_alice)->>'name' = 'Seashell');
    perform pg_temp.ck('re-checking your OWN name does not report it taken',
                       (public.name_available('Seashell')->>'ok')::boolean);

    -- What a new sign-in gets when the provider hands over a name somebody --
    -- or some bot -- already has.
    perform pg_temp.ck('unique_name works around a bot collision',
                       public.normalize_name(public.unique_name('Maya')) <> 'maya',
                       public.unique_name('Maya'));
    perform pg_temp.ck('and never returns something too long for the card',
                       length(public.unique_name('Bartholomew Fitz')) <= 16,
                       public.unique_name('Bartholomew Fitz'));
    perform pg_temp.ck('an empty provider name still yields something usable',
                       public.name_problem(public.unique_name('')) is null,
                       public.unique_name(''));

    -- --- reporting and blocking --------------------------------------------
    perform pg_temp.be(alice);
    r := public.find_target('steal', 30);
    perform pg_temp.ck('there is somebody to find before any blocking',
                       r is not null, coalesce(r::text, 'NULL'));
    -- Block every bot in band, then confirm the well really is dry, so the
    -- next assertion is testing the block and not an empty pool.
    insert into public.blocks (blocker, blocked)
        select p_alice, id from public.players where is_bot = true;
    perform pg_temp.ck('blocking every candidate leaves find_target with nobody',
                       public.find_target('steal', 30) is null,
                       coalesce(public.find_target('steal', 30)::text, 'NULL'));
    delete from public.blocks where blocker = p_alice;

    r := public.report_player((select id from public.players where is_bot = true limit 1), 'name');
    perform pg_temp.ck('reporting succeeds', (r->>'ok')::boolean, r::text);
    perform pg_temp.ck('and blocks in the same breath',
                       (select count(*) from public.blocks where blocker = p_alice) = 1);
    perform pg_temp.ck('reporting twice does not raise or duplicate',
                       (public.report_player((select id from public.players where is_bot = true limit 1))->>'ok')::boolean
                   and (select count(*) from public.reports where reporter = p_alice) = 1);
    delete from public.blocks where blocker = p_alice;

    -- The leaderboard sorts on a number the client asserts. It still does --
    -- the economy lives in main.gd -- but the assertion is now bounded by how
    -- much time has passed, so "instantly first" is not one push away.
    perform pg_temp.be(alice);
    r := public.push_save('{"coins": 1}'::jsonb, 2000000000, 6, 100, 0, '{1,0,0,0,0}');
    perform pg_temp.ck('a push cannot declare two billion stars',
                       (r->>'status') = 'ok'
                   and (r->>'rank_stars')::int < 10000,
                       r::text);
    perform pg_temp.ck('and the leaderboard shows the bounded number, not the claim',
                       (select rank_stars from public.players where id = p_alice) < 10000,
                       (select rank_stars::text from public.players where id = p_alice));
    -- An ordinary push is untouched: a handful of stars since the last one.
    declare
        v_before integer;
    begin
        select rank_stars into v_before from public.players where id = p_alice;
        r := public.push_save('{"coins": 2}'::jsonb, v_before + 7, 6, 100, 0, '{1,0,0,0,0}');
        perform pg_temp.ck('an honest push is not clamped at all',
                           (r->>'rank_stars')::int = v_before + 7, r::text);
    end;
    -- And a deliberate wipe still goes all the way down.
    r := public.push_save('{"coins": 0}'::jsonb, 0, 1, 0, 0, '{0,0,0,0,0}', true);
    perform pg_temp.ck('a forced wipe is still allowed past the bound',
                       (select rank_stars from public.players where id = p_alice) = 0,
                       (select rank_stars::text from public.players where id = p_alice));
    -- Put her back for the checks that follow.
    r := public.push_save('{"coins": 4000}'::jsonb, 130, 6, 12000, 0, '{2,2,0,0,0}', true);

    -- --- what the 2026-08-31 red team walked through -----------------------
    --
    -- Every check below is a door that was open. They are grouped because they
    -- were found together, not because they share a mechanism.

    -- The table-wide UPDATE grant. The policy checked which ROW and never which
    -- COLUMN, so one PATCH to /rest/v1/players set display_name, rank_stars and
    -- deleted_at past every rule the RPCs enforce.
    perform pg_temp.ck('authenticated cannot write public.players directly',
                       not has_table_privilege('authenticated', 'public.players', 'update'));
    perform pg_temp.ck('but it can still read back its own island',
                       has_table_privilege('authenticated', 'public.players', 'select'));
    perform pg_temp.ck('and it never gained insert or delete',
                       not has_table_privilege('authenticated', 'public.players', 'insert')
                   and not has_table_privilege('authenticated', 'public.players', 'delete'));
    perform pg_temp.ck('the offer table is not exposed to the API at all',
                       not has_table_privilege('authenticated', 'public.raid_offers', 'select'));

    -- The name filter was a raw substring match over a charset that admits
    -- periods and the whole Unicode alphanumeric range.
    perform pg_temp.ck('a name spelled around the filter with periods is refused',
                       public.name_problem('a.d.m.i.n') is not null,
                       coalesce(public.name_problem('a.d.m.i.n'), 'ACCEPTED'));
    perform pg_temp.ck('and one spelled with a Greek lookalike is refused',
                       public.name_problem('supp' || U&'\03BF' || 'rt') is not null,
                       coalesce(public.name_problem('supp' || U&'\03BF' || 'rt'), 'ACCEPTED'));
    perform pg_temp.ck('while an ordinary name is still free',
                       public.name_problem('Coral Reef') is null,
                       coalesce(public.name_problem('Coral Reef'), ''));
    perform pg_temp.ck('and a Hebrew name still is too',
                       public.name_problem(U&'\05D2\05D9\05D0') is null,
                       coalesce(public.name_problem(U&'\05D2\05D9\05D0'), ''));

    -- set_emoji had a twelve-face allowlist; claim_player, the other create
    -- path, stored whatever arrived -- an unfiltered second name field on every
    -- raid card.
    declare
        dave uuid := gen_random_uuid();
        p_dave uuid;
        erin uuid := gen_random_uuid();
        p_erin uuid;
    begin
        insert into auth.users (id, email) values (dave, 'dave@example.com');
        insert into auth.identities (user_id, provider) values (dave, 'google');
        perform pg_temp.be(dave);
        r := public.claim_player('{"coins": 1}'::jsonb, 'Dave',
                                 repeat('X', 400), 2000000000, 6, 800, 0, '{1,0,0,0,0}');
        p_dave := (r->'player'->>'id')::uuid;
        perform pg_temp.ck('claim_player refuses an emoji that is not one of the faces',
                           (select emoji from public.players where id = p_dave) = U&'\+01F642',
                           (select emoji from public.players where id = p_dave));
        perform pg_temp.ck('and a fresh island cannot claim the top of the leaderboard',
                           (select rank_stars from public.players where id = p_dave) = 1000000,
                           (select rank_stars::text from public.players where id = p_dave));

        -- A shield is bought with real money. find_target only ever tests it in
        -- its `attack` branch, and main.gd only ever asks for `steal`, so until
        -- now nothing tested it at all.
        insert into auth.users (id, email) values (erin, 'erin@example.com');
        insert into auth.identities (user_id, provider) values (erin, 'apple');
        perform pg_temp.be(erin);
        r := public.claim_player('{"coins": 1}'::jsonb, 'Erin', U&'\+01F419', 100, 6, 4000, 0, '{2,2,0,0,0}');
        p_erin := (r->'player'->>'id')::uuid;

        -- Whoever it picks -- Alice and Erin are both eligible humans in band,
        -- so this is a coin toss by design -- it must have written the offer
        -- that record_raid will look for. That is the whole contract between
        -- the two functions.
        perform pg_temp.be(dave);
        r := public.find_target('steal');
        perform pg_temp.ck('find_target records an offer for the rival it returns',
                           exists (select 1 from public.raid_offers o
                                    where o.attacker = p_dave
                                      and o.victim = (r->>'id')::uuid
                                      and o.used_at is null
                                      and o.expires_at > now()),
                           coalesce(r::text, 'NULL'));

        -- The rest of this block needs Erin specifically, so hand Dave the
        -- offer directly rather than searching until the draw cooperates.
        delete from public.raid_offers where attacker = p_dave;
        insert into public.raid_offers (attacker, victim) values (p_dave, p_erin);
        update public.players set shields = 1 where id = p_erin;
        begin
            r := public.record_raid(p_erin, 'attack', 0, 1);
            perform pg_temp.ck('a shielded island cannot be attacked', false,
                               'record_raid returned ' || coalesce(r::text, 'NULL'));
        exception when others then
            perform pg_temp.ck('a shielded island cannot be attacked',
                               sqlerrm like '%shielded%', sqlerrm);
        end;

        -- The offer survives a refused attack: nothing was spent.
        update public.players set shields = 0 where id = p_erin;
        r := public.record_raid(p_erin, 'attack', 0, 99);
        perform pg_temp.ck('an out-of-range hut is stored as no hut at all',
                           (select hut from public.raids
                             where attacker = p_dave and victim = p_erin) is null);

        -- One offer, one raid. The leaderboard hands out every uuid in the
        -- game, and this is what stops a for-loop over it.
        begin
            r := public.record_raid(p_erin, 'steal', 100);
            perform pg_temp.ck('an offer cannot be spent twice', false,
                               'record_raid returned ' || coalesce(r::text, 'NULL'));
        exception when others then
            perform pg_temp.ck('an offer cannot be spent twice',
                               sqlerrm like '%no open raid offer%'
                            or sqlerrm like '%already raided%', sqlerrm);
        end;

        -- Collecting offers rather than spending them. The 24-hour rule means
        -- each rival can only be hit once, so the ceiling here is the backstop
        -- against one account raiding a very large number of strangers.
        declare
            v_flood uuid;
        begin
            for i in 1..205 loop
                insert into public.players (display_name, emoji, island_level,
                                            vault_coins, buildings)
                values ('Flood' || i, U&'\+01F642', 6, 100, '{1,0,0,0,0}')
                returning id into v_flood;
                insert into public.raid_offers (attacker, victim) values (p_dave, v_flood);
                begin
                    perform public.record_raid(v_flood, 'steal', 10);
                exception when others then
                    exit;
                end;
            end loop;
            perform pg_temp.ck('one account cannot raid an unbounded number of strangers',
                               (select count(*) from public.raids
                                 where attacker = p_dave
                                   and created_at > now() - interval '1 hour') <= 200,
                               (select count(*)::text from public.raids where attacker = p_dave));
        end;
        delete from public.raids where attacker = p_dave;

        -- Blocking is the only recourse a harassed player has, and record_raid
        -- never consulted it.
        perform pg_temp.be(erin);
        perform public.block_player(p_dave);
        perform pg_temp.be(dave);
        update public.raids set created_at = now() - interval '2 days'
         where attacker = p_dave and victim = p_erin;
        insert into public.raid_offers (attacker, victim) values (p_dave, p_erin);
        begin
            r := public.record_raid(p_erin, 'steal', 100);
            perform pg_temp.ck('a player who blocked you cannot be raided', false,
                               'record_raid returned ' || coalesce(r::text, 'NULL'));
        exception when others then
            perform pg_temp.ck('a player who blocked you cannot be raided',
                               sqlerrm like '%blocked%', sqlerrm);
        end;
    end;

    -- --- deletion ----------------------------------------------------------
    perform pg_temp.be(bob);
    r := public.delete_account();
    perform pg_temp.ck('delete_account removes the identities it found',
                       (r->>'identities')::int = 1, r::text);
    perform pg_temp.ck('and the island is gone from every read path',
                       public.public_player(p_bob) is null);
    -- A Google sign-in publishes the player's real full name as their handle,
    -- so a soft delete that keeps display_name is not erasure.
    perform pg_temp.ck('deletion takes the published name with it',
                       (select display_name from public.players where id = p_bob)
                           = 'Former islander',
                       (select display_name from public.players where id = p_bob));
    perform pg_temp.ck('and the thirty-day undo still has the save to restore',
                       (select save_blob from public.players where id = p_bob) is not null);

    -- --- diagnostics -------------------------------------------------------
    -- The table exists so that twenty-five strangers testing the game for two
    -- weeks produce something more than a count. Every rule the migration
    -- claims in prose is checked here.
    perform pg_temp.be(alice);
    n := public.report_diagnostics('inst-1', 'Android', '15', 'Pixel 8', 62, '[
            {"kind": "crash", "detail": {"where": "slot"}},
            {"kind": "usage", "detail": {"spins": 40}}
        ]'::jsonb);
    perform pg_temp.ck('report_diagnostics writes the batch it is handed', n = 2, n::text);
    perform pg_temp.ck('and files it against the caller''s island',
                       (select count(*) from public.diagnostics where player = p_alice) = 2);

    n := public.report_diagnostics('inst-1', 'Android', '15', 'Pixel 8', 62, '[
            {"kind": "nonsense", "detail": {}},
            {"kind": "error",    "detail": {"at": "iap"}}
        ]'::jsonb);
    perform pg_temp.ck('an unknown kind is skipped without failing its batch', n = 1, n::text);

    n := public.report_diagnostics('inst-1', 'Android', '15', 'Pixel 8', 62, 'null'::jsonb);
    perform pg_temp.ck('a malformed payload is refused rather than raising', n = 0, n::text);

    -- The client is told to drop what the cap refuses. If this ever returns the
    -- batch size instead of 0, a flushing loop becomes an infinite one.
    insert into public.diagnostics (player, install_id, kind)
        select p_alice, 'inst-1', 'usage' from generate_series(1, 120);
    n := public.report_diagnostics('inst-1', 'Android', '15', 'Pixel 8', 62,
                                   '[{"kind": "crash", "detail": {}}]'::jsonb);
    perform pg_temp.ck('over the hourly cap it accepts nothing and says so', n = 0, n::text);

    delete from public.diagnostics where player = p_alice;

    -- --- diagnostics: the door is the only way in ---------------------------
    perform pg_temp.ck('authenticated cannot write the diagnostics table directly',
                       not has_table_privilege('authenticated', 'public.diagnostics', 'insert')
                   and not has_table_privilege('authenticated', 'public.diagnostics', 'select'));
    perform pg_temp.ck('and anon cannot call the function that can',
                       not has_function_privilege('anon',
                           'public.report_diagnostics(text, text, text, text, integer, jsonb)',
                           'execute'));
    perform pg_temp.ck('while authenticated can',
                       has_function_privilege('authenticated',
                           'public.report_diagnostics(text, text, text, text, integer, jsonb)',
                           'execute'));
    perform pg_temp.ck('pruning is not reachable from any client at all',
                       not has_function_privilege('authenticated',
                           'public.prune_diagnostics(integer, integer)', 'execute')
                   and not has_function_privilege('anon',
                           'public.prune_diagnostics(integer, integer)', 'execute'));

    -- --- diagnostics: an account with no island -----------------------------
    declare
        nomad uuid := gen_random_uuid();
    begin
        insert into auth.users (id, email) values (nomad, 'nomad@example.com');
        perform pg_temp.be(nomad);
        begin
            n := public.report_diagnostics('inst-9', 'iOS', '18', 'iPhone', 62,
                                           '[{"kind": "crash", "detail": {}}]'::jsonb);
            perform pg_temp.ck('a session with no island cannot file diagnostics', false,
                               'it returned ' || n::text);
        exception when others then
            perform pg_temp.ck('a session with no island cannot file diagnostics',
                               sqlerrm like '%no island%', sqlerrm);
        end;
    end;

    -- --- diagnostics: pruning keeps the rare rows ---------------------------
    perform pg_temp.be(alice);
    insert into public.diagnostics (player, install_id, kind, created_at) values
        (p_alice, 'inst-1', 'usage', now() - interval '30 days'),
        (p_alice, 'inst-1', 'crash', now() - interval '30 days'),
        (p_alice, 'inst-1', 'usage', now());
    n := public.prune_diagnostics();
    perform pg_temp.ck('pruning drops stale usage rows', n = 1, n::text);
    perform pg_temp.ck('and keeps a crash that is older than any of them',
                       (select count(*) from public.diagnostics
                         where player = p_alice and kind = 'crash') = 1);
    delete from public.diagnostics where player = p_alice;

    -- --- the tournament -----------------------------------------------------
    --
    -- The board is a league of islands at a similar stage scored on one cycle,
    -- so the three things worth proving are that the league really is a filter,
    -- that a rollover does not eat the score the prize is owed on, and that an
    -- offline device cannot push its stale total over a fresher one.
    declare
        cyc    integer := public.tourney_now_id();
        far    uuid := gen_random_uuid();   -- an island ten leagues away
        p_far  uuid;
    begin
        perform pg_temp.ck('a league is three islands wide',
                           public.tourney_league(1) = 1 and public.tourney_league(3) = 1
                       and public.tourney_league(4) = 2, public.tourney_league(4)::text);
        perform pg_temp.ck('and everything past the economy curve shares the top one',
                           public.tourney_league(30) = 10 and public.tourney_league(97) = 10);

        insert into auth.users (id, email) values (far, 'far@example.com');
        insert into auth.identities (user_id, provider) values (far, 'google');
        perform pg_temp.be(far);
        r := public.claim_player('{}'::jsonb, 'Far', '😎', 4000, 28, 0, 0, '{0,0,0,0,0}');
        p_far := (r->'player'->>'id')::uuid;
        r := public.tourney_report(cyc, 9000);
        perform pg_temp.ck('tourney_report accepts a score for the current cycle',
                           r->>'status' = 'ok', r::text);

        perform pg_temp.be(alice);
        r := public.tourney_report(cyc, 400);
        perform pg_temp.ck('and again for a second island', r->>'status' = 'ok', r::text);
        r := public.tourney_report(cyc, 120);
        perform pg_temp.ck('a stale device cannot push its lower total over a fresher one',
                           (select tourney_points from public.players where id = p_alice) = 400,
                           (select tourney_points::text from public.players where id = p_alice));
        r := public.tourney_report(cyc - 4, 999999);
        perform pg_temp.ck('nor can a phone with a wound-forward clock post into another cycle',
                           r->>'status' = 'stale_cycle', r::text);

        -- Alice is on island 6 (league 2) after the push_save above; Far is on
        -- 28 (league 10). Neither may appear on the other's board.
        r := public.tourney_board(100);
        perform pg_temp.ck('the board is one league, not the world',
                           not (r::text like '%' || p_far::text || '%'), r::text);
        perform pg_temp.ck('and the caller is on their own board',
                           r::text like '%' || p_alice::text || '%', r::text);
        perform pg_temp.ck('every row carries the points it is ranked on',
                           (select count(*) from jsonb_array_elements(r) e
                             where e ? 'points') = jsonb_array_length(r), r::text);

        -- --- the rollover, which is what makes the prize payable ------------
        r := public.tourney_report(cyc, 500);
        update public.players set tourney_id = tourney_id - 1 where id = p_alice;
        r := public.tourney_report(cyc, 10);
        perform pg_temp.ck('a new cycle starts from the score it was given',
                           (select tourney_points from public.players where id = p_alice) = 10);
        perform pg_temp.ck('and the finished cycle is kept rather than dropped',
                           (select tourney_prev_points from public.players where id = p_alice) = 500);

        r := public.tourney_result(cyc - 1);
        perform pg_temp.ck('tourney_result reads the cycle that has ended',
                           (r->>'points')::integer = 500, r::text);
        perform pg_temp.ck('and answers with a place inside a field of at least one',
                           (r->>'place')::integer >= 1
                       and (r->>'field')::integer >= (r->>'place')::integer, r::text);

        -- --- a bot is never sitting on nothing ------------------------------
        perform pg_temp.ck('a bot carries a score for the cycle, so the board is not half zeroes',
                           public.tourney_bot_points(p_bot, cyc, 6, 1.0) > 0,
                           public.tourney_bot_points(p_bot, cyc, 6, 1.0)::text);
        perform pg_temp.ck('the same bot has the same finish all cycle',
                           public.tourney_bot_points(p_bot, cyc, 6, 1.0)
                             = public.tourney_bot_points(p_bot, cyc, 6, 1.0));
        perform pg_temp.ck('and a different one when the cycle turns',
                           public.tourney_bot_points(p_bot, cyc, 6, 1.0)
                            <> public.tourney_bot_points(p_bot, cyc + 1, 6, 1.0));

        -- --- and the bot ARRIVES over the three days ------------------------
        -- The board is opened mid-cycle far more often than at the buzzer, and
        -- a field already sitting on its final totals is a race that has been
        -- run rather than one to join.
        perform pg_temp.ck('a bot has nothing at the start of a cycle',
                           public.tourney_bot_points(p_bot, cyc, 6, 0.0) = 0,
                           public.tourney_bot_points(p_bot, cyc, 6, 0.0)::text);
        perform pg_temp.ck('and climbs as the cycle runs',
                           public.tourney_bot_points(p_bot, cyc, 6, 0.2)
                             < public.tourney_bot_points(p_bot, cyc, 6, 0.6)
                       and public.tourney_bot_points(p_bot, cyc, 6, 0.6)
                             < public.tourney_bot_points(p_bot, cyc, 6, 1.0));
        perform pg_temp.ck('a third of the way in it is well short of its finish',
                           public.tourney_bot_points(p_bot, cyc, 6, 0.33)
                             < public.tourney_bot_points(p_bot, cyc, 6, 1.0) * 0.8);
        perform pg_temp.ck('progress outside 0..1 cannot push a bot past its finish',
                           public.tourney_bot_points(p_bot, cyc, 6, 9.0)
                             = public.tourney_bot_points(p_bot, cyc, 6, 1.0));
        -- Not every bot on the same curve: a field that moves in lockstep is
        -- one bot drawn nine times.
        perform pg_temp.ck('bots run at different paces',
                           (select count(distinct round(
                               public.tourney_bot_points(p.id, cyc, 6, 0.3)::numeric
                             / greatest(public.tourney_bot_points(p.id, cyc, 6, 1.0), 1), 2))
                              from public.players p where p.is_bot) > 3);
        perform pg_temp.ck('the live progress fraction is inside its own cycle',
                           public.tourney_progress() >= 0.0
                       and public.tourney_progress() <= 1.0,
                           public.tourney_progress()::text);

        -- --- the bot field is the FLOOR, in every league --------------------
        --
        -- "They are the floor, not the ceiling -- somebody playing properly
        -- passes all of them." That sentence was false in seven of the ten
        -- leagues until 2026-09-07, because the bot span climbed with the
        -- island while a human's cycle total does not vary with it at all.
        --
        -- Derived, not typed. A human's 72h score is spins x points-per-spin
        -- plus the capped build term, and a casual player is 450 spins; the
        -- expected top of twelve uniform md5 draws on [0, span) is span*12/13.
        -- Typed, this check would go stale the moment any of those moved --
        -- and stale in the loose direction, which is the direction a bound
        -- must never go stale in.
        declare
            casual   numeric := 450 * 2.21 + 300;   -- 150 spins/day, cap
            span     integer;
            top_bot  numeric;
            broken   integer := 0;
        begin
            for i in 1..10 loop
                span := 750 + 20 * least(3 * i, 30);
                top_bot := span * 12.0 / 13.0;
                if top_bot >= casual then
                    broken := broken + 1;
                end if;
            end loop;
            perform pg_temp.ck('a casual player passes the whole bot field in EVERY league',
                               broken = 0, broken::text || ' leagues where they do not');
        end;
        perform pg_temp.ck('and the top league is still a harder room than the first',
                           public.tourney_bot_points(p_bot, cyc, 30, 1.0) >= 0
                       and (750 + 20 * 30) > (750 + 20 * 3));
        -- The slope is a gentle tilt now, not a curve that outruns the player.
        perform pg_temp.ck('the bot span no more than doubles across the ten leagues',
                           (750 + 20 * 30)::numeric / (750 + 20 * 3)::numeric < 2.0,
                           ((750 + 20 * 30)::numeric / (750 + 20 * 3)::numeric)::text);
        perform pg_temp.ck('a bot in the top league is still capped under the first reward rung',
                           (750 + 20 * 30) < 2500, (750 + 20 * 30)::text);

        -- --- brackets -------------------------------------------------------
        --
        -- The board returns at most 40 rows and the end-of-cycle dialog counted
        -- the whole league, so at scale the two named different competitions.
        -- These are the properties that stop that: the slot space partitions
        -- exactly, a slice change SPLITS a bracket rather than reshuffling it,
        -- and both readers ask the same question.
        perform pg_temp.ck('one slice is the whole league, which is how this behaved before',
                           public.tourney_bracket_range(0, 1) = array[0, 1024]
                       and public.tourney_bracket_range(1023, 1) = array[0, 1024],
                           public.tourney_bracket_range(1023, 1)::text);
        perform pg_temp.ck('a slot always falls inside its own bracket',
                           (select bool_and(s >= (public.tourney_bracket_range(s, k))[1]
                                        and s <  (public.tourney_bracket_range(s, k))[2])
                              from generate_series(0, 1023) s,
                                   unnest(array[1,2,3,4,7,16,30,64]) k));
        -- The partition property, which is the one that matters: no slot in two
        -- brackets and no slot in none. A gap is a player nobody competes with.
        perform pg_temp.ck('the brackets tile the slot space with no gap and no overlap',
                           (select bool_and(ok) from (
                               select count(distinct (public.tourney_bracket_range(s, k))[1]
                                                  || ':' ||
                                       (public.tourney_bracket_range(s, k))[2]) = k as ok
                                 from generate_series(0, 1023) s,
                                      unnest(array[1,2,4,8,16,32,64]) k
                                group by k) t));
        -- Contiguous runs, not modulo, is what makes a resize a SPLIT: everyone
        -- who shared a bracket at k slices shares one of its two halves at 2k.
        -- Modulo would scatter the whole league every time it grew.
        perform pg_temp.ck('growing a league splits brackets instead of reshuffling them',
                           (select bool_and(
                               (public.tourney_bracket_range(a, 8))[1]
                                   >= (public.tourney_bracket_range(a, 4))[1]
                           and (public.tourney_bracket_range(a, 8))[2]
                                   <= (public.tourney_bracket_range(a, 4))[2])
                              from generate_series(0, 1023) a));
        perform pg_temp.ck('a league nobody has reported in is one bracket',
                           public.tourney_slices(7) = 1, public.tourney_slices(7)::text);
        -- The cache is kept warm by the write path, because the board is
        -- `stable` and cannot write. Alice reported above, so league 2 has a row.
        perform pg_temp.ck('reporting a score refreshes the league size',
                           (select members from public.tourney_leagues where league = 2) >= 1,
                           coalesce((select members::text from public.tourney_leagues
                                      where league = 2), 'no row'));
        -- Driven off a written count rather than the fixture's own population,
        -- which is whatever the tests above happened to insert.
        update public.tourney_leagues set members = 30 where league = 2;
        perform pg_temp.ck('thirty members is one bracket',
                           public.tourney_slices(2) = 1, public.tourney_slices(2)::text);
        update public.tourney_leagues set members = 31 where league = 2;
        perform pg_temp.ck('and thirty-one is two',
                           public.tourney_slices(2) = 2, public.tourney_slices(2)::text);
        update public.tourney_leagues set members = 100000 where league = 2;
        perform pg_temp.ck('a huge league is capped at 64 slices rather than shredded',
                           public.tourney_slices(2) = 64, public.tourney_slices(2)::text);
        update public.tourney_leagues set members = 1 where league = 2;
        -- The defect itself: the board and the result must name one field.
        perform pg_temp.be(alice);
        r := public.tourney_board(100);
        perform pg_temp.ck('the caller is still on their own board after bracketing',
                           r::text like '%' || p_alice::text || '%', r::text);
        perform pg_temp.ck('and the board and the end-of-cycle field agree on who was in it',
                           (public.tourney_result(cyc)->>'field')::integer
                             >= jsonb_array_length(r) - 1,
                           public.tourney_result(cyc)::text || ' vs ' ||
                             jsonb_array_length(r)::text || ' rows');
        perform pg_temp.ck('every island has a slot to be bracketed by',
                           not exists (select 1 from public.players where tourney_slot is null));
        perform pg_temp.ck('and every slot is inside the space the ranges cover',
                           (select bool_and(tourney_slot between 0 and 1023)
                              from public.players));

        -- --- grants ---------------------------------------------------------
        perform pg_temp.ck('anon cannot report a tournament score',
                           not has_function_privilege('anon',
                               'public.tourney_report(integer, integer)', 'execute'));
        perform pg_temp.ck('while a signed-in player can',
                           has_function_privilege('authenticated',
                               'public.tourney_report(integer, integer)', 'execute'));
        -- The league sizes are a population figure, which is exactly the kind
        -- of thing a scraper wants and no player needs.
        perform pg_temp.ck('nobody can ask the server how big a league is',
                           not has_function_privilege('authenticated',
                               'public.tourney_slices(integer)', 'execute')
                       and not has_table_privilege('authenticated',
                               'public.tourney_leagues', 'select'));
    end;


    -- =========================================================================
    --  clans, and giving a spare card to a clanmate
    -- =========================================================================
    --
    -- Every rule here is one the CLIENT could otherwise lie about. The card
    -- collection lives in save_blob and the server never sees it, so these
    -- checks are the whole of what "no holes" can mean for this feature.
    declare
        dave uuid := gen_random_uuid();
        erin uuid := gen_random_uuid();
        p_dave uuid; p_erin uuid;
        clan_id uuid;
        g jsonb;
        i integer;
    begin
        insert into auth.users (id, email) values
            (dave, 'dave@example.com'), (erin, 'erin@example.com');
        insert into auth.identities (user_id, provider) values
            (dave, 'google'), (erin, 'google');

        perform pg_temp.be(dave);
        perform public.claim_player('{}'::jsonb, 'Dave', '🧔', 50, 4, 3000, 0, '{1,1,0,0,0}');
        select id into p_dave from public.players
         where id = public.current_player();
        perform pg_temp.be(erin);
        perform public.claim_player('{}'::jsonb, 'Erin', '👩', 60, 4, 3000, 0, '{1,1,0,0,0}');
        select id into p_erin from public.players
         where id = public.current_player();

        -- --- making and joining one ----------------------------------------
        perform pg_temp.be(dave);
        r := public.create_clan('Sea Dogs', '🐕');
        perform pg_temp.ck('a clan can be made', (r->>'ok')::boolean, r::text);
        clan_id := ((r->'clan')->>'id')::uuid;
        perform pg_temp.ck('and its founder is in it',
            jsonb_array_length((r->'clan')->'members') = 1);

        perform pg_temp.ck('a second clan by the same person is refused',
            not (public.create_clan('Other Crew')->>'ok')::boolean);

        perform pg_temp.be(erin);
        perform pg_temp.ck('a name that differs only by case or spacing is taken',
            (public.create_clan('  sea   dogs ')->>'reason') = 'taken');
        perform pg_temp.ck('a name that is too short is refused',
            (public.create_clan('ab')->>'reason') = 'length');

        r := public.join_clan(clan_id);
        perform pg_temp.ck('somebody else can join it', (r->>'ok')::boolean, r::text);
        perform pg_temp.ck('and the roster now shows both',
            jsonb_array_length((r->'clan')->'members') = 2);
        perform pg_temp.ck('the member count kept up',
            (select members from public.clans where id = clan_id) = 2);
        perform pg_temp.ck('my_clan answers with the one I am in',
            (public.my_clan()->>'id')::uuid = clan_id);

        -- --- the four rules the client cannot be trusted with ---------------
        perform pg_temp.be(dave);

        perform pg_temp.ck('SENDING TO YOURSELF IS REFUSED',
            (public.send_card(p_dave, 'reef', 2, 1)->>'reason') = 'self');

        perform pg_temp.ck('A FIVE-STAR CARD CANNOT BE SENT',
            (public.send_card(p_erin, 'reef', 2, 5)->>'reason') = 'stars');
        perform pg_temp.ck('...nor anything pretending to be one',
            (public.send_card(p_erin, 'reef', 2, 99)->>'reason') = 'stars'
        and (public.send_card(p_erin, 'reef', 2, 0)->>'reason') = 'stars');

        -- ...and it holds even if send_card is bypassed entirely. The check
        -- constraint is the floor under the function.
        begin
            insert into public.card_gifts (from_player, to_player, set_id, card_idx, stars)
                 values (p_dave, p_erin, 'reef', 2, 5);
            perform pg_temp.ck('a 5-star gift cannot be written even directly', false);
        exception when check_violation then
            perform pg_temp.ck('a 5-star gift cannot be written even directly', true);
        end;
        begin
            insert into public.card_gifts (from_player, to_player, set_id, card_idx, stars)
                 values (p_dave, p_dave, 'reef', 2, 1);
            perform pg_temp.ck('a self-gift cannot be written even directly', false);
        exception when check_violation then
            perform pg_temp.ck('a self-gift cannot be written even directly', true);
        end;

        -- --- a real send ----------------------------------------------------
        g := public.send_card(p_erin, 'reef', 2, 3);
        perform pg_temp.ck('a legitimate gift to a clanmate goes through',
            (g->>'ok')::boolean, g::text);

        perform pg_temp.be(erin);
        r := public.unseen_gifts();
        perform pg_temp.ck('the receiver has it waiting', jsonb_array_length(r) = 1);
        perform pg_temp.ck('...with the card it was sent',
            (r->0->>'set') = 'reef' and (r->0->>'idx')::int = 2
            and (r->0->>'stars')::int = 3);
        -- Compared against the stored name rather than the literal passed to
        -- claim_player: display names are uniqued on the way in and a taken
        -- one is handed back with a suffix, so the literal is not what the
        -- row necessarily holds.
        perform pg_temp.ck('...and who sent it, so the game can say so',
            ((r->0->'by')->>'name')
            = (select display_name from public.players where id = p_dave),
            coalesce((r->0->'by')->>'name', '<null>'));

        perform public.ack_gifts(array[(r->0->>'id')::uuid]);
        perform pg_temp.ck('once applied it stops arriving',
            jsonb_array_length(public.unseen_gifts()) = 0);

        -- --- clan membership is the gate ------------------------------------
        perform public.leave_clan();
        perform pg_temp.be(dave);
        perform pg_temp.ck('SOMEBODY WHO LEFT CANNOT BE SENT TO',
            (public.send_card(p_erin, 'reef', 3, 1)->>'reason') = 'not_clanmates');
        perform pg_temp.be(erin);
        perform pg_temp.ck('and they cannot send in either',
            (public.send_card(p_dave, 'reef', 3, 1)->>'reason') = 'not_clanmates');
        perform public.join_clan(clan_id);

        -- --- the caps, which are the ceiling on the whole feature ------------
        perform pg_temp.be(dave);
        -- Dave has already sent one. The receive cap is the tighter of the two,
        -- so it is what stops him first.
        i := 0;
        while (public.send_card(p_erin, 'reef', 10 + i, 1)->>'ok')::boolean loop
            i := i + 1;
            exit when i > 20;
        end loop;
        perform pg_temp.ck('THE RECEIVER CANNOT BE PUSHED PAST THEIR DAILY CAP',
            (select count(*) from public.card_gifts
              where to_player = p_erin and created_at > now() - interval '24 hours')
            = public.gift_receive_cap(),
            (select count(*)::text from public.card_gifts where to_player = p_erin));
        perform pg_temp.ck('...and the refusal says which cap it was',
            (public.send_card(p_erin, 'reef', 40, 1)->>'reason') = 'their_cap');

        perform pg_temp.ck('the budget readout matches what was actually sent',
            (public.gift_budget()->>'sent')::int
            = (select count(*) from public.card_gifts where from_player = p_dave
                and created_at > now() - interval '24 hours'));

        -- The give cap bites even when fresh receivers are available, which is
        -- what stops one modified client servicing everybody.
        perform pg_temp.be(erin);
        perform pg_temp.ck('nobody is left holding more give budget than the cap',
            (public.gift_budget()->>'give_cap')::int = public.gift_give_cap()
        and (public.gift_budget()->>'receive_cap')::int = public.gift_receive_cap());

        -- --- leaving tidies up ----------------------------------------------
        perform public.leave_clan();
        perform pg_temp.be(dave);
        perform public.leave_clan();
        perform pg_temp.ck('the last member out takes the empty clan with them',
            not exists (select 1 from public.clans where id = clan_id));

        -- --- grants ----------------------------------------------------------
        perform pg_temp.ck('anon cannot send a card',
            not has_function_privilege('anon',
                'public.send_card(uuid, text, integer, integer)', 'execute'));
        perform pg_temp.ck('while a signed-in player can',
            has_function_privilege('authenticated',
                'public.send_card(uuid, text, integer, integer)', 'execute'));
        perform pg_temp.ck('anon cannot read anybody''s gift inbox',
            not has_function_privilege('anon', 'public.unseen_gifts()', 'execute'));
    end;

    -- =========================================================================
    --  Diagnostics: the guest door, and the funnel
    -- =========================================================================
    --
    -- The point of these is that the guest door is the first unauthenticated
    -- write in the schema. Its budgets are the only thing standing between it
    -- and the rest of the table, so they are tested rather than trusted.
    declare
        frank uuid := gen_random_uuid();
        p_frank uuid;
        ev jsonb := '[{"kind":"milestone","detail":{"name":"first_spin","since_install_s":42}}]'::jsonb;
        wrote integer;
    begin
        insert into auth.users (id, email) values (frank, 'frank@example.com');
        insert into auth.identities (user_id, provider) values (frank, 'google');
        perform pg_temp.be(frank);
        perform public.claim_player('{}'::jsonb, 'Frank', '🦀', 1, 0, 0, 0, '{0,0,0,0,0}');
        p_frank := public.current_player();

        -- --- the signed-in door still attaches the player --------------------
        perform pg_temp.ck('a signed-in player still files against their island',
            public.report_diagnostics('inst-frank', 'iOS', '18.0', 'iPhone', 107, ev) = 1);
        perform pg_temp.ck('...and the row carries the player',
            exists (select 1 from public.diagnostics
                     where player = p_frank and kind = 'milestone'));

        -- --- milestone is a kind now -----------------------------------------
        perform pg_temp.ck('milestone survives the kind constraint',
            (select count(*) from public.diagnostics where kind = 'milestone') = 1);

        -- --- the guest door ---------------------------------------------------
        perform pg_temp.be(null);
        wrote := public.report_diagnostics_guest('inst-guest', 'Android', '14', 'Pixel', 107, ev);
        perform pg_temp.ck('A GUEST CAN FILE AT ALL -- the hole this closes', wrote = 1);
        perform pg_temp.ck('and the guest row has no player',
            exists (select 1 from public.diagnostics
                     where install_id = 'inst-guest' and player is null));

        -- An install id is the only handle a guest row has. Without one the row
        -- can be neither rate limited nor learned from.
        perform pg_temp.ck('a guest with no install id is refused',
            public.report_diagnostics_guest('', 'Android', '14', 'Pixel', 107, ev) = 0);
        perform pg_temp.ck('...and wrote nothing',
            not exists (select 1 from public.diagnostics where install_id = ''));

        -- --- the per-install ceiling -----------------------------------------
        insert into public.diagnostics (player, install_id, kind, detail)
        select null, 'inst-flood', 'usage', '{}'::jsonb from generate_series(1, 40);
        perform pg_temp.ck('ONE INSTALL CANNOT EXCEED ITS HOURLY BUDGET',
            public.report_diagnostics_guest('inst-flood', 'Android', '14', 'Pixel', 107, ev) = 0);

        -- ...and the cap is per install, so one noisy install does not silence
        -- everybody else. That is the property the global ceiling below is
        -- deliberately allowed to break, and only under a real flood.
        perform pg_temp.ck('while a different install is unaffected',
            public.report_diagnostics_guest('inst-quiet', 'Android', '14', 'Pixel', 107, ev) = 1);

        -- --- kinds and sizes --------------------------------------------------
        perform pg_temp.ck('a made-up kind is skipped, not fatal',
            public.report_diagnostics_guest('inst-kinds', 'iOS', '18', 'iPhone', 107,
                '[{"kind":"nonsense","detail":{}},{"kind":"crash","detail":{}}]'::jsonb) = 1);
        perform pg_temp.ck('an oversized detail is skipped',
            public.report_diagnostics_guest('inst-big', 'iOS', '18', 'iPhone', 107,
                jsonb_build_array(jsonb_build_object(
                    'kind', 'error', 'detail', repeat('x', 5000)))) = 0);
        perform pg_temp.ck('a non-array batch is refused',
            public.report_diagnostics_guest('inst-bad', 'iOS', '18', 'iPhone', 107,
                '{"kind":"crash"}'::jsonb) = 0);

        -- --- grants -----------------------------------------------------------
        perform pg_temp.ck('ANON CAN REACH THE GUEST DOOR AND ONLY THE GUEST DOOR',
            has_function_privilege('anon',
                'public.report_diagnostics_guest(text, text, text, text, integer, jsonb)',
                'execute'));
        perform pg_temp.ck('anon still cannot reach the signed-in one',
            not has_function_privilege('anon',
                'public.report_diagnostics(text, text, text, text, integer, jsonb)',
                'execute'));
        perform pg_temp.ck('and anon cannot prune the table it can write to',
            not has_function_privilege('anon',
                'public.prune_diagnostics(integer, integer)', 'execute'));

        -- --- the read side ----------------------------------------------------
        -- Views are for a human in the SQL editor; nothing in the game reads
        -- them and no role should be able to.
        perform pg_temp.ck('the funnel counts the milestone that was filed',
            (select installs from public.diag_funnel where milestone = 'first_spin') >= 1);
        perform pg_temp.ck('...and knows how long it took',
            (select median_secs from public.diag_funnel where milestone = 'first_spin') = 42);
        perform pg_temp.ck('every install that spoke is in diag_installs',
            (select count(*) from public.diag_installs where install_id = 'inst-guest') = 1);
        perform pg_temp.ck('retention counts a cohort for today',
            (select installs from public.diag_retention where cohort = current_date) > 0);
        perform pg_temp.ck('and marks it not yet mature for D7',
            not (select mature_d7 from public.diag_retention where cohort = current_date));
        perform pg_temp.ck('anon cannot read the funnel',
            not has_table_privilege('anon', 'public.diag_funnel', 'select'));
        perform pg_temp.ck('nor a signed-in player',
            not has_table_privilege('authenticated', 'public.diag_retention', 'select'));

        -- --- the global circuit breaker ---------------------------------------
        -- Last, because it fills the table: 50,000 anon rows in the hour, which
        -- is the ceiling. Everything above had to run before the breaker trips.
        insert into public.diagnostics (player, install_id, kind, detail)
        select null, 'inst-storm-' || g, 'usage', '{}'::jsonb from generate_series(1, 50000) g;
        perform pg_temp.ck('A ROTATING FLOOD TRIPS THE GLOBAL CEILING',
            public.report_diagnostics_guest('inst-brand-new', 'iOS', '18', 'iPhone', 107, ev) = 0);
        -- The failure mode that makes the trade acceptable: guests go quiet,
        -- signed-in reporting is on its own budget and does not notice.
        perform pg_temp.be(frank);
        perform pg_temp.ck('...while a signed-in player still files through it',
            public.report_diagnostics('inst-frank', 'iOS', '18.0', 'iPhone', 107, ev) = 1);
    end;

    raise notice 'ALL FUNCTIONAL TESTS PASSED';
end;
$$;
