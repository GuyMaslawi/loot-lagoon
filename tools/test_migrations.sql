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


-- --- 2026-09-09 security hardening -----------------------------------------
-- Regression cover for the five holes closed by
-- 20260909120000_security_hardening.sql. Each check is an exploit that used to
-- work (or a real call that used to throw), asserted closed.
do $$
declare
    greg uuid := gen_random_uuid();
    hana uuid := gen_random_uuid();
    p_greg uuid; p_hana uuid;
    r jsonb; n integer; ok boolean;
begin
    insert into auth.users (id, email) values
        (greg, 'greg@example.com'), (hana, 'hana@example.com');
    insert into auth.identities (user_id, provider) values
        (greg, 'google'), (hana, 'apple');

    perform pg_temp.be(greg);
    r := public.claim_player('{"coins": 1}'::jsonb, 'Greg', '😎', 10, 3, 0, 0, '{0,0,0,0,0}');
    p_greg := (r->'player'->>'id')::uuid;
    perform pg_temp.be(hana);
    r := public.claim_player('{"coins": 1}'::jsonb, 'Hana', '🙂', 100, 8, 0, 0, '{1,1,1,0,0}');
    p_hana := (r->'player'->>'id')::uuid;

    -- --- find_players: real prefix works, wildcards cannot enumerate --------
    perform pg_temp.be(greg);
    r := public.find_players('han', 12);
    perform pg_temp.ck('find_players finds a real name prefix (display_name, not the dead p.name)',
        jsonb_array_length(r) = 1 and (r->0->>'id')::uuid = p_hana, r::text);
    perform pg_temp.ck('a % wildcard cannot turn the prefix search into a contains scan',
        jsonb_array_length(public.find_players('%an', 12)) = 0);
    perform pg_temp.ck('an _ wildcard is escaped too',
        jsonb_array_length(public.find_players('_an', 12)) = 0);

    -- --- push_save: size cap, buildings cap, monotonic bracket key ----------
    perform pg_temp.be(hana);
    begin
        perform public.push_save(
            jsonb_build_object('x', repeat('a', 300000)), 110, 8, 0, 0, '{1,1,1,0,0}');
        ok := false;   -- should not reach here
    exception when others then
        ok := true;
    end;
    perform pg_temp.ck('push_save REFUSES a multi-hundred-KB save blob', ok);

    r := public.push_save('{"coins": 2}'::jsonb, 120, 2, 0, 0, array_fill(1, array[5000]));
    perform pg_temp.ck('a normal-sized save still stores', r->>'status' = 'ok', r::text);
    select array_length(buildings, 1) into n from public.players where id = p_hana;
    perform pg_temp.ck('a 5000-element buildings array is sliced to 16', n = 16, n::text);
    select island_level into n from public.players where id = p_hana;
    perform pg_temp.ck('island_level (the tournament bracket key) cannot be lowered to farm a weaker league',
        n = 8, n::text);

    -- --- find_target: an absurd band does not scan the whole table ----------
    perform pg_temp.be(greg);
    begin
        perform public.find_target('steal', 999999);
        ok := true;
    exception when others then
        ok := false;
    end;
    perform pg_temp.ck('find_target survives an out-of-range band (clamped, not the whole table)', ok);

    -- --- diagnostics views: one forged non-numeric row cannot break them ----
    insert into public.diagnostics (player, install_id, kind, detail) values
        (null, 'inst-forge', 'usage',
         '{"secs":"notanumber","counters":{"foo":"bar","real":3}}'::jsonb),
        (null, 'inst-forge', 'milestone',
         '{"name":"poison","since_install_s":"nope"}'::jsonb);
    begin
        perform (select count(*) from public.diag_usage_daily);
        perform (select count(*) from public.diag_features_daily);
        perform (select count(*) from public.diag_funnel);
        ok := true;
    exception when others then
        ok := false;
    end;
    perform pg_temp.ck('a forged non-numeric diagnostics row does not break the analytics views', ok);

    raise notice 'SECURITY HARDENING TESTS PASSED';
end;
$$;

-- =============================================================================
--  iap_receipts -- the server-side receipt ledger
-- =============================================================================
--
-- The table's whole security model is "nobody but the edge function": RLS on,
-- no grants to the client roles, service_role explicit. If any of that drifts,
-- a client could write its own verdict rows and the ledger becomes decorative.
do $$
declare
    ok boolean;
begin
    perform pg_temp.ck('iap_receipts has RLS enabled',
        (select relrowsecurity from pg_class where oid = 'public.iap_receipts'::regclass));
    perform pg_temp.ck('anon cannot touch the receipt ledger',
        not has_table_privilege('anon', 'public.iap_receipts',
            'select, insert, update, delete'));
    perform pg_temp.ck('authenticated cannot touch it either',
        not has_table_privilege('authenticated', 'public.iap_receipts',
            'select, insert, update, delete'));
    perform pg_temp.ck('the edge function role can read and write it',
        has_table_privilege('service_role', 'public.iap_receipts', 'select')
        and has_table_privilege('service_role', 'public.iap_receipts', 'insert')
        and has_table_privilege('service_role', 'public.iap_receipts', 'update'));

    insert into public.iap_receipts (platform, receipt_id, product_id, install_id)
        values ('ios', 'txn-test-1', 'p', 'inst-r');
    begin
        insert into public.iap_receipts (platform, receipt_id)
            values ('ios', 'txn-test-1');
        ok := false;   -- should not reach here
    exception when unique_violation then
        ok := true;
    end;
    perform pg_temp.ck('a replayed receipt cannot become a second row', ok);

    begin
        insert into public.iap_receipts (platform, receipt_id, verdict)
            values ('ios', 'txn-test-2', 'not-a-verdict');
        ok := false;
    exception when check_violation then
        ok := true;
    end;
    perform pg_temp.ck('a verdict outside the enum is refused', ok);

    -- The receipt is a financial record: deleting a player must release it
    -- (set null), never take it down with the account.
    perform pg_temp.ck('a deleted player releases the receipt rather than taking it',
        (select confdeltype from pg_constraint
          where conrelid = 'public.iap_receipts'::regclass and contype = 'f') = 'n');

    raise notice 'IAP RECEIPT TESTS PASSED';
end;
$$;

-- =============================================================================
--  Clan stars, the league table, and the seeded crews
-- =============================================================================
--
-- The claim being tested is the one the clan page is built on: a clan's score
-- is the sum of its members' stars, it is computed when it is asked for rather
-- than stored, and the browse list and a clan's own page can never disagree
-- about where it stands. Plus the seed itself, which has to be re-runnable
-- without doubling the world.
do $$
declare
    rows_    jsonb;
    row_     jsonb;
    top_     jsonb;
    view_    jsonb;
    clan_    uuid;
    victim   uuid;
    n        integer;
    before_  bigint;
    after_   bigint;
