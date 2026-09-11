// =============================================================================
//  verify_purchase -- ask the store itself whether a receipt is real
// =============================================================================
//
// The client grants first and reports here after; see the comment on the
// iap_receipts migration for why. This function's contract with the client:
//
//   POST { platform: "ios"|"android", receipt_id, product_id, install_id }
//   ->   { verdict, detail, final }
//
// `final: true` means the client should stop retrying (valid / invalid /
// refunded). `final: false` means the question could not be answered yet --
// missing secrets, store auth failure, a transient error -- and the client's
// queue keeps the receipt for a later attempt. EVERY failure path here is
// deliberately non-final and non-punitive: a paying player must never lose
// anything to this function being misconfigured.
//
// iOS: the plugin hands the game Apple's transactionId. We ask the App Store
// Server API for the signed transaction record. The JWS payload is decoded
// without re-verifying its certificate chain, deliberately: the record was
// fetched from Apple's own endpoint over TLS in this same request, so the
// chain check would prove what the transport already proves. (Chain
// verification matters when the JWS arrives THROUGH the client; this one
// never does.)
//
// Android: the client reports the purchaseToken. We ask the Play Developer
// API purchases.products.get, authenticated as the publisher service account.
// A (product, token) pair Google never issued answers 400/404, which is the
// entire spoofing-tool detection in one status code.
//
// Deploy notes: verify_jwt must be OFF for this function (guests buy packs
// too, and a receipt is its own credential -- the store lookup is the auth).
// Secrets it reads: APPLE_IAP_KEY_P8, APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID,
// GOOGLE_SA_JSON. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected by
// the platform.

// Types only, for editors: the edge runtime provides `Deno` at run time, and
// this import is what stops a TypeScript checker outside that runtime from
// underlining every Deno.env line as an error. Nothing about behaviour.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUNDLE_ID = Deno.env.get("APP_BUNDLE_ID") ?? "com.guymaslawi.lootlagoon";
const APPLE_KEY_P8 = Deno.env.get("APPLE_IAP_KEY_P8") ?? "";
const APPLE_KEY_ID = Deno.env.get("APPLE_IAP_KEY_ID") ?? "";
const APPLE_ISSUER = Deno.env.get("APPLE_IAP_ISSUER_ID") ?? "";
const GOOGLE_SA_JSON = Deno.env.get("GOOGLE_SA_JSON") ?? "";

const APPLE_PROD = "https://api.storekit.itunes.apple.com";
const APPLE_SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

// One install filing more receipts than this in an hour is not buying packs,
// it is probing. Generous on purpose: a whale clearing an Ask-to-Buy backlog
// plus a launch reconcile is maybe a dozen.
const RATE_LIMIT_PER_HOUR = 40;

type Verdict = {
  verdict: "pending" | "valid" | "invalid" | "refunded" | "unknown";
  detail: string;
  payload?: unknown;
};

const final = (v: Verdict) =>
  v.verdict === "valid" || v.verdict === "invalid" || v.verdict === "refunded";

// --- base64url without padding, both directions ------------------------------

const b64url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");

const b64urlDecode = (s: string): Uint8Array => {
  const b64 = s.replaceAll("-", "+").replaceAll("_", "/");
  const bin = atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
};

const pemToDer = (pem: string): Uint8Array =>
  Uint8Array.from(
    atob(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );

const utf8 = new TextEncoder();

async function signJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  key: CryptoKey,
  alg: { name: string; hash: string },
): Promise<string> {
  const signingInput = `${b64url(utf8.encode(JSON.stringify(header)))}.${
    b64url(utf8.encode(JSON.stringify(payload)))
  }`;
  const sig = await crypto.subtle.sign(alg, key, utf8.encode(signingInput));
  return `${signingInput}.${b64url(new Uint8Array(sig))}`;
}

// --- Apple -------------------------------------------------------------------

async function appleToken(): Promise<string> {
  const der = pemToDer(APPLE_KEY_P8);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  return await signJwt(
    { alg: "ES256", kid: APPLE_KEY_ID, typ: "JWT" },
    { iss: APPLE_ISSUER, iat: now, exp: now + 1200, aud: "appstoreconnect-v1", bid: BUNDLE_ID },
    key,
    { name: "ECDSA", hash: "SHA-256" },
  );
}

