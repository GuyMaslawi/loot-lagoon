-- =============================================================================
--  The ops tool could not reach the table it owns
-- =============================================================================
--
-- 20261001120000 enabled RLS on app_config and granted execute on the reader
-- function to anon and authenticated, which is right and was verified live: a
-- phone gets its answer, and neither anon nor authenticated can touch the table
-- underneath it.
--
-- What it never granted was anything to `service_role`, and tools/liveops.py is
-- the only thing in this project that WRITES config. So the table shipped
-- correct and unusable:
--
--     permission denied for table app_config
--
-- WHY THIS WAS NOT CAUGHT. Two reasons, and both are now closed:
--
--   * test_migrations.sql asserted that anon is REFUSED and never that
--     service_role is ADMITTED. A deny-side test passes just as happily on a
--     table nobody at all can reach.
--   * validate_migrations.sh runs every statement as the local superuser, which
--     has every privilege by construction, so no grant bug can fail there. The
--     assertions are the only thing that can catch one, which is why the ones
--     below are has_table_privilege checks rather than live queries.
--
-- WHY THE GRANT IS NEEDED AT ALL, given that service_role carries BYPASSRLS.
-- Bypassing row level security and holding a privilege on the relation are
-- different things: BYPASSRLS says no policy will filter the rows, and says
-- nothing about whether the role may read the table in the first place. Older
-- Supabase projects hid this behind default privileges on `public` that granted
-- new tables to all three roles; newer ones do not, so a table created today is
-- reachable by exactly whoever is named here.

grant select, insert, update, delete on public.app_config to service_role;

-- The id column is a bigserial, so an INSERT that does not name it reads the
-- sequence. Without this the grant above admits the role to the table and then
-- fails on the first write, which is a worse failure than being locked out
-- entirely -- it looks like a bug in the tool rather than a missing grant.
grant usage, select on sequence public.app_config_id_seq to service_role;

-- NOT GRANTED TO ANYBODY ELSE, and that is the whole shape of this table. anon
-- and authenticated reach the config through public.app_config() and must never
-- reach the rows: the function is a stable contract, and a client that could
-- SELECT here would break the first time a column was added.
revoke all on public.app_config from anon, authenticated;