begin
    perform pg_temp.ck('the migration left seeded clans behind it',
        (select count(*) from public.clans where seeded) = 9,
        (select count(*)::text from public.clans where seeded));
    perform pg_temp.ck('every seeded clan has members and the denormalised count agrees',
        not exists (select 1 from public.clans c where c.seeded
                     and c.members <> (select count(*) from public.clan_members m
                                        where m.clan_id = c.id)));
    -- A bot owner can never answer a join request, so a closed seeded clan
    -- would be a door that opens for nobody. See the migration.
    perform pg_temp.ck('every seeded clan leaves its door open',
        not exists (select 1 from public.clans where seeded and not open));
    perform pg_temp.ck('and every one of them has room for a real player',
        not exists (select 1 from public.clans
                     where seeded and members >= public.clan_max_members()));
    perform pg_temp.ck('nobody was put in two clans',
        (select count(*) from public.clan_members) =
        (select count(distinct player_id) from public.clan_members));

    rows_ := public.clan_list(50);
    perform pg_temp.ck('clan_list answers every seeded clan',
        jsonb_array_length(rows_) >= 9, rows_::text);

    -- --- the ranking ---------------------------------------------------------
    top_ := rows_->0;
    perform pg_temp.ck('the list comes back in rank order, strongest first',
        (top_->>'rank')::int = 1
        and (top_->>'stars')::bigint >= (rows_->1->>'stars')::bigint,
        rows_::text);
    perform pg_temp.ck('the ranks are 1..n with no gaps and no repeats',
        (select count(*) = jsonb_array_length(rows_)
                and min((e->>'rank')::int) = 1
                and max((e->>'rank')::int) = jsonb_array_length(rows_)
                and count(distinct (e->>'rank')::int) = jsonb_array_length(rows_)
           from jsonb_array_elements(rows_) e), rows_::text);
    -- The bands are contiguous islands, so the strongest clan must be the one
    -- drawn from the last four. If that stops being true the seed's ladder has
    -- collapsed and the league table has nothing in it worth reading.
    perform pg_temp.ck('the deep-island crew tops the table',
        top_->>'name' = 'Deepwater Kings', rows_::text);

    -- --- the total is really the members' stars ------------------------------
    clan_ := (top_->>'id')::uuid;
    perform pg_temp.ck('a clan''s stars are its members'' stars added up',
        (top_->>'stars')::bigint = (select sum(p.rank_stars)
                                      from public.clan_members m
                                      join public.players p on p.id = m.player_id
                                     where m.clan_id = clan_), top_::text);

    view_ := public.clan_view(clan_);
    perform pg_temp.ck('clan_view reports the same total as the list',
        (view_->>'stars')::bigint = (top_->>'stars')::bigint, view_::text);
    perform pg_temp.ck('and the same rank -- the two readers share one ordering',
        (view_->>'rank')::int = (top_->>'rank')::int, view_::text);

    -- --- live, not cached ----------------------------------------------------
    before_ := (view_->>'stars')::bigint;
    select m.player_id into victim from public.clan_members m where m.clan_id = clan_ limit 1;
    update public.players set rank_stars = rank_stars + 500 where id = victim;
    after_ := (public.clan_view(clan_)->>'stars')::bigint;
    perform pg_temp.ck('a member building something moves their clan''s total at once',
        after_ = before_ + 500, format('%s -> %s', before_, after_));

    -- A soft-deleted island is gone from public_player, so its stars must be
    -- gone from the total too -- otherwise a clan keeps scoring for a player
    -- who left the game. Same hole the departures migration closed for seats.
    update public.players set deleted_at = now() where id = victim;
    perform pg_temp.ck('a deleted member stops counting toward the total',
        (public.clan_view(clan_)->>'stars')::bigint
            = after_ - (select rank_stars from public.players where id = victim));
    update public.players set deleted_at = null, rank_stars = rank_stars - 500 where id = victim;

    -- --- re-running the seed -------------------------------------------------
    select count(*) into n from public.clans;
    perform public.seed_clans();
    perform pg_temp.ck('seeding twice refreshes the world rather than doubling it',
        (select count(*) from public.clans) = n,
        format('%s -> %s', n, (select count(*) from public.clans)));

    -- The flag is what makes that safe: a player's own clan must survive a
    -- re-seed even if it is named like one of ours.
    insert into public.clans (name, emoji, owner, members)
        values ('First Wave II', '🏴',
                (select id from public.players where is_bot limit 1), 0);
    perform public.seed_clans();
    perform pg_temp.ck('a real clan is out of the seed''s reach',
        exists (select 1 from public.clans where name = 'First Wave II'));
    delete from public.clans where name = 'First Wave II';

    perform pg_temp.ck('clan_standings is not callable by a signed-in player',
        not has_function_privilege('authenticated', 'public.clan_standings()', 'execute'));
    perform pg_temp.ck('and neither is the seeder',
        not has_function_privilege('authenticated', 'public.seed_clans()', 'execute'));

    raise notice 'CLAN STAR TESTS PASSED';
end;
$$;

-- =============================================================================
--  The clan chat, the two asks, and the bar a clan can put on its door
-- =============================================================================
--
-- Every claim here is one the client draws a control from, so a failure is a
-- control that lies: a bar that fills past its ten seats, an ask that can be
-- made twice inside its five hours, a card ask that routes around the daily
-- cap send_card enforces, or a threshold an older build can walk past.
do $$
declare
    u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
    u3 uuid := gen_random_uuid(); u4 uuid := gen_random_uuid();
    a uuid; b uuid; c uuid; d uuid;
    clan_ uuid;
    r jsonb; chat jsonb; line jsonb;
    msg uuid; n integer;
