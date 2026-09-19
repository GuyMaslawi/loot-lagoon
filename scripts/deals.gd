class_name Deals
extends RefCounted

# =============================================================================
#  THE DEAL CHAIN IS GONE — removed 2026-09-19
# =============================================================================
#
# Six rungs, taken in order, each one revealing the next. Guy's call, off the
# build: *"this ladder is generally redundant -- get rid of it."* It is worth
# saying what it was so nobody rebuilds it by accident: it shared the events
# disc with the fair, it ran 24 hours in every 54, and its third rung was
# always a purchase.
#
# WHAT IT COST THE REST OF THE GAME while it existed, which is most of the
# argument for it being gone: it owned the events calendar. The fair could
# only run inside the chain's dark window, the teaser clock had to decide
# which of two events it was counting down to, and one receipt could credit
# both the chain and the 1+2 for a single purchase. The fair now has the disc
# and a clock of its own.
#
# The save still carries `deal_*` keys on every phone that ever ran a build
# before this one. They are simply not read -- see _load_game, which has never
# required a key to exist -- so there is no migration and nothing to clean up.

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
#  THE SOLO DEAL — one offer, one screen, one button
# =============================================================================
#
# Guy, 2026-09-13: the deals wanted to be SEVERAL SHAPES, and the third is "a
# big deal on its own, where the icons are big and prominent and there is one
# big buy button".
#
# It is worth saying why that is a third mechanic rather than a smaller version
# of the other two, because on a spreadsheet all three are "a pack with extra
# in it" and only one of them would then deserve to exist.
#
#   THE CHAIN IS A QUEUE.  One rung is live, the next is locked, and its whole
#   pull is that the thing you want is visible and not yet yours. It asks for a
#   sitting.
#
#   THE 1+2 IS A COMPARISON.  Three columns, a price under one of them and FREE
#   under the other two. Its pull is that there is nothing to price it against.
#   It asks for a look.
#
#   THE SOLO IS A CLAIM.  One heap of goods, one number saying what it is worth,
#   one button. Nothing to choose, nothing to read, nothing locked. It asks for
#   ten seconds, which is the only budget most sessions have -- and it is the
#   shape the reference stores put in front of a player who has just run out of
#   spins, because at that moment a ladder is an obstacle and a grid is work.
#
# WHAT MAKES IT HONEST IS THE MULTIPLE, AND THE MULTIPLE IS MEASURED. The badge
# on the burst does not say "MEGA" and hope; it says how many times the shop's
# own entry rung would charge for the same goods, computed by `worth_usd` from
# the three price ladders that are actually on the shelf. It is rounded DOWN and
# `solo_verify` refuses a deal that cannot reach x3, so the number on the screen
# is a floor rather than a boast. A store that is caught rounding its own
# discount up is a store that does not get a second purchase.
#
# THE CONTENTS UNDERCUT THE SHELF ON PURPOSE, and the calendar is what keeps
# that from eating the shop: the solo runs for SOLO_HOURS inside the 1+2's dark
# window (see SOLO_GAP in main.gd), which is about eight hours in thirty-six.
# A deal that is always available is a price list, and a price list that
# undercuts the shelf by half is just a cheaper shelf.

# The entry rung of the chest ladder: two cards for $0.99. The spin and coin
# ladders keep their own base rates in CV, and this is the third -- a mixed heap
# cannot be valued without one, and picking a number by feel is exactly what the
# rest of this file refuses to do with prices.
const CARD_BASE_RATE := 2.0 / 0.99

# What a heap of goods would cost, in dollars, bought at the cheapest rung of
# each of the shop's own ladders.
#
# SHIELDS COUNT AS NOTHING, because no product in the store sells one and a
# price invented here would be a price nobody can check. That makes every
# multiple computed from this an UNDERSTATEMENT, which is the safe direction for
# a number printed next to a price.
static func worth_usd(reward: Dictionary) -> float:
	var usd := 0.0
	if int(reward.get("spins", 0)) > 0:
		usd += float(reward["spins"]) / CV.SPIN_BASE_RATE
	if int(reward.get("coins", 0)) > 0:
		usd += float(reward["coins"]) / CV.COIN_BASE_RATE
	if int(reward.get("cards", 0)) > 0:
		usd += float(reward["cards"]) / CARD_BASE_RATE
	return usd

# Eight hours, which is shorter than either of the other two events and is meant
# to be: the solo has nothing to come back for. A chain rewards a second visit
# because there is another rung; the fair rewards one because the stalls
# restock. This is one button, so the only thing its clock can do is say how
# long the player has to press it, and a clock that says "tomorrow" says
# "later".
const SOLO_HOURS := 8.0
const SOLO_DURATION := SOLO_HOURS * 3600.0

