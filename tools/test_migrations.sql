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
    perform pg_temp.ck('with no eligible human, find_target falls back to a bot',
                       (r->>'id')::uuid = p_bot, coalesce(r::text, 'NULL'));

    -- --- the server clamps a lying client ----------------------------------
    update public.players set vault_coins = 500 where id = p_bob;
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

    -- --- deletion ----------------------------------------------------------
    perform pg_temp.be(bob);
    r := public.delete_account();
    perform pg_temp.ck('delete_account removes the identities it found',
                       (r->>'identities')::int = 1, r::text);
    perform pg_temp.ck('and the island is gone from every read path',
                       public.public_player(p_bob) is null);

    raise notice 'ALL FUNCTIONAL TESTS PASSED';
end;
$$;