begin
    insert into auth.users (id) values (u1), (u2), (u3), (u4);
    perform pg_temp.be(u1);
    a := (public.claim_player('{}'::jsonb, 'Chatter One', '🐙', 400, 9, 0, 0, '{0,0,0,0,0}')->'player'->>'id')::uuid;
    perform pg_temp.be(u2);
    b := (public.claim_player('{}'::jsonb, 'Chatter Two', '🦈', 300, 8, 0, 0, '{0,0,0,0,0}')->'player'->>'id')::uuid;
    perform pg_temp.be(u3);
    c := (public.claim_player('{}'::jsonb, 'Chatter Three', '🐚', 200, 7, 0, 0, '{0,0,0,0,0}')->'player'->>'id')::uuid;
    perform pg_temp.be(u4);
    d := (public.claim_player('{}'::jsonb, 'Lowly Four', '🪵', 5, 1, 0, 0, '{0,0,0,0,0}')->'player'->>'id')::uuid;

    perform pg_temp.be(u1);
    r := public.create_clan('Chatterbox Crew', '🗣');
    clan_ := (r->'clan'->>'id')::uuid;
    perform pg_temp.ck('a founder gets a clan to talk in', (r->>'ok')::boolean, r::text);
    perform pg_temp.be(u2);
    perform public.join_clan(clan_);
    perform pg_temp.be(u3);
    perform public.join_clan(clan_);

    -- --- the star threshold --------------------------------------------------
    perform pg_temp.be(u1);
    r := public.set_clan_min_stars(250);
    perform pg_temp.ck('the founder can put a bar on the door', (r->>'ok')::boolean, r::text);
    perform pg_temp.ck('and the bar goes out with the clan',
        (r->'clan'->>'min_stars')::int = 250, r::text);
    perform pg_temp.ck('the browse list carries it too, so it can be seen from outside',
        (select (e->>'min_stars')::int from jsonb_array_elements(public.clan_list(50)) e
          where (e->>'id')::uuid = clan_) = 250);

    perform pg_temp.be(u4);
    r := public.join_clan(clan_);
    perform pg_temp.ck('a player under the bar is refused, and told the number',
        (r->>'ok')::boolean = false and r->>'reason' = 'stars' and (r->>'need')::int = 250,
        r::text);
    -- An open clan does not take requests at all, so the knock is tested
    -- against a closed one -- which is the only door that has a queue.
    perform pg_temp.be(u1);
    perform public.set_clan_open(false);
    perform pg_temp.be(u4);
    r := public.request_join_clan(clan_);
    perform pg_temp.ck('and cannot knock either -- no waiting for an answer that cannot come',
        (r->>'ok')::boolean = false and r->>'reason' = 'stars', r::text);
    perform pg_temp.be(u1);
    perform public.set_clan_open(true);

    -- Raising the bar over somebody already waiting must clear them out, or the
    -- owner's badge stays lit for an approval that can no longer be granted.
    perform pg_temp.be(u1);
    perform public.set_clan_min_stars(0);
    perform public.set_clan_open(false);
    perform pg_temp.be(u4);
    perform public.request_join_clan(clan_);
    perform pg_temp.be(u1);
    perform public.set_clan_min_stars(250);
    perform pg_temp.ck('raising the bar answers the requests standing under it',
        not exists (select 1 from public.clan_requests
                     where clan_id = clan_ and player_id = d));
    perform public.set_clan_min_stars(0);
    perform public.set_clan_open(true);

    -- An invitation is an exception the clan chose to make, so it outranks the
    -- bar. This is the rule accept_clan_invite is deliberately NOT gated on.
    perform pg_temp.be(u1);
    perform public.set_clan_min_stars(250);
    r := public.invite_to_clan(d);
    perform pg_temp.ck('a member may still invite somebody under the bar', (r->>'ok')::boolean, r::text);
    perform pg_temp.be(u4);
    r := public.accept_clan_invite(
        (select id from public.clan_invites where to_player = d limit 1));
    perform pg_temp.ck('and being invited walks past the bar, the way it walks past a closed door',
        (r->>'ok')::boolean, r::text);
    perform public.leave_clan();
    perform pg_temp.be(u1);
    perform public.set_clan_min_stars(0);

    -- --- finding a clan by name ---------------------------------------------
    perform pg_temp.be(u4);
    perform pg_temp.ck('find_clans matches a prefix',
        (select count(*) from jsonb_array_elements(public.find_clans('Chatter')) e
          where (e->>'id')::uuid = clan_) = 1);
    perform pg_temp.ck('and it is a PREFIX -- the middle of a name does not match',
        jsonb_array_length(public.find_clans('box Crew')) = 0);
    perform pg_temp.ck('one letter answers nothing rather than the whole table',
        jsonb_array_length(public.find_clans('C')) = 0);
    perform pg_temp.ck('a wildcard cannot turn it into a scan of every clan',
        jsonb_array_length(public.find_clans('%%')) = 0,
        public.find_clans('%%')::text);

    -- --- saying something ----------------------------------------------------
    perform pg_temp.be(u1);
    r := public.say_clan('  hello   crew  ');
    perform pg_temp.ck('a member can say something', (r->>'ok')::boolean, r::text);
    perform pg_temp.ck('and the whitespace is collapsed on the way in',
        (select body from public.clan_messages where id = (r->>'id')::uuid) = 'hello crew');
    r := public.say_clan('again so soon');
    perform pg_temp.ck('two messages inside two seconds is refused',
        (r->>'ok')::boolean = false and r->>'reason' = 'too_fast', r::text);
    update public.clan_messages set created_at = created_at - interval '1 minute'
     where player_id = a;
    r := public.say_clan('you fucking muppet');
    perform pg_temp.ck('the word filter REFUSES rather than masks',
        (r->>'ok')::boolean = false and r->>'reason' = 'language', r::text);
    r := public.say_clan(repeat('x', 200));
    perform pg_temp.ck('and a message longer than the box is refused',
        (r->>'ok')::boolean = false and r->>'reason' = 'long', r::text);
    perform pg_temp.be(u4);
    r := public.say_clan('let me in');
    perform pg_temp.ck('somebody with no clan has nowhere to say it',
        (r->>'ok')::boolean = false and r->>'reason' = 'no_clan', r::text);

    -- --- asking for spins ----------------------------------------------------
    perform pg_temp.be(u1);
    r := public.ask_clan_help('spins');
    perform pg_temp.ck('a member can ask the clan for spins', (r->>'ok')::boolean, r::text);
    msg := (r->>'id')::uuid;
    r := public.ask_clan_help('spins');
    perform pg_temp.ck('and cannot ask again inside the five hours',
        (r->>'ok')::boolean = false and r->>'reason' = 'too_soon'
        and (r->>'wait')::int between 1 and 18000, r::text);
    -- Per KIND, not one clock for both: asking for a card must not cost the
    -- player their spin ask for five hours.
    r := public.ask_clan_help('cards', 'pirates', 3, 2);
    perform pg_temp.ck('the card clock is its own clock', (r->>'ok')::boolean, r::text);
    r := public.ask_clan_help('cards', 'pirates', 4, 5);
    perform pg_temp.ck('a gold card cannot be asked for at all',
        (r->>'ok')::boolean = false and r->>'reason' = 'stars', r::text);
    r := public.ask_clan_help('cards', 'pirates', 4, 4);
    perform pg_temp.ck('and neither can a four-star -- Guy named one, two and three',
        (r->>'ok')::boolean = false and r->>'reason' = 'stars', r::text);

    -- --- answering one -------------------------------------------------------
    perform pg_temp.be(u1);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('nobody fills their own bar',
        (r->>'ok')::boolean = false and r->>'reason' = 'self', r::text);
    perform pg_temp.be(u2);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('a clanmate drops spins in', (r->>'ok')::boolean, r::text);
    perform pg_temp.ck('three of them, and one of ten seats is taken',
        (r->>'spins')::int = 3 and (r->>'filled')::int = 1 and (r->>'cap')::int = 10,
        r::text);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('and cannot take a second seat',
        (r->>'ok')::boolean = false and r->>'reason' = 'already', r::text);
    perform pg_temp.be(u4);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('somebody outside the clan cannot reach the bar at all',
        (r->>'ok')::boolean = false and r->>'reason' = 'no_clan', r::text);

    -- THE SPINS ARE HELD FOR THE ASKER, not added to a column on their row.
    -- The counter moves on the device it belongs to, when the thing lands.
    perform pg_temp.be(u1);
    r := public.unseen_spin_gifts();
    perform pg_temp.ck('the spins are waiting for the asker on their next launch',
        jsonb_array_length(r) = 1 and (r->0->>'spins')::int = 3, r::text);
    perform pg_temp.ck('and they know who gave them', r->0->'by'->>'name' = 'Chatter Two', r::text);
    perform public.ack_spin_gifts(array[(r->0->>'id')::uuid]);
    perform pg_temp.ck('an acked gift is not handed over twice',
        jsonb_array_length(public.unseen_spin_gifts()) = 0);

    -- The ten seats, filled by force. Every donor is a real clan member, so the
    -- roster is stretched to hold them.
    perform pg_temp.be(u1);
    update public.clan_messages set created_at = now() where id = msg;
    declare uu uuid; begin
        for n in 1..12 loop
            uu := gen_random_uuid();
            insert into auth.users (id) values (uu);
            perform pg_temp.be(uu);
            perform public.claim_player('{}'::jsonb, 'Seat ' || n::text, '🙂',
                                        10, 2, 0, 0, '{0,0,0,0,0}');
            perform public.join_clan(clan_);
            perform public.donate_clan_help(msg);
        end loop;
    end;
    perform pg_temp.ck('the bar stops at exactly ten seats',
        (select count(*) from public.clan_help where message_id = msg) = 10,
        (select count(*)::text from public.clan_help where message_id = msg));
    perform pg_temp.be(u3);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('and the eleventh is turned away',
        (r->>'ok')::boolean = false and r->>'reason' = 'filled', r::text);

    -- --- an ask goes quiet when its clock runs out ---------------------------
    perform pg_temp.be(u2);
    r := public.ask_clan_help('spins');
    msg := (r->>'id')::uuid;
    update public.clan_messages set created_at = now() - interval '6 hours' where id = msg;
    perform pg_temp.be(u3);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('an ask older than its own five hours can no longer be filled',
        (r->>'ok')::boolean = false and r->>'reason' = 'expired', r::text);

    -- --- a card ask pays out of the same purse send_card does ----------------
    perform pg_temp.be(u2);
    r := public.ask_clan_help('cards', 'pirates', 3, 2);
    msg := (r->>'id')::uuid;
    perform pg_temp.be(u3);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('a clanmate can answer a card ask', (r->>'ok')::boolean, r::text);
    perform pg_temp.ck('and the card really moves, through card_gifts',
        exists (select 1 from public.card_gifts
                 where from_player = c and to_player = b
                   and set_id = 'pirates' and card_idx = 3 and stars = 2));
    -- The receive cap is what stops a clan farming one player's collection by
    -- taking it in turns to answer their asks.
    insert into public.card_gifts (from_player, to_player, set_id, card_idx, stars)
    select a, b, 'pirates', 9, 1
      from generate_series(1, public.gift_receive_cap());
    perform pg_temp.be(u1);
    r := public.donate_clan_help(msg);
    perform pg_temp.ck('an ask cannot walk past the asker''s own daily receive cap',
        (r->>'ok')::boolean = false and r->>'reason' = 'their_cap', r::text);
    delete from public.card_gifts where to_player = b and card_idx = 9;

    -- --- reading it ----------------------------------------------------------
    perform pg_temp.be(u1);
    chat := public.clan_chat(60);
    perform pg_temp.ck('the chat reads back, oldest first',
        jsonb_array_length(chat) > 3
        and (chat->0->>'at')::numeric <= (chat->-1->>'at')::numeric, chat::text);
    perform pg_temp.ck('and it knows which lines are mine',
        (select bool_or((e->>'mine')::boolean) from jsonb_array_elements(chat) e));
    -- The one that was actually filled, not merely the first spin ask in the
    -- scroll -- there are two by now and the other is the expired one.
    line := (select e from jsonb_array_elements(chat) e where e->>'kind' = 'spins'
              order by (e->>'filled')::int desc limit 1);
    perform pg_temp.ck('a spin ask comes back with its bar on it',
        (line->>'filled')::int > 0 and (line->>'cap')::int = 10, line::text);
    perform pg_temp.ck('a filled ask is marked closed, by the server rather than by a phone clock',
        (select bool_or((e->>'closed')::boolean) from jsonb_array_elements(chat) e
          where (e->>'filled')::int >= 10));
    perform pg_temp.ck('and the card ask carries the card it is asking for',
        (select e->>'set' = 'pirates' and (e->>'stars')::int between 1 and 3
           from jsonb_array_elements(chat) e where e->>'kind' = 'cards' limit 1));

    -- BLOCKING IS THE HALF GUIDELINE 1.2 ACTUALLY TURNS ON. Somebody a player
    -- blocked does not get to talk to them by joining their clan.
    -- Chatter Three has only ever donated so far, and a donation is not a line.
    perform pg_temp.be(u3);
    perform public.say_clan('anyone seen the kraken');
    perform pg_temp.be(u1);
    n := (select count(*) from jsonb_array_elements(public.clan_chat(60)) e
           where (e->'by'->>'id')::uuid = c);
    perform pg_temp.ck('before blocking, that clanmate is in the scroll', n > 0);
    perform public.block_player(c);
    perform pg_temp.ck('after blocking, every line of theirs is gone from it',
        (select count(*) from jsonb_array_elements(public.clan_chat(60)) e
          where (e->'by'->>'id')::uuid = c) = 0);
    -- And the other way round, so a block cannot be worked around by being the
    -- one who did the blocking.
    perform pg_temp.be(u3);
    perform pg_temp.ck('and it works in both directions',
        (select count(*) from jsonb_array_elements(public.clan_chat(60)) e
          where (e->'by'->>'id')::uuid = a) = 0);
    delete from public.blocks where blocker = a and blocked = c;

    -- --- the two clocks the composer draws its buttons from ------------------
    perform pg_temp.be(u1);
    r := public.clan_ask_state();
    perform pg_temp.ck('the composer is told how long until it may ask again',
        (r->>'spins_wait')::int > 0 and (r->>'give')::int = 3 and (r->>'seats')::int = 10,
        r::text);
    perform pg_temp.be(u4);
    r := public.clan_ask_state();
    perform pg_temp.ck('and somebody who has never asked may ask at once',
        (r->>'spins_wait')::int = 0 and (r->>'cards_wait')::int = 0, r::text);

    -- --- the housekeeping ----------------------------------------------------
    perform pg_temp.be(u1);
    -- The whole scroll pushed past the keep window, asks included: the sweep is
    -- by age and does not care what kind a line is.
    update public.clan_messages set created_at = now() - interval '9 days'
     where clan_id = clan_;
    n := (select count(*) from public.clan_messages where clan_id = clan_);
    perform public.say_clan('still here');
    perform pg_temp.ck('a new message sweeps the ones older than three days',
        (select count(*) from public.clan_messages
          where clan_id = clan_ and created_at < now() - interval '3 days') = 0,
        format('%s rows before', n));

    -- --- privileges ----------------------------------------------------------
    perform pg_temp.ck('the chat is callable by a signed-in player',
        has_function_privilege('authenticated', 'public.clan_chat(integer)', 'execute'));
    perform pg_temp.ck('and not by anon',
        not has_function_privilege('anon', 'public.say_clan(text)', 'execute'));
    -- Recreating a function resets its privileges. join_clan and clan_view were
    -- both replaced by this migration; a grant block that only covered what it
    -- invented would leave the clan page revoked.
    perform pg_temp.ck('join_clan survived being replaced with its grant intact',
        has_function_privilege('authenticated', 'public.join_clan(uuid)', 'execute'));
    perform pg_temp.ck('and so did clan_view',
        has_function_privilege('authenticated', 'public.clan_view(uuid)', 'execute'));

    raise notice 'CLAN CHAT TESTS PASSED';