# The deals. One pack each, plus a bonus paid on top of everything the pack
# already pays -- never carved out of it, for the same reason the 1+2's two free
# columns are real: a discount the player can disprove with arithmetic is worse
# than no discount.
#
# Three price points, and the multiple CLIMBS with the price (x5, x6, x7) for
# the same reason the shop's ladders do: the small rung exists to be compared
# against, and the revenue lives above it.
const SOLOS := [
	{
		"id": "so_squall",
		"name": "Squall Hoard",
		"tag": "SPECIAL  DEAL",
		"blurb": "Everything in the Squall Bundle, and the same again free",
		"pack": "to_squall",
		"chest": "chest_t0",
		"hue": Color(0.325, 0.596, 0.902),
		"bonus": {"spins": 90, "coins": 90000, "cards": 1},
	},
	{
		"id": "so_moon",
		"name": "Moonlit Hoard",
		"tag": "MEGA  DEAL",
		"blurb": "One press, and the whole hoard is yours",
		"pack": "to_moon",
		"chest": "chest_t1",
		"hue": Color(0.949, 0.588, 0.180),
		# NO SHIELD, AND THAT IS A RULE ABOUT THE SCREEN RATHER THAN ABOUT THE
		# VALUE. The solo draws three kinds of goods at 128 units each and a
		# fourth will not fit at a size worth drawing -- so a shield in here is
		# something the player pays for and never sees advertised, which is
		# value thrown away. Anything that cannot go on the stage does not go in
		# the box.
		"bonus": {"spins": 200, "coins": 280000, "cards": 1},
	},
	{
		"id": "so_kraken",
		"name": "Kraken's Hoard",
		"tag": "BIGGEST  DEAL",
		"blurb": "The largest haul the lagoon has ever floated",
		"pack": "to_kraken",
		"chest": "chest_t2",
		"hue": Color(0.549, 0.353, 0.855),
		"bonus": {"spins": 320, "coins": 500000, "cards": 3},
	},
]

static func solo_by_id(id: String) -> Dictionary:
	for s in SOLOS:
		if String(s["id"]) == id:
			return s
	return {}

static func solo_pack(solo: Dictionary) -> Dictionary:
	return CV.pack_by_id(String(solo.get("pack", "")))

# The bonus alone -- what the pack does NOT already pay. This is what
# _solo_credit_purchase hands over once the pack itself has been granted, so it
# is the one place that decides what "on top" means.
static func solo_bonus(solo: Dictionary) -> Dictionary:
	return solo.get("bonus", {})

# Everything the button buys, pack and bonus in one record. This is what the
# screen draws, and it is built rather than written down so the two halves can
# never disagree about what is in the box.
static func solo_total(solo: Dictionary) -> Dictionary:
	var pack := solo_pack(solo)
	var bonus: Dictionary = solo_bonus(solo)
	var out := {}
	for key in ["spins", "coins", "cards", "shields"]:
		var n := int(pack.get(key, 0)) + int(bonus.get(key, 0))
		if n > 0:
			out[key] = n
	# The cards come out of the PACK's chest, at the pack's tier and with the
	# pack's guarantee -- the bonus cards are drawn the same way (see
	# _solo_credit_purchase), so one tier describes the whole heap.
	out["tier"] = int(pack.get("tier", 1))
	out["guarantee5"] = bool(pack.get("guarantee5", false))
	return out

# How many times over the shop's entry rungs would charge for the same goods.
# Rounded DOWN, and never printed below 2 -- see the note on worth_usd.
static func solo_multiple(solo: Dictionary) -> int:
	var usd := CV.price_usd(solo_pack(solo))
	if usd <= 0.0:
		return 0
	return int(floor(worth_usd(solo_total(solo)) / usd))

static func solo_verify() -> Array:
	var problems := []
	var seen := {}
	for solo in SOLOS:
		var id := String(solo["id"])
		if seen.has(id):
			problems.append("duplicate solo id: %s" % id)
		seen[id] = true
		var pack := solo_pack(solo)
		# The same rule every price in this game obeys: it has to name a product
		# Apple and Google already sell. See verify().
		if pack.is_empty():
			problems.append("%s: no such pack '%s'" % [id, solo.get("pack", "")])
			continue
		if not IAP.all_product_ids().has(IAP.product_id(pack)):
			problems.append("%s: '%s' is not a sold product" % [id, solo["pack"]])
		if (solo_bonus(solo) as Dictionary).is_empty():
			problems.append("%s: nothing is paid on top of the pack" % id)
		# THE NUMBER ON THE BURST IS THE WHOLE PITCH, and a solo that cannot
		# reach x3 is selling the shelf rate with bunting on it -- the top of
		# the standing shop already runs about x4 on its own.
		var mult := solo_multiple(solo)
		if mult < 3:
			problems.append("%s: worth only x%d -- the shelf already beats that"
				% [id, mult])
		# A solo whose cards are randomized needs the pack to say what tier they
		# are drawn at, or the odds door on the screen opens onto the wrong
		# table.
		if int(solo_total(solo).get("cards", 0)) > 0 and not pack.has("tier"):
			problems.append("%s: pays cards but its pack names no chest tier" % id)
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
