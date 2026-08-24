-- =============================================================================
--  Which sign-ins already open this island
-- =============================================================================
--
-- The linking screen has to draw "Apple ✓ connected" next to "Connect Google",
-- and only the server knows which is which: the answer lives in
-- player_identities, which spans every device this player has ever signed in
-- on. Asking the phone would give the wrong answer on the second phone, which
-- is precisely the case linking exists for.
--
-- Providers only. Never the auth_uid -- the screen has no use for it, and a
-- client that could read other people's identity rows is a client that could
-- work out which islands belong to the same person.
create or replace function public.my_identities()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(jsonb_agg(distinct pi.provider), '[]'::jsonb)
      from public.player_identities pi
     where pi.player_id = public.current_player()
$$;

revoke all on function public.my_identities() from public, anon;
grant execute on function public.my_identities() to authenticated;