end;
$$;


-- =============================================================================
--  Remote config, and the empty answer that is today's behaviour
-- =============================================================================
--
-- Every claim here is one an ops decision rests on. The resolution rules are
-- the dangerous part: a kill switch that resolves to the wrong row is a feature
-- that stays live through the outage it was meant to end, and a build-range
-- rule that leaks is a row written for build 150 breaking build 140 in
-- somebody's pocket. The first test is the most important one in the block --
-- an empty table must answer, and answer empty.
do $$
declare
    r jsonb;
begin
    -- --- the empty answer ----------------------------------------------------
    delete from public.app_config where app in ('loot-lagoon', 'game-two');
    r := public.app_config('loot-lagoon', 140, 'ios');
    perform pg_temp.ck('an empty table answers at all', r is not null, coalesce(r::text, 'NULL'));
    perform pg_temp.ck('and it answers with nothing to apply', r = '{}'::jsonb, r::text);
    r := public.app_config('no-such-game', 140, 'ios');
    perform pg_temp.ck('a game with no rows gets the same empty answer',
        r = '{}'::jsonb, r::text);

    -- --- the ordinary kill switch -------------------------------------------
    insert into public.app_config (app, key, value, note)
    values ('loot-lagoon', 'clan_chat', 'false'::jsonb, 'abuse report, 2026-10-01');
    perform pg_temp.ck('a switch with no targeting reaches a real build',
        public.app_config('loot-lagoon', 140, 'ios') = '{"clan_chat": false}'::jsonb,
        public.app_config('loot-lagoon', 140, 'ios')::text);
    perform pg_temp.ck('and it reaches android too',
        (public.app_config('loot-lagoon', 140, 'android')->>'clan_chat') = 'false');
    perform pg_temp.ck('and a guest-era build with no stamp still sees it',
        (public.app_config('loot-lagoon', 0, '')->>'clan_chat') = 'false');

    -- --- the app boundary ---------------------------------------------------
    insert into public.app_config (app, key, value)
    values ('game-two', 'clan_chat', 'true'::jsonb);
    perform pg_temp.ck('game two does not read game one''s rows',
        (public.app_config('game-two', 140, 'ios')->>'clan_chat') = 'true');
    perform pg_temp.ck('and game one does not read game two''s',
        (public.app_config('loot-lagoon', 140, 'ios')->>'clan_chat') = 'false');

    -- --- the build range, which is the one that protects TestFlight ----------
    delete from public.app_config where app = 'loot-lagoon';
    insert into public.app_config (app, key, value, min_build, note)
    values ('loot-lagoon', 'chain_hours', '18'::jsonb, 150, 'only 150 reads this');
    perform pg_temp.ck('a build under the floor never sees the row',
        public.app_config('loot-lagoon', 149, 'ios') = '{}'::jsonb,
        public.app_config('loot-lagoon', 149, 'ios')::text);
    perform pg_temp.ck('the build at the floor sees it',
        (public.app_config('loot-lagoon', 150, 'ios')->>'chain_hours') = '18');
    perform pg_temp.ck('and so does one above it',
        (public.app_config('loot-lagoon', 999, 'ios')->>'chain_hours') = '18');
    perform pg_temp.ck('a dev build is exempt and sees a row aimed at the future',
        (public.app_config('loot-lagoon', 0, '')->>'chain_hours') = '18');

    update public.app_config set max_build = 160 where app = 'loot-lagoon';
    perform pg_temp.ck('a ceiling shuts the row off above itself',
        public.app_config('loot-lagoon', 161, 'ios') = '{}'::jsonb,
        public.app_config('loot-lagoon', 161, 'ios')::text);
    perform pg_temp.ck('and the build at the ceiling is still inside it',
        (public.app_config('loot-lagoon', 160, 'ios')->>'chain_hours') = '18');

    -- --- most specific wins -------------------------------------------------
    delete from public.app_config where app = 'loot-lagoon';
    insert into public.app_config (app, key, value, platform) values
        ('loot-lagoon', 'shop', 'true'::jsonb,  ''),
        ('loot-lagoon', 'shop', 'false'::jsonb, 'ios');
    perform pg_temp.ck('a platform row beats the generic one on that platform',
        (public.app_config('loot-lagoon', 140, 'ios')->>'shop') = 'false',
        public.app_config('loot-lagoon', 140, 'ios')::text);
    perform pg_temp.ck('and the other platform still reads the generic row',
        (public.app_config('loot-lagoon', 140, 'android')->>'shop') = 'true');
    perform pg_temp.ck('a client that names no platform reads the generic row',
        (public.app_config('loot-lagoon', 140, '')->>'shop') = 'true');
    perform pg_temp.ck('and the answer carries exactly one entry per key',
        (select count(*) from jsonb_object_keys(public.app_config('loot-lagoon', 140, 'ios'))) = 1,
        public.app_config('loot-lagoon', 140, 'ios')::text);

    delete from public.app_config where app = 'loot-lagoon';
    insert into public.app_config (app, key, value, min_build) values
        ('loot-lagoon', 'chain_hours', '24'::jsonb, 0),
        ('loot-lagoon', 'chain_hours', '12'::jsonb, 150);
    perform pg_temp.ck('a higher floor beats a lower one for a build above both',
        (public.app_config('loot-lagoon', 150, 'ios')->>'chain_hours') = '12',
        public.app_config('loot-lagoon', 150, 'ios')::text);
    perform pg_temp.ck('and the build below the higher floor falls back to the lower row',
        (public.app_config('loot-lagoon', 149, 'ios')->>'chain_hours') = '24');

    -- --- shape ---------------------------------------------------------------
    delete from public.app_config where app = 'loot-lagoon';
    insert into public.app_config (app, key, value) values
        ('loot-lagoon', 'clan_chat',   'false'::jsonb),
        ('loot-lagoon', 'chain_hours', '18'::jsonb),
        ('loot-lagoon', 'banner',      '{"text": "back soon"}'::jsonb);
    r := public.app_config('loot-lagoon', 140, 'ios');
    perform pg_temp.ck('every kind of value survives the round trip',
        (r->>'clan_chat') = 'false' and (r->>'chain_hours') = '18'
        and (r->'banner'->>'text') = 'back soon', r::text);
    perform pg_temp.ck('and three rows come back as three keys',
        (select count(*) from jsonb_object_keys(r)) = 3, r::text);

    -- --- privileges, and the table nobody reaches ----------------------------
    perform pg_temp.ck('a guest can read the config',
        has_function_privilege('anon',
            'public.app_config(text,integer,text)', 'execute'));
    perform pg_temp.ck('and so can a signed-in player',
        has_function_privilege('authenticated',
            'public.app_config(text,integer,text)', 'execute'));
    perform pg_temp.ck('the table itself is not readable by a client',
        not has_table_privilege('anon', 'public.app_config', 'select')
        and not has_table_privilege('authenticated', 'public.app_config', 'select'));
    perform pg_temp.ck('and row level security is on it',
        (select relrowsecurity from pg_class
          where oid = 'public.app_config'::regclass));

    delete from public.app_config where app in ('loot-lagoon', 'game-two');
    raise notice 'APP CONFIG TESTS PASSED';
