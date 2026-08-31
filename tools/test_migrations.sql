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

    raise notice 'ALL FUNCTIONAL TESTS PASSED';
end;
$$;