async function verifyApple(receiptId: string, productId: string): Promise<Verdict> {
  if (APPLE_KEY_P8 === "" || APPLE_KEY_ID === "" || APPLE_ISSUER === "") {
    return { verdict: "unknown", detail: "apple key not configured" };
  }
  // Transaction ids are numeric strings; refuse anything else before it can
  // ride into a URL.
  if (!/^[0-9]{1,32}$/.test(receiptId)) {
    return { verdict: "invalid", detail: "not an apple transaction id" };
  }
  const token = await appleToken();
  // TestFlight and pre-release purchases live in the sandbox environment, so
  // "unknown in production" routinely means "ask sandbox", not "fake".
  let env = "production";
  let res = await fetch(`${APPLE_PROD}/inApps/v1/transactions/${receiptId}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) {
    env = "sandbox";
    res = await fetch(`${APPLE_SANDBOX}/inApps/v1/transactions/${receiptId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
  }
  if (res.status === 404) {
    return { verdict: "invalid", detail: "apple knows no such transaction" };
  }
  if (res.status === 401) {
    // Our credentials, not their receipt. Never final.
    return { verdict: "unknown", detail: "apple rejected our api key" };
  }
  if (!res.ok) {
    return { verdict: "unknown", detail: `apple answered ${res.status}` };
  }
  const body = await res.json();
  const jws = String(body?.signedTransactionInfo ?? "");
  const parts = jws.split(".");
  if (parts.length !== 3) {
    return { verdict: "unknown", detail: "apple answer carried no transaction" };
  }
  const txn = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
  const keep = {
    env,
    bundleId: txn.bundleId,
    productId: txn.productId,
    type: txn.type,
    purchaseDate: txn.purchaseDate,
    revocationDate: txn.revocationDate ?? null,
  };
  if (txn.bundleId !== BUNDLE_ID) {
    return { verdict: "invalid", detail: `receipt belongs to ${txn.bundleId}`, payload: keep };
  }
  if (txn.revocationDate !== undefined && txn.revocationDate !== null) {
    return { verdict: "refunded", detail: `refunded (${env})`, payload: keep };
  }
  if (productId !== "" && txn.productId !== productId) {
    // The receipt is real but the client granted something else off it --
    // the substitution attack, on the platform where we could not check the
    // signed payload locally.
    return {
      verdict: "invalid",
      detail: `receipt is for ${txn.productId}, client granted ${productId}`,
      payload: keep,
    };
  }
  return { verdict: "valid", detail: env, payload: keep };
}

// --- Google ------------------------------------------------------------------

async function googleAccessToken(): Promise<string | null> {
  const sa = JSON.parse(GOOGLE_SA_JSON);
  const der = pemToDer(String(sa.private_key ?? ""));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    key,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) return null;
  return String((await res.json()).access_token ?? "") || null;
}

async function verifyGoogle(receiptId: string, productId: string): Promise<Verdict> {
  if (GOOGLE_SA_JSON === "") {
    return { verdict: "unknown", detail: "google service account not configured" };
  }
  if (productId === "" || !/^[A-Za-z0-9._-]{1,200}$/.test(productId)) {
    return { verdict: "unknown", detail: "no plausible product id to look up" };
  }
  if (!/^[A-Za-z0-9._-]{1,300}$/.test(receiptId)) {
    return { verdict: "invalid", detail: "not a play purchase token" };
  }
  const token = await googleAccessToken();
  if (token === null) {
    return { verdict: "unknown", detail: "google would not exchange our key" };
  }
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${BUNDLE_ID}` +
    `/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(receiptId)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 400 || res.status === 404) {
    // Google's answer for a token it never issued, or a token that does not
    // belong to this product -- both are the spoofing/substitution case.
    return { verdict: "invalid", detail: `google knows no such purchase (${res.status})` };
  }
  if (res.status === 401 || res.status === 403) {
    // Our permissions (the service account may not have financial-data
    // access yet), not their receipt. Never final.
    return { verdict: "unknown", detail: `google refused us (${res.status})` };
  }
  if (!res.ok) {
    return { verdict: "unknown", detail: `google answered ${res.status}` };
  }
  const p = await res.json();
  const keep = {
    purchaseState: p.purchaseState,
    consumptionState: p.consumptionState,
    purchaseTimeMillis: p.purchaseTimeMillis,
    orderId: p.orderId,
    purchaseType: p.purchaseType ?? null, // 0 = license-tester "purchase"
  };
  if (p.purchaseState === 1) {
    return { verdict: "refunded", detail: "canceled/refunded", payload: keep };
  }
  if (p.purchaseState === 2) {
    return { verdict: "pending", detail: "payment pending", payload: keep };
  }
  if (p.purchaseState === 0) {
    const tester = p.purchaseType === 0 ? " (license tester)" : "";
    return { verdict: "valid", detail: `purchased${tester}`, payload: keep };
  }
  return { verdict: "unknown", detail: `unrecognised purchaseState ${p.purchaseState}` };
}

