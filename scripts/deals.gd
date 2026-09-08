class_name Deals
extends RefCounted

# =============================================================================
#  THE DEAL CHAIN — a limited-time event that unlocks itself as you take it
# =============================================================================
#
# The one shape of event every top-grossing game in this genre runs and Loot
# Lagoon had no version of: a themed ladder of six rewards where TAKING ONE
# REVEALS THE NEXT. Coin Master runs it as "Happy Potion Hunt", Monopoly GO as
# its partner events, and the reason it works is not the rewards -- our shop
# already gives away more than this does -- it is the shape:
#
#   * A player who takes rung one has opened a loop, and an open loop is what
#     brings them back tonight rather than on Thursday.
#   * The next rung is always visible and always locked, so the reward the
#     player wants is one they can see and cannot have yet.
#   * A paid rung sits between two free ones. It is never the wall -- the chain
#     always continues past it for free -- so the offer is a shortcut through a
#     queue rather than a toll gate, which is the difference between a store
#     that converts and one that gets uninstalled.
#
# WHAT A RUNG IS. Six per chain, taken strictly in order:
#
#     {"spins": 40, "coins": 25000}          a free rung
#     {"pack": "to_squall"}                  a paid rung: the goods are the
#                                            pack's, the price is the pack's
#
# PAID RUNGS NAME AN EXISTING PRODUCT AND MUST KEEP DOING SO. Every price the
# game can charge has to be a product Apple and Google already know about --
# there are 25 of them and they went through review with build 111. A chain
# that invented its own price point would render a button that cannot be
# pressed on a real phone, and it would look completely fine on desktop, which
# is the worst possible failure mode. `verify()` below is the guard, and
# qa_flows calls it.
#
# COINS ARE IN ISLAND-1 UNITS, like every other coin figure in the game. The
# rung pays `_scaled()` of what is written here, so a chain taken on island 60
# is worth what island 60 is worth. Spins and cards are absolute -- a spin is a
# spin anywhere.

# How long a chain stays live, and how long the game goes quiet afterwards.
#
# 24 hours live is deliberate and it is the shortest number that works. The
# chain is six rungs deep and a player who only opens the game once a day has
# to be able to finish it in one sitting -- an event that expires mid-ladder
# teaches the player that starting one is a waste, which costs more than the
# event ever earned. The dark period is longer than the live one so that "an
# event is running" stays information rather than wallpaper.
const CHAIN_HOURS := 24.0
const CHAIN_DURATION := CHAIN_HOURS * 3600.0
const CHAIN_COOLDOWN := 30.0 * 3600.0

# The grand prize for clearing all six rungs, over and above the rungs
# themselves. Coins are island-1 units.
const FINALE := {"spins": 120, "coins": 90000, "cards": 2}

# The chains. Each is one themed run of six.
#
# The reward curve inside a chain climbs -- rung six is worth about four times
# rung one -- because the whole mechanic is a sunk-cost ladder and a ladder
# whose top rung is not obviously the prize has no reason to be climbed.
const CHAINS := [
	{
		"id": "tide_hunt",
		"name": "High Tide Hunt",
		"blurb": "Take each deal to reveal the next",
		"glyph": "moon",
		"hue": Color(0.325, 0.596, 0.902),
		"steps": [
			{"spins": 25},
			{"coins": 40000},
			{"pack": "to_squall"},
			{"spins": 60, "coins": 60000},
			{"pack": "to_tide"},
			{"spins": 110, "cards": 1},
		],
	},
	{
		"id": "lantern_run",
		"name": "Lantern Run",
		"blurb": "Take each deal to reveal the next",
		"glyph": "sun",
		"hue": Color(0.949, 0.588, 0.180),
		"steps": [
			{"coins": 30000},
			{"spins": 35},
			{"pack": "spins_m"},
			{"coins": 90000, "cards": 1},
			{"pack": "to_moon"},
			{"spins": 130, "coins": 140000},
		],
	},
	{
		"id": "kraken_watch",
		"name": "Kraken Watch",
		"blurb": "Take each deal to reveal the next",
		"glyph": "spark",
		"hue": Color(0.549, 0.353, 0.855),
		"steps": [
			{"spins": 30},
			{"coins": 45000, "shields": 1},
			{"pack": "bundle_s"},
			{"spins": 70},
			{"pack": "to_kraken"},
			{"spins": 150, "cards": 2},
		],
	},
	{
		"id": "reef_festival",
		"name": "Reef Festival",
		"blurb": "Take each deal to reveal the next",
		"glyph": "crown",
		"hue": Color(0.925, 0.278, 0.400),
		"steps": [
			{"coins": 35000},
			{"spins": 40},
			{"pack": "to_squall"},
			{"spins": 55, "shields": 1},
			{"pack": "spins_l"},
			{"coins": 200000, "cards": 2},
		],
	},
]

