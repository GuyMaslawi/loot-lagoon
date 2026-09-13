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
#
# HOW OFTEN IT COMES ROUND. Twelve hours live is the offer itself; the dark
# window is how often a player meets one at all, and forty hours was too long
# by a wide margin. Twelve in fifty-two is under a quarter of the time, and the
# takeover only fires at the start of a session -- so a player who opens the
# game twice a day could honestly go a week without the feature existing for
# them, which is what Guy reported on 2026-09-13 ("I still don't see the trio
# deal"). At twenty the offer is live better than a third of the time and every
# player meets one most days, which is the least this can be and still be a
# thing the game HAS. It is still a minority of the clock, which is the part
# that matters: an offer that is always on is a price list.
const POWERUP_HOURS := 12.0
const POWERUP_DURATION := POWERUP_HOURS * 3600.0
const POWERUP_COOLDOWN := 20.0 * 3600.0

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

# =============================================================================
#  THE FAIR — nine one-off deals, taken in any order, on a points board
# =============================================================================
#
# Guy, 2026-09-13, pointing back at the reference shots he sent on the 7th:
# "I did not see you add any new promo deals." The one deals screen in that set
# with no counterpart here is the celebration event — nine rewards in a grid
# under a bar reading "Rewards Collected 0/9", with four prizes strung along it
# and a grand prize on the end.
#
# WHY IT IS NOT JUST A LONGER CHAIN, which is the trap this design had to get
# past. The chain is a QUEUE: one rung is live, the next is locked, and the
# whole of its pull is that the thing you want is visible and not yet yours.
# Nine of those would be the same feeling held for longer, and the game would
# have two events that feel identical with different bunting.
#
# So the fair is a MARKET. Every stall is open, nothing is locked behind the
# stall next to it, and the player chooses which to spend their turn on. What
# paces it is not an order, it is a RESTOCK: take a free deal and the free half
# of the fair shuts for two hours. That is a different loop on purpose — the
# chain wants one long sitting, the fair wants six short visits — and it is the
# one shape that turns a day-long event into a reason to open the game at
# lunch. The paid stalls never shut, because a queue in front of a till is a
# sale the store did not make.
#
# THE POINTS BOARD IS WHAT MAKES A GRID AN EVENT. Nine unrelated deals is a
# shop shelf. The same nine, each worth points toward four prizes and a grand
# one, is a board the player is trying to finish — and it is the half that
# gives the paid stalls a reason to exist that is not "spend money": a purchase
# is worth several free stalls of points, so it moves the board, and the board
# is reachable without it.
#
# THAT LAST CLAUSE IS THE RULE, and `fair_verify()` enforces it: THE GRAND
# PRIZE'S THRESHOLD MUST BE REACHABLE ON THE FREE STALLS ALONE. A board whose
# top prize needs a purchase is a paywall with bunting on it, which is the same
# thing `verify()` refuses to let a chain become by ending one on a paid rung.

const FAIR_HOURS := 24.0
const FAIR_DURATION := FAIR_HOURS * 3600.0
# How long the free half of the fair shuts for after a free stall is taken.
# Two hours, so a player who opens the game morning, lunch and evening walks
# away with three of them and the whole board is a day's worth of visits rather
# than a single sitting's worth of tapping.
const FAIR_RESTOCK := 2.0 * 3600.0
const FAIR_SLOTS := 9