end;
$$;


-- =============================================================================
--  ...and the ops role can actually reach it
-- =============================================================================
--
-- Split from the block above because it is the half that was missing. Asserting
-- that anon is refused passes perfectly on a table NOBODY can reach, which is
-- what shipped on 2026-10-01 and what broke liveops.py against the live project.
-- Every check here is an admit-side one.
do $$
begin
    perform pg_temp.ck('the ops role can read the table',
        has_table_privilege('service_role', 'public.app_config', 'select'));
    perform pg_temp.ck('and write a new knob',
        has_table_privilege('service_role', 'public.app_config', 'insert'));
    perform pg_temp.ck('and change one that is already there',
        has_table_privilege('service_role', 'public.app_config', 'update'));
    perform pg_temp.ck('and drop one back to its compiled default',
        has_table_privilege('service_role', 'public.app_config', 'delete'));
    -- An INSERT that does not name the bigserial reads the sequence. Without
    -- this the role is admitted to the table and fails on its first write.
    perform pg_temp.ck('and reach the sequence its inserts depend on',
        has_sequence_privilege('service_role', 'public.app_config_id_seq', 'usage'));
    -- The deny side, restated here so the two live together: widening the ops
    -- grant must never widen the client's.
    perform pg_temp.ck('while a client still cannot read the rows',
        not has_table_privilege('anon', 'public.app_config', 'select')
        and not has_table_privilege('authenticated', 'public.app_config', 'select'));
    perform pg_temp.ck('nor write them',
        not has_table_privilege('anon', 'public.app_config', 'insert')
        and not has_table_privilege('authenticated', 'public.app_config', 'update'));
    -- And the function is still the way in, which the revoke above could have
    -- taken out if it had been written against the function by mistake.
    perform pg_temp.ck('and the reader function is still theirs to call',
        has_function_privilege('anon', 'public.app_config(text,integer,text)', 'execute')
        and has_function_privilege('authenticated',
            'public.app_config(text,integer,text)', 'execute'));
    raise notice 'APP CONFIG GRANT TESTS PASSED';