const STEPS := 6

static func by_id(id: String) -> Dictionary:
	for c in CHAINS:
		if String(c["id"]) == id:
			return c
	return {}

# The pack behind a paid rung, or an empty dictionary for a free one.
static func step_pack(step: Dictionary) -> Dictionary:
	var pid := String(step.get("pack", ""))
	if pid == "":
		return {}
	return CV.pack_by_id(pid)

static func is_paid(step: Dictionary) -> bool:
	return step.has("pack")

# What a rung actually pays out. A free rung is its own record; a paid rung
# pays whatever its pack pays, so the two can never drift apart.
static func step_reward(step: Dictionary) -> Dictionary:
	if is_paid(step):
		var p := step_pack(step)
		return {
			"spins": p.get("spins", 0),
			"coins": p.get("coins", 0),
			"cards": p.get("cards", 0),
			"tier": p.get("tier", 1),
			"guarantee5": p.get("guarantee5", false),
		}
	return step

# Every chain is well-formed: six rungs, at least one free rung after the last
# paid one, and every paid rung naming a product the stores already sell.
#
# THE "FREE RUNG AFTER THE LAST PAID ONE" RULE IS THE LOAD-BEARING ONE. A chain
# that ends on a purchase is a paywall wearing an event's clothes: the player
# who declines it is left staring at a locked grand prize they can never reach,
# which is the single fastest way to turn a retention mechanic into a
# one-star review. Every chain here ends on a free rung by construction and
# this is what keeps it that way.
static func verify() -> Array:
	var problems := []
	var seen := {}
	for c in CHAINS:
		var id := String(c["id"])
		if seen.has(id):
			problems.append("duplicate chain id: %s" % id)
		seen[id] = true
		var steps: Array = c["steps"]
		if steps.size() != STEPS:
			problems.append("%s: %d rungs, expected %d" % [id, steps.size(), STEPS])
		var last_paid := -1
		for i in steps.size():
			var s: Dictionary = steps[i]
			if not is_paid(s):
				if step_reward(s).is_empty():
					problems.append("%s rung %d: free and pays nothing" % [id, i + 1])
				continue
			last_paid = i
			var pid := String(s["pack"])
			if CV.pack_by_id(pid).is_empty():
				problems.append("%s rung %d: no such pack '%s'" % [id, i + 1, pid])
			elif not IAP.all_product_ids().has(IAP.product_id(CV.pack_by_id(pid))):
				problems.append("%s rung %d: '%s' is not a sold product" % [id, i + 1, pid])
		if last_paid == steps.size() - 1:
			problems.append("%s: ends on a paid rung -- the grand prize is unreachable" % id)
	return problems