# The fairs. Nine stalls each: six free, three sold.
#
# The reward scale is deliberately UNDER the chain's. The fair runs inside the
# chain's own dark window (see the calendar in main.gd), so the two of them
# together roughly double how much of the week has an event running on it —
# and every free spin in this game is measured somewhere else, most sharply by
# the tournament margin qa_full checks. A second event is worth having because
# it gives the calendar a second rhythm, not because the game needed to pay out
# more.
const FAIRS := [
	{
		"id": "harbour_fair",
		"name": "Harbour Fair",
		"blurb": "Nine stalls — take them in any order",
		"glyph": "crown",
		"hue": Color(0.925, 0.278, 0.400),
		"deals": [
			{"spins": 20, "pts": 40},
			{"coins": 25000, "pts": 40},
			{"pack": "to_squall", "pts": 150},
			{"spins": 30, "pts": 55},
			{"coins": 35000, "pts": 55},
			{"pack": "bundle_s", "pts": 200},
			{"spins": 40, "shields": 1, "pts": 70},
			{"coins": 40000, "cards": 1, "pts": 70},
			{"pack": "to_tide", "pts": 260},
		],
		"miles": [
			{"at": 80,  "spins": 25},
			{"at": 170, "coins": 30000},
			{"at": 260, "spins": 40, "cards": 1},
			{"at": 330, "spins": 90, "coins": 70000, "cards": 1},
		],
	},
	{
		"id": "lantern_fair",
		"name": "Lantern Market",
		"blurb": "Nine stalls — take them in any order",
		"glyph": "sun",
		"hue": Color(0.949, 0.588, 0.180),
		"deals": [
			{"coins": 22000, "pts": 40},
			{"spins": 22, "pts": 40},
			{"pack": "spins_m", "pts": 150},
			{"coins": 32000, "pts": 55},
			{"spins": 32, "pts": 55},
			{"pack": "to_moon", "pts": 220},
			{"coins": 38000, "shields": 1, "pts": 70},
			{"spins": 45, "cards": 1, "pts": 70},
			{"pack": "bundle_m", "pts": 260},
		],
		"miles": [
			{"at": 80,  "coins": 28000},
			{"at": 170, "spins": 35},
			{"at": 260, "coins": 55000, "cards": 1},
			{"at": 330, "spins": 85, "coins": 75000, "cards": 1},
		],
	},
]

static func fair_by_id(id: String) -> Dictionary:
	for f in FAIRS:
		if String(f["id"]) == id:
			return f
	return {}

# A stall's goods. Paid stalls pay through _grant_pack like every other
# purchase, so this answers empty for them -- the pack is the single source of
# what a pack is worth, bought from a shelf or from a stall.
static func fair_reward(deal: Dictionary) -> Dictionary:
	var out := {}
	for key in ["spins", "coins", "cards", "shields", "tier"]:
		if deal.has(key):
			out[key] = deal[key]
	return out

static func fair_pack(deal: Dictionary) -> Dictionary:
	var pid := String(deal.get("pack", ""))
	if pid == "":
		return {}
	return CV.pack_by_id(pid)

static func fair_free_points(fair: Dictionary) -> int:
	var total := 0
	for d in fair["deals"]:
		if String((d as Dictionary).get("pack", "")) == "":
			total += int((d as Dictionary)["pts"])
	return total

static func fair_verify() -> Array:
	var problems := []
	var seen := {}
	for fair in FAIRS:
		var id := String(fair["id"])
		if seen.has(id):
			problems.append("duplicate fair id: %s" % id)
		seen[id] = true
		var deals: Array = fair["deals"]
		if deals.size() != FAIR_SLOTS:
			problems.append("%s: %d stalls, wants %d" % [id, deals.size(), FAIR_SLOTS])
		var free_n := 0
		for d in deals:
			var deal: Dictionary = d
			if int(deal.get("pts", 0)) <= 0:
				problems.append("%s: a stall is worth no points" % id)
			var pid := String(deal.get("pack", ""))
			if pid == "":
				free_n += 1
				if fair_reward(deal).is_empty():
					problems.append("%s: a free stall pays nothing" % id)
				continue
			# The same rule every price in this game obeys: it has to name a
			# product Apple and Google already sell. See verify().
			var pack := CV.pack_by_id(pid)
			if pack.is_empty():
				problems.append("%s: no such pack '%s'" % [id, pid])
			elif not IAP.all_product_ids().has(IAP.product_id(pack)):
				problems.append("%s: '%s' is not a sold product" % [id, pid])
		if free_n < 5:
			problems.append("%s: only %d free stalls" % [id, free_n])
		var miles: Array = fair["miles"]
		if miles.size() < 2:
			problems.append("%s: needs a board with prizes on it" % id)
		var last := 0
		for m in miles:
			var at := int((m as Dictionary)["at"])
			if at <= last:
				problems.append("%s: milestone %d does not climb" % [id, at])
			last = at
		# THE RULE. The grand prize has to be reachable without paying for it.
		if last > fair_free_points(fair):
			problems.append("%s: grand prize at %d needs more than the %d free points"
				% [id, last, fair_free_points(fair)])
	return problems