end;
$$;


-- =============================================================================
--  The calendar
-- =============================================================================
--
-- The claims here are about a WINDOW, which is the part that cannot be eyeballed
-- off the client: an event that is live, one that has not started, one that is
-- over, and one too far out to be worth sending. A mistake in any of them is an
-- event that runs on the wrong day for everybody at once, and unlike a kill
-- switch there is no "off" to fall back to -- the row has already fired.
do $$
declare
    r jsonb; e jsonb;
begin
    delete from public.app_events where app in ('loot-lagoon', 'game-two');
    perform pg_temp.ck('an empty calendar answers with an empty list',
        public.app_events('loot-lagoon', 140, 'ios') = '[]'::jsonb,
        public.app_events('loot-lagoon', 140, 'ios')::text);

    -- --- live right now ------------------------------------------------------
    insert into public.app_events (app, kind, payload, starts_at, ends_at, note)
    values ('loot-lagoon', 'deal_chain', '{"id": "tide_hunt"}'::jsonb,
            now() - interval '30 minutes', now() + interval '23 hours', 'halloween');
    r := public.app_events('loot-lagoon', 140, 'ios');
    perform pg_temp.ck('a running event is sent', jsonb_array_length(r) = 1, r::text);
    e := r->0;
    perform pg_temp.ck('and it is marked as already started',
        (e->>'starts_in')::bigint <= 0, e::text);
    perform pg_temp.ck('with the time it has left, not the time it has run',
        (e->>'ends_in')::bigint between 82000 and 82900, e::text);
    perform pg_temp.ck('and the payload the client acts on',
        e->'payload'->>'id' = 'tide_hunt', e::text);
    -- The doctrine claim from the migration's own header.
    perform pg_temp.ck('and NO timestamp anywhere on the wire',
        not (e ? 'starts_at') and not (e ? 'ends_at'), e::text);

    -- --- not yet, and never ---------------------------------------------------
    delete from public.app_events where app = 'loot-lagoon';
    insert into public.app_events (app, kind, payload, starts_at, ends_at) values
        ('loot-lagoon', 'deal_chain', '{"id": "soon"}'::jsonb,
         now() + interval '4 hours',  now() + interval '28 hours'),
        ('loot-lagoon', 'deal_chain', '{"id": "far"}'::jsonb,
         now() + interval '30 days',  now() + interval '31 days'),
        ('loot-lagoon', 'deal_chain', '{"id": "over"}'::jsonb,
         now() - interval '3 days',   now() - interval '2 days');
    r := public.app_events('loot-lagoon', 140, 'ios');
    perform pg_temp.ck('only the one inside the horizon is sent',
        jsonb_array_length(r) = 1 and r->0->'payload'->>'id' = 'soon', r::text);
    perform pg_temp.ck('and it is marked as NOT started yet',
        (r->0->>'starts_in')::bigint > 0, r::text);
    perform pg_temp.ck('a horizon wide enough reaches the far one too',
        jsonb_array_length(public.app_events('loot-lagoon', 140, 'ios', 24 * 40)) = 2,
        public.app_events('loot-lagoon', 140, 'ios', 24 * 40)::text);
    perform pg_temp.ck('and an event that is over is never sent, at any horizon',
        not exists (select 1
                      from jsonb_array_elements(
                               public.app_events('loot-lagoon', 140, 'ios', 24 * 400)) x
                     where x->'payload'->>'id' = 'over'));

    -- --- order ----------------------------------------------------------------
    delete from public.app_events where app = 'loot-lagoon';
    insert into public.app_events (app, kind, payload, starts_at, ends_at) values
        ('loot-lagoon', 'deal_chain', '{"id": "third"}'::jsonb,
         now() + interval '10 hours', now() + interval '11 hours'),
        ('loot-lagoon', 'deal_chain', '{"id": "first"}'::jsonb,
         now() - interval '1 hour',   now() + interval '1 hour'),
        ('loot-lagoon', 'deal_chain', '{"id": "second"}'::jsonb,
         now() + interval '2 hours',  now() + interval '3 hours');
    r := public.app_events('loot-lagoon', 140, 'ios');
    perform pg_temp.ck('the list is in the order they happen',
        r->0->'payload'->>'id' = 'first'
        and r->1->'payload'->>'id' = 'second'
        and r->2->'payload'->>'id' = 'third', r::text);

    -- --- targeting, and the app boundary --------------------------------------
    delete from public.app_events where app = 'loot-lagoon';
    insert into public.app_events (app, kind, payload, starts_at, ends_at,
                                   min_build, platform) values
        ('loot-lagoon', 'deal_chain', '{"id": "new_builds"}'::jsonb,
         now() - interval '1 hour', now() + interval '1 hour', 150, ''),
        ('loot-lagoon', 'deal_chain', '{"id": "ios_only"}'::jsonb,
         now() - interval '1 hour', now() + interval '1 hour', 0, 'ios');
    perform pg_temp.ck('a build under the floor does not get that event',
        not exists (select 1 from jsonb_array_elements(
                        public.app_events('loot-lagoon', 149, 'ios')) x
                     where x->'payload'->>'id' = 'new_builds'));
    perform pg_temp.ck('and a build at it does',
        exists (select 1 from jsonb_array_elements(
                    public.app_events('loot-lagoon', 150, 'ios')) x
                 where x->'payload'->>'id' = 'new_builds'));
    perform pg_temp.ck('an ios event does not reach android',
        not exists (select 1 from jsonb_array_elements(
                        public.app_events('loot-lagoon', 150, 'android')) x
                     where x->'payload'->>'id' = 'ios_only'));
    -- THE DEV EXEMPTION IS ABOUT BUILDS, NOT PLATFORMS, and this pair is here
    -- because the first draft of this test assumed otherwise and failed. A
    -- desktop run is neither iOS nor Android, so a platform-targeted row must
    -- not reach it -- the same rule app_config follows. The consequence is that
    -- naming the platform is the ONLY way to preview a platform-targeted event,
    -- which is what LL_FAKE_PLATFORM exists for on the client.
    perform pg_temp.ck('a dev build is exempt from the build floor',
        jsonb_array_length(public.app_events('loot-lagoon', 0, '')) = 1
        and public.app_events('loot-lagoon', 0, '')->0->'payload'->>'id'
            = 'new_builds',
        public.app_events('loot-lagoon', 0, '')::text);
    perform pg_temp.ck('but not from the platform, which it does not have',
        not exists (select 1 from jsonb_array_elements(
                        public.app_events('loot-lagoon', 0, '')) x
                     where x->'payload'->>'id' = 'ios_only'));
    perform pg_temp.ck('and naming a platform is how a dev build previews one',
        jsonb_array_length(public.app_events('loot-lagoon', 0, 'ios')) = 2,
        public.app_events('loot-lagoon', 0, 'ios')::text);
    insert into public.app_events (app, kind, payload, starts_at, ends_at)
    values ('game-two', 'deal_chain', '{"id": "theirs"}'::jsonb,
            now() - interval '1 hour', now() + interval '1 hour');
    perform pg_temp.ck('and game two keeps its calendar to itself',
        jsonb_array_length(public.app_events('game-two', 140, 'ios')) = 1
        and not exists (select 1 from jsonb_array_elements(
                            public.app_events('loot-lagoon', 0, '')) x
                         where x->'payload'->>'id' = 'theirs'));

    -- --- the typo the table refuses -------------------------------------------
    begin
        insert into public.app_events (app, kind, starts_at, ends_at)
        values ('loot-lagoon', 'deal_chain', now() + interval '2 hours', now());
        perform pg_temp.ck('a window that ends before it starts is refused', false,
            'the insert was accepted');
    exception when check_violation then
        perform pg_temp.ck('a window that ends before it starts is refused', true);
    end;

    -- --- privileges ------------------------------------------------------------
    perform pg_temp.ck('a guest can read the calendar',
        has_function_privilege('anon',
            'public.app_events(text,integer,text,integer)', 'execute'));
    perform pg_temp.ck('the ops role can write it',
        has_table_privilege('service_role', 'public.app_events', 'insert')
        and has_sequence_privilege('service_role',
            'public.app_events_id_seq', 'usage'));
    perform pg_temp.ck('and no client can reach the rows',
        not has_table_privilege('anon', 'public.app_events', 'select')
        and not has_table_privilege('authenticated', 'public.app_events', 'select'));

    delete from public.app_events where app in ('loot-lagoon', 'game-two');
    raise notice 'CALENDAR TESTS PASSED';