# =============================================================================
#  THE POWER UP — one price, three columns, two of them free
# =============================================================================
#
# The other shape the reference stores all run: a takeover that shows THREE
# stacks of goods side by side, with a price under the middle one and FREE under
# the other two. Buying the middle hands over all three.
#
# It is worth being exact about what this is, because it would be easy to
# dismiss as a bundle with a bigger picture. Mechanically that is what it is:
# one product id, one charge, more goods than the pack alone. The reason it
# converts better than the same value sold as one card is that a player cannot
# price three columns against anything -- there is no shelf rate for "a pack
# plus two gifts" -- while a single card with a bigger number on it is compared
# straight back to the rung below it. The columns are the product.
#
# So the value has to be REAL, and it is: `bonus` below is paid on top of
# everything the pack already pays. A "1+2" whose two free columns were carved
# out of the pack's own contents would be a lie the player could work out with
# arithmetic, and the one thing a store cannot survive is being caught at that.
const POWERUP_HOURS := 12.0
const POWERUP_DURATION := POWERUP_HOURS * 3600.0
const POWERUP_COOLDOWN := 40.0 * 3600.0

# Coins are island-1 units, like everywhere else.
const POWERUPS := [
	{
		"id": "pu_deckhand",
		"name": "Perfect Power Up",
		"pack": "bundle_s",
		"bonus": [
			{"spins": 60, "coins": 50000},
			{"spins": 40, "cards": 1},
		],
	},
	{
		"id": "pu_quartermaster",
		"name": "Triple Haul",
		"pack": "bundle_m",
		"bonus": [
			{"spins": 200, "coins": 200000},
			{"spins": 150, "cards": 2, "shields": 1},
		],
	},
	{
		"id": "pu_squall",
		"name": "Storm Triple",
		"pack": "to_squall",
		"bonus": [
			{"spins": 50, "coins": 45000},
			{"spins": 35, "cards": 1},
		],
	},
]

static func powerup_by_id(id: String) -> Dictionary:
	for p in POWERUPS:
		if String(p["id"]) == id:
			return p
	return {}

# The three columns, left to right, as plain reward records. The PAID one is in
# the middle, which is not decoration: it is the column the eye lands on first,
# and putting a price there with FREE on both sides is the entire composition.
static func powerup_columns(pu: Dictionary) -> Array:
	var pack := CV.pack_by_id(String(pu["pack"]))
	var bonus: Array = pu["bonus"]
	return [
		{"reward": bonus[0], "paid": false},
		{"reward": {
			"spins": pack.get("spins", 0),
			"coins": pack.get("coins", 0),
			"cards": pack.get("cards", 0),
			"shields": pack.get("shields", 0),
		}, "paid": true, "pack": pack},
		{"reward": bonus[1], "paid": false},
	]

# --- the loyalty card --------------------------------------------------------
#
# The bar across the top of the reference's takeover is not a progress bar for
# the offer -- it counts PURCHASES, and it pays a chest every few. It survives
# the offer that showed it, which is what makes it a reason to buy the next one.
#
# Five is the number because it has to be reachable by a player who buys the
# small packs and still mean something to one who buys the big ones, and the
# reward is cards rather than currency for the same reason: cards are the one
# thing in this game that money buys and grinding does not reliably produce.
const LOYALTY_TARGET := 5
const LOYALTY_REWARD := {"cards": 3, "tier": 2, "spins": 60}

static func powerup_verify() -> Array:
	var problems := []
	var seen := {}
	for pu in POWERUPS:
		var id := String(pu["id"])
		if seen.has(id):
			problems.append("duplicate power-up id: %s" % id)
		seen[id] = true
		var pack := CV.pack_by_id(String(pu["pack"]))
		if pack.is_empty():
			problems.append("%s: no such pack '%s'" % [id, pu["pack"]])
		elif not IAP.all_product_ids().has(IAP.product_id(pack)):
			problems.append("%s: '%s' is not a sold product" % [id, pu["pack"]])
		if (pu["bonus"] as Array).size() != 2:
			problems.append("%s: needs exactly two free columns" % id)
		for b in pu["bonus"]:
			if (b as Dictionary).is_empty():
				problems.append("%s: a free column pays nothing" % id)
	return problems