// --- the receipt table -------------------------------------------------------

const dbHeaders = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  "Content-Type": "application/json",
};

async function dbSelect(platform: string, receiptId: string) {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/iap_receipts?platform=eq.${platform}` +
      `&receipt_id=eq.${encodeURIComponent(receiptId)}&select=verdict,detail`,
    { headers: dbHeaders },
  );
  if (!res.ok) return null;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function dbRecentCount(installId: string): Promise<number> {
  const hourAgo = new Date(Date.now() - 3600_000).toISOString();
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/iap_receipts?install_id=eq.${encodeURIComponent(installId)}` +
      `&created_at=gte.${hourAgo}&select=id&limit=${RATE_LIMIT_PER_HOUR + 1}`,
    { headers: dbHeaders },
  );
  if (!res.ok) return 0; // the limiter failing must not block real receipts
  const rows = await res.json();
  return Array.isArray(rows) ? rows.length : 0;
}

async function dbRecord(
  row: Record<string, unknown>,
  v: Verdict,
): Promise<void> {
  const body = {
    ...row,
    verdict: v.verdict,
    detail: v.detail.slice(0, 500),
    store_payload: v.payload ?? null,
    verified_at: v.verdict === "pending" || v.verdict === "unknown"
      ? null
      : new Date().toISOString(),
  };
  await fetch(
    `${SUPABASE_URL}/rest/v1/iap_receipts?on_conflict=platform,receipt_id`,
    {
      method: "POST",
      headers: { ...dbHeaders, Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify(body),
    },
  );
}

// --- the handler -------------------------------------------------------------

const answer = (v: Verdict, status = 200) =>
  new Response(
    JSON.stringify({ verdict: v.verdict, detail: v.detail, final: final(v) }),
    { status, headers: { "Content-Type": "application/json" } },
  );

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return answer({ verdict: "unknown", detail: "POST only" }, 405);
  }
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return answer({ verdict: "unknown", detail: "not json" }, 400);
  }
  const platform = String(body.platform ?? "");
  const receiptId = String(body.receipt_id ?? "").slice(0, 400);
  const productId = String(body.product_id ?? "").slice(0, 200);
  const installId = String(body.install_id ?? "").slice(0, 80);
  if ((platform !== "ios" && platform !== "android") || receiptId === "") {
    return answer({ verdict: "unknown", detail: "bad request" }, 400);
  }

  // A receipt already settled answers from the table, so a replayed report --
  // the client retrying, or a copied receipt -- costs no store round trip.
  const seen = await dbSelect(platform, receiptId);
  if (seen !== null && ["valid", "invalid", "refunded"].includes(seen.verdict)) {
    return answer(seen as Verdict);
  }

  if (installId !== "" && (await dbRecentCount(installId)) > RATE_LIMIT_PER_HOUR) {
    // Deliberately non-final: a real receipt caught in the limiter is
    // retried by the client's queue hours later and lands fine.
    return answer({ verdict: "unknown", detail: "rate limited" }, 429);
  }

  const row = {
    platform,
    receipt_id: receiptId,
    product_id: productId,
    install_id: installId,
  };

  let v: Verdict;
  try {
    v = platform === "ios"
      ? await verifyApple(receiptId, productId)
      : await verifyGoogle(receiptId, productId);
  } catch (e) {
    // A bug or a store outage must read as "ask again later", never as a
    // verdict on the player.
    v = { verdict: "unknown", detail: `error: ${String(e).slice(0, 200)}` };
  }
  await dbRecord(row, v);
  return answer(v);
});
