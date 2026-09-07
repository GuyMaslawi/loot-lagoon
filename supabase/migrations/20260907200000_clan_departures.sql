-- =============================================================================
--  Leaving a clan properly -- including by deleting the account
-- =============================================================================
--
-- THE DEFECT, found 2026-09-07 by driving delete_account against a clan.
--
-- `delete_account` was written on 2026-08-31 and clans landed on 2026-09-04.
-- Nobody went back. It soft-deletes the player -- `deleted_at = now()`, which
-- is right, because other devices hold cached raid cards naming that island --
-- and then stops. The `clan_members` row is still there, and a soft delete
-- fires no `on delete cascade`, so it stays there for ever.
--
-- Four things follow from that one missing line, and all four are permanent:
--
--   1. THE SEAT IS NEVER GIVEN BACK. `clans.members` is a denormalised count
--      that only `leave_clan` decrements. A clan that loses people to account
--      deletion keeps counting them, reaches the thirty-member cap with fewer
--      than thirty real players in it, and can never be joined again. It reads
--      to everybody browsing as a popular clan and refuses all of them.
--
--   2. THE ROSTER SHOWS A HOLE. `clan_view` builds its member list from
--      `public_player`, which answers NULL for a deleted island, so the array
--      carries a JSON null. The client skips it -- `if typeof(m) !=
--      TYPE_DICTIONARY: continue` -- so the page draws N-1 people under a
--      header that says N, with no way to tell which.
--
--   3. AN OWNER WHO LEAVES TAKES THE CONTROLS WITH THEM. `clans.owner` is
--      never reassigned by anything. `set_clan_open`, `clan_join_requests` and
--      `answer_clan_request` are all gated on `owner = v_me`, so a clan whose
--      owner deletes their account can never open or close its door and can
--      never see a join request again. If the door happened to be shut, it is
--      shut for ever.
--
--      This half is NOT specific to deletion. `leave_clan` has the same hole:
--      an owner who simply presses LEAVE strands the clan exactly as
--      thoroughly. Its own comment says "there is no ownership transfer flow
--      to hand it to" -- there is one now, below.
--
--   4. AN EMPTY CLAN HOLDS ITS NAME FOR EVER. leave_clan disbands a clan when
--      the last member goes, and says why: "a clan with nobody in it is a name
--      held for ever against everybody else". The deletion path skipped that,
--      so the last member deleting their account produced precisely the thing
--      that comment forbids.
--
-- The pending rows have the same shape and are cleaned here too: `clan_invites`
-- and `clan_requests` reference `players` with `on delete cascade`, which a
-- soft delete does not fire, so a deleted player keeps a live invite and a live
-- request -- one lighting a badge on somebody's phone for an island that is
-- gone, the other sitting in an owner's queue waiting to be answered.

