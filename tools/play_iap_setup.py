"""Create Loot Lagoon's 25 one-time products in Google Play.

The Play twin of tools/iap_setup.py, which does the same job in App Store
Connect. The product list is READ OUT OF iap_setup.py rather than copied, so
the two stores can never drift: one list, two uploaders.

    python3 tools/play_iap_setup.py                    # dry run: say what it would do
    python3 tools/play_iap_setup.py --apply            # create and activate all 25
    python3 tools/play_iap_setup.py --only chest_w --apply
    python3 tools/play_iap_setup.py --list             # what Play holds right now

Credentials are play_upload.py's -- PLAY_SERVICE_ACCOUNT -- and its token()
and call() are imported rather than reimplemented.

THE SERVICE ACCOUNT NEEDS A MONETIZATION GRANT, not just the release-to-
testing-tracks one play_upload.py runs on, and there is no cheap probe for it.
An empty-body POST to :batchUpdate answers 400 "requests field must be set"
even with no permission at all -- Google validates the body BEFORE it checks
the caller -- so a 400 there proves nothing. The first honest answer comes from
pricing:convertRegionPrices, which 403s "The caller does not have permission"
until the account is granted orders/monetization access in Play Console under
Users and permissions.

WHY THIS IS NOT THE OLD inappproducts API. That endpoint now answers
403 "Please migrate to the new publishing API" for this app and is gone for
good. The replacement is oneTimeProducts, and it is a different shape: a
product is a shell, and the thing that actually carries a price is a PURCHASE
OPTION underneath it. A product with no active purchase option is invisible to
the billing client -- which looks exactly like a product that was never
created.

THREE TRAPS, each of which produced a wrong-looking result on the way here:

1. Google's own URL casing is inconsistent. list/get want oneTimeProducts,
   patch wants onetimeproducts. The natural-looking /monetization/... prefix
   does not exist at all and answers an HTML 404 rather than a JSON one.
2. HTTP 204 No Content is what an EMPTY catalogue looks like. It is success,
   not an error, and it reads identically whether the merchant account exists
   or not -- so it cannot be used to prove the products page is unlocked.
3. legacyCompatible must be true on the buy option. The game asks Play for
   plain product ids (scripts/iap.gd, queryProductDetails with productType
   INAPP); without this flag the id resolves to nothing and every Pay button
   reports "Can't reach Google Play yet" forever. At most one buy option per
   product may carry it.

PRICES ARE NOT INVENTED HERE. Each USD price from iap_setup.py goes through
pricing:convertRegionPrices, which is the same conversion the Console runs
behind its "auto-convert" button, and comes back as a price for every region
Play sells in plus a USD/EUR pair for regions added later. Hand-rolling that
would mean shipping an exchange-rate table that goes stale silently.
"""

import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_upload as play  # noqa: E402

API = play.API
PACKAGE = play.PACKAGE
PREFIX = "com.guymaslawi.lootlagoon."

# The one purchase option under each product. The id is arbitrary but is what
# the Console shows, so it is named for what it is rather than left as "1".
BUY_OPTION = "buy"


def call(method: str, url: str, tok: str, body=None):
	"""play.call, but patient with Google having a bad minute.

	Creating 25 products is ~75 requests, and a single 503 partway through used
	to leave a product created-but-DRAFT -- which the game cannot tell apart
	from a product that does not exist. Retrying is cheaper than reasoning
	about where a half-finished run stopped.
	"""
	for attempt in range(4):
		try:
			return play.call(method, url, tok, body=body)
		except SystemExit as e:
			transient = any(f"HTTP {c}" in str(e) for c in (429, 500, 502, 503, 504))
			if not transient or attempt == 3:
				raise
			time.sleep(2 ** attempt)


def products() -> list:
	"""The 25 products, parsed out of iap_setup.py's PRODUCTS table.

	Deliberately a parse and not an import: importing iap_setup runs it, and it
	ends by calling main() against App Store Connect.
	"""
	src = open(os.path.join(os.path.dirname(__file__), "iap_setup.py")).read()
	block = src.split("PRODUCTS = [", 1)[1].split("\n]", 1)[0]
	rows = re.findall(
		r'\(\s*"([a-z0-9_]+)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([0-9.]+)"',
		block)
	if len(rows) != 25:
		raise SystemExit(f"parsed {len(rows)} products out of iap_setup.py, expected 25")
	return rows


def money(usd: str) -> dict:
	"""Google wants whole units and nanos, never a float. $2.99 -> 2 + 990000000."""
	units, _, cents = usd.partition(".")
	return {"currencyCode": "USD", "units": units,
		"nanos": int((cents + "00")[:2]) * 10_000_000}


def converted(tok: str, usd: str) -> tuple:
	"""Ask Play what this USD price is worth everywhere it sells."""
	r = call("POST", f"{API}/applications/{PACKAGE}/pricing:convertRegionPrices",
		tok, body={"price": money(usd)})
	regions = r.get("convertedRegionPrices", {})
	other = r.get("convertedOtherRegionsPrice", {})
	version = (r.get("regionVersion") or {}).get("version", "")
	return regions, other, version