# =============================================================================
#  THE VOYAGE — seven days, three goals a day, one board
# =============================================================================
#
# The last of the reference screens with no counterpart here: a limited board
# of tasks with a prize bar over it and a row of day ribbons under it, running
# for one week and then gone.
#
# WHAT IT ADDS THAT THE MISSION BOARD DOES NOT, because on paper they are the
# same object and if they really were this should not exist. Missions REPEAT:
# the daily board rolls at midnight whatever you did with it, which makes it a
# routine, and a routine is something a player does while they are already
# here. The voyage has a DEADLINE and a bar that only fills forwards -- what
# you miss on Tuesday is gone, and Thursday's prize is further away because of
# it. That is the difference between "something to do while I am playing" and
# "a reason to open the game today", and it is the strongest retention shape
# this genre has after the daily bonus itself.
#
# THREE GOALS A DAY, NOT FIVE OR EIGHT. Guy, 2026-09-13: "do not put too much
# information on it." The mission board already carries eight rows and it is a
# page you go to; this is a dialog you check, and a dialog with twenty-one
# things on it is a spreadsheet. Only TODAY's three are ever on screen.
#
# THE GOALS ARE WRITTEN IN THE COUNTERS THE MISSIONS ALREADY KEEP -- `spins`,
# `builds`, `cards` and the rest go through `_mission_add`, so the voyage hooks
# one function and cannot drift out of step with what the game actually counts.
# Anything a player does for one board counts for the other, which is also the
# honest reading: they did the thing.

const VOYAGE_DAYS := 7
const VOYAGE_DAY := 24.0 * 3600.0
const VOYAGE_DURATION := float(VOYAGE_DAYS) * VOYAGE_DAY
# Three days dark. Long enough that a voyage ending is felt, short enough that
# a player who missed most of one gets another chance inside a week.
const VOYAGE_COOLDOWN := 3.0 * 24.0 * 3600.0

# Seven days of three. Targets climb, and so do the stamps a goal is worth --
# day seven has to be worth coming back for after six.
#
# Coins are island-1 units like everywhere else. The per-goal rewards are
# deliberately small: the BAR is the prize, and a board whose rows pay as well
# as its bar does is one the player can ignore the bar on.
const VOYAGE_GOALS := [
	[	{"id": "spins",      "target": 20,    "stamps": 10, "coins": 1200},
		{"id": "daily_gift", "target": 1,     "stamps": 10, "spins": 8},
		{"id": "builds",     "target": 1,     "stamps": 10, "coins": 1500}],
	[	{"id": "spins",      "target": 30,    "stamps": 12, "coins": 1600},
		{"id": "cards",      "target": 2,     "stamps": 12, "coins": 1800},
		{"id": "attacks",    "target": 2,     "stamps": 12, "coins": 1700}],
	[	{"id": "spins",      "target": 40,    "stamps": 14, "coins": 2000},
		{"id": "builds",     "target": 3,     "stamps": 14, "coins": 2300},
		{"id": "steals",     "target": 2,     "stamps": 14, "spins": 10}],
	[	{"id": "spins",      "target": 50,    "stamps": 16, "coins": 2400},
		{"id": "cards",      "target": 3,     "stamps": 16, "coins": 2700},
		{"id": "coins_won",  "target": 40000, "stamps": 16, "spins": 12}],
	[	{"id": "spins",      "target": 60,    "stamps": 18, "coins": 2900},
		{"id": "builds",     "target": 4,     "stamps": 18, "coins": 3200},
		{"id": "attacks",    "target": 4,     "stamps": 18, "spins": 14}],
	[	{"id": "spins",      "target": 70,    "stamps": 20, "coins": 3400},
		{"id": "cards",      "target": 4,     "stamps": 20, "coins": 3800},
		{"id": "steals",     "target": 4,     "stamps": 20, "spins": 16}],
	[	{"id": "spins",      "target": 90,    "stamps": 24, "coins": 4200},
		{"id": "builds",     "target": 5,     "stamps": 24, "coins": 4600},
		{"id": "cards",      "target": 5,     "stamps": 24, "spins": 20}],
]

