"""Create Loot Lagoon's in-app purchases in App Store Connect.

Run it as often as you like: it reads what already exists and only fills in
what is missing. That matters more here than usual, because a product id can
never be deleted or reused once created -- a script that had to be run exactly
once would be a trap.

    export ASC_KEY_ID=... ASC_ISSUER_ID=...
    python3 tools/iap_setup.py            # show what would change
    python3 tools/iap_setup.py --apply    # make the changes

Apple also demands a screenshot of where each purchase is sold before it will
review one. Produce a fresh one straight from the game and hand it over:

    SHOT=shop godot --resolution 720x1280
    python3 tools/iap_setup.py --apply \
      --screenshot="$HOME/Library/Application Support/Godot/app_userdata/Loot Lagoon/shot_shop.png"

It is not kept in the repo on purpose: a stale picture of an old shop is worse
than no picture, and regenerating it costs one command.

The display name and description below are what a player sees in the App
Store's own purchase sheet, so they are written for that context rather than
lifted from cv.gd -- and Apple caps them at 30 and 45 characters. Coin packs
deliberately quote no number: the amount granted scales with island level, and
a fixed figure in the store would be wrong for most players.
"""

import hashlib
import os
import sys
import urllib.request

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import asc  # noqa: E402

APP_ID = "6803260415"
PREFIX = "com.guymaslawi.lootlagoon."

# short id, reference name, display name, description, USD price, where to find it
PRODUCTS = [
	("starter",    "First Timer Pack",     "First Timer Pack",     "60 spins, coins and a Golden Chest.",  "1.99",  "SHOP page, top offer. One per account."),
	("piggy",      "Piggy Bank",           "Piggy Bank",           "Break it open for every coin you banked.", "3.99", "SHOP page, Piggy Bank card. Fills as you play."),
	("chest_w",    "Wooden Chest",         "Wooden Chest",         "2 collectible cards for your album.",   "0.99",  "SHOP page, Chests row."),
	("chest_g",    "Golden Chest",         "Golden Chest",         "4 cards with better star odds.",        "2.99",  "SHOP page, Chests row."),
	("chest_m",    "Magical Chest",        "Magical Chest",        "6 cards, one 5-star guaranteed.",       "6.99",  "SHOP page, Chests row."),
	("spins_s",    "Spins - Breeze",       "Breeze",               "30 spins for the slot machine.",        "0.99",  "SHOP page, Spins grid."),
	("spins_m",    "Spins - Storm",        "Storm",                "80 spins for the slot machine.",        "1.99",  "SHOP page, Spins grid."),
	("spins_l",    "Spins - Cyclone",      "Cyclone",              "200 spins for the slot machine.",       "3.99",  "SHOP page, Spins grid."),
	("spins_xl",   "Spins - Hurricane",    "Hurricane",            "450 spins for the slot machine.",       "7.99",  "SHOP page, Spins grid."),
	("spins_2xl",  "Spins - Monsoon",      "Monsoon",              "1,200 spins for the slot machine.",     "19.99", "SHOP page, Spins grid."),
	("spins_3xl",  "Spins - Maelstrom",    "Maelstrom",            "3,400 spins for the slot machine.",     "49.99", "SHOP page, Spins grid."),
	("spins_4xl",  "Spins - Leviathan",    "Leviathan",            "7,500 spins for the slot machine.",     "99.99", "SHOP page, Spins grid."),
	("coins_s",    "Coins - Sack",         "Sack of Coins",        "A sack of coins for building.",         "0.99",  "SHOP page, Coins grid."),
	("coins_m",    "Coins - Wagon",        "Wagon of Coins",       "A wagon of coins for building.",        "2.99",  "SHOP page, Coins grid."),
	("coins_l",    "Coins - Galleon",      "Galleon of Coins",     "A galleon of coins for building.",      "9.99",  "SHOP page, Coins grid."),
	("coins_xl",   "Coins - Reef",         "Reef of Coins",        "A reef of coins for building.",         "24.99", "SHOP page, Coins grid."),
	("coins_2xl",  "Coins - Trench",       "Trench of Coins",      "A trench of coins for building.",       "59.99", "SHOP page, Coins grid."),
	("coins_3xl",  "Coins - Sunken City",  "Sunken City",          "A sunken city of coins for building.",  "99.99", "SHOP page, Coins grid."),
	("bundle_s",   "Bundle - Deckhand",    "Deckhand's Haul",      "150 spins, coins and 2 cards.",         "4.99",  "SHOP page, Bundles row."),
	("bundle_m",   "Bundle - Quartermaster", "Quartermaster's Haul", "700 spins, coins and 5 cards.",       "19.99", "SHOP page, Bundles row."),
	("bundle_l",   "Bundle - Captain",     "Captain's Hoard",      "2,000 spins, coins and 12 cards.",      "49.99", "SHOP page, Bundles row."),
	("to_squall",  "Offer - Squall",       "Squall Bundle",        "150 spins, coins and 1 card.",          "2.99",  "SHOP page, timed offer. Rotates every few hours."),
	("to_tide",    "Offer - High Tide",    "High Tide Chest",      "120 spins, coins and 3 cards.",         "4.99",  "SHOP page, timed offer. Rotates every few hours."),
	("to_moon",    "Offer - Moonlit Raid", "Moonlit Raid Pack",    "260 spins, coins and 2 cards.",         "6.99",  "SHOP page, timed offer. Rotates every few hours."),
	("to_kraken",  "Offer - Kraken",       "Kraken's Cut",         "400 spins, coins and 4 cards.",         "9.99",  "SHOP page, timed offer. Rotates every few hours."),
]