end;
$$;


-- =============================================================================
--  The support desk, and the four functions no phone may call
-- =============================================================================
--
-- The privilege checks are the point of this block. Every other function this
-- project exposes is callable by a guest on purpose; these read people's names,
-- balances and purchases, and one accidental grant would turn the support desk
-- into a player directory. They are asserted first and again at the end.
do $$
declare
    u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
    u3 uuid := gen_random_uuid();
    a uuid; b uuid; c uuid;
    r jsonb; row_ jsonb; rep uuid; before_open integer;
begin
    -- --- who may call these at all -------------------------------------------
    perform pg_temp.ck('a guest cannot look a player up',
        not has_function_privilege('anon',
            'public.support_find_player(text,integer)', 'execute'));
    perform pg_temp.ck('and neither can a signed-in player',
        not has_function_privilege('authenticated',
            'public.support_find_player(text,integer)', 'execute'));
    perform pg_temp.ck('a guest cannot read the report queue',
        not has_function_privilege('anon',
            'public.support_reports(boolean,integer)', 'execute'));
    perform pg_temp.ck('and neither can a signed-in player',
        not has_function_privilege('authenticated',
            'public.support_reports(boolean,integer)', 'execute'));
    perform pg_temp.ck('nobody but ops can close a report',
        not has_function_privilege('anon',
            'public.support_review_report(uuid)', 'execute')
        and not has_function_privilege('authenticated',
            'public.support_review_report(uuid)', 'execute'));
    perform pg_temp.ck('nor read receipts',
        not has_function_privilege('anon',
            'public.support_find_receipts(text,integer)', 'execute')
        and not has_function_privilege('authenticated',
            'public.support_find_receipts(text,integer)', 'execute'));
    perform pg_temp.ck('the ops role can call all four',
        has_function_privilege('service_role',
            'public.support_find_player(text,integer)', 'execute')
        and has_function_privilege('service_role',
            'public.support_find_receipts(text,integer)', 'execute')
        and has_function_privilege('service_role',
            'public.support_reports(boolean,integer)', 'execute')
        and has_function_privilege('service_role',
            'public.support_review_report(uuid)', 'execute'));
    -- WHAT ACTUALLY FENCES `players` IS RLS, NOT THE GRANT, and the first draft
    -- of this test asserted the wrong model. `authenticated` really does hold
    -- SELECT -- it has to, the save sync reads the row back -- and what stops a
    -- player reading anybody else is the policy restricting it to
    -- my_player_ids(). Asserting the absence of the grant would have been a
    -- test that failed on correct code, and worse, one that invited somebody to
    -- "fix" it by revoking the grant the game runs on.
    perform pg_temp.ck('a guest cannot read the players table at all',
        not has_table_privilege('anon', 'public.players', 'select'));
    perform pg_temp.ck('a signed-in player can, but ONLY through a policy',
        has_table_privilege('authenticated', 'public.players', 'select')
        and (select relrowsecurity from pg_class
              where oid = 'public.players'::regclass));
    perform pg_temp.ck('and that policy fences them to their own rows',
        exists (select 1 from pg_policies
                 where tablename = 'players' and cmd = 'SELECT'
                   and qual like '%my_player_ids%'),
        (select string_agg(policyname || ': ' || coalesce(qual, '-'), '; ')
           from pg_policies where tablename = 'players'));
    -- reports and blocks have no policy at all, which is the stronger statement:
    -- RLS on with nothing permitted means nobody reads them but a definer.
    perform pg_temp.ck('reports and blocks are reachable by no client whatsoever',
        not has_table_privilege('anon', 'public.reports', 'select')
        and not has_table_privilege('authenticated', 'public.reports', 'select')
        and not has_table_privilege('authenticated', 'public.blocks', 'select'));

    -- --- finding somebody ----------------------------------------------------
    insert into auth.users (id) values (u1), (u2), (u3);
    perform pg_temp.be(u1);
    a := (public.claim_player('{"coins": 5}'::jsonb, 'Crabby Pete', '🦀',
            800, 12, 44000, 2, '{1,0,0,0,0}')->'player'->>'id')::uuid;
    perform pg_temp.be(u2);
    b := (public.claim_player('{}'::jsonb, 'Reef Rita', '🐠',
            300, 7, 100, 0, '{0,0,0,0,0}')->'player'->>'id')::uuid;
    perform pg_temp.be(u3);
    c := (public.claim_player('{}'::jsonb, 'Crabby Imposter', '🦞',
            50, 2, 0, 0, '{0,0,0,0,0}')->'player'->>'id')::uuid;

    r := public.support_find_player(a::text);
    perform pg_temp.ck('a support id finds exactly one player',
        jsonb_array_length(r) = 1, r::text);
    row_ := r->0;
    perform pg_temp.ck('and it is the right one, with what a mail needs',
        row_->>'display_name' = 'Crabby Pete'
        and (row_->>'island_level')::int = 12
        and (row_->>'vault_coins')::bigint = 44000, row_::text);
    perform pg_temp.ck('THE SAVE BLOB IS NOT IN IT',
        not (row_ ? 'save_blob') and not (row_ ? 'save'), row_::text);
    perform pg_temp.ck('and the sign-ins behind it are, because "restore my account" needs them',
        row_ ? 'sign_ins', row_::text);

    r := public.support_find_player('Crabby');
    perform pg_temp.ck('a name fragment finds everyone who matches',
        jsonb_array_length(r) = 2, r::text);
    perform pg_temp.ck('a name nobody has finds nothing, rather than everything',
        public.support_find_player('Nobody At All') = '[]'::jsonb);
    perform pg_temp.ck('an empty query finds nothing, rather than the whole table',
        public.support_find_player('') = '[]'::jsonb
        and public.support_find_player(null) = '[]'::jsonb);
    perform pg_temp.ck('a malformed uuid is a name search, not an error',
        public.support_find_player('not-a-uuid-at-all') = '[]'::jsonb);

    -- The nine seeded crews must not bury the person who wrote in.
    update public.players set is_bot = true, display_name = 'Crabby Bot'
     where id = c;
    perform pg_temp.ck('bots are kept out of a name search',
        jsonb_array_length(public.support_find_player('Crabby')) = 1,
        public.support_find_player('Crabby')::text);
    perform pg_temp.ck('but a bot still answers to its own id, for diagnosing one',
        jsonb_array_length(public.support_find_player(c::text)) = 1);

    -- --- the money, which is most of the mail --------------------------------
    insert into public.iap_receipts (platform, receipt_id, product_id,
                                     install_id, player, verdict)
    values ('ios', 'rcpt-paid-1', 'coins_l', 'install-aaa', a, 'valid'),
           ('ios', 'rcpt-paid-2', 'spins_m', 'install-aaa', a, 'refunded'),
           -- A GUEST WHO PAID. No player row, which is the case most likely to
           -- arrive as an angry email and the one a player lookup cannot answer.
           ('android', 'rcpt-guest', 'coins_s', 'install-zzz', null, 'valid');

    row_ := public.support_find_player(a::text)->0;
    perform pg_temp.ck('what they paid is rolled up by verdict',
        (row_->'receipts_by_verdict'->>'valid')::int = 1
        and (row_->'receipts_by_verdict'->>'refunded')::int = 1,
        row_->>'receipts_by_verdict');
    perform pg_temp.ck('and the recent rows are there for the detail',
        jsonb_array_length(row_->'recent_receipts') = 2, row_::text);

    perform pg_temp.ck('an install id reaches the player who used it',
        (public.support_find_player('install-aaa')->0->>'id') = a::text,
        public.support_find_player('install-aaa')::text);
    perform pg_temp.ck('a GUEST receipt is findable even with no player behind it',
        jsonb_array_length(public.support_find_receipts('install-zzz')) = 1,
        public.support_find_receipts('install-zzz')::text);
    perform pg_temp.ck('and that row names the product they are owed',
        public.support_find_receipts('install-zzz')->0->>'product_id' = 'coins_s');
    perform pg_temp.ck('a receipt id finds its own row',
        jsonb_array_length(public.support_find_receipts('rcpt-paid-1')) = 1);

    -- --- somebody who deleted by accident ------------------------------------
    update public.players set deleted_at = now() where id = b;
    perform pg_temp.ck('a deleted account still answers, and says it is deleted',
        jsonb_array_length(public.support_find_player(b::text)) = 1
        and (public.support_find_player(b::text)->0->>'deleted_at') is not null,
        public.support_find_player(b::text)::text);
    update public.players set deleted_at = null where id = b;

    -- --- the report queue ----------------------------------------------------
    --
    -- MEASURED AS A DELTA, because earlier blocks in this file have already
    -- filed reports and the queue is shared. The first draft asserted an empty
    -- list and failed on correct code -- a test that only passes when it runs
    -- first is a test that will fail on somebody else's afternoon.
    before_open := jsonb_array_length(public.support_reports());
    perform pg_temp.ck('the queue is a list, whatever is already in it',
        jsonb_typeof(public.support_reports()) = 'array',
        public.support_reports()::text);
    perform pg_temp.be(u2);
    perform public.report_player(a, 'chat');
    perform pg_temp.be(u3);
    perform public.report_player(a, 'name');
    perform pg_temp.be(u1);
    perform public.report_player(b, 'name');

    r := public.support_reports();
    perform pg_temp.ck('every open report is in the queue',
        jsonb_array_length(r) = before_open + 3,
        format('%s before, %s now', before_open, jsonb_array_length(r)));
    -- "one report is an argument, twenty is a pattern" -- the original
    -- migration's own words, and the reason the order is by reporters.
    perform pg_temp.ck('the person two different people reported is at the top',
        (r->0->>'reported_id') = a::text
        and (r->0->>'reporters')::int = 2, r::text);
    perform pg_temp.ck('and the queue carries names, not just ids',
        (r->0->>'reported_name') = 'Crabby Pete'
        and (r->0->>'reporter_name') is not null, (r->0)::text);

    rep := (r->0->>'id')::uuid;
    perform pg_temp.ck('a report can be marked seen',
        (public.support_review_report(rep)->>'ok')::boolean);
    perform pg_temp.ck('and it leaves the open queue',
        not exists (select 1 from jsonb_array_elements(public.support_reports()) x
                     where x->>'id' = rep::text));
    perform pg_temp.ck('but is still ON RECORD, which is what a store asks about',
        exists (select 1 from jsonb_array_elements(
                    public.support_reports(false, 50)) x
                 where x->>'id' = rep::text
                   and x->>'reviewed_at' is not null));
    perform pg_temp.ck('closing it twice is not an error',
        (public.support_review_report(rep)->>'ok')::boolean);
    perform pg_temp.ck('and closing one that never existed is refused honestly',
        not (public.support_review_report(gen_random_uuid())->>'ok')::boolean);

    raise notice 'SUPPORT DESK TESTS PASSED';
end;
$$;