def body_for(short: str, disp: str, desc: str, usd: str, tok: str) -> tuple:
	regions, other, version = converted(tok, usd)
	pricing = [{"regionCode": code, "price": v["price"], "availability": "AVAILABLE"}
		for code, v in sorted(regions.items())]
	option = {
		"purchaseOptionId": BUY_OPTION,
		# One-shot currencies, bought again and again -- the same CONSUMABLE the
		# App Store side declares. multiQuantity would let a buyer take four
		# Piggy Banks in one tap, which the grant path in iap.gd does not model.
		"buyOption": {"legacyCompatible": True, "multiQuantityEnabled": False},
		"regionalPricingAndAvailabilityConfigs": pricing,
	}
	if other.get("usdPrice") and other.get("eurPrice"):
		# Play adds countries; without this a product is simply absent in each
		# new one until somebody notices and edits 25 products by hand.
		option["newRegionsConfig"] = {
			"usdPrice": other["usdPrice"], "eurPrice": other["eurPrice"],
			"availability": "AVAILABLE"}
	product = {
		"packageName": PACKAGE,
		"productId": PREFIX + short,
		"listings": [{"languageCode": "en-US", "title": disp, "description": desc}],
		"purchaseOptions": [option],
	}
	return product, version, len(pricing)


def existing(tok: str) -> dict:
	"""What Play holds now. An empty catalogue answers 204 with no body."""
	url = f"{API}/applications/{PACKAGE}/oneTimeProducts?pageSize=100"
	r = call("GET", url, tok)
	return {p["productId"]: p for p in (r or {}).get("oneTimeProducts", [])}


def activate(tok: str, pid: str) -> None:
	"""Created products land in DRAFT.

	A draft purchase option is not sellable and not visible to the billing
	client, so this is not an optional flourish -- a product left here looks
	from the game exactly like a product that was never created.

	packageName and productId go INSIDE activatePurchaseOptionRequest. Putting
	them on the wrapper, where every other batch endpoint in this API carries
	them, answers 400 "Cannot find field".
	"""
	call("POST",
		f"{API}/applications/{PACKAGE}/oneTimeProducts/{pid}/purchaseOptions:batchUpdateStates",
		tok, body={"requests": [{"activatePurchaseOptionRequest": {
			"packageName": PACKAGE, "productId": pid,
			"purchaseOptionId": BUY_OPTION}}]})


def create(tok: str, short: str, disp: str, desc: str, usd: str) -> None:
	product, version, n = body_for(short, disp, desc, usd, tok)
	pid = PREFIX + short
	url = (f"{API}/applications/{PACKAGE}/onetimeproducts/{pid}"
		f"?allowMissing=true&regionsVersion.version={version}"
		"&updateMask=listings,purchaseOptions")
	call("PATCH", url, tok, body=product)
	activate(tok, pid)
	print(f"  created + activated  {pid:44} ${usd:>6}  {n} regions")


def main() -> None:
	args = sys.argv[1:]
	apply = "--apply" in args
	only = args[args.index("--only") + 1] if "--only" in args else ""

	path = os.environ.get("PLAY_SERVICE_ACCOUNT", "")
	if not path or not os.path.exists(os.path.expanduser(path)):
		raise SystemExit(
			"no service account. Point PLAY_SERVICE_ACCOUNT at the JSON key:\n"
			"    export PLAY_SERVICE_ACCOUNT=~/.playconsole/loot-lagoon-publisher.json")
	tok = play.token(json.load(open(os.path.expanduser(path))))

	have = existing(tok)
	if "--list" in args:
		print(f"{len(have)} products in Play")
		for pid, p in sorted(have.items()):
			opts = p.get("purchaseOptions", [])
			states = ",".join(o.get("state", "?") for o in opts) or "no purchase option"
			print(f"  {pid:44} {states}")
		return

	rows = [r for r in products() if not only or r[0] == only]
	if only and not rows:
		raise SystemExit(f"no product named {only!r} in iap_setup.py")
	print(f"{len(have)} of {len(products())} products already in Play\n")
	if not apply:
		print("dry run -- pass --apply to create them\n")

	for short, _ref, disp, desc, usd in rows:
		pid = PREFIX + short
		if pid in have:
			# A product created by a run that died before activating is still
			# DRAFT, and DRAFT is indistinguishable from absent to the game.
			# Finish it rather than reporting it as done.
			states = [o.get("state") for o in have[pid].get("purchaseOptions", [])]
			if "ACTIVE" in states:
				print(f"  exists               {pid:44} ${usd:>6}")
			elif apply:
				activate(tok, pid)
				print(f"  activated draft      {pid:44} ${usd:>6}")
			else:
				print(f"  would activate       {pid:44} ${usd:>6}  (state {states})")
			continue
		if not apply:
			print(f"  would create         {pid:44} ${usd:>6}  {disp!r}")
			continue
		create(tok, short, disp, desc, usd)

	print("\ndone" if apply else "\ndry run complete")


main()