V1 = "https://api.appstoreconnect.apple.com/v1"
V2 = "https://api.appstoreconnect.apple.com/v2"

APPLY = "--apply" in sys.argv
SHOT = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--screenshot=")), "")


def ensure_product(short, ref_name, product_id, review_note, existing):
	if product_id in existing:
		return existing[product_id]
	print(f"  create   {product_id}")
	if not APPLY:
		return None
	r = asc.call("POST", f"{V2}/inAppPurchases", {"data": {
		"type": "inAppPurchases",
		"attributes": {"name": ref_name, "productId": product_id,
			"inAppPurchaseType": "CONSUMABLE", "familySharable": False,
			"reviewNote": review_note},
		"relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
	return r["data"]["id"]


def ensure_localization(iap_id, name, description):
	locs = asc.paged(f"{V2}/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
	if any(l["attributes"].get("locale") == "en-US" for l in locs):
		return False
	print("    + localization")
	if APPLY:
		asc.call("POST", f"{V1}/inAppPurchaseLocalizations", {"data": {
			"type": "inAppPurchaseLocalizations",
			"attributes": {"locale": "en-US", "name": name, "description": description},
			"relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})
	return True


def ensure_price(iap_id, usd):
	try:
		sched = asc.call("GET", f"{V2}/inAppPurchases/{iap_id}/iapPriceSchedule")
		if sched.get("data"):
			return False
	except SystemExit:
		pass  # no schedule yet -- Apple 404s rather than returning an empty one
	print(f"    + price ${usd}")
	if not APPLY:
		return True
	points = asc.paged(f"{V2}/inAppPurchases/{iap_id}/pricePoints", **{"filter[territory]": "USA"})
	match = [p for p in points if p["attributes"]["customerPrice"] == usd]
	if not match:
		raise SystemExit(f"no USA price point at ${usd}")
	asc.call("POST", f"{V1}/inAppPurchasePriceSchedules", {
		"data": {"type": "inAppPurchasePriceSchedules", "relationships": {
			"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
			"baseTerritory": {"data": {"type": "territories", "id": "USA"}},
			"manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p}"}]}}},
		"included": [{"type": "inAppPurchasePrices", "id": "${p}",
			"attributes": {"startDate": None},
			"relationships": {"inAppPurchasePricePoint": {
				"data": {"type": "inAppPurchasePricePoints", "id": match[0]["id"]}}}}]})
	return True


def ensure_screenshot(iap_id, path):
	"""Apple will not let a purchase leave MISSING_METADATA without one.

	The same image is fine for all 25 -- it only has to show a reviewer where in
	the app the thing is sold, and every one of these is sold on the shop page.
	Uploading is three steps: reserve a slot and get a one-time URL, PUT the
	bytes at it, then confirm with a checksum so Apple can tell the upload did
	not truncate.
	"""
	# A to-one relationship, so this is a plain GET -- paged() would attach a
	# limit, which Apple rejects outright on this endpoint.
	try:
		if asc.call("GET", f"{V2}/inAppPurchases/{iap_id}/appStoreReviewScreenshot").get("data"):
			return False
	except SystemExit:
		pass  # 404 when there is none yet
	print("    + review screenshot")
	if not APPLY:
		return True
	blob = open(path, "rb").read()
	made = asc.call("POST", f"{V1}/inAppPurchaseAppStoreReviewScreenshots", {"data": {
		"type": "inAppPurchaseAppStoreReviewScreenshots",
		"attributes": {"fileSize": len(blob), "fileName": os.path.basename(path)},
		"relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})
	shot_id = made["data"]["id"]
	for op in made["data"]["attributes"]["uploadOperations"]:
		chunk = blob[op["offset"]: op["offset"] + op["length"]]
		req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
		for h in op["requestHeaders"]:
			req.add_header(h["name"], h["value"])
		urllib.request.urlopen(req).read()
	asc.call("PATCH", f"{V1}/inAppPurchaseAppStoreReviewScreenshots/{shot_id}", {"data": {
		"type": "inAppPurchaseAppStoreReviewScreenshots", "id": shot_id,
		"attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
	return True


def main():
	if not APPLY:
		print("dry run -- pass --apply to make changes\n")
	existing = {i["attributes"]["productId"]: i["id"]
		for i in asc.paged(f"/apps/{APP_ID}/inAppPurchasesV2")}
	print(f"{len(existing)} of {len(PRODUCTS)} products already exist\n")
	for short, ref, disp, desc, usd, note in PRODUCTS:
		assert len(disp) <= 30, f"{short}: display name over 30 chars"
		assert len(desc) <= 45, f"{short}: description over 45 chars"
		pid = PREFIX + short
		print(f"{pid}")
		iap_id = ensure_product(short, ref, pid, note, existing)
		if iap_id is None:
			continue
		ensure_localization(iap_id, disp, desc)
		ensure_price(iap_id, usd)
		if SHOT:
			ensure_screenshot(iap_id, SHOT)
	print("\ndone" if APPLY else "\ndry run complete")


main()