-- -----------------------------------------------------------------------------
--  One place that knows how to take a player out of a clan
-- -----------------------------------------------------------------------------
--
-- Both callers do the same five things and getting one of them out of step is
-- how this file came to exist, so they share a body rather than each spelling
-- it out. Not granted to anybody: it is called from inside two security
-- definer functions, which run as the owner.
create or replace function public.clan_release(p_player uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_clan  uuid;
    v_owner uuid;
    v_left  integer;
    v_heir  uuid;
begin
    -- Whatever else was pending for this player is moot either way, and it is
    -- cleared even when they are in no clan at all -- an invite is addressed
    -- to a player, not to a membership.
    delete from public.clan_invites  where to_player = p_player;
    delete from public.clan_requests where player_id = p_player;

    select clan_id into v_clan from public.clan_members where player_id = p_player;
    if v_clan is null then
        return;
    end if;

    -- Locked before the count moves, exactly as join_clan and leave_clan do:
    -- a departure racing a join must not let both read `members` and write it.
    select owner into v_owner from public.clans where id = v_clan for update;

    delete from public.clan_members where player_id = p_player;
    update public.clans set members = greatest(0, members - 1)
     where id = v_clan
 returning members into v_left;

    -- The last one out takes the clan with them.
    if coalesce(v_left, 0) <= 0 then
        delete from public.clans where id = v_clan;
        return;
    end if;

    -- THE HANDOVER. Longest-standing member remaining, which is the only
    -- ordering the table already carries and the only one a player could
    -- predict. A clan with a live door and a live request queue is worth more
    -- than a clan that remembers who founded it.
    if v_owner = p_player then
        select m.player_id into v_heir
          from public.clan_members m
          join public.players p on p.id = m.player_id
         where m.clan_id = v_clan
           and p.deleted_at is null
         order by m.joined_at
         limit 1;
        -- No living heir: everybody left in the room is themselves deleted, so
        -- the clan is a shell. Disbanded rather than handed to a ghost.
        if v_heir is null then
            delete from public.clan_members where clan_id = v_clan;
            delete from public.clans where id = v_clan;
        else
            update public.clans set owner = v_heir where id = v_clan;
        end if;
    end if;
end;
$$;

-- -----------------------------------------------------------------------------
--  The two doors out, both going through it
-- -----------------------------------------------------------------------------

create or replace function public.leave_clan()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me uuid := public.current_player();
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;
    perform public.clan_release(v_me);
    return jsonb_build_object('ok', true);
end;
$$;

-- Unchanged except for the one call. Everything about the soft delete itself --
-- the placeholder name, the emoji, the identities going and the auth rows with
-- them -- is exactly as 20260831190000 left it, and deliberately so: the reason
-- the island row survives is that other devices hold cached raid cards naming
-- it, and that reason has not changed.
create or replace function public.delete_account()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_me   uuid := public.current_player();
    v_uids uuid[];
begin
    if v_me is null then
        raise exception 'no island for this account' using errcode = '28000';
    end if;

    select array_agg(auth_uid) into v_uids
      from public.player_identities where player_id = v_me;

    -- BEFORE the soft delete, so the handover can still see this player as a
    -- living member and so `clan_release` reads a consistent roster.
    perform public.clan_release(v_me);

    update public.players
       set deleted_at   = now(),
           display_name = 'Former islander',
           emoji        = '🙂'
     where id = v_me;

    delete from public.player_identities where player_id = v_me;
    delete from auth.users where id = any(v_uids);

    return jsonb_build_object('status', 'deleted',
                              'identities', coalesce(array_length(v_uids, 1), 0));
end;
$$;

-- -----------------------------------------------------------------------------
--  Backfill: the clans that are already wrong
-- -----------------------------------------------------------------------------
--
-- Anybody who deleted their account while in a clan is still sitting in it.
-- The count is rebuilt from the roster rather than adjusted, because there is
-- no record of how far it drifted.
delete from public.clan_members m
 using public.players p
 where p.id = m.player_id and p.deleted_at is not null;

delete from public.clan_invites  i
 using public.players p
 where p.id = i.to_player   and p.deleted_at is not null;

delete from public.clan_requests r
 using public.players p
 where p.id = r.player_id   and p.deleted_at is not null;

update public.clans c
   set members = coalesce((select count(*) from public.clan_members m
                            where m.clan_id = c.id), 0);

-- Ownership, for clans whose owner is gone but which still have somebody in
-- them. Same rule as the handover above.
update public.clans c
   set owner = (select m.player_id
                  from public.clan_members m
                  join public.players p on p.id = m.player_id
                 where m.clan_id = c.id and p.deleted_at is null
                 order by m.joined_at
                 limit 1)
 where not exists (select 1 from public.players p
                    where p.id = c.owner and p.deleted_at is null)
   and exists (select 1 from public.clan_members m
                join public.players p2 on p2.id = m.player_id
               where m.clan_id = c.id and p2.deleted_at is null);

delete from public.clans where members <= 0;

-- -----------------------------------------------------------------------------
--  Grants
-- -----------------------------------------------------------------------------
--
-- Recreating a function resets its privileges. clan_release is deliberately
-- granted to nobody -- it takes a player id, and a grant would let one account
-- evict another.
do $$
declare fn text;
begin
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('leave_clan', 'delete_account')
    loop
        execute format('revoke all on function %s from public, anon', fn);
        execute format('grant execute on function %s to authenticated', fn);
    end loop;
    for fn in
        select p.oid::regprocedure::text
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'clan_release'
    loop
        execute format('revoke all on function %s from public, anon, authenticated', fn);
    end loop;
end;
$$;