# What the bar pays. The last one is the voyage, and it is a chest of cards
# because cards are the one thing in this game that money buys and grinding
# does not reliably produce -- which is what makes a free one worth a week.
#
# 260 OF A POSSIBLE 336, and the gap is the design. Every goal cleared is 336
# stamps, so the grand prize survives a whole day missed -- a board that
# punishes one busy Tuesday with "you cannot reach the top any more" is a board
# nobody opens on Wednesday.
const VOYAGE_MILES := [
	{"at": 70,  "spins": 40},
	{"at": 130, "coins": 60000},
	{"at": 195, "spins": 60, "cards": 1},
	{"at": 260, "spins": 150, "coins": 150000, "cards": 3, "tier": 2},
]

static func voyage_day_goals(day: int) -> Array:
	if day < 0 or day >= VOYAGE_GOALS.size():
		return []
	return VOYAGE_GOALS[day]

static func voyage_total_stamps() -> int:
	var total := 0
	for day in VOYAGE_GOALS:
		for g in day:
			total += int((g as Dictionary)["stamps"])
	return total

static func voyage_reward(entry: Dictionary) -> Dictionary:
	var out := {}
	for key in ["spins", "coins", "cards", "shields", "tier"]:
		if entry.has(key):
			out[key] = entry[key]
	return out

static func voyage_verify() -> Array:
	var problems := []
	if VOYAGE_GOALS.size() != VOYAGE_DAYS:
		problems.append("the voyage has %d days of goals, wants %d"
			% [VOYAGE_GOALS.size(), VOYAGE_DAYS])
	for d in VOYAGE_GOALS.size():
		var day: Array = VOYAGE_GOALS[d]
		if day.size() != 3:
			problems.append("day %d has %d goals, wants 3" % [d + 1, day.size()])
		var seen := {}
		for g in day:
			var goal: Dictionary = g
			var id := String(goal["id"])
			# TWO GOALS OF THE SAME KIND ON ONE DAY WOULD SHARE A COUNTER and
			# so complete together, which reads as the board paying twice for
			# one action.
			if seen.has(id):
				problems.append("day %d counts '%s' twice" % [d + 1, id])
			seen[id] = true
			if int(goal.get("target", 0)) <= 0:
				problems.append("day %d: '%s' has no target" % [d + 1, id])
			if int(goal.get("stamps", 0)) <= 0:
				problems.append("day %d: '%s' is worth no stamps" % [d + 1, id])
			if voyage_reward(goal).is_empty():
				problems.append("day %d: '%s' pays nothing" % [d + 1, id])
	var last := 0
	for m in VOYAGE_MILES:
		var at := int((m as Dictionary)["at"])
		if at <= last:
			problems.append("the bar's %d does not climb" % at)
		last = at
		if voyage_reward(m).is_empty():
			problems.append("the bar's %d pays nothing" % at)
	# The grand prize has to survive a missed day, or the board dies on the
	# first one a player has no time for.
	var worst_day := 0
	for day in VOYAGE_GOALS:
		var sum := 0
		for g in day:
			sum += int((g as Dictionary)["stamps"])
		worst_day = maxi(worst_day, sum)
	if last > voyage_total_stamps() - worst_day:
		problems.append("the grand prize at %d cannot survive a missed day (%d of %d)"
			% [last, worst_day, voyage_total_stamps()])
	return problems
