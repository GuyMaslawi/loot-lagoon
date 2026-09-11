-- =============================================================================
--  iap_receipts -- the server's own record of every store receipt it has seen
-- =============================================================================
--
-- Until now the only record of a purchase lived on the device that made it:
-- the StoreKit/Play answer, checked on the phone, written to a local ledger.
-- That check can be patched out by anyone who can patch the client, and the
-- receipt-spoofing tools sold for exactly that purpose (a patched billing
-- service, a jailbreak StoreKit shim) hand the app receipts Google and Apple
-- never issued.
--
-- This table is written by the verify_purchase edge function, which asks the
-- store that supposedly issued the receipt -- Apple's App Store Server API,
-- Google's Play Developer API -- whether it is real. The client GRANTS FIRST
-- and reports AFTER: a paying player is never made to wait on this round trip,
-- and a verdict of 'invalid' claws nothing back on its own. What it buys is
-- a server-side ledger a cheat cannot edit, which is the prerequisite for any
-- future enforcement and for reconciling refunds -- and it catches the
-- off-the-shelf spoofing tools cold, because the store answers "no such
-- purchase" regardless of what the patched client asserted.
--
-- No RLS policies are written for it on purpose, same as diagnostics: RLS is
-- enabled and nothing is granted to anon or authenticated, so the only way in
-- is the edge function, which holds the service role. A client that could
-- write its own verdict row would make the whole exercise decorative.

create table if not exists public.iap_receipts (
    id           bigint generated always as identity primary key,

    platform     text not null check (platform in ('ios', 'android')),

    -- Apple's transactionId or Play's purchaseToken. One row per receipt for
    -- ever: the unique pair below is what makes a replayed receipt read as
    -- "already seen" instead of as a fresh sale.
    receipt_id   text not null,

    -- What the CLIENT said it was granted for. The store's own answer decides
    -- the verdict; a mismatch between the two is itself the finding.
    product_id   text not null default '',

    -- Same install id diagnostics uses: random per install, made on the
    -- device, reset by a reinstall. Not a person, not a device id. It exists
    -- so a burst of junk receipts can be rate-limited and attributed to one
    -- install without identifying anybody.
    install_id   text not null default '',

    -- Filled when the reporting client was signed in. Nullable, and set null
    -- rather than cascading: the receipt is a financial record and outlives
    -- the account (purge_deleted_players must not take the money trail with
    -- it), but it must not point at a player row that no longer exists.
    player       uuid references public.players (id) on delete set null,

    -- 'pending'  -- row created, store not yet answered
    -- 'valid'    -- the store confirms this receipt (detail says if sandbox)
    -- 'invalid'  -- the store does not know it, or it names another product
    -- 'refunded' -- real once, then revoked/refunded; not fraud
    -- 'unknown'  -- the store could not be asked (config missing, auth
    --               failed, transient error); the client may retry
    verdict      text not null default 'pending'
                 check (verdict in ('pending', 'valid', 'invalid', 'refunded', 'unknown')),
    detail       text not null default '',

    -- The subset of the store's answer worth keeping for a human reading an
    -- incident later. Never the whole response: no customer data belongs here.
    store_payload jsonb,

    created_at   timestamptz not null default now(),
    verified_at  timestamptz,

    unique (platform, receipt_id)
);

alter table public.iap_receipts enable row level security;
revoke all on table public.iap_receipts from public, anon, authenticated;

-- The service role is what the edge function connects as. Explicit rather
-- than inherited, so a change to default privileges cannot silently cut the
-- function off from its own table.
grant select, insert, update on table public.iap_receipts to service_role;

-- The rate-limit question the edge function asks on every call: how many rows
-- has this install created in the last hour.
create index if not exists iap_receipts_install_idx
    on public.iap_receipts (install_id, created_at);
