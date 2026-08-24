extends Control

const SAVE_PATH := "user://coinvillage_save.json"
# Scratch file and previous-good copy. See _write_save.
const SAVE_TMP := "user://coinvillage_save.json.tmp"
const SAVE_BAK := "user://coinvillage_save.json.bak"
const SPIN_CAP := 50
# The furthest the island counter is allowed to go. Nothing in the art needs a
# ceiling -- themes, palettes and building textures all wrap with % -- and the
# economy stops compounding at CV.ECONOMY_MAX_LEVEL, so this is only here to
# keep the number itself finite and to give the save loader something honest to
# clamp against.
const MAX_ISLAND := 999
const SPIN_REGEN_SECS := 120.0
const SPIN_REGEN_AMOUNT := 3
const STAR_COSTS := [400, 900, 2000, 4500, 9000]

var coins := 1500
var spins := 30
var shields := 0
var island_level := 1

# =============================================================================
#  Stars
# =============================================================================
#
# The one number in the game that is not spent on a slot machine. Coins are
# income and spins are fuel -- both churn, both are back to roughly where they
# were an hour later, and neither says anything about how far a player has
# actually got. Stars only ever come from something that stays built:
#
#   * a hut, once per upgrade, worth the level it just reached -- so a hut
#     taken from nothing to 5⭐ has paid 1+2+3+4+5 = 15, and a finished
#     island is 75
#   * a card, the first time you own it, worth its own rarity
#   * a duplicate card, melted down for what its rarity was worth
#
# The first three of those pay into two counters at once, and the split is the
# whole design:
#
#   * `rank_stars` is what you have earned, ever. It is the number in the top
#     bar and the number the leaderboard sorts on, and nothing in the game
#     subtracts from it. A standing you can lose by playing is not a standing,
#     it is a balance wearing a trophy -- and the board used to do exactly
#     that, dropping you places for opening a box you had earned.
#   * `stars` is the spendable half, and it buys exactly one thing: the card
#     boxes. It lives on the boxes page, where spending happens, and nowhere
#     else.
#
# Melting a duplicate tops up `stars` only. The card was already counted for
# rank the first time it was owned, and a spare is a second copy of a thing
# you have, not a second thing.
var stars := 0
var rank_stars := 0
var buildings := [0, 0, 0, 0, 0]
var revenge_pending := false
var npcs: Array = []
# The raccoons' mark. Picked before the spin, not after it, so the pot on the
# machine's card is a promise rather than a decoration -- the coins you see are
# the coins at stake, and the name you see is whose vault gets opened.
var next_target: Dictionary = {}
# A rival fetched from the server, waiting to be the next one on the card.
#
# Fetched AHEAD, never during. matchmaking.gd's own comment is the constraint:
# the rival the search lands on is "the rival main.gd already committed to --
# the one whose name and vault have been sitting on the card above the wheel
# since before the reels moved". A request made when the raid starts would
# either stall the spin or swap the card out from under a player who had
# already read it. So one is kept warm, and if none arrived the local pool
# answers exactly as it does today.
var _server_rival: Dictionary = {}

var slot_page: Control
# The win read-out currently on the reels, if any. See `_show_win`.
var _win_slug: Control
var village_page: Control
var slot: SlotView
var village: VillageView
var _current_page: Control
var _visit: IslandVisit
var _match: Matchmaking
# True from the instant a raid is *decided* until the payout lands.
#
# _visit and _match were not enough on their own. An attack builds its search
# screen synchronously, so _match covers it from the first frame -- but a steal
# goes straight to the island behind a half-second tween, and for that half
# second nothing existed to say a raid was coming. The reels have already
# re-enabled SPIN and BET by then, so the player could raise the bet to x5 and
# spin again while the STEAL banner was still on screen, and the raid, built
# later, read the new bet as its multiplier. A x1 stake paid out at x5, minted
# out of nothing.
# --- the clock ---------------------------------------------------------

# The furthest forward the game has ever seen the device clock. Rides in the
# save.
#
# Every cooldown, deadline and countdown in this file is a comparison against
# the device clock, and on iOS that is a number the player edits in Settings.
# Two taps in Date & Time and the daily bonus is ready again, the free chest is
# ready again, the quest periods roll over, and a "2 hours only" offer either
# never expires or can be re-rolled to a better one on demand. The whole loop
# ran in about fifteen seconds and could be repeated all afternoon, because it
# depended on setting the clock *back* to real time between claims.
#
# _now() is the only clock the game logic is allowed to read: the device clock
# or the high-water mark, whichever is later. Winding the clock back is now
# simply ignored -- game time stands still until the real clock catches up.
#
# That kills the round trip, which is what made the exploit repeatable. A
# forward jump is still a forward jump; nothing on a device can stop a player
# ageing their own save. What it can no longer be is undone. Jump a day forward
# to claim a daily, and the game's clock is a day ahead for good -- put the
# phone back to real time and the next bonus is 48 hours away, not 24. Farming
# now costs the farmer a permanently broken clock.
#
# It also fixes the honest version of the same bug. A phone whose battery died,
# or that boots before it reaches a time server, used to hand _sanitize_clock a
# backdated "now" and have a whole collection season deleted for it.
var clock_hw := 0.0

func _now() -> float:
	var t := Time.get_unix_time_from_system()
	if t > clock_hw:
		clock_hw = t
	return clock_hw

# --- reading a save that may say anything -----------------------------------

# The save is a JSON file on a device the player owns. It can be hand-edited,
# it can be restored from a backup written by an older build, and a kill at the
# wrong moment can leave a stale one behind. So every value read out of it goes
# through one of these.
#
# The reason is not cheating -- a single-player balance is the player's own
# business. It is that GDScript's int(), float(), bool() and String() raise on
# a Variant they cannot convert, and a raise inside _load_game does not stop
# the game: it abandons the rest of the function and lets boot carry on. One
# `"muted": "yes"` and the load quietly gives up partway, the game comes up on
# defaults, and the next autosave writes those defaults over the real file --
# rotating the only good copy into .bak on the way past. A wipe, silently, from
# one wrong type in one field.
#
# bool() is the sharpest edge of the four: it raises on any string at all.
static func _i(v, def := 0) -> int:
	match typeof(v):
		TYPE_INT: return v
		TYPE_BOOL: return 1 if v else 0
		TYPE_FLOAT:
			# NAN fails every comparison, including the clamp's, and INF
			# overflows the cast. Both are reachable: JSON.parse_string turns
			# 1e400 into INF without complaint.
			if is_nan(v) or is_inf(v): return def
			return int(clampf(v, -9.0e15, 9.0e15))
		TYPE_STRING: return int(v) if (v as String).is_valid_int() else def
	return def

static func _f(v, def := 0.0) -> float:
	match typeof(v):
		TYPE_FLOAT:
			if is_nan(v) or is_inf(v): return def
			return v
		TYPE_INT: return float(v)
		TYPE_BOOL: return 1.0 if v else 0.0
		TYPE_STRING: return float(v) if (v as String).is_valid_float() else def
	return def

static func _b(v, def := false) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return v != 0
	return def

static func _s(v, def := "") -> String:
	return v if typeof(v) == TYPE_STRING else def

var _raid_pending := false
# The stake the raid was won at, captured where the raid is decided rather than
# read back off the machine where it is built. Between those two moments the
# bet no longer belongs to this raid.
var _raid_mult := 1
# The rival the current raid is against, held from the moment the reels land
# until the raid is paid out. next_target is free to move on afterwards; this
# is the one the search screen shows and the one the island belongs to, and
# nothing in between the two is allowed to swap it.
var _raid_target: Dictionary = {}
# Who you hit last. They are the ones with a reason to come back at you.
var _last_raided: Dictionary = {}

var _hud_labels: Array = []
var _regen_accum := 0.0
var _transitioning := false

const DAILY_COOLDOWN := 86400.0
const DAILY_BONUS_COINS := 1200
const DAILY_BONUS_SPINS := 8
var daily_last := 0.0
var muted := false
# Missions run in three reset cycles. "coins" is the base reward at island 1;
# actual payouts scale with the same 1.6^(level-1) curve as star costs, so a
# mission is always worth the same fraction of a building at any island.
const MISSION_DEFS := {
	"daily": [
		{"id": "spins", "emoji": "🌀", "desc": "Spin the wheel", "target": 15, "coins": 800},
		{"id": "coins_won", "emoji": "💰", "desc": "Win coins on spins", "target": 8000, "coins": 900},
		{"id": "attacks", "emoji": "🔨", "desc": "Attack rival islands", "target": 3, "coins": 1200},
		{"id": "steals", "emoji": "🦝", "desc": "Steal from rivals", "target": 2, "coins": 1100},
		{"id": "builds", "emoji": "🏗️", "desc": "Build star upgrades", "target": 2, "coins": 1400},
		{"id": "daily_gift", "emoji": "🎁", "desc": "Claim the daily bonus", "target": 1, "spins": 5},
		{"id": "big_bet", "emoji": "🎯", "desc": "Spin at bet x2 or more", "target": 5, "coins": 850},
		{"id": "cards", "emoji": "🃏", "desc": "Find collection cards", "target": 2, "coins": 1000},
	],
	"weekly": [
		{"id": "spins", "emoji": "🌀", "desc": "Spin the wheel", "target": 100, "coins": 3600},
		{"id": "coins_won", "emoji": "💰", "desc": "Win coins on spins", "target": 60000, "coins": 4300},
		{"id": "attacks", "emoji": "🔨", "desc": "Attack rival islands", "target": 15, "coins": 4000},
		{"id": "steals", "emoji": "🦝", "desc": "Steal from rivals", "target": 12, "coins": 3700},
		{"id": "builds", "emoji": "🏗️", "desc": "Build star upgrades", "target": 10, "coins": 5000},
		{"id": "daily_gift", "emoji": "🎁", "desc": "Claim 5 daily bonuses", "target": 5, "coins": 3200},
		{"id": "big_bet", "emoji": "🎯", "desc": "Spin at bet x2 or more", "target": 30, "coins": 3400},
		{"id": "cards", "emoji": "🃏", "desc": "Find collection cards", "target": 10, "coins": 3700},
	],
	"monthly": [
		{"id": "spins", "emoji": "🌀", "desc": "Spin the wheel", "target": 400, "coins": 11000},
		{"id": "coins_won", "emoji": "💰", "desc": "Win coins on spins", "target": 250000, "coins": 12500},
		{"id": "attacks", "emoji": "🔨", "desc": "Attack rival islands", "target": 50, "coins": 11800},
		{"id": "steals", "emoji": "🦝", "desc": "Steal from rivals", "target": 40, "coins": 11000},
		{"id": "builds", "emoji": "🏗️", "desc": "Build star upgrades", "target": 35, "coins": 14000},
		{"id": "islands", "emoji": "⛵", "desc": "Complete an island", "target": 1, "coins": 17000},
		{"id": "daily_gift", "emoji": "🎁", "desc": "Claim 20 daily bonuses", "target": 20, "coins": 10500},
	],
}
# Extra chest for claiming every mission in a cycle (coins scale like above).
const MISSION_BONUS := {
	"daily": {"emoji": "🎁", "coins": 2600, "spins": 15},
	"weekly": {"emoji": "🧰", "coins": 10000, "spins": 45},
	"monthly": {"emoji": "🏆", "coins": 26000, "spins": 90},
}
const MISSION_TAB_INFO := {
	"daily": {"emoji": "☀️", "title": "DAILY", "color": Color(0.3, 0.62, 0.38)},
	"weekly": {"emoji": "🗓️", "title": "WEEKLY", "color": Color(0.25, 0.5, 0.85)},
	"monthly": {"emoji": "👑", "title": "MONTHLY", "color": Color(0.6, 0.4, 0.85)},
}
const MISSION_ICON_COLORS := {
	"spins": Color(0.3, 0.55, 0.9), "coins_won": Color(0.85, 0.65, 0.2),
	"attacks": Color(0.8, 0.35, 0.3), "steals": Color(0.55, 0.45, 0.75),
	"builds": Color(0.85, 0.5, 0.2), "daily_gift": Color(0.85, 0.35, 0.55),
	"big_bet": Color(0.3, 0.7, 0.65), "cards": Color(0.5, 0.55, 0.85),
	"islands": Color(0.25, 0.6, 0.8),
}
var mission_state := {}
var quests_tab := "daily"
var _quests_timer_label: Label = null
var _popup: Control
var _journey_layer: Control
var _badges := {}
var profile := {}
var _login_layer: Control
var _village_bg: TextureRect
var _village_stage: Control
var _village_sky: ColorRect
var _island_title: Label
# SPIN page pieces that get repainted per island by _apply_island_theme().
var _slot_bg: TextureRect
var _slot_bg_mat: ShaderMaterial
var _slot_rays_mat: ShaderMaterial
var _slot_floor_mat: ShaderMaterial
var _slot_glow_mat: ShaderMaterial
var _slot_logo: Label
var _slot_decor: Array = []
# Menu-page water, repainted with the island's palette by _apply_island_theme().
var _page_backdrops: Array = []

var pages := {}
var _page_bodies := {}
var auto_spin := false
var _last_bet := 1
var purchased_ids := []
var shop_free_last := 0.0
# Coins banked behind the piggy's glass. Filled by playing, spent only by
# buying it back -- nothing else in the game reads or drains this.
var piggy_coins := 0
# What the piggy held at the moment Pay was pressed. Persisted, because the
# transaction it belongs to can be delivered on a later launch -- see
# _break_piggy for why an empty bank must not be able to swallow a real charge.
var piggy_promised := 0
# The live limited-time offer: which pack, when it dies, and the earliest the
# next one may roll. All three persist, so a countdown a player left running
# is still running when they come back.
var offer_id := ""
var offer_until := 0.0
var offer_next := 0.0
# Where each shelf starts, by key. Node references, rebuilt with the page every
# time it is filled -- so this is cleared at the top of _fill_shop rather than
# held across a rebuild, where every entry would be a freed node.
var _shop_anchors := {}
# A top-up that has been paid for but not yet delivered: {"id", "coins"}.
# Saved, because the window it lives in is a StoreKit sheet, and the app can be
# killed inside one.
var topup_pending := {}
var _ui_tick := 0.0
var _shop_gift_timer_label: Label
var _offer_timer_label: Label
var col_owned := {}
# set id -> [count, count, ...], how many spare copies of each card are held.
# Pulling a card you already have used to be a dead beat with a coin refund
# stapled to it; the spares are kept now because they are the raw material the
# boxes are opened with.
var col_dupes := {}
var col_claimed := {}
var col_mega_claimed := false
var col_deadline := 0.0
# The Cards tab is two screens behind one nav button: a shelf of six sets, and
# the set you tapped. Empty means the shelf.
var col_open := ""
var _convert_btn: Button
var _convert_badge: Panel
# The spendable-star figure on the Card Boxes page. Melting flies stars into
# this rather than into the top bar, which holds rank and does not move.
var _star_bank_label: Label

# How many failed saves in a row before the player is told.
# A rival's purse, at the very most. Everything about a raid payout is derived
# from it, so an unbounded one is an unbounded payout.
const NPC_COIN_CAP := 5_000_000

const SAVE_FAIL_WARN := 3
var _save_fails := 0
# Whether this session read the save file through to the end. Guards the backup
# rotation in _write_save.
var _load_ok := false
# The sign-in attempt currently in flight, if any.
var _auth: Node = null

const NOTIF_LOG_MAX := 30
# The longest absence any offline system will pay out for. Everything it
# feeds is capped per load anyway; this stops the *inputs* being absurd.
const MAX_AWAY_SECS := 7.0 * 86400.0
var notif_enabled := true
# Each of these is both an in-game alert and a phone notification -- one
# switch, because a player who turns off "attack alerts" means the phone one
# at least as much as the toast.
var notif_types := {"attack": true, "steal": true, "spins": true, "gift": true, "events": true}
var notif_log := []
# Whether the player has already been asked to let the game send phone
# notifications. iOS puts its prompt up exactly once per install and a refusal
# is close to permanent, so the ask is spent carefully -- see _ask_for_alerts.
var notif_prompted := false
var _toast: Control
var _offline_spins_gained := 0
# What rivals are going to do while the app is asleep, decided before it goes
# to sleep. See _preroll_raids.
var pending_raids := []
# Wall clock at the moment the app went to the background, or 0 while it is in
# the foreground. See _notification.
var _away_since := 0.0
# DEMO_ISLAND=17 previews that island's theme without grinding to it. Saving is
# disabled while it's set so a preview can never overwrite real progress.
var _preview_island := false

# The title screen holds for at least this long. The work behind it finishes in
# well under a second on a modern phone, and a splash that flashes past is
# worse than no splash -- the wordmark has to have time to be read.
const BOOT_MIN_SECS := 2.0

var _boot: Boot
var _preloaded: Array = []

func _ready() -> void:
	randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Fonts and the root theme first: the title screen is built out of the same
	# type as everything else, so it can't come up before they exist.
	_setup_global_font_fallbacks()
	_boot = Boot.new()
	add_child(_boot)
	_run_boot()

# The load sequence, spread across frames so the bar can be drawn between the
# pieces. Every step does real work and the bar only moves once that work has
# returned, so the percentage measures something instead of animating.
#
# The order matters in one place: the save is read first. That is what lets
# every page be built already holding the player's island and counters, rather
# than being built on defaults and repainted afterwards, which is what used to
# happen.
func _run_boot() -> void:
	var started := Time.get_ticks_msec()
	await _boot_step(0.14, "Reading your logbook", _boot_load)
	_boot.set_island(CV.island_palette(island_level), CV.island_bg_tex(island_level))
	await _boot_step(0.34, "Charting %s" % CV.island_theme(island_level)["name"], _boot_warm_art)
	await _boot_step(0.58, "Polishing the reels", _build_slot_page)
	await _boot_step(0.74, "Raising the village", _build_village_page)
	await _boot_step(0.90, "Stocking shop, cards and quests", _build_menu_pages)
	await _boot_step(1.00, "Casting off", _boot_finish_build)

	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	if elapsed < BOOT_MIN_SECS:
		await get_tree().create_timer(BOOT_MIN_SECS - elapsed).timeout

	# Cleared before the fade rather than after it: the game underneath is
	# fully built by now, so it may as well start ticking while the title
	# screen dissolves off it.
	var splash := _boot
	_boot = null
	await splash.dismiss()
	_after_boot()

# One step: name it, give the screen a frame to actually paint that name, do
# the work, then let the bar catch up to where the work got us.
func _boot_step(ratio: float, label: String, work: Callable) -> void:
	_boot.set_status(label)
	await get_tree().process_frame
	work.call()
	await _boot.advance(ratio)

func _boot_load() -> void:
	_load_game()
	if OS.has_environment("DEMO_ISLAND"):
		var preview := int(OS.get_environment("DEMO_ISLAND"))
		if preview >= 1:
			island_level = preview
			_preview_island = true
	_stock_rivals()
	_ensure_missions()
	_ensure_collections()
	if muted:
		AudioServer.set_bus_mute(0, true)
	_load_profile()

# Pulls the textures the first screens will ask for through the loader now,
# while there is a progress bar accounting for the time, and keeps a reference
# to each so the resource cache can't drop them again before the pages that
# use them are built.
func _boot_warm_art() -> void:
	_preloaded.clear()
	_preloaded.append(CV.island_bg_tex(island_level))
	for i in CV.BUILDINGS.size():
		_preloaded.append(CV.island_building_tex(island_level, i))
	for id in CV.SYMBOLS:
		_preloaded.append(CV.symbol_tex(id))
	_preloaded.append(CV.bg_tex("slot_room"))
	_preloaded.append(CV.bg_tex("village"))
	_preloaded.append(CV.emoji_font())
	_preloaded.append(Lagoon.display_font())
	_preloaded.append(Lagoon.ui_bold_font())

func _boot_finish_build() -> void:
	village_page.visible = false
	_current_page = slot_page
	# DEMO_PAGE opens straight onto one screen, so a change to a page four taps
	# deep can be looked at without playing four taps' worth of game first.
	var demo_page := OS.get_environment("DEMO_PAGE")
	if demo_page == "island":
		slot_page.visible = false
		village_page.visible = true
		_current_page = village_page
	elif pages.has(demo_page):
		slot_page.visible = false
		pages[demo_page].visible = true
		_current_page = pages[demo_page]
	_build_nav()
	if pages.has(demo_page):
		_fill_page(demo_page)
	_apply_island_theme()
	_update_badges()
	_refresh()

# Everything that addresses the player waits until the title screen is gone --
# a toast or a sign-in sheet fading up behind a splash is one nobody reads.
func _after_boot() -> void:
	# Connected here rather than in _ready: a transaction interrupted on a
	# previous launch is replayed the instant IAP starts popping events, and it
	# has to land on a game whose pages already exist.
	IAP.purchase_succeeded.connect(_on_purchase_ok)
	IAP.purchase_failed.connect(_on_purchase_fail)
	IAP.purchase_cancelled.connect(_on_purchase_cancel)
	IAP.products_loaded.connect(_on_products_loaded)
	IAP.begin()

	# Same reasoning as IAP above: an island adopted from the server repaints
	# pages, and those pages have to exist by the time it lands.
	Cloud.session_ready.connect(_cloud_claim)
	Cloud.signed_in.connect(_on_cloud_signed_in)
	Cloud.save_rejected.connect(_on_cloud_save_rejected)
	Cloud.raids_arrived.connect(_on_cloud_raids)
	Cloud.link_result.connect(_on_cloud_link_result)
	Cloud.sign_in_failed.connect(_on_cloud_sign_in_failed)
	# A session that survived from a previous launch still has to claim, because
	# claiming is also how the game asks what happened while it was closed.
	if Cloud.linked():
		_cloud_claim()
	call_deferred("_check_island_complete")
	# A lock during the title screen. _notification stamped it and left the
	# credit to here, where there are pages to repaint and a toast to land on.
	if _away_since > 0.0:
		_credit_time_away(clampf(_now() - _away_since, 0.0, MAX_AWAY_SECS))
		_away_since = 0.0
	if _offline_spins_gained > 0:
		_notify("spins", "While you were away, spins refilled  +%d  (%d/%d)" % [_offline_spins_gained, spins, SPIN_CAP], "🌀")
		_offline_spins_gained = 0
	_offline_raids()
	# Anything iOS delivered while the app was shut has been read by the act of
	# opening it, and the icon should stop claiming otherwise.
	Alerts.clear_delivered()
	Alerts.set_badge(_unread_count())
	if profile.is_empty():
		_show_login()
	# DEMO_RAID sails straight to a raid. An attack needs three hammers on the
	# reels to happen for real, which is not a thing you can spin up on demand
	# while looking at the animation it plays.
	var demo_raid := OS.get_environment("DEMO_RAID")
	if demo_raid == "attack" or demo_raid == "steal":
		var go := create_tween()
		go.tween_interval(0.6)
		go.tween_callback(_start_visit.bind(demo_raid))
	# DEMO_OFFER=coins:<shortfall> opens the build-blocked top-up on demand.
	# Reaching it by playing means spending a village down to the exact wrong
	# number first, which is not a thing you can do while looking at the dialog
	# you are trying to lay out.
	# DEMO_OFFER=spins:<held>:<bet> does the same for the spin wall, at either of
	# the two shapes it comes in -- an empty meter, or a meter a raised bet
	# outruns -- because arriving at the second one honestly means burning a
	# balance down to exactly four and then remembering to set bet x5.
	var demo_offer := OS.get_environment("DEMO_OFFER")
	if demo_offer.begins_with("coins"):
		var parts := demo_offer.split(":")
		var short_by := int(parts[1]) if parts.size() > 1 else 43000
		var go2 := create_tween()
		go2.tween_interval(0.4)
		go2.tween_callback(func() -> void: _offer_need_coins(short_by))
	elif demo_offer.begins_with("spins"):
		var parts := demo_offer.split(":")
		spins = int(parts[1]) if parts.size() > 1 else 0
		var bet := int(parts[2]) if parts.size() > 2 else 1
		var go3 := create_tween()
		go3.tween_interval(0.4)
		go3.tween_callback(func() -> void: _offer_out_of_spins(bet))
	# SHOT=<page key> opens that page, lets it settle and writes a PNG, then
	# quits. Apple will not review an in-app purchase without a screenshot of
	# where it is sold, and there are twenty-five of them -- shooting those by
	# hand, and again after every redesign of the shop, is not a job worth
	# doing twice.
	if OS.has_environment("SHOT"):
		call_deferred("_capture_page", OS.get_environment("SHOT"))
		return
	if OS.has_environment("DEMO_QUESTS"):
		var demo_tab := OS.get_environment("DEMO_QUESTS")
		if MISSION_DEFS.has(demo_tab):
			quests_tab = demo_tab
		call_deferred("_goto", pages["quests"])

func _scrolls_in(node: Node) -> Array:
	var out := []
	for c in node.get_children():
		if c is ScrollContainer and c.is_visible_in_tree():
			out.append(c)
		out.append_array(_scrolls_in(c))
	return out

func _capture_page(key: String) -> void:
	# SHOT=shop:spins shoots the shop already scrolled to a named shelf, which
	# is both how the plus buttons are checked and how a screenshot of one
	# particular product family gets taken without counting pixels first.
	if key.begins_with("shop:"):
		_goto_shop(key.split(":")[1])
		await get_tree().create_timer(2.0).timeout
		var shot := get_viewport().get_texture().get_image()
		var at := "user://shot_%s.png" % key.replace(":", "_")
		shot.save_png(at)
		print("SHOT written: %s (%dx%d)" % [ProjectSettings.globalize_path(at), shot.get_width(), shot.get_height()])
		get_tree().quit()
		return
	if pages.has(key):
		_goto(pages[key])
	elif key == "slot":
		_goto(slot_page)
	# Long enough for the page transition and the card art to finish arriving;
	# a screenshot of a half-built shop is worse than none.
	await get_tree().create_timer(2.0).timeout
	# SHOT_SCROLL=<px> shoots the page wound down to that offset. The shop is
	# four screens tall and the products Apple wants to see sold are on the
	# third and fourth, so without this the only part of it that can be
	# screenshotted automatically is the part above the fold.
	var scroll := OS.get_environment("SHOT_SCROLL")
	if scroll != "":
		for sc in _scrolls_in(self):
			sc.scroll_vertical = int(scroll)
		await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	var path := "user://shot_%s%s.png" % [key, scroll]
	img.save_png(path)
	print("SHOT written: %s (%dx%d)" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])
	get_tree().quit()

# Establishes the game's two typefaces (see Lagoon) as the global baseline, so
# every control that doesn't ask for something specific already speaks in the
# right voice. Both are chained ahead of DejaVu (for ★ and other symbols) and
# Noto Color Emoji, because on iOS the default font can't reach the system
# emoji font and those glyphs otherwise render blank.
func _setup_global_font_fallbacks() -> void:
	var body := Lagoon.ui_font()
	ThemeDB.fallback_font = body

	# Godot's built-in theme defaults to 16px, which is ~8pt once the 720x1280
	# canvas is scaled down to a phone -- well under the 11pt floor. A theme on
	# the root sets the baseline for every control that doesn't override it.
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = UI.F_LABEL
	# Text sits on sea glass almost everywhere, so ink-on-light is the default
	# and the few places that invert say so explicitly.
	t.set_color("font_color", "Label", Lagoon.INK)
	theme = t

# --- login ---

func _load_profile() -> void:
	if not FileAccess.file_exists("user://profile.json"):
		return
	var f := FileAccess.open("user://profile.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	# Coerced here so no caller has to. The name is passed straight into
	# _popup_row_label(text: String), and a typed parameter rejects a
	# Dictionary by raising -- which aborted the leaderboard halfway through
	# building itself, leaving a half-drawn modal on screen.
	profile = {
		"name": _s(d.get("name", "Player"), "Player"),
		"email": _s(d.get("email", "")),
		"provider": _s(d.get("provider", "guest"), "guest"),
	}

func _save_profile() -> void:
	var f := FileAccess.open("user://profile.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile))

func _show_login() -> void:
	if _login_layer != null:
		return
	_login_layer = Control.new()
	_login_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_login_layer.z_index = 200
	add_child(_login_layer)
	_login_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# First screen of the game, so it shows the lagoon rather than a dark
	# splash: whatever the player sees here is the promise the rest has to keep.
	Lagoon.tint_backdrop(Lagoon.backdrop(_login_layer), CV.island_palette(island_level))

	var coin_t := CV.symbol_tex("coin")
	if coin_t != null:
		for i in 6:
			var tr := TextureRect.new()
			tr.texture = coin_t
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# Clear of the wordmark and of the sign-in column, which runs from
			# 640 to the bottom of the screen between x=130 and x=590. Half the
			# coins go big in the open band above it; the rest go small down the
			# two margins beside it, where no button reaches.
			var margin := i % 2 == 1
			var s := randf_range(38, 62) if margin else randf_range(50, 110)
			tr.size = Vector2(s, s)
			tr.position = Vector2(randf_range(6, 124 - s) if i % 4 == 1 else randf_range(596, 714 - s), randf_range(700, 1180)) if margin \
				else Vector2(randf_range(20, 610 - s), randf_range(70, 460))
			tr.modulate = Color(1, 1, 1, randf_range(0.35, 0.6))
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_login_layer.add_child(tr)
			FX.float_bob(tr, randf_range(12, 28), randf_range(2.0, 3.6))

	var logo := Lagoon.wordmark("LOOT  LAGOON", 68)
	_login_layer.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 240.0 + safe_top()
	logo.offset_bottom = 330.0 + safe_top()
	FX.pulse_forever(logo, 1.04, 2.2)

	var tagline := Lagoon.title("Spin · Raid · Build your island", UI.F_BODY, Color.WHITE, Lagoon.ABYSS)
	_login_layer.add_child(tagline)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tagline.offset_top = 336.0 + safe_top()
	tagline.offset_bottom = 386.0 + safe_top()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_login_layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_left = 130.0
	box.offset_right = -130.0
	box.offset_top = 640.0 + safe_top()

	# Three branded pills stacked in a column is a wall: the eye has to read
	# each one to find out it is not the other two, and none of them looks like
	# the way in. So the column has one loud thing in it, and everything else
	# gets quieter as it goes down -- one full-width button for the sign-in that
	# belongs on this device, the rest as marks in a row, and the way past all
	# of it as text.
	var providers := _providers_here()
	if not providers.is_empty():
		var primary := _primary_provider(providers)
		_provider_button(box, primary)
		var rest := providers.filter(func(p: Dictionary) -> bool: return p != primary)
		if not rest.is_empty():
			var or_line := Lagoon.title("or continue with", UI.F_TINY, Color.WHITE, Lagoon.ABYSS)
			or_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(or_line)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 28)
			box.add_child(row)
			for p in rest:
				_provider_chip(row, p)

		# What signing in actually buys, said plainly. Nothing here reaches a
		# server: the island lives in user:// either way and an account is a
		# name on it. Saying so is not modesty -- an app that demands a login it
		# does not need is Guideline 5.1.1(v), and "we take your email for
		# nothing" is the version of this screen that gets rejected.
		var why := Lagoon.title("Your island is saved on this device either way — signing in just puts your name on it.", UI.F_TINY, Color.WHITE, Lagoon.ABYSS)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(why)

	# The way in. With sign-in above it, it is text rather than a fourth pill --
	# quiet, but the widest tap target on the screen, because an escape hatch
	# the eye cannot find is the same dark pattern as no escape hatch at all.
	# With no sign-in at all there is nothing to be an alternative *to*, and a
	# grey link asking a player to "play as guest" on a screen with no other
	# option is a title screen apologising for itself. Then it is simply Play.
	var alone := providers.is_empty()
	var guest := Button.new()
	guest.text = "START  PLAYING" if alone else "Play as guest"
	guest.custom_minimum_size = Vector2(0, UI.TAP_COMFY if alone else UI.TAP)
	if alone:
		guest.add_theme_font_size_override("font_size", UI.F_BODY)
		_candy_button(guest, Color(0.28, 0.68, 0.34))
	else:
		guest.flat = true
		guest.add_theme_font_size_override("font_size", UI.F_LABEL)
		guest.add_theme_font_override("font", Lagoon.display_font())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			guest.add_theme_color_override(c, Color.WHITE)
		guest.add_theme_color_override("font_outline_color", Lagoon.ABYSS)
		guest.add_theme_constant_override("outline_size", 8)
		guest.focus_mode = Control.FOCUS_NONE
	FX.press_feedback(guest)
	guest.pressed.connect(func() -> void:
		profile = {"name": "Guest", "email": "", "provider": "guest"}
		_save_profile()
		_close_login()
	)
	box.add_child(guest)

# Which sign-in gets to be the button rather than a mark in a row. The one the
# device already knows: Apple's on an Apple platform, Google's elsewhere. On
# iOS that is also what Guideline 4.8 wants -- Sign in with Apple is meant to
# be at least as prominent as the alternatives, and full-width above a row of
# 84px circles is not a close call.
func _primary_provider(providers: Array) -> Dictionary:
	var want := "apple" if OS.get_name() in ["iOS", "macOS"] else "google"
	for p in providers:
		if String(p["id"]) == want:
			return p
	return providers[0]

# A secondary sign-in: the mark alone, on the brand's colour, in a circle. No
# label, because the marks are the most recognisable thing on the screen and a
# word next to each would put the wall back.
func _provider_chip(row: HBoxContainer, p: Dictionary) -> void:
	var face: Color = p["face"]
	var ink: Color = p["ink"]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(UI.TAP, UI.TAP)
	btn.tooltip_text = String(p["label"])
	var bevel := face.darkened(0.32) if face.get_luminance() > 0.12 else Color("#2E2E2E")
	Lagoon.button_custom(btn, face, bevel, ink, int(UI.TAP * 0.5))
	FX.press_feedback(btn)
	btn.pressed.connect(_start_login.bind(String(p["id"])))
	row.add_child(btn)
	Lagoon.button_gloss(btn, int(UI.TAP * 0.5))

	var mark := BrandMark.new()
	mark.kind = String(p["id"])
	mark.ink = ink
	mark.behind = face
	btn.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in [["offset_left", 22.0], ["offset_right", -22.0], ["offset_top", 22.0], ["offset_bottom", -26.0]]:
		mark.set(m[0], m[1])
	# Under the gloss, for the same reason the full-width mark is -- see
	# _provider_button.
	btn.move_child(mark, 0)

# Which sign-in buttons this device gets, and it is two questions, not one.
#
# `platforms` is the device half. Sign in with Apple is an Apple-platform
# service: on Android it is a button that cannot work, and on iOS it is one
# Apple insists on -- Guideline 4.8 says an app offering Google or Facebook
# sign-in must also offer a privacy-preserving equivalent, and Apple's is the
# one that qualifies. Google is right everywhere, which is why an Android
# build ends up with exactly the set Guy expected without anyone writing
# "if Android" twice.
#
# `ready` is the review half, and it is the stricter of the two: a button whose
# flow does not exist yet is not drawn at all. A black Apple button that opens
# nothing is Guideline 2.1 -- the same rejection the old "Facebook — coming
# soon" banner was asking for. The design is finished and waiting; the day a
# flow works, one flag turns its button on.
const SIGN_IN_PROVIDERS := [
	{"id": "apple", "label": "Sign in with Apple", "face": Color("#000000"),
	 "ink": Color.WHITE, "platforms": ["iOS", "macOS"], "ready": false},
	{"id": "google", "label": "Sign in with Google", "face": Color("#FFFFFF"),
	 "ink": Color("#1F1F1F"), "platforms": [], "ready": true},
	{"id": "facebook", "label": "Continue with Facebook", "face": Color("#1877F2"),
	 "ink": Color.WHITE, "platforms": [], "ready": false},
]

# Whether a provider's flow actually exists on THIS device, right now.
#
# It used to be a constant in the table, which was right while no flow existed
# and became a lie the moment one did: Sign in with Apple is a native plugin,
# and the plugin is only in an iOS build. A hardcoded `true` would draw the
# black Apple button in the editor and on desktop, where tapping it can do
# nothing at all -- Guideline 2.1, the same rejection the old "Facebook — coming
# soon" banner was asking for.
#
# Asking the plugin instead means the button appears exactly where it works, and
# the 4.8 rule below keeps doing its job for free: on a Mac there is no plugin,
# so Apple is absent, so the whole set is withheld and the title screen stays
# the single green START PLAYING button it is today.
func _provider_ready(p: Dictionary) -> bool:
	match String(p["id"]):
		"apple":
			return AppleAuth.available()
		_:
			return bool(p["ready"])

func _providers_here() -> Array:
	var here := OS.get_name()
	var out := []
	for p in SIGN_IN_PROVIDERS:
		if not _provider_ready(p):
			continue
		var only: Array = p["platforms"]
		if not only.is_empty() and not only.has(here):
			continue
		out.append(p)
	# Guideline 4.8 is a rule about the *set*, not about any one button: on an
	# Apple platform, offering Google or Facebook obliges the app to offer Sign
	# in with Apple as well. So on iOS the others are hostages to it -- if
	# Apple's flow is not there, none of them ship, and the day it is, they all
	# come back on their own. Encoded here rather than remembered, because the
	# version of this that gets rejected is the one where somebody turns Google
	# on for a quick test and forgets.
	if (here == "iOS" or here == "macOS") and not out.is_empty():
		var has_apple := false
		for p in out:
			if String(p["id"]) == "apple":
				has_apple = true
		if not has_apple:
			return []
	return out

# A sign-in button in someone else's colours.
#
# It keeps the game's moulded shape -- a flat rectangle would look pasted onto
# this screen -- but nothing else: the face, the ink and the mark are the
# brand's, the label is set in the plain UI face rather than the game's display
# one, and it loses the cartoon outline every other button in the game wears.
func _provider_button(box: VBoxContainer, p: Dictionary) -> void:
	var face: Color = p["face"]
	var ink: Color = p["ink"]
	var btn := Button.new()
	btn.text = String(p["label"])
	btn.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	# The lip under the face is the brand colour's own shadow, except under
	# black, which has none -- there it is a dark grey, or the button loses its
	# bottom edge against the water.
	var bevel := face.darkened(0.32) if face.get_luminance() > 0.12 else Color("#2E2E2E")
	Lagoon.button_custom(btn, face, bevel, ink)
	btn.add_theme_font_override("font", Lagoon.ui_font())
	btn.add_theme_font_size_override("font_size", UI.F_LABEL)
	btn.add_theme_constant_override("outline_size", 0)
	# Room on the left for the mark, so a long label never runs under it.
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = btn.get_theme_stylebox(st)
		if sb != null:
			sb.content_margin_left = 92.0
	FX.press_feedback(btn)
	btn.pressed.connect(_start_login.bind(String(p["id"])))
	box.add_child(btn)
	Lagoon.button_gloss(btn, 22)

	var mark := BrandMark.new()
	mark.kind = String(p["id"])
	mark.ink = ink
	mark.behind = face
	btn.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	mark.offset_left = 24.0
	mark.offset_right = 80.0
	mark.offset_top = 20.0
	mark.offset_bottom = -20.0
	# Beneath the gloss, not over it. The bite in the Apple mark is painted in
	# the button's own face colour, and the specular arc drawn across the top
	# is what stops that patch reading as a seam.
	btn.move_child(mark, 0)

func _start_login(id: String) -> void:
	match id:
		"google":
			_login_google()
		"apple":
			_login_apple()
		_:
			# Unreachable while `ready` gates the buttons, and left in as the
			# thing that happens if a flag is flipped before a flow exists.
			_banner("%s sign-in is not wired up in this build yet." % id.capitalize(), Color(1.0, 0.8, 0.4))

# Everything a completed sign-in has to do, for either provider.
#
# The profile is written to disk FIRST and unconditionally, before anything is
# sent anywhere. Apple hands over the player's name exactly once -- on the first
# authorization this app ever receives -- and if that write is skipped because a
# network call failed, the name is gone for good and the account is called
# "Islander" for the rest of its life.
func _on_login(p: Dictionary) -> void:
	# An empty name from Apple on a later sign-in is Apple being Apple, not a
	# player who deleted their name. Keep what is already stored.
	if str(p.get("name", "")) == "" and str(profile.get("name", "")) != "":
		p["name"] = profile["name"]
	profile = p
	_save_profile()
	_close_login()

	# From here on nothing is required for the game to carry on. A player whose
	# sign-in worked and whose cloud save did not is a player with a name on
	# their island and a grey sync icon, which is exactly what they had a moment
	# ago -- not an error worth a banner.
	if not Cloud.configured():
		return
	var token := str(p.get("id_token", ""))
	if token == "":
		return
	Cloud.sign_in(str(p.get("provider", "")), token, str(p.get("nonce", "")))

# =============================================================================
#  The island, and the server's copy of it
# =============================================================================
#
# Sending the local save is not a nicety. Everyone who reaches a sign-in button
# has already been playing -- until Sign in with Apple existed the title screen
# was one green START PLAYING button and nothing else -- so the ordinary case is
# a real island meeting the server for the first time. Claiming without it would
# create an empty row and strand the island on the device.
# Held up while the server is being asked what it has.
#
# Without this the player watches their island be wrong. A fresh install shows
# island 1 with island-1 prices, and some seconds later -- once claim_player has
# answered -- it is replaced by the island they actually own. Nothing is lost
# from the real island, because push_save refuses a save carrying less rank than
# the one it holds. What IS lost is whatever they earned on the fresh one while
# waiting, and the confusing part is that they were never told any of it was
# provisional.
var _restoring := false

func _cloud_claim() -> void:
	if not Cloud.linked():
		return
	_open_restoring()
	Cloud.claim(_save_dict(), str(profile.get("name", "Islander")), "😎",
			rank_stars, island_level, coins, shields, buildings)

# What the server had. `is_new` means it had nothing and has just been given
# what was on this device, so there is nothing to reconcile.
func _on_cloud_signed_in(_who: Dictionary, is_new: bool, remote: Dictionary) -> void:
	_close_restoring()
	if is_new or remote.is_empty():
		_flush_save()
		return
	_reconcile(remote)

func _on_cloud_sign_in_failed(reason: String) -> void:
	# Was silent until now, which meant a sign-in that failed looked exactly
	# like one that worked and did nothing.
	_close_restoring()
	_banner("Couldn't sign in: %s" % reason, Color(0.95, 0.4, 0.4))

# A held screen rather than a spinner in a corner, because the point is that the
# island underneath is not yet the player's own and must not be played on.
func _open_restoring() -> void:
	if _restoring:
		return
	_restoring = true
	var box := _open_popup("One moment")
	var e := _emoji_label("🏝️", 56)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(e)
	var body := _popup_row_label("Fetching your island…", UI.F_CAPTION)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	# A server that never answers must not cost the player the game. After this
	# they are let through to play locally; the island still arrives whenever
	# the request lands, and the reconcile at that point is the same one that
	# runs on every launch.
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		if _restoring:
			_close_restoring()
			_banner("Couldn't reach your saved island — playing offline.",
					Color(0.95, 0.55, 0.3))
	)

func _close_restoring() -> void:
	if not _restoring:
		return
	_restoring = false
	_close_popup(true)

# push_save refused: the server holds an island further along than this one.
func _on_cloud_save_rejected(_stored_rank: int, remote: Dictionary) -> void:
	if remote.is_empty():
		return
	_reconcile(remote)

# Which island wins, and the rule is rank_stars for the reason main.gd already
# relies on everywhere else: nothing in the game subtracts from it. Between two
# states of the SAME island the larger one is strictly the later one, so there
# is nothing to ask about.
#
# The case that does need asking is two DIFFERENT islands -- somebody who played
# as a guest, then signed into an account that already had one. Rank cannot tell
# those apart from a stale device, so anything with real progress on both sides
# stops and asks rather than quietly throwing an evening away.
func _reconcile(remote: Dictionary) -> void:
	var theirs := int(remote.get("rank_stars", 0))
	if theirs <= rank_stars:
		# Ours is the same or further on. Push over it.
		_flush_save()
		return
	if rank_stars == 0:
		# Nothing here to lose -- a fresh install signing in. This is the whole
		# point of the feature, and stopping to ask would be theatre.
		_adopt_remote(remote)
		return
	_ask_which_island(remote)

func _adopt_remote(remote: Dictionary) -> void:
	if not _write_save(remote):
		_banner("Couldn't restore your island — check your free space.", Color(0.95, 0.4, 0.4))
		return
	_load_game()
	_refresh()
	_banner("Your island is back.", Color(0.5, 0.9, 0.6), "🏝️")

func _ask_which_island(remote: Dictionary) -> void:
	var box := _open_popup("Two islands")
	var head := _popup_row_label(
		"This account already has an island. Only one can be kept — the other is gone.",
		UI.F_CAPTION)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)

	var keep_theirs := Button.new()
	keep_theirs.text = "Restore  ⭐ %s  ·  island %d" % [
		_fmt_compact(int(remote.get("rank_stars", 0))), int(remote.get("island_level", 1))]
	keep_theirs.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(keep_theirs, Color(0.28, 0.68, 0.34))
	FX.press_feedback(keep_theirs)
	keep_theirs.pressed.connect(func() -> void:
		_close_popup()
		_adopt_remote(remote)
	)
	box.add_child(keep_theirs)

	var keep_mine := Button.new()
	keep_mine.text = "Keep this one  ⭐ %s  ·  island %d" % [_fmt_compact(rank_stars), island_level]
	keep_mine.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(keep_mine, Color(0.85, 0.45, 0.25))
	FX.press_feedback(keep_mine)
	keep_mine.pressed.connect(func() -> void:
		_close_popup()
		# Deliberate, so it goes up with force -- otherwise the server refuses a
		# lower rank and the two sides argue with each other for ever.
		Cloud.note_save(_save_dict(), rank_stars, island_level, coins, shields, buildings, true)
		Cloud.flush()
	)
	box.add_child(keep_mine)

# A second sign-in was attached to this island -- or could not be.
#
# "conflict" is the only one that stops the game: both identities already had an
# island with progress on them, and merging silently would throw one away. It
# reuses the same chooser the save reconciliation uses, because it is the same
# question asked from a different direction.
func _on_cloud_link_result(status: String, mine: Dictionary, theirs: Dictionary) -> void:
	match status:
		"linked":
			_banner("Sign-ins connected — your island is safe.", Color(0.5, 0.9, 0.6), "🔗")
		"conflict":
			_ask_which_link(mine, theirs)
		_:
			# Expired, or the token was already spent. Nothing is broken and
			# nothing was lost; the player can start it again.
			_banner("That took too long — try connecting again.", Color(0.95, 0.55, 0.3))

func _ask_which_link(mine: Dictionary, theirs: Dictionary) -> void:
	var box := _open_popup("Two islands")
	var head := _popup_row_label(
		"Both sign-ins already have an island. Only one can be kept — the other is gone.",
		UI.F_CAPTION)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	for pair in [[theirs, Color(0.28, 0.68, 0.34)], [mine, Color(0.85, 0.45, 0.25)]]:
		var isl: Dictionary = pair[0]
		if isl.is_empty():
			continue
		var b := Button.new()
		b.text = "Keep  ⭐ %s  ·  island %d" % [
			_fmt_compact(int(isl.get("rank_stars", 0))), int(isl.get("island_level", 1))]
		b.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
		_candy_button(b, pair[1])
		FX.press_feedback(b)
		b.pressed.connect(func() -> void:
			_close_popup()
			Cloud.resolve_link(str(isl.get("id", "")))
		)
		box.add_child(b)

# What happened while the app was shut.
#
# The server recorded that a raid happened and did not touch the save -- see the
# note on record_raid in migration 0002. Applying it is this side's job, under
# this side's rules, which is the only place those rules exist.
func _on_cloud_raids(raids: Array) -> void:
	var ids := []
	var taken := 0
	var smashed := 0
	for r in raids:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		ids.append(str(r.get("id", "")))
		match str(r.get("mode", "")):
			"steal":
				var c := int(r.get("coins", 0))
				# maxi, because the vault moved on while the app was closed and
				# a raid must never push a player into debt.
				taken += mini(c, coins)
				coins = maxi(0, coins - c)
			"attack":
				var h := int(r.get("hut", -1))
				if h >= 0 and h < buildings.size() and int(buildings[h]) > 0:
					buildings[h] = int(buildings[h]) - 1
					smashed += 1
	if ids.is_empty():
		return
	Cloud.ack_raids(ids)
	_flush_save()
	_refresh()
	if taken > 0:
		_banner("Raided while you were away — %s taken." % _fmt_compact(taken),
				Color(0.95, 0.55, 0.3), "🏴‍☠️")
	elif smashed > 0:
		_banner("Someone knocked a hut down while you were away.",
				Color(0.95, 0.55, 0.3), "🔨")

func _login_apple() -> void:
	if _auth != null and is_instance_valid(_auth):
		return
	var auth := AppleAuth.new()
	_auth = auth
	add_child(auth)
	auth.login_finished.connect(func(p: Dictionary) -> void:
		_on_login(p)
		_auth = null
		auth.queue_free()
	)
	auth.login_failed.connect(func(reason: String) -> void:
		_banner("Login failed: %s" % reason, Color(0.95, 0.4, 0.4))
		_auth = null
		auth.queue_free()
	)
	# Backing out of the sheet is a decision, not a failure. Nothing on screen,
	# for the same reason iap.gd keeps purchase_cancelled off the banner.
	auth.login_cancelled.connect(func() -> void:
		_auth = null
		auth.queue_free()
	)
	if not auth.start():
		_banner("Sign in with Apple is not available here", Color(1.0, 0.8, 0.4))
		_auth = null
		auth.queue_free()

func _login_google() -> void:
	if GoogleAuth.load_config().is_empty():
		_banner("Google login needs a one-time setup — see SETUP_LOGIN.md", Color(1.0, 0.8, 0.4))
		return
	# One at a time. Each attempt binds a fixed loopback port and starts a
	# repeating poll timer, and the overwhelmingly common outcome is that the
	# player never comes back from the browser -- so without this, every tap
	# left another node, another timer and another socket alive for the rest
	# of the session, and every tap after the first also reopened the browser.
	if _auth != null and is_instance_valid(_auth):
		_banner("Sign-in is already open in your browser.", Color(0.7, 0.9, 1.0))
		return
	var auth := GoogleAuth.new()
	_auth = auth
	add_child(auth)
	_banner("Opening Google sign-in in your browser...", Color(0.7, 0.9, 1.0))
	auth.login_finished.connect(func(p: Dictionary) -> void:
		_on_login(p)
		_auth = null
		auth.queue_free()
	)
	auth.login_failed.connect(func(reason: String) -> void:
		_banner("Login failed: %s" % reason, Color(0.95, 0.4, 0.4))
		_auth = null
		auth.queue_free()
	)
	if not auth.start():
		_banner("Could not start Google login", Color(0.95, 0.4, 0.4))
		_auth = null
		auth.queue_free()

func _close_login() -> void:
	if _login_layer == null:
		return
	var l := _login_layer
	_login_layer = null
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)
	Sfx.play("jackpot", -4.0)
	FX.confetti(self, 30)
	_banner("Welcome, %s!" % profile.get("name", "Player"), Color(1.0, 0.85, 0.3))

func _process(delta: float) -> void:
	# The pages are built a step at a time behind the title screen, so until it
	# is gone half of what this function reaches for does not exist yet.
	if _boot != null:
		return

	_regen_accum += delta
	if _regen_accum >= SPIN_REGEN_SECS:
		# Subtracted, not zeroed: zeroing threw away however far past the mark
		# the frame landed, so the meter's countdown drifted a little later
		# every cycle over a long session.
		_regen_accum -= SPIN_REGEN_SECS
		if spins < SPIN_CAP:
			var gained := mini(SPIN_REGEN_AMOUNT, SPIN_CAP - spins)
			spins += gained
			_refresh()
			if spins >= SPIN_CAP:
				_notify("spins", "Spins refilled — you're full!  (%d/%d)" % [spins, SPIN_CAP], "🌀")
			else:
				_notify("spins", "+%d spins refilled  (%d/%d)" % [gained, spins, SPIN_CAP], "🌀")
	if _save_pending and float(Time.get_ticks_msec()) / 1000.0 - _save_flushed >= SAVE_FLUSH_GAP:
		_flush_save()
	_ui_tick += delta
	if _ui_tick >= 1.0:
		_ui_tick = 0.0
		# A raid that came due behind an overlay or a modal, landing as soon as
		# the screen is the player's again. See _offline_raids.
		if not pending_raids.is_empty():
			_offline_raids()
		if slot != null:
			slot.set_meter(spins, SPIN_CAP, SPIN_REGEN_SECS - _regen_accum, SPIN_REGEN_AMOUNT)
		if _shop_free_ready() or _piggy_full() or not _active_offer().is_empty():
			# the gift, the piggy or an offer may have come due while playing
			if _badges.has("shop_free") and not _badges["shop_free"].visible:
				_update_badges()
				if _current_page == pages.get("shop"):
					_fill_page("shop")
		elif _shop_gift_timer_label != null and is_instance_valid(_shop_gift_timer_label):
			_shop_gift_timer_label.text = "⏳  Next gift in  %s" % _shop_free_countdown_text()
		_offer_tick()
		if _offer_timer_label != null and is_instance_valid(_offer_timer_label):
			_offer_timer_label.text = "⏳  ENDS  IN  %s" % _offer_countdown_text()
		if _current_page == pages.get("quests"):
			# roll missions over live if a cycle ends while the page is open
			if mission_state.get(quests_tab, {}).is_empty() or int(mission_state[quests_tab]["key"]) != _period_key(quests_tab):
				_ensure_missions()
				_fill_page("quests")
			else:
				_update_quests_timer()

# The app leaving and coming back.
#
# This used to answer NOTIFICATION_WM_CLOSE_REQUEST and nothing else, which is
# a desktop-only event: a phone never sends it. iOS backgrounds an app and then
# kills it whenever it likes, with no further warning, so on the platform this
# game actually ships to *nothing* was ever saved on the way out -- everything
# rested on the save calls scattered through play, and anything since the last
# one was gone. Backgrounding is the honest "we might not be back" moment, so
# that is where the save goes.
#
# Coming back is the other half. The offline catch-up -- spins refilled, rivals
# who came for your island while you were away -- ran only in _load_game, so it
# was credited on a cold launch and skipped entirely for a player who left the
# app open in the background overnight. Both paths go through the same code now.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_WINDOW_FOCUS_OUT, \
		MainLoop.NOTIFICATION_APPLICATION_PAUSED, MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Quitting mid-load would otherwise write the starting 1500/30 over
			# a real save, since the file has not necessarily been read yet.
			# The stamp is still taken: somebody who locks the phone on the
			# title screen and comes back at lunchtime was away for those
			# hours whether or not the game had finished opening, and it used
			# to be credited to nobody. _after_boot settles up once there is
			# something to settle up against.
			if _boot != null:
				if _away_since <= 0.0:
					_away_since = _now()
				return
			_go_away()
		NOTIFICATION_WM_WINDOW_FOCUS_IN, \
		MainLoop.NOTIFICATION_APPLICATION_RESUMED, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
			if _boot != null:
				return
			_resume_from_away()

# The app is going to sleep, and this is the last code that runs before it
# does. Three things have to happen here and nowhere else:
#
#  - the save, because iOS kills backgrounded apps without further warning;
#  - the raid roll, because a notification has to carry the same words the
#    game will say when it is opened, and it cannot roll dice while asleep;
#  - the notification plan, because nothing can schedule one after this point.
#
# iOS sends resignActive and then didEnterBackground for a single screen lock,
# so this runs twice in a row. Stamping the later of the two is harmless.
# Re-rolling the raids on the second pass is not -- it would throw away the
# plan the first pass just handed to iOS and quietly replace it with a
# different one -- hence the guard.
func _go_away() -> void:
	if _away_since <= 0.0:
		_away_since = _now()
		_preroll_raids(_away_since)
	_flush_save()
	Alerts.schedule(_alert_plan(_now()), _now())
	Alerts.set_badge(_unread_count())

# Coming back.
func _resume_from_away() -> void:
	if _away_since <= 0.0:
		return
	# Bounded the way the cold load already bounds its own elapsed figure. A
	# week is longer than any absence the offline systems have anything left
	# to give for, and this path used to hand the raw number straight on.
	var elapsed := clampf(_now() - _away_since, 0.0, MAX_AWAY_SECS)
	_away_since = 0.0
	# Whatever iOS has not delivered yet was planned against a state the player
	# is now standing in front of and about to change, and whatever it did
	# deliver has been read by the act of opening the game.
	Alerts.cancel_all()
	Alerts.clear_delivered()
	# Every second counts, however short the hop -- see _credit_time_away.
	_credit_time_away(elapsed)
	# Announcing it is a separate question. Under a minute is somebody flicking
	# to another app and back, and "while you were away" over a four-second
	# glance is the game talking to itself.
	if elapsed >= 60.0:
		if _offline_spins_gained > 0:
			_notify("spins", "While you were away, spins refilled  +%d  (%d/%d)" % [_offline_spins_gained, spins, SPIN_CAP], "🌀")
		_offline_raids()
	_offline_spins_gained = 0
	_refresh()
	_flush_save()
	Alerts.set_badge(_unread_count())

# Spins that regenerated over `elapsed` seconds. Shared by the cold load and
# the resume so the two can never drift apart.
#
# The remainder is the whole point of the accumulator. This used to be
# int(elapsed / SPIN_REGEN_SECS) with the leftover dropped on the floor, which
# is fine for one long absence and ruinous for the way a phone game is
# actually played: twelve visits of under two minutes is twenty-two real
# minutes of regen and it paid nothing at all, twelve times over. Banking the
# leftover in the same accumulator _process ticks makes a minute away and a
# minute in front of the screen worth exactly the same, which is what the
# player already assumes and what the "spins are full" notification promises.
func _credit_time_away(elapsed: float) -> void:
	if elapsed <= 0.0:
		return
	if spins >= SPIN_CAP:
		# A full meter is not accruing. Left standing, the leftover would pay
		# out the instant the player spent down to 49.
		_regen_accum = 0.0
		return
	_regen_accum += elapsed
	var steps := int(_regen_accum / SPIN_REGEN_SECS)
	_regen_accum -= float(steps) * SPIN_REGEN_SECS
	var regen := steps * SPIN_REGEN_AMOUNT
	if regen <= 0:
		return
	# Added rather than assigned: a lock during the title screen is credited on
	# top of the cold load's own figure, and one report covers both.
	var gained := mini(regen, SPIN_CAP - spins)
	_offline_spins_gained += gained
	spins += gained
	if spins >= SPIN_CAP:
		_regen_accum = 0.0

# When the meter will next read full, in game time. The one number the "spins
# are full" notification is scheduled against, so it lives next to the maths
# that fills the meter rather than being re-derived at the call site.
func _spins_full_at(from: float) -> float:
	if spins >= SPIN_CAP:
		return 0.0
	var steps := int(ceil(float(SPIN_CAP - spins) / float(SPIN_REGEN_AMOUNT)))
	return from + float(steps) * SPIN_REGEN_SECS - _regen_accum

# --- page transitions ---

# Left to right: the bottom bar's own order, Island / Shop / Spin / Cards /
# Quests, with the three pages the bar has no room for hanging off the end --
# Boxes straight after Cards because that is what you arrive from, then Options
# and Alerts, which nothing leads onward from.
#
# One order now does two jobs. It picks the side a page slides in from, and it
# is the line a swipe walks, so a page that arrives from the right is always a
# page that sits to the right on the bar. The old order counted outward from
# Spin, which had Island and Shop -- opposite ends of the bar -- both sliding
# in from the same side.
const PAGE_ORDER := ["island", "shop", "spin", "collections", "boxes", "quests", "options", "alerts"]

func _page_rank(p: Control) -> int:
	if p == village_page:
		return 0
	if p == slot_page:
		return 2
	for i in PAGE_ORDER.size():
		if pages.get(PAGE_ORDER[i]) == p:
			return i
	return 2

func _goto(target: Control) -> void:
	if _transitioning or target == _current_page or _raiding() or _journey_layer != null:
		return
	if target != pages.get("collections"):
		col_open = ""
	for key in pages:
		if pages[key] == target:
			_fill_page(key)
	_transitioning = true
	Sfx.play("pop", -10.0)
	var from := _current_page
	# Where a back swipe should leave a page the bar cannot reach. Only ever
	# recorded as a page that is on the bar, so that drilling from one off-bar
	# page into another cannot leave the pair swiping back and forth at each
	# other with no way out.
	if _strip_index(target) < 0 and _strip_index(from) >= 0:
		_swipe_home = from
	_current_page = target
	target.visible = true
	var dir := 1.0 if _page_rank(target) > _page_rank(from) else -1.0
	# A page slides in from exactly one screen away, whatever a screen is here.
	var span := view_size().x
	target.position = Vector2(span * dir, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(from, "position", Vector2(-span * dir, 0), 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(target, "position", Vector2.ZERO, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func() -> void:
		from.visible = false
		from.position = Vector2.ZERO
		_transitioning = false
	)
	if target == slot_page:
		_schedule_auto_spin(0.8)
	if target == village_page:
		call_deferred("_check_island_complete")
	_update_nav()
	_refresh()

# Into the shop, aimed at a shelf.
#
# The shop is one scroll of twenty-five products and it stays that way: for a
# casual title the scroll IS the merchandising, and a player who passes the
# $49.99 bundle on the way to a $0.99 spin pack has been shown something that
# tabs would have hidden behind a tap. What the single scroll costs is the
# player who already knows what they want -- six sections between an empty spin
# meter and the spin packs. So the plus on each counter carries a destination,
# and the browsing case keeps the browse.
#
# The bottom nav's Shop tab deliberately does not pass one. Tapping "Shop" is
# not a request for anything in particular, and it should land where the timed
# offer is.
const SHOP_ANCHOR_LEAD := 18.0

func _goto_shop(anchor := "") -> void:
	# Already on the page, so there is no transition to hide the movement --
	# which makes this the one case that should be seen happening. A list that
	# teleports when you tap something outside it reads as the page having been
	# replaced.
	if _current_page == pages.get("shop"):
		var sc_here := _shop_scroll()
		var to_here := _shop_anchor_y(anchor)
		if sc_here == null or to_here < 0:
			return
		# Clamped before it is compared, because the bottom shelves ask to be
		# scrolled further than the list can go: on a tall phone the coin packs
		# sit inside the last screenful, so the raw anchor never equals the
		# scroll position and the "nothing to do" case below would never fire.
		to_here = mini(to_here, int(maxf(sc_here.get_v_scroll_bar().max_value - sc_here.size.y, 0.0)))
		if absi(sc_here.scroll_vertical - to_here) <= 2:
			_nudge_shelf(anchor)
			return
		var tw := create_tween()
		tw.tween_property(sc_here, "scroll_vertical", to_here, 0.32) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return

	_goto(pages["shop"])
	if anchor == "":
		return
	# _goto fills the page; the container still needs a frame of its own to lay
	# the new cards out before any of them has a position worth reading. Set
	# rather than tweened: the page is still sliding in, and it should arrive
	# already looking at the right shelf instead of arriving and then moving.
	await get_tree().process_frame
	var sc := _shop_scroll()
	var to := _shop_anchor_y(anchor)
	if sc != null and to >= 0:
		sc.scroll_vertical = to

# What the plus does when it has nowhere to take you.
#
# Tapping "+" on the coin counter while already parked on the coin packs asks
# the page for a movement of zero pixels, and a button whose whole answer is a
# still screen reads as broken. So the shelf answers for itself: one short bob
# of its nameplate, which says "this is the thing you asked for, and it is
# already in front of you" without moving the list out from under a thumb.
func _nudge_shelf(anchor: String) -> void:
	var node = _shop_anchors.get(anchor)
	if node == null or not is_instance_valid(node):
		return
	var row := node as Control
	row.pivot_offset = row.size * 0.5
	Sfx.play("pop", -12.0)
	# Created on the row rather than on the page, so a player who leaves the
	# shop mid-bob takes the tween with them -- the shop rebuilds its cards
	# from scratch on every visit, and this one is animating a node that is
	# about to be freed.
	var tw := row.create_tween()
	tw.tween_property(row, "scale", Vector2(1.06, 1.06), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _shop_scroll() -> ScrollContainer:
	var body: VBoxContainer = _page_bodies.get("shop")
	return body.get_parent() as ScrollContainer if body != null else null

# -1 for "no such shelf", which is not the same answer as 0 -- 0 is the top of
# the list and a legitimate place to be sent.
func _shop_anchor_y(anchor: String) -> int:
	if anchor == "":
		return 0
	var node = _shop_anchors.get(anchor)
	if node == null or not is_instance_valid(node):
		return -1
	return int(maxf((node as Control).position.y - SHOP_ANCHOR_LEAD, 0.0))

# --- swipe between pages ---
#
# The bar at the bottom stays the way most people move around. This is for the
# rest, who reach for a page by shoving the one they are on out of the way, and
# for whom a five-tab bar is something they never look at twice.
#
# It reads the touch before the interface does, which is the only place it can
# work from: by the time a drag has reached the GUI it belongs to whatever
# button the finger happened to land on. So this watches every touch, stays out
# of the way while the direction is still in doubt, and takes the gesture over
# only once it has clearly gone sideways.

const SWIPE_SLOP := 20.0       # travel before a drag has to declare an axis
const SWIPE_FRACTION := 0.16   # of the screen's width -- turns the page on distance
const SWIPE_FLICK := 520.0     # px/s -- turns it on speed, however short the throw
const SCROLL_SLOP := 16.0      # a list's own deadzone; see _make_page

var _swipe_id := -1
var _swipe_from := Vector2.ZERO
var _swipe_axis := 0           # 0 undecided, 1 ours (sideways), -1 the list's (up and down)
var _swipe_dx := 0.0
var _swipe_vx := 0.0
var _swipe_px := 0.0
var _swipe_ms := 0
var _swipe_home: Control

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_swipe_touch(event)
		return
	if event is InputEventScreenDrag:
		_swipe_drag(event)
		return
	# Every touch is shadowed by an emulated mouse event, and that is the one a
	# Button actually listens to. Once a swipe owns the gesture those have to go
	# too, or the button the finger started on gets its release and fires as the
	# page is already sliding away.
	if _swipe_axis == 1 and (event is InputEventMouseButton or event is InputEventMouseMotion):
		get_viewport().set_input_as_handled()

func _swipe_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		if t.index == 0 and _swipe_ready():
			_swipe_id = 0
			_swipe_from = t.position
			_swipe_axis = 0
			_swipe_dx = 0.0
			_swipe_vx = 0.0
			_swipe_px = t.position.x
			_swipe_ms = Time.get_ticks_msec()
		return
	if t.index != _swipe_id:
		return
	var ours := _swipe_axis == 1
	_swipe_id = -1
	_swipe_axis = 0
	if not ours:
		return
	# A cancelled touch is the system taking the finger away -- a call arriving,
	# the app going to the background. It is not a decision to turn the page.
	if not t.canceled:
		_swipe_settle()
	get_viewport().set_input_as_handled()

func _swipe_drag(d: InputEventScreenDrag) -> void:
	if d.index != _swipe_id:
		return
	if _swipe_axis == 0:
		var moved := d.position - _swipe_from
		if moved.length() < SWIPE_SLOP:
			return
		if absf(moved.x) <= absf(moved.y):
			# Up and down: this is a list being scrolled. Hand the whole gesture
			# back and do not look at it again until the finger lifts.
			_swipe_axis = -1
			return
		# Taken. Let go of whatever is holding the press first -- the order
		# matters, because the release below is pushed back through this same
		# handler and must not be swallowed by the branch it is about to enable.
		_drop_press()
		_swipe_axis = 1
	if _swipe_axis != 1:
		return
	_swipe_dx = d.position.x - _swipe_from.x
	# Timed here rather than read off the event. Godot fills a drag's own
	# velocity from a tracker that needs about a tenth of a second of samples
	# before it reports anything at all, and a flick -- the one gesture that
	# lives or dies on speed -- is regularly over before that. It arrives as a
	# clean zero, which reads as a finger that never moved.
	var ms := Time.get_ticks_msec()
	var dt := float(ms - _swipe_ms) / 1000.0
	if dt >= 0.004:
		var inst := (d.position.x - _swipe_px) / dt
		# Smoothed, so one stuttered frame cannot decide a page turn on its own.
		_swipe_vx = inst if _swipe_vx == 0.0 else lerpf(_swipe_vx, inst, 0.5)
		_swipe_px = d.position.x
		_swipe_ms = ms
	get_viewport().set_input_as_handled()

# Unpresses whatever the finger came down on, without letting it fire. There is
# no call for this, so it is done the way the control itself understands: the
# pointer is moved somewhere it cannot be over anything and released there. A
# button reached that way lifts quietly -- it still reports the release, so the
# press animation returns to rest, but it does not count as having been clicked.
func _drop_press() -> void:
	var away := Vector2(-4000, -4000)
	var mm := InputEventMouseMotion.new()
	mm.position = away
	mm.global_position = away
	get_viewport().push_input(mm)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.position = away
	mb.global_position = away
	get_viewport().push_input(mb)

# A swipe counts if it went far enough, or if it went fast enough -- a short
# hard flick is how people who know the gesture use it, and asking them for a
# sixth of the screen as well makes it feel like it is not listening.
func _swipe_settle() -> void:
	# A raid announcing itself, or an offer popping, between the finger moving
	# and the finger lifting. Whatever arrived is what the player is looking at.
	if not _swipe_ready():
		return
	var dir := 0
	if absf(_swipe_dx) >= view_size().x * SWIPE_FRACTION:
		dir = 1 if _swipe_dx > 0.0 else -1
	elif absf(_swipe_vx) >= SWIPE_FLICK:
		dir = 1 if _swipe_vx > 0.0 else -1
	if dir != 0:
		_swipe_page(dir)

# dir is +1 for a finger travelling right, which fetches the page to the left.
func _swipe_page(dir: int) -> void:
	# An opened card set is the nearest thing to go back out of, so a back swipe
	# closes it before it does anything to the page underneath.
	if dir > 0 and _current_page == pages.get("collections") and not col_open.is_empty():
		col_open = ""
		_fill_page("collections")
		Sfx.play("pop", -12.0)
		return
	var here := _strip_index(_current_page)
	if here < 0:
		# Somewhere you drilled into. There is nothing forward of it; back leaves.
		if dir > 0:
			_goto(_swipe_home if _swipe_home != null else slot_page)
		return
	var there := here - dir
	if there >= 0 and there < _swipe_strip().size():
		_goto(_swipe_strip()[there])

# The five pages the bar can reach, in the order it shows them.
func _swipe_strip() -> Array:
	return [village_page, pages.get("shop"), slot_page, pages.get("collections"), pages.get("quests")]

func _strip_index(p: Control) -> int:
	return _swipe_strip().find(p)

# Nothing is turning the page out from under a raid, a popup, the title screen,
# or a transition that has not landed yet.
func _swipe_ready() -> bool:
	return _boot == null and not _transitioning and not _raiding() \
		and _journey_layer == null and _popup == null and _login_layer == null

# --- bottom navigation bar ---

var _nav_tabs := {}
var _spin_nav: Button
var _spin_glow: ColorRect
var _float_options: Button

const NAV_BAR_H := 118.0
const NAV_ROOT_H := 152.0

# How the 118 units of a tab are spent, top to bottom: the glyph in its plate,
# then a gap, then the word, then the clearance the home indicator needs. The
# bands are written out here, in one place and all measured from the top, so
# they can be seen not to overlap. Scattered as anchor offsets through
# _build_nav they were not: the caption's were measured from the *other* end of
# the button, and ran 24 units back up into the glyph without anyone noticing.
const NAV_PLATE_TOP := 8.0
const NAV_PLATE_H   := 62.0
const NAV_ICON_TOP  := 16.0
const NAV_ICON_H    := 48.0
const NAV_CAP_TOP   := 68.0
const NAV_CAP_H     := 34.0

# The screen the game actually got, and the parts of it that are ours to draw
# on. The arithmetic lives in UI, which the title screen and the raid overlay
# reach for too; these are just the shorthands this file reads better with.

func view_size() -> Vector2:
	return get_viewport_rect().size

func safe_top() -> float:
	return UI.safe_top(view_size())

func safe_bottom() -> float:
	return UI.safe_bottom(view_size())

# Where the nav bar cuts the page off. Everything above it is the page's.
func content_bottom() -> float:
	return view_size().y - NAV_ROOT_H - safe_bottom()

# The top edge of the nav bar's glass slab, a little below where the bar's own
# rect starts -- the raised SPIN button hangs in the gap between them. Art that
# reaches this line leaves nothing bare behind the bar.
func nav_slab_top() -> float:
	return content_bottom() + (NAV_ROOT_H - NAV_BAR_H)

func _build_nav() -> void:
	var nav_root := Control.new()
	nav_root.z_index = 50
	nav_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nav_root)
	nav_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# Grown downward past the home indicator: the slab fills that strip so no
	# background shows under it, while the tabs inside stop above it.
	nav_root.offset_top = -(NAV_ROOT_H + safe_bottom())

	# A slab of sea glass resting on the water with a brass lip along its top
	# edge -- the same two materials as every card above it, so the bar reads as
	# part of the game rather than an operating-system chrome strip.
	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.90)
	sb.corner_radius_top_left = 34
	sb.corner_radius_top_right = 34
	sb.border_width_top = 4
	sb.border_color = Lagoon.BRASS
	sb.shadow_size = 18
	sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.30)
	sb.shadow_offset = Vector2(0, -5)
	bar.add_theme_stylebox_override("panel", sb)
	nav_root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_top = NAV_ROOT_H - NAV_BAR_H
	Lagoon.add_gloss(bar, 34)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	nav_root.add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_top = NAV_ROOT_H - NAV_BAR_H
	hb.offset_bottom = -safe_bottom()

	var tabs := [
		["island", "Island", "island"],
		["shop", "Shop", "shop"],
		null,  # gap under the raised center Spin button
		["cards", "Cards", "collections"],
		["quests", "Quests", "quests"],
	]
	for t in tabs:
		if t == null:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(150, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(gap)
			continue
		var key: String = t[2]
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		hb.add_child(btn)
		FX.press_feedback(btn)

		# The live tab's glyph sits in a plate of its own. Coral means "this is
		# the live one" here for the same reason it means "tap this" on a
		# button, but as a wash rather than a fill -- one solid coral shape
		# belongs on this bar and it is the SPIN disc.
		#
		# This used to be a coral tick pinned to the top edge of the button,
		# which is a strip the glyph wants when it grows for the active state
		# and the alert badge wants all the time. Behind the glyph it collides
		# with neither, and it says which tab you are on from further away.
		var plate := Panel.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(Lagoon.CORAL.r, Lagoon.CORAL.g, Lagoon.CORAL.b, 0.18)
		psb.set_corner_radius_all(22)
		psb.set_border_width_all(3)
		psb.border_color = Color(Lagoon.CORAL.r, Lagoon.CORAL.g, Lagoon.CORAL.b, 0.55)
		plate.add_theme_stylebox_override("panel", psb)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.visible = false
		btn.add_child(plate)
		plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		plate.offset_left = -42.0
		plate.offset_right = 42.0
		plate.offset_top = NAV_PLATE_TOP
		plate.offset_bottom = NAV_PLATE_TOP + NAV_PLATE_H

		var icon := Glyph.new()
		icon.kind = t[0]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.resized.connect(func() -> void: icon.pivot_offset = icon.size * 0.5)
		btn.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		icon.offset_top = NAV_ICON_TOP
		icon.offset_bottom = NAV_ICON_TOP + NAV_ICON_H

		# The word gets a band of its own below the icon. It used to be anchored
		# so that its box climbed 24 units back up into the glyph, and a caption
		# printed over a drawn palm tree is not a caption -- it is texture. The
		# two never overlap now, at any tab scale.
		var cap := Lagoon.label(t[1], UI.F_CAPTION, Lagoon.INK_MUTE, true)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cap)
		cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		cap.offset_top = -(NAV_BAR_H - NAV_CAP_TOP)
		cap.offset_bottom = -(NAV_BAR_H - NAV_CAP_TOP - NAV_CAP_H)

		if key == "island":
			btn.pressed.connect(func() -> void: _goto(village_page))
		else:
			btn.pressed.connect(func() -> void: _goto(pages[key]))

		_nav_tabs[key] = {"button": btn, "icon": icon, "cap": cap, "plate": plate}

	# raised circular Spin button in the middle of the bar
	_spin_glow = ColorRect.new()
	var glow_sh := Lagoon.shader("""
shader_type canvas_item;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.3, 1.0, d)) * 0.55;
	COLOR = vec4(1.0, 0.55, 0.40, a);
}
""")
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = glow_sh
	_spin_glow.material = glow_mat
	_spin_glow.size = Vector2(214, 214)
	_spin_glow.position = Vector2(360 - 107, -42)
	_spin_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_root.add_child(_spin_glow)

	# The one coral disc on the bar, ringed in brass and lifted above the glass.
	# Nothing else in the nav is coral, so the eye lands here first every time.
	_spin_nav = Button.new()
	_spin_nav.size = Vector2(132, 132)
	_spin_nav.position = Vector2(360 - 66, 0)
	_spin_nav.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var csb := StyleBoxFlat.new()
		match state:
			"hover":
				csb.bg_color = Lagoon.CORAL_HI
			"pressed":
				csb.bg_color = Lagoon.CORAL.darkened(0.12)
			_:
				csb.bg_color = Lagoon.CORAL
		csb.set_corner_radius_all(66)
		csb.set_border_width_all(6)
		csb.border_color = Lagoon.BRASS
		csb.shadow_size = 14
		csb.shadow_color = Color(Lagoon.CORAL_LO.r, Lagoon.CORAL_LO.g, Lagoon.CORAL_LO.b, 0.45)
		csb.shadow_offset = Vector2(0, 5)
		_spin_nav.add_theme_stylebox_override(state, csb)
	_spin_nav.pressed.connect(func() -> void: _goto(slot_page))
	nav_root.add_child(_spin_nav)
	Lagoon.button_gloss(_spin_nav, 66)

	var spin_icon := Glyph.new()
	spin_icon.kind = "wheel"
	spin_icon.tint = Lagoon.SAND
	_spin_nav.add_child(spin_icon)
	spin_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	spin_icon.offset_left = 36.0
	spin_icon.offset_right = -36.0
	spin_icon.offset_top = 18.0
	spin_icon.offset_bottom = 78.0

	# Lifted clear of the wheel above it, for the same reason as the tab
	# captions -- the rim of the wheel was landing on the S and the P.
	var spin_cap := Lagoon.title("SPIN", UI.F_LABEL, Lagoon.SAND, Lagoon.CORAL_LO)
	spin_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_spin_nav.add_child(spin_cap)
	spin_cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	spin_cap.offset_top = -52.0
	spin_cap.offset_bottom = -10.0

	_build_float_options()

	# alert badges live on the nav tabs
	_badges["missions"] = _nav_badge(_nav_tabs["quests"]["button"])
	_badges["collections"] = _nav_badge(_nav_tabs["collections"]["button"])
	_badges["shop_free"] = _nav_badge(_nav_tabs["shop"]["button"], "1")

	_update_nav()

# floating Options button — sits over the game at the top right instead of
# taking a slot in the bottom bar, which keeps the bar symmetric (2 + spin + 2)
func _build_float_options() -> void:
	var layer := Control.new()
	layer.z_index = 60
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Small, quiet and out of the wordmark's way: settings is the one control on
	# the page nobody is meant to be drawn to.
	_float_options = Button.new()
	_float_options.size = Vector2(66, 66)
	_float_options.position = Vector2(view_size().x - 14.0 - 66.0, 96.0 + safe_top())
	_float_options.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.80) if state != "hover" else Color(1, 1, 1, 0.95)
		sb.set_corner_radius_all(33)
		sb.set_border_width_all(3)
		sb.border_color = Lagoon.BRASS
		sb.shadow_size = 6
		sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.25)
		sb.shadow_offset = Vector2(0, 3)
		_float_options.add_theme_stylebox_override(state, sb)
	_float_options.pressed.connect(func() -> void: _goto(pages["options"]))
	FX.press_feedback(_float_options)
	layer.add_child(_float_options)
	var gear := Glyph.new()
	gear.kind = "gear"
	gear.tint = Lagoon.INK_SOFT
	_float_options.add_child(gear)
	gear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in [["offset_left", 13.0], ["offset_right", -13.0], ["offset_top", 13.0], ["offset_bottom", -13.0]]:
		gear.set(m[0], m[1])

func _nav_badge(parent: Control, text := "!") -> Panel:
	var badge := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Lagoon.REEF
	bsb.set_corner_radius_all(15)
	bsb.set_border_width_all(3)
	bsb.border_color = Color.WHITE
	bsb.shadow_size = 5
	bsb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.3)
	badge.add_theme_stylebox_override("panel", bsb)
	badge.visible = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	badge.offset_left = 18.0
	badge.offset_right = 48.0
	badge.offset_top = 2.0
	badge.offset_bottom = 32.0
	var bang := Lagoon.label(text, UI.F_CAPTION, Color.WHITE, true)
	bang.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bang.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bang)
	bang.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return badge

func _update_nav() -> void:
	var active := "spin"
	if _current_page == village_page:
		active = "island"
	else:
		for pkey in pages:
			if pages[pkey] == _current_page:
				active = pkey
				break
	for key in _nav_tabs:
		var tab: Dictionary = _nav_tabs[key]
		var is_active: bool = key == active
		var icon: Control = tab["icon"]
		icon.pivot_offset = icon.size * 0.5
		var target := Vector2(1.14, 1.14) if is_active else Vector2.ONE
		icon.create_tween().tween_property(icon, "scale", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Inactive tabs wash out toward the glass rather than dimming to grey --
		# on a light bar, "further away" reads better than "switched off".
		# Only the drawing washes out, though. A tab you cannot read is not a
		# quieter tab, it is a missing one, so the word underneath holds a
		# contrast the eye can still land on and the icon carries the state.
		icon.modulate = Color.WHITE if is_active else Color(1, 1, 1, 0.72)
		(tab["cap"] as Label).add_theme_color_override("font_color", Lagoon.INK if is_active else Lagoon.INK_MUTE)
		tab["plate"].visible = is_active
	if _float_options != null:
		_float_options.visible = active != "options"
	var spin_active := active == "spin"
	if _spin_glow != null:
		_spin_glow.create_tween().tween_property(_spin_glow, "modulate:a", 1.0 if spin_active else 0.3, 0.25)
	if _spin_nav != null:
		_spin_nav.pivot_offset = _spin_nav.size * 0.5
		var s := Vector2(1.08, 1.08) if spin_active else Vector2(0.94, 0.94)
		_spin_nav.create_tween().tween_property(_spin_nav, "scale", s, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- pages ---

func _build_slot_page() -> void:
	slot_page = Control.new()
	add_child(slot_page)
	slot_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_add_slot_stage(slot_page)

	# The page's own vertical budget. Everything above the machine hangs off the
	# top of the safe area; the machine gets whatever is left between that and
	# the nav bar, which is what keeps a tall phone from opening a lake of dead
	# background under the cabinet.
	var top := safe_top()
	var band := Rect2(Vector2(0.0, 316.0 + top),
		Vector2(view_size().x, content_bottom() - (316.0 + top)))

	# floating decorative symbols
	# Three, in the corners of the band beside the quick-action row. This used to
	# be seven scattered anywhere, which put a stray gem on top of the legend and
	# a coin behind the nav bar on a page that already has plenty to look at.
	var decor_ids := ["coin", "gem", "coin"]
	for i in decor_ids.size():
		var t := CV.symbol_tex(decor_ids[i])
		if t == null:
			continue
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var s := randf_range(46, 86)
		tr.size = Vector2(s, s)
		tr.rotation = randf_range(-0.3, 0.3)
		# The page is busy enough: decor lives only in the two thin bands the
		# wordmark and the machine leave free, and stays faint.
		tr.position = Vector2(
			randf_range(6, 62) if i % 2 == 0 else view_size().x - randf_range(56, 120),
			randf_range(196, 292) + top)
		tr.modulate = Color(1, 1, 1, randf_range(0.26, 0.40))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_page.add_child(tr)
		FX.float_bob(tr, randf_range(10, 24), randf_range(1.8, 3.4))
		_slot_decor.append({"node": tr, "alpha": tr.modulate.a})

	# glow behind slot machine
	var glow := ColorRect.new()
	var glow_shader := Lagoon.shader("""
shader_type canvas_item;
uniform vec3 glow_col = vec3(1.0, 0.85, 0.4);
void fragment() {
	float d = length(UV - 0.5);
	float a = smoothstep(0.5, 0.05, d) * 0.35;
	COLOR = vec4(glow_col, a);
}
""")
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = glow_shader
	glow.material = glow_mat
	_slot_glow_mat = glow_mat
	glow.size = Vector2(band.size.x + 80.0, band.size.y * 0.86)
	glow.position = Vector2(-40.0, band.position.y + 56.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_page.add_child(glow)
	FX.pulse_forever(glow, 1.05, 1.6)

	# The wordmark: sand-coloured display type cut with a deep brass outline, so
	# it reads as a carved sign rather than coloured text. Unlike the rest of
	# the SPIN page it does *not* change per island -- the one thing that must
	# look identical on all thirty is the game's own name.
	var logo := Lagoon.wordmark("LOOT  LAGOON", 62)
	slot_page.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 92.0 + top
	logo.offset_bottom = 172.0 + top
	FX.pulse_forever(logo, 1.03, 2.4)
	_slot_logo = logo

	slot = SlotView.new()
	slot_page.add_child(slot)
	slot.position = band.position
	slot.size = band.size
	slot.spin_requested.connect(_on_spin_requested)
	slot.spin_finished.connect(_on_spin_finished)
	slot.auto_toggled.connect(func(on: bool) -> void:
		auto_spin = on
		if on:
			_schedule_auto_spin(0.25)
	)

	_pick_next_target()

	_add_topbar(slot_page)
	_add_side_buttons(slot_page)

# The SPIN page backdrop. Instead of one fixed slot-room painting, it layers
# the island's own artwork -- blurred, dimmed and tinted so it reads as a lit
# room rather than a competing illustration -- under colored light rays and a
# floor gradient. Every island therefore has its own spin room.
func _add_slot_stage(page: Control) -> void:
	var bg := TextureRect.new()
	bg.texture = CV.island_bg_tex(island_level)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_sh := Lagoon.shader("""
shader_type canvas_item;

uniform vec3 haze = vec3(0.72, 0.92, 0.96);
uniform float haze_amt = 0.52;
uniform float lift = 1.10;
uniform float blur_px = 3.2;

void fragment() {
	// cheap 9-tap gaussian: enough to push the island art out of focus so the
	// cabinet in front of it stays the sharpest thing on screen
	vec2 s = TEXTURE_PIXEL_SIZE * blur_px;
	vec4 c = texture(TEXTURE, UV) * 0.196;
	c += (texture(TEXTURE, UV + vec2(s.x, 0.0)) + texture(TEXTURE, UV - vec2(s.x, 0.0))
	   +  texture(TEXTURE, UV + vec2(0.0, s.y)) + texture(TEXTURE, UV - vec2(0.0, s.y))) * 0.118;
	c += (texture(TEXTURE, UV + s) + texture(TEXTURE, UV - s)
	   +  texture(TEXTURE, UV + vec2(s.x, -s.y)) + texture(TEXTURE, UV + vec2(-s.x, s.y))) * 0.083;
	// Aerial perspective, not a dimmer: the island art is washed toward the
	// island's own sky colour and lifted, so the machine has something bright
	// to sit against. The page reads as noon on the water rather than a
	// darkened arcade -- and the blur still keeps the cabinet the sharpest
	// thing on screen.
	vec3 rgb = mix(c.rgb * lift, haze, haze_amt);
	// distance haze: clearest around the cabinet, mistiest at the edges
	vec2 v = (UV - vec2(0.5, 0.42)) * vec2(1.15, 1.0);
	rgb = mix(rgb, haze, smoothstep(0.22, 0.98, length(v)) * 0.45);
	COLOR = vec4(rgb, 1.0);
}
""")
	_slot_bg_mat = ShaderMaterial.new()
	_slot_bg_mat.shader = bg_sh
	bg.material = _slot_bg_mat
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_bg = bg

	var rays := ColorRect.new()
	var rays_sh := Lagoon.shader("""
shader_type canvas_item;

uniform vec3 ray_col = vec3(1.0, 0.82, 0.40);

void fragment() {
	// fan of soft beams from a point just above the top edge, drifting slowly
	vec2 p = UV - vec2(0.5, -0.15);
	float ang = atan(p.x, p.y);
	float rays = pow(0.5 + 0.5 * sin(ang * 24.0 + TIME * 0.22), 3.5);
	float fall = smoothstep(1.15, 0.08, length(p));
	COLOR = vec4(ray_col, rays * fall * smoothstep(1.0, 0.12, UV.y) * 0.24);
}
""")
	_slot_rays_mat = ShaderMaterial.new()
	_slot_rays_mat.shader = rays_sh
	rays.material = _slot_rays_mat
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(rays)
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var floor_rect := ColorRect.new()
	var floor_sh := Lagoon.shader("""
shader_type canvas_item;

uniform vec3 floor_col = vec3(0.55, 0.87, 0.90);

void fragment() {
	// Shallow water washing up to the nav bar. It grounds the bottom of the
	// page the way the old dark floor did, but by getting brighter toward the
	// edge instead of darker -- foam, not shadow.
	float t = smoothstep(0.50, 1.0, UV.y);
	COLOR = vec4(floor_col, t * 0.80);
}
""")
	_slot_floor_mat = ShaderMaterial.new()
	_slot_floor_mat.shader = floor_sh
	floor_rect.material = _slot_floor_mat
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(floor_rect)
	floor_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# --- side menu buttons ---

# Daily / Alerts / Ranks as a row of brass-ringed glass discs in the band
# between the wordmark and the machine.
#
# These used to be two vertical columns pinned to the page edges, which only
# works if the machine is narrower than the screen -- ours is 660 of 720 wide,
# so the Alerts button sat on top of the cabinet's marquee. A centred row owns
# a horizontal band nothing else is using and can never collide with the stage.
func _add_side_buttons(page: Control) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	page.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_top = 184.0 + safe_top()
	row.offset_bottom = 306.0 + safe_top()
	_side_button(row, "gift", "Daily", "daily", _open_daily)
	_side_button(row, "bell", "Alerts", "alerts", func() -> void: _goto(pages["alerts"]))
	_side_button(row, "trophy", "Ranks", "ranks", _open_ranks)

func _side_button(container: BoxContainer, icon_kind: String, caption: String, badge_key: String, action: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	container.add_child(box)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(UI.TAP_COMFY, UI.TAP_COMFY)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.92) if state != "hover" else Color(1, 1, 1, 1.0)
		sb.set_corner_radius_all(UI.TAP_COMFY / 2)
		sb.set_border_width_all(4)
		sb.border_color = Lagoon.BRASS
		sb.shadow_size = 8
		sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.30)
		sb.shadow_offset = Vector2(0, 4)
		btn.add_theme_stylebox_override(state, sb)
	btn.pressed.connect(action)
	FX.press_feedback(btn)
	box.add_child(btn)
	Lagoon.add_gloss(btn, UI.TAP_COMFY / 2)

	var icon := Glyph.new()
	icon.kind = icon_kind
	btn.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in [["offset_left", 16.0], ["offset_right", -16.0], ["offset_top", 16.0], ["offset_bottom", -16.0]]:
		icon.set(m[0], m[1])

	var badge := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Lagoon.REEF
	bsb.set_corner_radius_all(17)
	bsb.set_border_width_all(3)
	bsb.border_color = Color.WHITE
	badge.add_theme_stylebox_override("panel", bsb)
	badge.size = Vector2(34, 34)
	badge.position = Vector2(UI.TAP_COMFY - 28, -6)
	badge.visible = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge)
	var bang := Lagoon.label("!", UI.F_CAPTION, Color.WHITE, true)
	bang.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bang.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bang)
	bang.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badges[badge_key] = badge

	var cap := Lagoon.title(caption, UI.F_CAPTION, Color.WHITE, Lagoon.ABYSS)
	box.add_child(cap)

func _update_badges() -> void:
	if _badges.is_empty():
		return
	if _badges.has("daily"):
		_badges["daily"].visible = _daily_ready()
	if _badges.has("missions"):
		var any_claim := false
		for period in MISSION_DEFS:
			if _period_claimable(period):
				any_claim = true
				break
		_badges["missions"].visible = any_claim
	if _badges.has("collections"):
		var any_col := false
		for c in CV.COLLECTIONS:
			if not col_claimed.get(c["id"], false) and _collection_complete(c):
				any_col = true
				break
		_badges["collections"].visible = any_col
	if _badges.has("alerts"):
		var unread := _unread_count()
		_badges["alerts"].visible = unread > 0
		var bl := _badges["alerts"].get_child(0) as Label
		if bl != null:
			bl.text = str(mini(unread, 9)) if unread > 0 else "!"
	if _badges.has("shop_free"):
		_badges["shop_free"].visible = _shop_free_ready() or _piggy_full() or not _active_offer().is_empty()
	if _convert_badge != null and is_instance_valid(_convert_badge):
		var spare := _dupe_card_count()
		_convert_badge.visible = spare > 0
		var cl := _convert_badge.get_child(0) as Label
		if cl != null:
			cl.text = str(mini(spare, 99))

func _daily_ready() -> bool:
	return _now() - daily_last >= DAILY_COOLDOWN

func _mission_add(id: String, amount := 1) -> void:
	_ensure_missions()
	for period in MISSION_DEFS:
		for m in MISSION_DEFS[period]:
			if m["id"] == id:
				var prog: Dictionary = mission_state[period]["progress"]
				prog[id] = int(prog.get(id, 0)) + amount
				break
	_update_badges()

# ONE curve for the whole economy. A star costs 1.6x more per island, so every
# coin the game mints -- reel wins, raids, gifts, missions, shop packs -- is
# written in the source at its island-1 price and run through here on the way
# out. Anything that skips this decays to nothing: a flat 100-coin reel win is
# 0.0001% of a build at island 30, which would leave missions as the only
# income worth collecting and turn the slot machine into decoration.
# Stars land in the counter the way coins do -- something leaves the thing that
# paid out and arrives at the number that went up -- because a currency that
# only ever appears as a label ticking over never becomes a currency the player
# thinks about.
# The single door every earned star comes through. Anything that credits stars
# by touching `stars` directly is a bug: it would pay the wallet and skip the
# standing, and the leaderboard would quietly stop matching the game.
func _earn_stars(n: int) -> void:
	if n <= 0:
		return
	stars += n
	rank_stars += n

func _award_stars(n: int, from_global := Vector2.ZERO) -> void:
	if n <= 0:
		return
	_earn_stars(n)
	_update_badges()
	_star_flight(n, from_global)

# The celebration half of _award_stars, on its own, for the one caller that has
# to bank the stars now and show them arriving later -- see
# _on_upgrade_requested, where the gap between the two is a scaffold animation
# the app may not survive.
func _star_flight(n: int, from_global := Vector2.ZERO) -> void:
	if n <= 0 or _hud_labels.is_empty() or not _hud_labels[0].has("stars"):
		return
	var to: Vector2 = _hud_labels[0]["stars"].global_position
	var src := from_global if from_global != Vector2.ZERO else Vector2(view_size().x * 0.5, view_size().y * 0.45)
	FX.fly_coins(self, src, to, clampi(n, 3, 10), "star", "\u2b50")
	Sfx.play("levelup", -10.0)

func _economy_mult() -> float:
	return CV.curve(island_level)

# Scaled coins, snapped to three significant digits. Payouts should read as
# "+660" and "+1.25M", never as "+655" and "+1,246,151".
func _scaled(base: int, level := 0) -> int:
	return CV.scaled(base, island_level if level <= 0 else level)

# Targets counted in coins ride the same curve as the payouts they measure --
# otherwise a single reel win clears the 250,000-coin monthly at high islands.
const MISSION_COIN_TARGETS := ["coins_won"]

# Sailing to the next island multiplies the coins_won target by 1.6, so the
# progress banked against it has to move with it. Without this a player who
# finishes an island at 90% of the weekly drops back to 56% for no reason they
# can see.
func _rescale_coin_progress() -> void:
	for period in MISSION_DEFS:
		var prog: Dictionary = mission_state.get(period, {}).get("progress", {})
		for id in MISSION_COIN_TARGETS:
			if prog.has(id):
				prog[id] = int(round(int(prog[id]) * 1.6))

func _mission_target(m: Dictionary) -> int:
	if m["id"] in MISSION_COIN_TARGETS:
		return _scaled(int(m["target"]))
	return int(m["target"])

func _mission_coins(m: Dictionary) -> int:
	return _scaled(int(m.get("coins", 0)))

func _bonus_coins(period: String) -> int:
	return _scaled(int(MISSION_BONUS[period]["coins"]))

func _period_key(period: String) -> int:
	var now := int(_now())
	match period:
		"weekly":
			# +3 aligns week boundaries to Monday (unix day 0 was a Thursday)
			return (now / 86400 + 3) / 7
		"monthly":
			var d := Time.get_datetime_dict_from_unix_time(now)
			return int(d["year"]) * 12 + int(d["month"])
	return now / 86400

func _period_reset_secs(period: String) -> int:
	var now := int(_now())
	match period:
		"weekly":
			var into := ((now / 86400 + 3) % 7) * 86400 + now % 86400
			return 7 * 86400 - into
		"monthly":
			var d := Time.get_datetime_dict_from_unix_time(now)
			var y := int(d["year"])
			var mo := int(d["month"]) + 1
			if mo > 12:
				mo = 1
				y += 1
			var next := Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": 1, "hour": 0, "minute": 0, "second": 0})
			return maxi(1, int(next) - now)
	return 86400 - now % 86400

func _countdown_text(secs: int) -> String:
	if secs >= 86400:
		return "%dd %02dh %02dm" % [secs / 86400, (secs % 86400) / 3600, (secs % 3600) / 60]
	return "%02d:%02d:%02d" % [secs / 3600, (secs % 3600) / 60, secs % 60]

func _ensure_missions() -> void:
	var changed := false
	for period in MISSION_DEFS:
		var key := _period_key(period)
		var raw_st = mission_state.get(period, {})
		var st: Dictionary = raw_st if typeof(raw_st) == TYPE_DICTIONARY else {}
		# Rolls forward only. This was `!= key`, which treats a period key that
		# has gone *backwards* as a new period -- so winding the device clock
		# back wiped and re-armed every quest set exactly the way winding it
		# forward does. Offensively that made the whole board plus its
		# completion bonus re-earnable on demand; accidentally, it deleted a
		# nearly-finished monthly set from anyone whose phone lost its clock.
		# All three key spaces (day count, week count, year*12+month) are
		# monotonic, so "later than the one we recorded" is well defined.
		if st.is_empty() or _i(st.get("key", -1), -1) < key:
			mission_state[period] = {"key": key, "progress": {}, "claimed": {}, "bonus": false}
			changed = true
	if changed:
		_update_badges()

func _mission_ready(period: String, m: Dictionary) -> bool:
	var st: Dictionary = mission_state[period]
	if bool(st["claimed"].get(m["id"], false)):
		return false
	return int(st["progress"].get(m["id"], 0)) >= _mission_target(m)

func _bonus_ready(period: String) -> bool:
	var st: Dictionary = mission_state[period]
	if bool(st.get("bonus", false)):
		return false
	for m in MISSION_DEFS[period]:
		if not bool(st["claimed"].get(m["id"], false)):
			return false
	return true

func _period_claimable(period: String) -> bool:
	if mission_state.get(period, {}).is_empty():
		return false
	if _bonus_ready(period):
		return true
	for m in MISSION_DEFS[period]:
		if _mission_ready(period, m):
			return true
	return false

# --- popups ---

func _open_popup(title: String) -> VBoxContainer:
	_close_popup(true)
	_popup = Control.new()
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.z_index = 120
	add_child(_popup)
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Deep water rather than black: the page behind stays readable as a place
	# you're still standing in, which is the difference between a dialog and a
	# modal that swallows the game.
	var dim := ColorRect.new()
	dim.color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_popup.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Negative separation hangs the brass nameplate over the lip of the glass,
	# so a modal reads as a labelled object instead of a box with a heading.
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", -26)
	center.add_child(holder)

	var plate_row := CenterContainer.new()
	holder.add_child(plate_row)
	var plate := Lagoon.plaque(title, 0.0, 76.0, UI.F_SUBHEAD)
	plate.z_index = 1
	plate_row.add_child(plate)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Lagoon.glass(Lagoon.R_PANEL, 0.96))
	panel.custom_minimum_size = Vector2(580, 0)
	holder.add_child(panel)
	FX.pop_in(holder, 0.32)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 44)  # clears the nameplate
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	Lagoon.add_gloss(panel, Lagoon.R_PANEL)

	# Close sits on the corner of the glass, not in the content flow, so it
	# never competes for space with what the modal is actually about.
	#
	# It is parented to the popup layer rather than to the panel: PanelContainer
	# stretches every child to fill its rect, so a button added there ignores
	# its anchors and swallows the whole modal. Instead it tracks the panel's
	# corner whenever the panel is laid out.
	var x := Button.new()
	x.size = Vector2(72, 72)
	Lagoon.button(x, "danger", 36)
	x.pressed.connect(func() -> void: _close_popup())
	_popup.add_child(x)
	x.z_index = 2
	# Guarded, because the call below is deferred to the end of the frame and
	# the popup may not last that long: _open_popup starts by closing whatever
	# was already up, so two modals opening in the same frame -- a purchase
	# confirm handing straight over to a chest result, most often -- free this
	# one's panel and button before the deferred call runs. GDScript passes a
	# freed capture as null rather than refusing to call.
	var place_close := func() -> void:
		if not is_instance_valid(x) or not is_instance_valid(panel):
			return
		x.position = panel.global_position + Vector2(panel.size.x - 40.0, -32.0)
	panel.resized.connect(place_close)
	panel.item_rect_changed.connect(place_close)
	place_close.call_deferred()

	var xg := Glyph.new()
	xg.kind = "close"
	x.add_child(xg)
	xg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in [["offset_left", 20.0], ["offset_right", -20.0], ["offset_top", 20.0], ["offset_bottom", -24.0]]:
		xg.set(m[0], m[1])

	Sfx.play("pop", -8.0)
	return vbox

func _close_popup(instant := false) -> void:
	if _popup == null:
		return
	var p := _popup
	_popup = null
	if instant:
		p.queue_free()
		return
	# On the popup, so opening another one mid-fade cannot leave a tween on main
	# calling queue_free on a node that has already gone.
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.16)
	tw.tween_callback(p.queue_free)

func _popup_row_label(text: String, size := UI.F_LABEL) -> Label:
	return Lagoon.label(text, size, Lagoon.INK)

# For copy that sits on the page itself rather than inside a card. Ink reads on
# glass and vanishes on water, so anything floating gets outlined white.
func _page_note(text: String, size := UI.F_CAPTION) -> Label:
	var l := Lagoon.title(text, size, Color.WHITE, Lagoon.ABYSS)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _open_daily() -> void:
	var vbox := _open_popup("Daily Bonus")
	var gift := _emoji_label("🎁", 74)
	gift.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gift)
	FX.pulse_forever(gift, 1.1, 1.0)
	if _daily_ready():
		var info := _popup_row_label("Your daily reward is ready!")
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(info)
		var claim := Button.new()
		var daily_coins := _scaled(DAILY_BONUS_COINS)
		claim.text = "CLAIM  +%s coins, +%d spins" % [_fmt_compact(daily_coins), DAILY_BONUS_SPINS]
		claim.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
		_candy_button(claim, Color(0.45, 0.75, 0.35))
		FX.press_feedback(claim)
		claim.pressed.connect(func() -> void:
			# Re-checked on the press, not just when the button was drawn.
			# _close_popup() fades the popup out over 0.16s and Godot does not
			# gate input on modulate, so the button stayed live and tappable
			# through the fade -- a double-tap claimed the day's bonus twice
			# and ticked the "claim N dailies" quests twice with it. Every
			# other claim in the game re-checks its own gate first; this was
			# the one that did not.
			if not _daily_ready():
				return
			claim.disabled = true
			daily_last = _now()
			coins += daily_coins
			# rewards always add — the cap only limits time-based regen
			spins += DAILY_BONUS_SPINS
			_mission_add("daily_gift")
			Sfx.play("jackpot", -3.0)
			FX.confetti(self, 36)
			FX.flash(self)
			FX.fly_coins(self, Vector2(360, 620), _hud_labels[0]["coins"].global_position, 8)
			_close_popup()
			_update_badges()
			_refresh()
			_save_game()
		)
		vbox.add_child(claim)
	else:
		var left := maxi(0, int(DAILY_COOLDOWN - (_now() - daily_last)))
		var info := _popup_row_label("Next bonus in  %s" % _countdown_text(left))
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(info)

func _claim_mission(period: String, m: Dictionary) -> void:
	if not _mission_ready(period, m):
		return
	mission_state[period]["claimed"][m["id"]] = true
	_grant_mission_reward(_mission_coins(m), int(m.get("spins", 0)))
	_fill_page("quests")

func _claim_mission_bonus(period: String) -> void:
	if not _bonus_ready(period):
		return
	mission_state[period]["bonus"] = true
	_grant_mission_reward(_bonus_coins(period), int(MISSION_BONUS[period]["spins"]))
	FX.confetti(self, 46)
	FX.flash(self)
	_fill_page("quests")

func _grant_mission_reward(coin_amt: int, spin_amt: int) -> void:
	if coin_amt > 0:
		coins += coin_amt
		FX.fly_coins(self, Vector2(360, 640), _hud_labels[0]["coins"].global_position, clampi(coin_amt / 400, 4, 10))
		FX.rise_label(self, Vector2(270, 560), "+%s" % _fmt_compact(coin_amt), Color(1.0, 0.85, 0.3), 36)
	if spin_amt > 0:
		spins += spin_amt
		FX.rise_label(self, Vector2(300, 630), "+%d  🌀" % spin_amt, Color(0.6, 0.9, 1.0), 30)
	Sfx.play("jackpot", -3.0)
	FX.confetti(self, 20)
	_update_badges()
	_refresh()
	_save_game()

# --- notifications ---

func _notify(ntype: String, text: String, emoji := "🔔", toast := true) -> bool:
	if not notif_enabled or not bool(notif_types.get(ntype, true)):
		return false
	notif_log.push_front({"type": ntype, "text": text, "emoji": emoji, "ts": _now(), "read": false})
	while notif_log.size() > NOTIF_LOG_MAX:
		notif_log.pop_back()
	_update_badges()
	if toast:
		_show_toast(text, emoji)
	_save_game()
	return true

func _unread_count() -> int:
	var n := 0
	for entry in notif_log:
		if not bool(entry.get("read", true)):
			n += 1
	return n

# Where the toast comes to rest, measured from below the safe area.
#
# It used to stop at 78, which put its 92-pixel body across 78..170 -- straight
# through the slot page's wordmark (92..170) and through every menu page's
# title plate (104..190). A notification that erases the name of the screen it
# arrived on reads as the screen having been replaced. Below both, it reads as
# what it is: a strip that dropped in over the top of the content and will go
# again on its own.
const TOAST_REST_Y := 196.0

func _show_toast(text: String, emoji := "🔔") -> void:
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Lagoon.SHELL.r, Lagoon.SHELL.g, Lagoon.SHELL.b, 0.96)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.95, 0.75, 0.25)
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(view_size().x - 48.0, 92)
	panel.position = Vector2(24, -90)
	panel.z_index = 130
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_toast = panel

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)
	hb.add_child(_emoji_label(emoji, UI.F_SUBHEAD))
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UI.F_LABEL)
	lbl.add_theme_color_override("font_color", Lagoon.INK)
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	hb.add_child(_emoji_label("🔔", UI.F_LABEL))

	Sfx.play("pop", -12.0)
	# Owned by the toast: the line at the top of this function frees whatever
	# toast was already up, and a tween on main would then be left driving it.
	var tw := panel.create_tween()
	tw.tween_property(panel, "position:y", TOAST_REST_Y + safe_top(), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)

func _time_ago(ts: float) -> String:
	var d := int(_now() - ts)
	if d < 60:
		return "now"
	if d < 3600:
		return "%dm ago" % (d / 60)
	if d < 86400:
		return "%dh ago" % (d / 3600)
	return "%dd ago" % (d / 86400)

# =============================================================================
#  Notifications
# =============================================================================
#
# This was a modal, and a modal was the wrong shape for it. A raid you slept
# through is news about your island, sometimes a week of it, and news does not
# belong in a box that dims the game behind it and has to be dismissed before
# anything else can happen. It is a place now: it scrolls the whole screen, it
# holds as many entries as the log has, and you leave it the same way you leave
# the shop.

func _fill_alerts(vb: VBoxContainer) -> void:
	if notif_log.is_empty():
		var card := _page_card(vb)
		var bell := _emoji_label("\U0001F514", 72)
		bell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bell.modulate = Color(1, 1, 1, 0.5)
		card.add_child(bell)
		var empty := _popup_row_label("No notifications yet", UI.F_SUBHEAD)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(empty)
		var sub := _popup_row_label("Raids on your island and spins that refill while you are away turn up here.", UI.F_CAPTION)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_color_override("font_color", Lagoon.INK_SOFT)
		card.add_child(sub)
	else:
		var unread_n := _unread_count()
		if unread_n > 0:
			var flag := HBoxContainer.new()
			flag.alignment = BoxContainer.ALIGNMENT_CENTER
			flag.add_theme_constant_override("separation", 10)
			vb.add_child(flag)
			flag.add_child(Lagoon.chip("%d NEW" % unread_n, Lagoon.REEF, UI.F_CAPTION))

		# One card per entry, straight into the page's own scroll. The old modal
		# nested a scroller inside a fixed-height panel, which is two scrolls
		# fighting over one flick.
		for entry in notif_log:
			var unread: bool = not bool(entry.get("read", true))
			var card := _tinted_card(vb, Lagoon.REEF if unread else Lagoon.BRASS_MID, unread)
			var pad := MarginContainer.new()
			for m in [["margin_left", 14], ["margin_right", 14], ["margin_top", 12], ["margin_bottom", 12]]:
				pad.add_theme_constant_override(m[0], m[1])
			card.add_child(pad)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			pad.add_child(row)
			var tok := Lagoon.token(str(entry.get("emoji", "\U0001F514")), 72.0,
				Lagoon.REEF if unread else Lagoon.BRASS)
			tok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tok)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			col.add_theme_constant_override("separation", 4)
			row.add_child(col)
			var txt := Label.new()
			txt.text = str(entry.get("text", ""))
			txt.add_theme_font_size_override("font_size", UI.F_CAPTION)
			txt.add_theme_color_override("font_color", Lagoon.INK if unread else Lagoon.INK_SOFT)
			txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(txt)
			var when := Label.new()
			when.text = _time_ago(float(entry.get("ts", 0.0)))
			when.add_theme_font_size_override("font_size", UI.F_TINY)
			when.add_theme_color_override("font_color", Lagoon.INK_FAINT)
			col.add_child(when)

		# Marked read on the way out of the builder rather than on the way in,
		# so the "NEW" chips above are the state the page was opened in.
		for entry in notif_log:
			entry["read"] = true
		_update_badges()
		_save_game()

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(btn_row)
	if not notif_log.is_empty():
		var clear := Button.new()
		clear.text = "Clear all"
		clear.custom_minimum_size = Vector2(0, UI.TAP)
		clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_candy_button(clear, Color(0.75, 0.3, 0.3))
		FX.press_feedback(clear)
		clear.pressed.connect(func() -> void:
			notif_log = []
			_update_badges()
			_save_game()
			_fill_page("alerts")
		)
		btn_row.add_child(clear)
	var settings := Button.new()
	settings.text = "Settings"
	settings.custom_minimum_size = Vector2(0, UI.TAP)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_candy_button(settings, Color(0.55, 0.45, 0.65))
	FX.press_feedback(settings)
	settings.pressed.connect(func() -> void: _goto(pages["options"]))
	btn_row.add_child(settings)

# --- full menu pages (shop / collections / quests / options) ---

func _build_menu_pages() -> void:
	for spec in [["shop", "Shop"], ["collections", "Cards"], ["boxes", "Card Boxes"],
			["quests", "Quests"], ["options", "Options"], ["alerts", "Alerts"]]:
		_make_page(spec[0], spec[1])

	# The way into the boxes: bottom-right of the Cards page, where the thumb
	# already is, carrying a count of what is waiting to be melted down.
	_convert_btn = Button.new()
	_convert_btn.custom_minimum_size = Vector2(232, 84)
	_convert_btn.size = Vector2(232, 84)
	_convert_btn.focus_mode = Control.FOCUS_NONE
	_convert_btn.text = "\u267B   BOXES"
	_convert_btn.add_theme_font_size_override("font_size", UI.F_LABEL)
	Lagoon.button(_convert_btn, "urchin", 34)
	Lagoon.button_gloss(_convert_btn, 34)
	FX.press_feedback(_convert_btn)
	_convert_btn.pressed.connect(func() -> void: _goto(pages["boxes"]))
	pages["collections"].add_child(_convert_btn)
	_convert_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_convert_btn.offset_left = -248.0
	_convert_btn.offset_right = -16.0
	_convert_btn.offset_top = -(NAV_ROOT_H + 18.0 + safe_bottom() + 84.0)
	_convert_btn.offset_bottom = -(NAV_ROOT_H + 18.0 + safe_bottom())
	# _nav_badge anchors to its parent's top centre; nudged out to the button's
	# top-right corner, which is where a count belongs on a wide button.
	_convert_badge = _nav_badge(_convert_btn, "0")
	_convert_badge.offset_left = 74.0
	_convert_badge.offset_right = 104.0
	_convert_badge.offset_top = -12.0
	_convert_badge.offset_bottom = 18.0

func _make_page(key: String, title: String) -> void:
	var page := Control.new()
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false

	# Every page stands on the same water. The menu screens used to each have
	# their own dark gradient, which made them feel like four different apps.
	var mat := Lagoon.backdrop(page)
	Lagoon.tint_backdrop(mat, CV.island_palette(island_level))
	_page_backdrops.append(mat)
	if key == "shop":
		_add_shop_night(page)

	var plate := Lagoon.plaque(title.to_upper(), 0.0, 86.0, UI.F_TITLE)
	page.add_child(plate)
	plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	plate.offset_left = -plate.custom_minimum_size.x * 0.5
	plate.offset_right = plate.custom_minimum_size.x * 0.5
	plate.offset_top = 104.0 + safe_top()
	plate.offset_bottom = 104.0 + 86.0 + safe_top()

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# How far a finger may travel before the list decides it is being scrolled
	# rather than tapped. Godot ships this at zero, which means a single pixel
	# of wobble -- and a thumb on glass always wobbles -- cancels the press of
	# the button underneath. A tap has to survive being a slightly untidy tap.
	sc.scroll_deadzone = SCROLL_SLOP
	page.add_child(sc)
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 16.0
	sc.offset_right = -16.0
	sc.offset_top = 208.0 + safe_top()
	sc.offset_bottom = -(NAV_ROOT_H + 6.0 + safe_bottom())

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	sc.add_child(vb)

	_add_topbar(page)
	pages[key] = page
	_page_bodies[key] = vb

# Dusk over the lagoon, on the shop page only.
#
# Everything in this store is brass, gold and coral, and none of it was
# carrying because it was all sitting on the same bright daylight water as the
# rest of the game -- pale on pale, with nothing for the gold to be brighter
# than. The one part of the shop that did read was the chest row, and the only
# thing separating it was a slightly darker ground.
#
# So the shop keeps the same lagoon and drops the sun out of it: the water goes
# deep, a single warm shaft stays lit over the top of the page where the live
# offer sits, and the cards on top are unchanged. It is the same island at
# night, which is a different room to be sold in without being a different
# game. Nothing else uses this -- a dark Quests page would just be dark.
func _add_shop_night(page: Control) -> void:
	var night := ColorRect.new()
	var sh := Lagoon.shader("""
shader_type canvas_item;
uniform vec3 deep = vec3(0.012, 0.110, 0.176);
uniform vec3 lamp = vec3(1.000, 0.780, 0.400);

void fragment() {
	// Deliberately opaque. A half-transparent dark blue laid over the bright
	// daylight sky does not read as night, it reads as grey -- the first pass
	// at this washed the top of the page out to the colour of wet concrete.
	// The layer has to commit to being water.
	float v = smoothstep(0.02, 0.62, UV.y) * 0.16 + 0.80;
	float edge = smoothstep(0.34, 0.02, abs(UV.x - 0.5) * 2.0 - 0.34);
	v += (1.0 - edge) * 0.06;

	// One warm shaft from above, over the top card. Cheap, and it is the only
	// thing on the page that says which end of it matters.
	float d = length((UV - vec2(0.5, -0.04)) * vec2(0.9, 1.25));
	float glow = smoothstep(0.80, 0.0, d);

	vec3 c = mix(deep, lamp, glow * 0.30);
	COLOR = vec4(c, clamp(v - glow * 0.16, 0.0, 1.0));
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	night.material = mat
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(night)
	night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _fill_page(key: String) -> void:
	var vb: VBoxContainer = _page_bodies[key]
	# Detached first, then freed. queue_free only schedules the free for the end
	# of the frame, so the old cards were still parented while the new ones were
	# being added: the container laid out both, the page was briefly twice as
	# tall, and _let_drags_through below walked a list of dead nodes on its way
	# through. Removing them is immediate and costs nothing.
	for c in vb.get_children():
		vb.remove_child(c)
		c.queue_free()
	match key:
		"shop": _fill_shop(vb)
		"quests": _fill_quests(vb)
		"collections": _fill_collections(vb)
		"boxes": _fill_boxes(vb)
		"alerts": _fill_alerts(vb)
		"options": _fill_options(vb)
	_let_drags_through(vb)

# Why a page full of cards would not scroll unless you found a gap between them.
#
# A touch drag goes to the control under the finger and then bubbles up to its
# parents -- but only until it meets one set to MOUSE_FILTER_STOP, which is what
# Button and PanelContainer are by default. So on these pages the drag died on
# whichever card the finger landed on and the ScrollContainer above it never
# heard a thing. The bare strips between the cards were the only places the
# list was actually listening, which is why it took several tries to get one
# moving: you were hunting for a gap without knowing it.
#
# PASS keeps every one of them tappable -- a control still handles and accepts
# the press it understands -- and lets what it does not understand, the drags,
# carry on up to the scroller. Applied after each fill, because these bodies are
# rebuilt from scratch every time their page is opened.
func _let_drags_through(node: Node) -> void:
	for child in node.get_children():
		var c := child as Control
		if c != null and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			c.mouse_filter = Control.MOUSE_FILTER_PASS
		_let_drags_through(child)

func _page_card(vb: VBoxContainer) -> VBoxContainer:
	return Lagoon.card(vb, Lagoon.R_CARD, 16)

# Sea glass with a coloured rim. Rarity, tier and set difficulty are all "this
# card is worth more" signals, and they now all say it the same way: the glass
# stays glass and only the metal around it changes, instead of each card type
# inventing its own dark fill.
func _tinted_card(parent: Node, tint: Color, strong := false, radius := Lagoon.R_CARD) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := Lagoon.glass(radius, 0.93)
	sb.bg_color = Color(1, 1, 1, 0.93).lerp(Color(tint.r, tint.g, tint.b, 0.93), 0.10)
	sb.set_border_width_all(4 if strong else 3)
	sb.border_color = tint
	sb.shadow_color = Color(tint.r, tint.g, tint.b, 0.30 if strong else 0.20)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	Lagoon.add_gloss(panel, radius)
	return panel

func _fill_shop(vb: VBoxContainer) -> void:
	_shop_gift_timer_label = null
	_offer_timer_label = null
	_shop_anchors.clear()

	# Order matters more here than anywhere else on the page. The two things
	# that expire -- the live offer and the one-time starter -- go above the
	# standing shelf, because a player who scrolls past a countdown to reach a
	# price list has already been told the countdown was the less urgent thing.
	var live := _active_offer()
	if not live.is_empty():
		_offer_card(vb, live)

	# one-time starter offer hero banner
	if not purchased_ids.has(CV.STARTER_PACK["id"]):
		_shop_hero_offer(vb)

	_shop_section(vb, "piggy", "PIGGY  BANK")
	_piggy_card(vb)

	_shop_section(vb, "bundles", "BUNDLES")
	for pack in CV.BUNDLE_PACKS:
		_bundle_card(vb, pack)
	vb.add_child(_page_note("Bundles cost less than the same spins, coins and cards bought apart", UI.F_TINY))

	_shop_section(vb, "chests", "TREASURE  CHESTS")
	var chest_row := HBoxContainer.new()
	chest_row.add_theme_constant_override("separation", 10)
	vb.add_child(chest_row)
	for pack in CV.CHEST_PACKS:
		_chest_card(chest_row, pack)
	vb.add_child(_page_note("Pricier chests hold more cards and better odds — every chest shows its full odds table before you pay", UI.F_TINY))

	_shop_section(vb, "spins", "SPIN  PACKS")
	var sgrid := GridContainer.new()
	sgrid.columns = 2
	sgrid.add_theme_constant_override("h_separation", 10)
	sgrid.add_theme_constant_override("v_separation", 10)
	vb.add_child(sgrid)
	for i in CV.SPIN_PACKS.size():
		var sp: Dictionary = CV.SPIN_PACKS[i]
		_shop_tile(sgrid, sp, Color(0.35, 0.75, 1.0), "%s  SPINS" % _fmt_compact(int(sp["spins"])), i, CV.SPIN_PACKS.size())

	_shop_section(vb, "coins", "COIN  PACKS")
	var cgrid := GridContainer.new()
	cgrid.columns = 2
	cgrid.add_theme_constant_override("h_separation", 10)
	cgrid.add_theme_constant_override("v_separation", 10)
	vb.add_child(cgrid)
	for i in CV.COIN_PACKS.size():
		var cp: Dictionary = CV.COIN_PACKS[i]
		_shop_tile(cgrid, cp, Color(1.0, 0.78, 0.25), "%s  COINS" % _fmt_compact(_scaled(int(cp["coins"]))), i, CV.COIN_PACKS.size())

	_shop_section(vb, "gift", "FREE  GIFT")
	_free_gift_card(vb)

	# The store is only a prototype where there is no StoreKit to talk to. On a
	# phone this line would be telling a paying customer their money is fake.
	if IAP.simulated():
		vb.add_child(_page_note("Simulated store — purchases are not charged.", UI.F_TINY))

# Section head:  ───  [ TITLE on brass ]  ───
#
# The same nameplate the page title and the machine's marquee use, one size
# down. Gold text floating on the page needed a heavy outline to survive the
# backdrop; on brass it needs none, and the reader gets a shape they have
# already learned to read as "heading".
func _shop_section(vb: VBoxContainer, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	if key != "":
		_shop_anchors[key] = row
	row.add_child(_section_line())
	var plate := Lagoon.plaque(title, 0.0, 54.0, UI.F_LABEL, false)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(plate)
	row.add_child(_section_line())

func _section_line() -> Panel:
	return Lagoon.divider()

func _tag_chip(text: String, color: Color, font_size := UI.F_TINY) -> PanelContainer:
	return Lagoon.chip(text, color, font_size)

# row of 5 stars, `lit` of them colored by rarity, the rest dim
func _star_row(lit: int, size := UI.F_CAPTION) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 1)
	var col: Color = CV.STAR_COLORS[clampi(lit, 1, CV.MAX_STAR) - 1]
	for i in CV.MAX_STAR:
		var s := Label.new()
		s.text = "★"
		s.add_theme_font_size_override("font_size", size)
		s.add_theme_color_override("font_color", col if i < lit else Color(Lagoon.INK_FAINT.r, Lagoon.INK_FAINT.g, Lagoon.INK_FAINT.b, 0.35))
		row.add_child(s)
	return row

# =============================================================================
#  Shop art
# =============================================================================
#
# The store used to draw every product with one system emoji at one size. That
# is two separate problems wearing one coat. The emoji came from Apple's design
# system rather than this game's, so a row of tiles looked like a settings
# screen with pictures on it; and because the size never changed, the $0.99 tile
# and the $99.99 tile were literally the same picture. The ladder was stated in
# the label and denied by the art.
#
# What the genre actually does is make the quantity visible: a handful, a bag, a
# chest, a chest you cannot close. So these piles are built out of art the game
# already ships -- the coin, gem and bag symbols and the chest prop -- and get
# denser and taller the higher the rung. Nothing new had to be drawn, and the
# tile now answers "how much" before the number is read.

const PILE_W := 200.0
const PILE_H := 104.0

# Rows of a heap, bottom-first, each narrower than the one under it. Four rows
# is the ceiling: past that a pile stops reading as a pile and starts reading as
# a wall of circles.
func _heap_rows(n: int) -> Array:
	var rows := []
	var left := n
	var w := 5 if n > 10 else 4
	while left > 0 and rows.size() < 4:
		var take := mini(w, left)
		rows.append(take)
		left -= take
		w = maxi(1, w - 1)
	return rows

# Depth here is child order, never z_index. A negative z_index on the child of
# a panel does not put it behind its siblings, it puts it behind the panel --
# which is opaque, so the first attempt at this drew a chest and a bag that were
# invisible underneath their own card.
func _pile_sprite(box: Control, tex: Texture2D, pos: Vector2, side: float) -> void:
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	tr.position = pos
	tr.size = Vector2(side, side)

# `rung` is the tile's place on its ladder, `rungs` how long the ladder is, so
# the same function serves a 6-tile coin shelf and a 7-tile spin shelf without
# either needing to know the other exists.
func _pile_art(kind: String, rung: int, rungs: int) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(0, PILE_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Control.new()
	box.custom_minimum_size = Vector2(PILE_W, PILE_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = false
	wrap.add_child(box)

	var f := float(rung) / float(maxi(1, rungs - 1))

	if kind == "spins":
		# Ship's wheels, drawn rather than textured -- the same glyph the HUD
		# counter and the nav disc use, so a bought spin looks like a spin.
		var n := 1 + int(round(f * 4.0))
		var side := 46.0 + f * 30.0
		# Outermost first, centre last, so the fan closes towards the front
		# instead of the front wheel disappearing under its own neighbours.
		var order := []
		for i in n:
			order.append(i)
		order.sort_custom(func(a: int, b: int) -> bool:
			return absf(float(a) - float(n - 1) * 0.5) > absf(float(b) - float(n - 1) * 0.5))
		for i in order:
			var g := Glyph.new()
			g.kind = "wheel"
			g.tint = Lagoon.LAGOON if i % 2 == 0 else Lagoon.LAGOON.lightened(0.20)
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(g)
			# A shallow fan rather than a stack: overlapping discs of one shape
			# read as a single smeared disc, a fan reads as several.
			var span := float(n - 1) * side * 0.58
			g.position = Vector2(
				PILE_W * 0.5 - span * 0.5 + float(i) * side * 0.58 - side * 0.5,
				PILE_H - side - (side * 0.16 * absf(float(i) - float(n - 1) * 0.5)))
			g.size = Vector2(side, side)
		return wrap

	# Coins, and nothing behind them.
	#
	# The first version put a bag behind the middle rungs and an open chest
	# behind the top ones, which is the obvious way to show scale. Both props
	# are authored on an opaque near-white backdrop -- invisible on the cream
	# chest cards where they have always been used, and a pale grey slab on
	# these. So the heap does the whole job: more coins, larger coins, and gems
	# once the pile is deep enough that another coin would not register.
	var coin := CV.symbol_tex("coin")
	var side := 44.0 + f * 16.0
	var count := 3 + int(round(f * 17.0))
	var rows := _heap_rows(count)
	var dy := side * 0.46
	for i in rows.size():
		var per: int = rows[i]
		var span := float(per - 1) * side * 0.62
		for j in per:
			_pile_sprite(box, coin,
				Vector2(PILE_W * 0.5 - span * 0.5 + float(j) * side * 0.62 - side * 0.5,
						PILE_H - side * 0.94 - float(i) * dy),
				side)

	# The top of the ladder gets the one thing coins are not.
	if f >= 0.55:
		var gem := CV.symbol_tex("gem")
		var crest := PILE_H - side * 0.94 - float(rows.size()) * dy
		_pile_sprite(box, gem, Vector2(PILE_W * 0.5 - side * 0.45, crest + side * 0.18), side * 0.9)
		if f >= 0.85:
			_pile_sprite(box, gem, Vector2(PILE_W * 0.5 - side * 1.35, crest + side * 0.62), side * 0.7)
			_pile_sprite(box, gem, Vector2(PILE_W * 0.5 + side * 0.62, crest + side * 0.62), side * 0.7)
	return wrap

# The corner ribbon.
#
# "POPULAR" and "BEST VALUE" used to be small pills sitting inside the card
# border, in a fixed-height slot every tile reserved whether it had a tag or
# not -- which cost every untagged tile 36 wasted pixels to say nothing. A label
# that stays inside the frame reads as metadata about the product. Crossing the
# frame is what turns it into an announcement about it, and it costs no layout
# at all, because it is positioned rather than flowed.
func _corner_ribbon(panel: Control, text: String, color: Color, reach := 98.0) -> void:
	# Drawn rather than built out of a rotated Panel, because a PanelContainer
	# lays out every Control child it has: the first version of this set its own
	# size and rotation and the card promptly stretched it back over the whole
	# tile. An overlay that is happy to be stretched to the full card, and draws
	# a band in one corner of whatever rect it is given, cannot be defeated that
	# way.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 8
	panel.add_child(overlay)

	var font := Lagoon.ui_bold_font()
	overlay.draw.connect(func() -> void:
		# A tall narrow tile has a whole empty corner to give; a wide card has
		# its name starting a hundred pixels in, and the same band would be
		# drawn straight through it. Callers say how much corner they have.
		var band := 30.0              # thickness, measured across the diagonal
		var d := Vector2(1, 1).normalized() * band
		var a := Vector2(0.0, reach)
		var b := Vector2(reach, 0.0)
		var quad := PackedVector2Array([a, b, b + d, a + d])
		overlay.draw_colored_polygon(quad, color)
		# A lit top edge and a shadow under the bottom one: the band has to sit
		# on the card rather than be a coloured hole cut in it.
		overlay.draw_line(a, b, color.lightened(0.35), 3.0, true)
		overlay.draw_line(a + d, b + d, color.darkened(0.30), 3.0, true)

		var mid := (a + b) * 0.5 + d * 0.5
		overlay.draw_set_transform(mid, -PI * 0.25, Vector2.ONE)
		# "BEST VALUE" is half again as long as "NEW", and a band that fits one
		# does not fit the other -- so the type is shrunk to the chord it has to
		# live on rather than the chord being sized for the longest tag any
		# pack might ever carry.
		var chord := a.distance_to(b) - 22.0
		var fs := UI.F_TINY
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > chord:
			fs = maxi(14, int(float(fs) * chord / w))
			w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		overlay.draw_string_outline(font, Vector2(-w * 0.5, float(fs) * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, color.darkened(0.45))
		overlay.draw_string(font, Vector2(-w * 0.5, float(fs) * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
		overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	)

# What a mixed pack contains, as icons and numbers instead of a sentence.
#
# "400 Spins + 600K Coins + 4 Cards" was set in caption grey under the name,
# which made the single most valuable line on the card the third-quietest thing
# on it. Same three facts, in the same order, at a size that matches what they
# are worth -- and each one next to the icon the HUD already uses for it, so the
# reader is being shown the counters they are about to move.
# `ink` exists because this row is now read on two backgrounds. On sea glass it
# is dark type on a pale panel; on the dark treasure card the same dark type is
# a smudge, so the caller passes the light it needs.
func _reward_row(pack: Dictionary, ink := Lagoon.INK, size := UI.F_BODY) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var spins_n := int(pack.get("spins", 0))
	var coins_n := _scaled(int(pack.get("coins", 0)))
	var cards_n := int(pack.get("cards", 0))

	for entry in [["wheel", spins_n], ["coin", coins_n], ["cards", cards_n]]:
		var n: int = entry[1]
		if n <= 0:
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		row.add_child(item)
		var icon := Glyph.new()
		icon.kind = String(entry[0])
		icon.custom_minimum_size = Vector2(34, 34)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(icon)
		var num := Lagoon.label(_fmt_compact(n), size, ink, true)
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(num)
	return row

# What the same goods would have cost at the shelf's own entry rate, struck
# through, beside what they cost here.
#
# The shop already said this, as "+65% MORE PER $". That is accurate, and it is
# arithmetic: it asks the reader to do the sum before they can feel the size of
# it. A crossed-out number says the identical thing and asks for nothing. Both
# are derived from the same published base rate, so neither can drift from the
# other or from the prices actually charged.
#
# Returns null for the bottom rung, which is the thing being compared against
# and therefore has no honest number to strike.
func _struck_price_row(pack: Dictionary, ink := Lagoon.INK_FAINT) -> Control:
	var bonus := CV.bonus_pct(pack)
	if bonus < 8:
		return null
	var usd := CV.price_usd(pack)
	if usd <= 0.0:
		return null
	var was := usd * (1.0 + float(bonus) / 100.0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	var old_price := Lagoon.label("$%.2f" % was, UI.F_CAPTION, ink)
	# Godot has no strikethrough on Label, so the rule is drawn over it -- which
	# also lets it be coral rather than the text colour, the way a price is
	# struck on a shelf tag.
	var bar := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Lagoon.CORAL
	bsb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("panel", bsb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	old_price.add_child(bar)
	# Anchored across the label rather than given a fixed width: "$6.58" and
	# "$149.98" are not the same number of characters, and a rule that stops
	# short of the digits it is cancelling reads as a stray line.
	bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	bar.anchor_right = 1.0
	bar.offset_left = -1.0
	bar.offset_right = 1.0
	bar.offset_top = -2.0
	bar.offset_bottom = 2.0
	row.add_child(old_price)

	row.add_child(_tag_chip("SAVE  %d%%" % int(round((1.0 - usd / was) * 100.0)), Lagoon.BRASS, UI.F_TINY))
	return row

func _radial_glow(color: Color, diameter: float) -> ColorRect:
	var glow := ColorRect.new()
	var sh := Lagoon.shader("""
shader_type canvas_item;
uniform vec4 glow_col : source_color = vec4(1.0, 0.8, 0.3, 1.0);
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.1, 1.0, d)) * 0.5 * glow_col.a;
	COLOR = vec4(glow_col.rgb, a);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("glow_col", color)
	glow.material = mat
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	glow.offset_left = -diameter * 0.5
	glow.offset_right = diameter * 0.5
	glow.offset_top = -diameter * 0.5
	glow.offset_bottom = diameter * 0.5
	return glow

# slow diagonal shine sweep laid over premium panels
func _shine_overlay(tint: Color) -> ColorRect:
	var r := ColorRect.new()
	var sh := Lagoon.shader("""
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	float band = fract(TIME * 0.22);
	float x = (UV.x + UV.y * 0.35) / 1.35;
	float a = smoothstep(0.1, 0.0, abs(x - band)) * 0.14;
	COLOR = vec4(tint.rgb, a);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", tint)
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# The live limited-time offer, at the very top of the store.
#
# Everything loud about this card is doing one job: making the difference
# between now and later feel like a difference. The countdown is the headline,
# the percentage is the reason, and the panel is the only red thing on a page
# that is otherwise brass and water.
func _offer_card(vb: VBoxContainer, pack: Dictionary) -> void:
	var panel := _tinted_card(vb, Lagoon.REEF, true)
	panel.add_child(_shine_overlay(Lagoon.CORAL_HI))

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_tag_chip("LIMITED  TIME", Lagoon.REEF, 11))
	head.add_child(_tag_chip("+%d%%  VALUE" % CV.bonus_pct(pack), Lagoon.URCHIN, 11))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	# Held on the node so the once-a-second tick can rewrite it in place
	# without rebuilding the page under the player's thumb.
	var timer := Lagoon.label("⏳  ENDS  IN  %s" % _offer_countdown_text(), UI.F_CAPTION, Lagoon.CORAL_LO, true)
	col.add_child(timer)
	_offer_timer_label = timer
	FX.pulse_forever(timer, 1.05, 1.0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)

	var art := Control.new()
	art.custom_minimum_size = Vector2(96, 100)
	row.add_child(art)
	art.add_child(_radial_glow(Lagoon.CORAL, 126))
	var e := _emoji_label(pack["emoji"], 56)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(e)
	e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	FX.pulse_forever(e, 1.1, 1.3)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	text.add_child(Lagoon.label(pack["name"], UI.F_BODY, Lagoon.INK, true))
	text.add_child(_reward_row(pack))
	# In the text column, not beside the button. The pay column's minimum width
	# is the button's; hanging "$29.36  SAVE 76%" off it instead made this the
	# widest row on the page, and a VBoxContainer gives its widest child's
	# minimum width to all of them -- which pushed the chest shelf and both tile
	# grids off the right edge of a 720-wide screen.
	var struck := _struck_price_row(pack)
	if struck != null:
		struck.alignment = BoxContainer.ALIGNMENT_BEGIN
		text.add_child(struck)

	var buy := Button.new()
	buy.text = IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(140, UI.TAP)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	row.add_child(buy)

# The piggy bank card: a fill bar, what is inside, and one price.
#
# The bar is the whole design. A number alone would read as another pack; a bar
# creeping toward a line the player can see reads as something of theirs
# accumulating, and that is the feeling the mechanic is built on.
func _piggy_card(vb: VBoxContainer) -> void:
	var full := _piggy_full()
	var pink := Color(1.0, 0.62, 0.72)
	var panel := _tinted_card(vb, pink, full)
	if full:
		panel.add_child(_shine_overlay(Color(1.0, 0.82, 0.88)))

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var art := Control.new()
	art.custom_minimum_size = Vector2(92, 96)
	row.add_child(art)
	art.add_child(_radial_glow(pink, 118))
	var e := _emoji_label("🐷", 56)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(e)
	e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	FX.pulse_forever(e, 1.1 if full else 1.04, 1.1 if full else 2.4)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 5)
	row.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(Lagoon.label("Piggy Bank", UI.F_BODY, Lagoon.INK, true))
	if full:
		head.add_child(_tag_chip("FULL!", Lagoon.REEF, 11))

	var amount := Lagoon.label("%s coins inside" % _fmt_compact(piggy_coins), UI.F_LABEL, Lagoon.INK, true)
	col.add_child(amount)

	# Fill bar: a well with a pink column drawn across the filled fraction.
	#
	# The track is a bare Control, not a PanelContainer, for the same reason the
	# modal's close button is not parented to its panel -- a PanelContainer
	# stretches every child to its own rect, so a hand-sized fill would sit there
	# at 100% no matter what the player had banked.
	var frac := _piggy_frac()
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 20)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar)
	var well := Panel.new()
	well.add_theme_stylebox_override("panel", Lagoon.glass_well(10))
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(well)
	well.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = pink
	fsb.set_corner_radius_all(10)
	fill.add_theme_stylebox_override("panel", fsb)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	# Same guard as the modal's close button: this is deferred, and the shop
	# page rebuilds itself whenever the piggy takes a coin, so the bar it sizes
	# can already be gone by the time it runs.
	var place_fill := func() -> void:
		if not is_instance_valid(bar) or not is_instance_valid(fill):
			return
		fill.position = Vector2.ZERO
		fill.size = Vector2(bar.size.x * frac, bar.size.y)
		fill.visible = frac > 0.0
	bar.resized.connect(place_fill)
	place_fill.call_deferred()

	var note := Lagoon.label(
		"Smash it now and the coins are yours" if full else "Fills as you spin and raid — %d%% of the way there" % int(frac * 100.0),
		UI.F_TINY, Lagoon.INK_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)

	var buy := Button.new()
	buy.text = IAP.price_for(CV.PIGGY_PACK)
	buy.custom_minimum_size = Vector2(140, UI.TAP)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	# An empty bank is not for sale -- charging for nothing is the one way this
	# mechanic can leave a player feeling cheated.
	buy.disabled = piggy_coins <= 0
	buy.modulate.a = 1.0 if piggy_coins > 0 else 0.45
	buy.pressed.connect(_confirm_piggy)
	row.add_child(buy)

func _confirm_piggy() -> void:
	var vbox := _open_popup("Smash the Piggy?")
	var e := _emoji_label("🐷", 68)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(e)
	var amount := _popup_row_label("%s coins inside" % _fmt_compact(piggy_coins), UI.F_BODY)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(amount)
	if not _piggy_full():
		var wait := _popup_row_label("It keeps filling — the price never changes.", UI.F_CAPTION)
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wait.add_theme_color_override("font_color", Lagoon.INK_FAINT)
		wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(wait)
	if IAP.simulated():
		var note := _popup_row_label("Simulated purchase — no real charge.", UI.F_TINY)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", Lagoon.INK_FAINT)
		vbox.add_child(note)
	var pay := Button.new()
	pay.text = "PAY  %s" % IAP.price_for(CV.PIGGY_PACK)
	pay.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(pay, Color(0.28, 0.68, 0.34))
	FX.press_feedback(pay)
	pay.pressed.connect(func() -> void:
		if IAP.busy:
			return
		# Written down and saved before Apple is asked for the money. Whatever
		# happens to this process between here and the grant -- including being
		# killed and the transaction arriving on a later launch -- the figure
		# the player was shown on this card is now on disk.
		piggy_promised = piggy_coins
		_flush_save()
		pay.disabled = true
		pay.text = "…"
		IAP.purchase(CV.PIGGY_PACK)
	)
	vbox.add_child(pay)

# A mixed bundle: a wide row, because unlike a spin pack it has three things to
# say and a two-column tile cannot say them without abbreviating all three.
func _bundle_card(vb: VBoxContainer, pack: Dictionary) -> void:
	var cc: Color = pack["color"]
	var top: bool = pack.get("guarantee5", false)
	var panel := _tinted_card(vb, cc, top)
	if top:
		panel.add_child(_shine_overlay(Lagoon.URCHIN.lightened(0.5)))

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 12)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var art := Control.new()
	art.custom_minimum_size = Vector2(84, 88)
	row.add_child(art)
	art.add_child(_radial_glow(cc, 108))
	var e := _emoji_label(pack["emoji"], 50)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(e)
	e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	FX.pulse_forever(e, 1.06, 2.2)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 7)
	col.add_child(head)
	head.add_child(Lagoon.label(pack["name"], UI.F_LABEL, Lagoon.INK, true))
	# Inline rather than a corner ribbon. The ribbon is for the narrow grid
	# tiles, which have a whole empty corner to give it; on a card laid out
	# left-to-right it either crosses the name or gets shrunk to a corner too
	# small to read "5\u2605 GUARANTEED" in.
	if pack.has("tag"):
		head.add_child(_tag_chip(pack["tag"], pack["tag_color"], 11))

	col.add_child(_reward_row(pack))
	# In the text column, not beside the button. The pay column's minimum width
	# is the button's; hanging "$29.36  SAVE 76%" off it instead made this the
	# widest row on the page, and a VBoxContainer gives its widest child's
	# minimum width to all of them -- which pushed the chest shelf and both tile
	# grids off the right edge of a 720-wide screen.
	var struck := _struck_price_row(pack)
	if struck != null:
		struck.alignment = BoxContainer.ALIGNMENT_BEGIN
		col.add_child(struck)
	else:
		col.add_child(Lagoon.label("+%d%%  vs  buying  it  separately" % CV.bonus_pct(pack), UI.F_TINY, Lagoon.KELP_LO, true))

	var buy := Button.new()
	buy.text = IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(128, UI.TAP)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	row.add_child(buy)

func _shop_hero_offer(vb: VBoxContainer) -> void:
	var pack: Dictionary = CV.STARTER_PACK
	var panel := _tinted_card(vb, Lagoon.BRASS, true)
	panel.add_child(_shine_overlay(Lagoon.BRASS_HI))

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var art := Control.new()
	art.custom_minimum_size = Vector2(96, 104)
	row.add_child(art)
	art.add_child(_radial_glow(Color(1.0, 0.8, 0.3), 126))
	var e := _emoji_label(pack["emoji"], 56)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(e)
	e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	FX.pulse_forever(e, 1.1, 1.4)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	col.add_child(name_row)
	var nm := Lagoon.label(pack["name"], UI.F_BODY, Lagoon.INK, true)
	name_row.add_child(nm)
	name_row.add_child(_tag_chip(pack["tag"], Lagoon.REEF))
	col.add_child(_reward_row(pack))
	var once := Lagoon.label("One time only!", UI.F_TINY, Lagoon.CORAL_LO, true)
	col.add_child(once)

	var buy := Button.new()
	buy.text = IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(140, UI.TAP)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	row.add_child(buy)

# the real treasure-chest sprite, tinted per tier; falls back to the pack emoji
func _chest_art(pack: Dictionary, emoji_size := 54) -> Control:
	var t := CV.prop_tex("chest")
	if t == null:
		var e := _emoji_label(pack["emoji"], emoji_size)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return e
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = pack.get("art_tint", Color.WHITE)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

# --- odds disclosure -------------------------------------------------------
#
# App Store Review Guideline 3.1.1: an app selling randomized items must
# disclose the odds before the purchase. Read as a rule it is an obligation;
# read as a player it is the difference between a chest and a shell game. So it
# goes where the decision is actually made -- a rate on the tile, and the whole
# table inside the confirm dialog, above the pay button rather than under it.
#
# Everything that grants cards is covered, not only the products with "chest"
# in the name: the starter pack, the bundles and the timed offers all draw from
# the same table, and most of the money is in those.
func _is_randomized(pack: Dictionary) -> bool:
	return int(pack.get("cards", 0)) > 0

# The one line a narrow tile has room for: the rate people are actually buying.
# The full breakdown is one tap away, in the dialog that takes the money.
func _odds_line(pack: Dictionary) -> String:
	var odds := CV.star_odds(int(pack.get("tier", 0)))
	if pack.get("guarantee5", false):
		return "5★ GUARANTEED"
	return "5★ CHANCE  %s" % CV.odds_pct(odds[CV.MAX_STAR - 1])

# Every rate on one line, for anywhere with the width to carry it.
func _odds_strip(pack: Dictionary) -> String:
	var odds := CV.star_odds(int(pack.get("tier", 0)))
	var parts: Array[String] = []
	for i in CV.MAX_STAR:
		parts.append("%d★ %s" % [i + 1, CV.odds_pct(odds[i])])
	return "  ·  ".join(parts)

# The full table, for the confirm dialog. Per drawn card, which is the only
# reading of "the odds" that means anything for a chest that draws six.
func _odds_table(vbox: VBoxContainer, pack: Dictionary) -> void:
	var head := _popup_row_label("CARD ODDS  ·  per card drawn", UI.F_TINY)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	vbox.add_child(head)

	var odds := CV.star_odds(int(pack.get("tier", 0)))
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 3)
	vbox.add_child(table)
	for i in CV.MAX_STAR:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		table.add_child(row)
		var st := _star_row(i + 1, UI.F_CAPTION)
		st.alignment = BoxContainer.ALIGNMENT_BEGIN
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(st)
		var pct := _popup_row_label(CV.odds_pct(odds[i]), UI.F_LABEL)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct)

	var cards := int(pack.get("cards", 0))
	var text := ""
	if pack.get("guarantee5", false):
		text = "One of the %d cards is always ★★★★★. The other %d each draw from the table above." % [cards, maxi(0, cards - 1)]
	else:
		text = "All %d cards draw from the table above, independently. Duplicates are possible." % cards
	# The cards being sold here have an expiry date, and this is the only place
	# the player can be told about it before paying.
	#
	# The Collections page has carried the season countdown all along, so the
	# reset itself was never hidden -- but the shop never repeated it, which
	# left the one screen where real money changes hands as the one screen that
	# did not mention that what it sells is cleared at the end of the season. A
	# disclosure the buyer reaches afterwards is not a disclosure, which is the
	# same reasoning that put the odds table above the pay button rather than
	# below it.
	if col_deadline > 0.0:
		var season_left := maxf(0.0, col_deadline - _now())
		text += "\n\nCards belong to the current season, which ends in %s. Every card and spare resets when a season ends, including cards from packs." % _countdown_text(int(season_left))
	var foot := _popup_row_label(text, UI.F_TINY)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	vbox.add_child(foot)

func _chest_card(row: HBoxContainer, pack: Dictionary) -> void:
	var cc: Color = pack["color"]
	var guaranteed: bool = pack.get("guarantee5", false)
	var panel := _tinted_card(row, cc, guaranteed)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if guaranteed:
		panel.add_child(_shine_overlay(Lagoon.URCHIN.lightened(0.5)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var tag_wrap := CenterContainer.new()
	tag_wrap.custom_minimum_size = Vector2(0, 36)
	col.add_child(tag_wrap)
	tag_wrap.add_child(_tag_chip(pack["tag"], pack["tag_color"], 11))

	# chest art on a rarity-colored glow
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 100)
	col.add_child(art)
	art.add_child(_radial_glow(cc, 122))
	var e := _chest_art(pack)
	art.add_child(e)
	e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	FX.pulse_forever(e, 1.04, 1.8 if guaranteed else 2.6)
	if guaranteed:
		var spark := _emoji_label("✨", UI.F_LABEL)
		art.add_child(spark)
		spark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		spark.offset_left = 22.0
		spark.offset_right = 52.0
		spark.offset_top = -46.0
		spark.offset_bottom = -16.0
		FX.pulse_forever(spark, 1.25, 1.1)

	var nm := Lagoon.label(pack["name"], UI.F_CAPTION, Lagoon.INK, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 5)
	col.add_child(cards_row)
	cards_row.add_child(_emoji_label("🃏", UI.F_CAPTION))
	cards_row.add_child(Lagoon.label("x%d CARDS" % int(pack["cards"]), UI.F_TINY, Lagoon.INK_SOFT))

	# No star row here any more. It was drawn from `star_cap`, which reads as a
	# ceiling -- the Wooden Chest rendered ★★☆☆☆ -- and sat directly above that
	# same chest's true line, "5★ CHANCE 1%". Two claims on one tile, disagreeing,
	# on the surface that exists to publish the odds. `star_cap` never capped
	# anything: _grant_chest_card rolls from CHEST_STAR_WEIGHTS and has never
	# looked at it.
	#
	# The odds line below is the honest half and is a better ladder anyway --
	# 1% -> 8% -> GUARANTEED orders the three chests with real numbers, and the
	# tag, the colour and the card count already carry the tier visually.

	var odds := Label.new()
	odds.text = _odds_line(pack)
	odds.add_theme_font_size_override("font_size", UI.F_TINY)
	odds.add_theme_color_override("font_color", Lagoon.BRASS_LO if guaranteed else Lagoon.INK_FAINT)
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(odds)
	if guaranteed:
		FX.pulse_forever(odds, 1.08, 1.2)

	var buy := Button.new()
	buy.text = IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(0, UI.TAP)
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	col.add_child(buy)

# square tile used for spin & coin packs (2-column grid)
# The treasure card: deep water in a brass frame, with light coming off the
# goods.
#
# Everywhere else in the game a card is sea glass -- milky, translucent, lit
# along the top edge -- and that is right for a card holding a mission or a
# collection, which are things to be read. It is wrong for a card whose whole
# job is to make a pile of gold look like a pile of gold, because pale gold on
# a pale panel has nothing to be brighter than. Darkening the shop page helped
# the cards; darkening the cards is what lets the contents glow.
#
# Only the two quantity shelves use it. The bundles, chests and piggy bank stay
# sea glass: they are cards you read before you decide, and they sit next to
# each other down the same column, so turning the whole page dark would take
# the emphasis back off the thing that is meant to have it.
func _treasure_card(parent: Node, top: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.204, 0.271, 0.97)
	sb.set_corner_radius_all(Lagoon.R_CARD)
	sb.set_border_width_all(4 if top else 3)
	sb.border_color = Lagoon.BRASS_HI if top else Lagoon.BRASS
	sb.shadow_size = 14 if top else 10
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	# Light from above the goods: a soft pool plus a slow fan of rays. Both are
	# strongest on the top rungs, which is one more thing saying "this one is
	# the one" without another badge on the card.
	var lit := ColorRect.new()
	var sh := Lagoon.shader("""
shader_type canvas_item;
uniform float strength = 1.0;
uniform vec4 warm : source_color = vec4(1.0, 0.86, 0.55, 1.0);

void fragment() {
	vec2 src = vec2(0.5, 0.04);
	vec2 d = UV - src;
	float dist = length(d * vec2(1.0, 0.85));

	// The pool the pile sits in.
	float pool = smoothstep(0.72, 0.0, dist) * 0.30;

	// Rays, thrown from the same point. Kept faint and wide -- a hard starburst
	// on a card this small reads as a scratch on the glass.
	float ang = atan(d.y, d.x);
	float fan = abs(sin(ang * 8.0 + TIME * 0.10));
	float rays = smoothstep(0.62, 1.0, fan) * smoothstep(0.66, 0.06, dist) * 0.16;

	COLOR = vec4(warm.rgb, (pool + rays) * strength);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("strength", 1.35 if top else 1.0)
	lit.material = mat
	lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lit)
	return panel

# One rung of a price ladder: spins or coins, six or seven of them in a
# two-column grid.
#
# The order of the column is the whole argument. What you get is now the
# largest thing on the tile and the first thing read; what it costs is the last.
# It used to be the other way round -- the price sat in a saturated green slab
# at 30px while the quantity was 19px of body text above it -- which is a tile
# that leads with the ask and buries the offer.
func _shop_tile(grid: GridContainer, pack: Dictionary, _accent: Color, amount_text: String,
		rung := 0, rungs := 1) -> void:
	var top := rungs > 1 and rung >= rungs - 2
	var panel := _treasure_card(grid, top)
	panel.custom_minimum_size = Vector2(338, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	margin.add_child(col)

	col.add_child(_pile_art("spins" if int(pack.get("spins", 0)) > 0 else "coins", rung, rungs))

	# The quantity, split so the number carries the weight and the unit only
	# labels it. "3,400 SPINS" set as one string at one size spends half its
	# width on the word.
	var parts := amount_text.split("  ", false)
	var amount := Lagoon.wordmark(String(parts[0]), 52)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(amount)
	if parts.size() > 1:
		var unit := Lagoon.label(String(parts[1]), UI.F_TINY, Lagoon.BRASS_HI, true)
		unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(unit)

	var nm := Lagoon.label(pack["name"], UI.F_TINY, Color(0.60, 0.76, 0.80))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	# The struck-price slot is reserved on every rung, discount or no discount.
	#
	# A grid row is as tall as its tallest cell and this column is centred, so a
	# tile that skipped the row did not come out shorter -- it came out the same
	# height with all of its contents shifted up by half a missing row. Breeze
	# and Storm sit side by side with their piles, their prices and their buy
	# buttons on three different lines, which reads as a rendering fault rather
	# than as one pack having a saving and the other not. The empty slot costs
	# the two entry rungs 40px of air and buys the whole grid one skyline.
	var save_slot := CenterContainer.new()
	save_slot.custom_minimum_size = Vector2(0, 40)
	col.add_child(save_slot)
	var struck := _struck_price_row(pack, Color(0.56, 0.71, 0.76))
	if struck != null:
		save_slot.add_child(struck)

	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(0, 6)
	col.add_child(pad2)

	var buy := Button.new()
	buy.text = IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(0, UI.TAP)
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	# Green all the way up the ladder said nothing about where you were on it.
	# The last two rungs are brass, which is the material this game already uses
	# to mean "worth more" -- on the frames, the plaques and the icon set.
	if top:
		Lagoon.button(buy, "brass")
		Lagoon.button_gloss(buy, 22)
	else:
		_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	col.add_child(buy)

	if pack.has("tag"):
		_corner_ribbon(panel, String(pack["tag"]), pack.get("tag_color", Lagoon.REEF))

func _free_gift_card(vb: VBoxContainer) -> void:
	var ready := _shop_free_ready()
	var cc := Lagoon.KELP
	var panel := _tinted_card(vb, cc if ready else Color(cc.r, cc.g, cc.b, 0.35), ready)
	if ready:
		panel.add_child(_shine_overlay(Lagoon.KELP.lightened(0.55)))

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var art := Control.new()
	art.custom_minimum_size = Vector2(96, 100)
	row.add_child(art)
	art.add_child(_radial_glow(Color(cc.r, cc.g, cc.b, 1.0 if ready else 0.35), 122))
	var e := _emoji_label("🎁", 54)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(e)
	e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ready:
		FX.pulse_forever(e, 1.12, 1.0)
	else:
		e.modulate = Color(1, 1, 1, 0.55)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var title := Lagoon.label("FREE  GIFT", UI.F_BODY, Lagoon.INK if ready else Lagoon.INK_SOFT, true)
	col.add_child(title)
	var sub := _popup_row_label("Every 24h:  +%s coins,  +%d spins  &  a card" % [_fmt_compact(_scaled(CV.SHOP_FREE_COINS)), CV.SHOP_FREE_SPINS], UI.F_CAPTION)
	sub.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	if not ready:
		var timer := _popup_row_label("⏳  Next gift in  %s" % _shop_free_countdown_text(), UI.F_CAPTION)
		timer.add_theme_color_override("font_color", Lagoon.KELP_LO)
		col.add_child(timer)
		_shop_gift_timer_label = timer

	if ready:
		var claim := Button.new()
		claim.text = "CLAIM"
		claim.custom_minimum_size = Vector2(140, UI.TAP)
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.add_theme_font_size_override("font_size", UI.F_LABEL)
		_candy_button(claim, Color(0.28, 0.68, 0.34))
		FX.press_feedback(claim)
		FX.pulse_forever(claim, 1.05, 1.1)
		claim.pressed.connect(_claim_shop_gift)
		row.add_child(claim)

func _shop_free_ready() -> bool:
	return _now() - shop_free_last >= CV.SHOP_FREE_COOLDOWN

func _shop_free_countdown_text() -> String:
	var left := maxi(0, int(CV.SHOP_FREE_COOLDOWN - (_now() - shop_free_last)))
	return "%02d:%02d:%02d" % [left / 3600, (left % 3600) / 60, left % 60]

func _claim_shop_gift() -> void:
	if not _shop_free_ready():
		return
	shop_free_last = _now()
	coins += _scaled(CV.SHOP_FREE_COINS)
	spins += CV.SHOP_FREE_SPINS
	var pre_complete := {}
	for c in CV.COLLECTIONS:
		pre_complete[c["id"]] = _collection_complete(c)
	var card := _grant_chest_card(0)
	var completed := []
	for c in CV.COLLECTIONS:
		if not pre_complete[c["id"]] and _collection_complete(c) and not col_claimed.get(c["id"], false):
			completed.append(c["name"])
	Sfx.play("jackpot", -3.0)
	FX.confetti(self, 44)
	FX.flash(self)
	_show_chest_result([card], "Free Gift!", "+%s coins    +%d spins" % [_fmt_compact(_scaled(CV.SHOP_FREE_COINS)), CV.SHOP_FREE_SPINS], completed)
	_update_badges()
	_refresh()
	_save_game()
	if _current_page == pages.get("shop"):
		_fill_page("shop")

# --- piggy bank ---------------------------------------------------------
#
# The bank is fed from play, never from the shop, so what is inside it always
# reads as the player's own winnings held back rather than a number the store
# invented. It stops at the cap and stays there: an offer that keeps growing
# forever gives the player a reason to keep waiting, and the point is to reach
# a ceiling that makes taking it obvious.
func _piggy_add(amount: int) -> void:
	var cap := _scaled(CV.PIGGY_CAP)
	if piggy_coins >= cap:
		return
	# The early return above means this crossing is seen exactly once.
	piggy_coins = mini(cap, piggy_coins + _scaled(amount))
	if piggy_coins >= cap:
		_notify("spins", "Your piggy bank is full — %s coins inside!" % _fmt_compact(piggy_coins), "🐷")
	if _current_page == pages.get("shop"):
		_fill_page("shop")

func _piggy_full() -> bool:
	return piggy_coins >= _scaled(CV.PIGGY_CAP)

func _piggy_frac() -> float:
	var cap := _scaled(CV.PIGGY_CAP)
	return 0.0 if cap <= 0 else clampf(float(piggy_coins) / float(cap), 0.0, 1.0)

# Paid for, so something has to come out of it.
#
# The bank is fed by play, which means it can be emptied between the moment a
# purchase is authorised and the moment the game hears about it -- most plainly
# when Apple delivers a transaction on the next launch, after an Ask to Buy
# approval or a kill mid-grant. This used to `return` on an empty bank, which
# is the single worst outcome the store can produce: a real charge, and nothing
# handed over. It pays out whatever the bank holds now or whatever it held when
# Pay was pressed, whichever is larger.
func _break_piggy() -> void:
	var got := maxi(piggy_coins, piggy_promised)
	piggy_promised = 0
	if got <= 0:
		_banner("Your piggy bank was already empty.", Color(0.9, 0.6, 0.4), "🐷")
		_flush_save()
		return
	piggy_coins = 0
	coins += got
	Sfx.play("jackpot", -3.0)
	FX.confetti(self, 52)
	FX.flash(self)
	_banner("Piggy smashed — +%s coins!" % _fmt_compact(got), Color(1.0, 0.62, 0.72), "🐷")
	_update_badges()
	_refresh()
	_flush_save()
	if _current_page == pages.get("shop"):
		_fill_page("shop")

# --- limited-time offer -------------------------------------------------
#
# One offer at a time, live for two hours, then five hours of nothing. The dark
# stretch is deliberate: an offer that is always on the shelf is just a price,
# and the countdown only means something if the player has seen it run out.
func _offer_tick() -> void:
	var now := _now()
	if offer_id != "":
		if now >= offer_until:
			offer_id = ""
			offer_until = 0.0
			offer_next = now + CV.OFFER_COOLDOWN
			_save_game()
			if _current_page == pages.get("shop"):
				_fill_page("shop")
		return
	if now < offer_next:
		return
	var pick: Dictionary = CV.TIMED_OFFERS[randi() % CV.TIMED_OFFERS.size()]
	offer_id = String(pick["id"])
	offer_until = now + CV.OFFER_DURATION
	_save_game()
	_notify("spins", "%s — %d%% extra value, 2 hours only!" % [pick["name"], CV.bonus_pct(pick)], pick["emoji"])
	_update_badges()
	if _current_page == pages.get("shop"):
		_fill_page("shop")

# The live offer's pack, or an empty dictionary when nothing is running.
func _active_offer() -> Dictionary:
	if offer_id == "" or _now() >= offer_until:
		return {}
	for o in CV.TIMED_OFFERS:
		if String(o["id"]) == offer_id:
			return o
	return {}

func _offer_countdown_text() -> String:
	var left := maxi(0, int(offer_until - _now()))
	return "%d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]

# --- contextual offers --------------------------------------------------
#
# The moment a player is stopped by a number is the moment the number is worth
# most to them, and every game in this genre sells into it -- Monopoly GO puts
# a cash offer in front of you the instant a building costs more than you have.
# Loot Lagoon used to answer both of those moments with an error beep.
#
# Neither of them is rate-limited any more. Both fire only on a tap the player
# made on purpose -- spin, or build -- and both answer the exact thing that tap
# could not do. A cooldown on an answer to a direct question is not a guard
# rail, it is the shop deciding to be shut.

# Shown when the reels are asked to spin and the meter cannot cover the bet.
#
# Two ways to arrive and they are the same wall: the meter is empty, or it holds
# four spins and the player has set bet x5. Both are "I asked to spin and could
# not", both are answered by the same pack, and answering the second with a red
# banner while the first got a store front was the shop closing at the one
# moment the player had already decided to spend.
#
# Leads with the free refill that is already coming, because burying it would
# make this a paywall -- the pack is the shortcut, not the only road.
func _offer_out_of_spins(bet := 1) -> void:
	var live := _active_offer()
	var pack: Dictionary = live if not live.is_empty() else _default_spin_pack()
	var short := bet > 1 and spins > 0
	var vbox := _open_popup("Not Enough Spins" if short else "Out of Spins")

	# What the wall actually is. A player holding four spins at bet x5 is not out
	# of spins, and a popup that tells them they are is wrong about the very
	# thing it interrupted them for.
	if short:
		var need := _popup_row_label("Bet  x%d  needs  %d  —  you have %d" % [bet, bet, spins], UI.F_BODY)
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(need)
	var wait := _popup_row_label("+%d spins free in %d min" % [SPIN_REGEN_AMOUNT, int(SPIN_REGEN_SECS / 60.0)],
		UI.F_CAPTION if short else UI.F_BODY)
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if short:
		wait.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	vbox.add_child(wait)
	var or_row := _popup_row_label("— or keep the run going —", UI.F_CAPTION)
	or_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_row.add_theme_color_override("font_color", Lagoon.INK_FAINT)
	vbox.add_child(or_row)
	_spin_offer_card(vbox, pack, not live.is_empty())
	_ctx_offer_footer(vbox)

# The rung this popup falls back to when no timed offer is live: whichever spin
# pack the shelf itself has marked POPULAR, so the interrupt and the store agree
# on what the sensible buy is instead of the popup holding its own opinion.
func _default_spin_pack() -> Dictionary:
	for p in CV.SPIN_PACKS:
		if p.has("tag"):
			return p
	return CV.SPIN_PACKS[mini(1, CV.SPIN_PACKS.size() - 1)]

# =============================================================================
#  The gap, sold as the gap
# =============================================================================
#
# A player who taps a hut they cannot afford is short a specific number. The
# store's answer to that used to be "here is the cheapest tin on the shelf that
# is bigger than your hole" -- 43,000 coins missing, so buy 90,000 for $2.99.
# That is a real answer, and it is the answer of a shop that would rather sell
# its own shelf than solve the problem: more than half of what it charges for is
# change the player did not ask for.
#
# So the gap is priced as the gap. Two rules keep that from becoming a trick in
# the other direction:
#
#   * The rate is the BEST rate published anywhere on the coin shelf, not the
#     worst and not one invented for this dialog. The player buying 43,000 coins
#     at the moment they are stuck pays the same per coin as the player who
#     calmly bought the $99.99 tier.
#   * The grant is never less than what that price buys in the shop. Rounding up
#     to a real Apple price tier always leaves a few cents of slack, and the
#     slack goes to the player, not the house.
#
# Which means the top-up is, by construction, never a worse deal than walking
# into the store and buying the same thing -- and usually a better one. It also
# needs no new products: it settles up through the coin-pack ids that are
# already registered, so nothing here waits on an App Store Connect round trip.
func _coin_rate() -> float:
	var best := 0.0
	for p in CV.COIN_PACKS:
		var usd := CV.price_usd(p)
		if usd > 0.0:
			best = maxf(best, float(_scaled(int(p["coins"]))) / usd)
	return best

func _topup_for(shortfall: int) -> Dictionary:
	var rate := _coin_rate()
	if rate <= 0.0 or shortfall <= 0:
		return {}
	var chosen: Dictionary = CV.COIN_PACKS[CV.COIN_PACKS.size() - 1]
	for p in CV.COIN_PACKS:
		if CV.price_usd(p) * rate >= float(shortfall):
			chosen = p
			break
	# Floored at what the shelf gives for this price, so the top-up is never the
	# worse deal; ceilinged at what that price is worth at the published rate,
	# so it is never a giveaway either. Without the ceiling, a shortfall bigger
	# than the whole top tier -- which is an ordinary Tuesday twenty islands in,
	# where a hut costs tens of millions -- would have sold ten times the
	# largest coin pack in the game for the price of one.
	var ceiling := int(CV.price_usd(chosen) * rate)
	var grant := clampi(shortfall, _scaled(int(chosen["coins"])), maxi(ceiling, _scaled(int(chosen["coins"]))))
	return {"pack": chosen, "coins": grant, "exact": grant >= shortfall}

# Shown the moment a build is tapped that the vault cannot cover. Fires on every
# such tap: the hut costs what it costs, the player asked for it by tapping it,
# and answering that with silence because the same thing happened twelve minutes
# ago is the store being coy at the one moment it was addressed.
func _offer_need_coins(shortfall: int) -> void:
	var offer := _topup_for(shortfall)
	if offer.is_empty():
		return
	var pack: Dictionary = offer["pack"]
	var grant: int = offer["coins"]
	var exact: bool = offer["exact"]

	var vbox := _open_popup("Not Enough Coins")

	var art := _pile_art("coins", 3, 5)
	vbox.add_child(art)

	var need := _popup_row_label("You're %s coins short" % _fmt_compact(shortfall), UI.F_BODY)
	need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(need)

	# Free money first. The piggy bank is coins the player has already earned,
	# and a store that hides that behind its own price list to make the sale is
	# a store that has decided its player is a mark.
	if piggy_coins > 0:
		var pig := _popup_row_label("\U0001F437  %s coins waiting in your piggy bank" % _fmt_compact(piggy_coins), UI.F_CAPTION)
		pig.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pig.add_theme_color_override("font_color", Color(1.0, 0.62, 0.72))
		vbox.add_child(pig)

	var card := _tinted_card(vbox, Lagoon.BRASS, true)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	card.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)

	var head := CenterContainer.new()
	col.add_child(head)
	# Three honest things this can be, and the badge says which. "Exactly what
	# you need" is only true when the number really is the number: under the
	# bottom rung it overshoots, and past the top rung it falls short. A badge
	# that says "exactly" over either is one the player learns to stop reading.
	var badge := "EXACTLY  WHAT  YOU  NEED"
	var badge_col := Lagoon.KELP_LO
	if not exact:
		badge = "THE  BIGGEST  PACK  THERE  IS"
		badge_col = Lagoon.BRASS_MID
	elif grant > shortfall:
		badge = "COVERS  IT,  WITH  CHANGE"
	head.add_child(_tag_chip(badge, badge_col, UI.F_TINY))

	var amount := Lagoon.wordmark("+%s" % _fmt_compact(grant), 56)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(amount)
	var unit := Lagoon.label("COINS", UI.F_TINY, Lagoon.BRASS_MID, true)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(unit)

	# Said out loud, because the whole point of this dialog is that it is not
	# the shelf price. A player who cannot check the claim has only been told
	# to trust it.
	var fair := Lagoon.label("Best coin rate in the shop — %s coins per $1" % _fmt_compact(int(_coin_rate())),
			UI.F_TINY, Lagoon.KELP_LO, true)
	fair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(fair)
	if not exact:
		var rest := Lagoon.label("Still %s short of this build after it" % _fmt_compact(shortfall - grant),
				UI.F_TINY, Lagoon.CORAL_LO, true)
		rest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(rest)

	if IAP.simulated():
		var note := Lagoon.label("Simulated purchase — no real charge.", UI.F_TINY, Lagoon.INK_FAINT)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(note)

	var pay := Button.new()
	pay.text = "PAY  %s" % IAP.price_for(pack)
	pay.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	pay.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(pay, Color(0.28, 0.68, 0.34))
	FX.press_feedback(pay)
	pay.pressed.connect(func() -> void:
		if IAP.busy:
			return
		pay.disabled = true
		pay.text = "…"
		# Written before the sheet opens and flushed to disk, not held in
		# memory until Apple answers. Between those two moments iOS is free to
		# kill the app, and a top-up that only existed in RAM would come back
		# on the next launch as an ordinary pack -- the player charged for the
		# gap and handed the shelf tin instead.
		topup_pending = {"id": String(pack["id"]), "coins": grant}
		_flush_save()
		IAP.purchase(pack)
	)
	col.add_child(pay)

	_ctx_offer_footer(vbox)

# The pack, sold the way the shop sells one.
#
# This card used to be a paragraph. Name in body type, contents as a grey
# sentence underneath -- "260 Spins + 4.19M Coins + 2 Cards" -- and a button.
# Every one of those facts was true and none of them was shown: the shelf four
# taps away draws the same product with a fan of wheels, the quantity at 52px,
# the old price struck through and a ribbon across the corner, and it does that
# because a pile of goods has to look like a pile of goods before a price means
# anything. The popup was asking for the sale in the harder position -- mid
# interrupt, unasked-for -- with a tenth of the art.
#
# So it is the shop tile now: same treasure card, same pile, same ladder of
# type, same ribbon. The one thing it keeps from the old card is the countdown,
# which is the only fact here the shelf cannot state.
func _spin_offer_card(vbox: VBoxContainer, pack: Dictionary, timed: bool) -> void:
	var card := _treasure_card(vbox, true)
	if timed:
		card.add_child(_shine_overlay(Lagoon.BRASS_HI))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	margin.add_child(col)

	# The clock first, and only when there is one. On a timed offer the deadline
	# is the reason to read the rest of the card; on the standing pack there is
	# no deadline, and inventing a chip to fill the slot would be inventing
	# urgency.
	if timed:
		var chip_wrap := CenterContainer.new()
		col.add_child(chip_wrap)
		chip_wrap.add_child(_tag_chip("⏳  %s  LEFT" % _offer_countdown_text(), Lagoon.REEF, UI.F_CAPTION))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		col.add_child(gap)

	var spins_n := int(pack.get("spins", 0))
	col.add_child(_pile_art("spins", _spin_pile_rung(spins_n), 5))

	# Spins are what the player came here short of, so spins are the headline and
	# everything else in the box is a supporting row -- even when the coins are
	# the larger number.
	var amount := Lagoon.wordmark(_fmt_compact(spins_n), 56)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(amount)
	var unit := Lagoon.label("SPINS", UI.F_CAPTION, Lagoon.BRASS_HI, true)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(unit)

	var nm := Lagoon.label(pack["name"], UI.F_CAPTION, Color(0.60, 0.76, 0.80))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	# The rest of the box, as counters rather than as a sentence -- and only the
	# rest of it: the spin count is already the headline, so repeating it here
	# would make the card argue with itself about what it is selling.
	if int(pack.get("coins", 0)) > 0 or int(pack.get("cards", 0)) > 0:
		var extras := {"coins": pack.get("coins", 0), "cards": pack.get("cards", 0)}
		var extras_wrap := CenterContainer.new()
		extras_wrap.custom_minimum_size = Vector2(0, 44)
		col.add_child(extras_wrap)
		extras_wrap.add_child(_reward_row(extras, Color(0.88, 0.95, 0.97), UI.F_LABEL))

	var save_slot := CenterContainer.new()
	save_slot.custom_minimum_size = Vector2(0, 40)
	col.add_child(save_slot)
	var struck := _struck_price_row(pack, Color(0.56, 0.71, 0.76))
	if struck != null:
		save_slot.add_child(struck)

	var buy := Button.new()
	buy.text = "GET  IT  —  %s" % IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	buy.add_theme_font_size_override("font_size", UI.F_BODY)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(func() -> void:
		_close_popup()
		_confirm_purchase(pack)
	)
	col.add_child(buy)

	# Reach is wider than the shop tile's because this card is wider: the band is
	# drawn corner-to-corner across the reach it is given, and 98px on a 500px
	# card is a stub sitting in open water rather than a ribbon crossing a frame.
	if pack.has("tag"):
		_corner_ribbon(card, String(pack["tag"]), pack.get("tag_color", Lagoon.REEF), 132.0)
	elif CV.bonus_pct(pack) >= 8:
		_corner_ribbon(card, "+%d%%  VALUE" % CV.bonus_pct(pack), Lagoon.URCHIN, 132.0)

# Where a spin count sits on the pile ladder, as a rung out of five.
#
# Floored at 2 rather than 0. The art fans one wheel at the bottom of the ladder
# and five at the top, which is right on a shelf where all seven rungs are on
# screen together and the smallest one has to look like the smallest one. Here
# there is exactly one card and nothing to be smaller than, so a single wheel
# is not modest, it is just a thin picture of the thing being sold.
func _spin_pile_rung(spins_n: int) -> int:
	var idx := 0
	for i in CV.SPIN_PACKS.size():
		if spins_n >= int(CV.SPIN_PACKS[i]["spins"]):
			idx = i
	return clampi(idx + 1, 2, 4)

# Every contextual offer keeps a plain way out that is not the close button, so
# dismissing never requires hunting for the small X.
func _ctx_offer_footer(vbox: VBoxContainer) -> void:
	var no := Button.new()
	no.text = "No thanks"
	no.custom_minimum_size = Vector2(0, UI.TAP)
	Lagoon.button(no, "glass", 22)
	no.add_theme_font_size_override("font_size", UI.F_CAPTION)
	FX.press_feedback(no)
	no.pressed.connect(func() -> void: _close_popup())
	vbox.add_child(no)

func _confirm_purchase(pack: Dictionary) -> void:
	var vbox := _open_popup("Confirm Purchase")
	if String(pack.get("id", "")).begins_with("chest_"):
		var art := _chest_art(pack, 64)
		art.custom_minimum_size = Vector2(0, 96)
		vbox.add_child(art)
	else:
		var e := _emoji_label(pack["emoji"], 64)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(e)
	var nm := _popup_row_label(pack["name"], UI.F_BODY)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(nm)
	var sub := _popup_row_label(_pack_sub(pack), UI.F_CAPTION)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Ink, not white: the modal is glass, and what the player is buying was
	# rendering as a ghost of itself on it.
	sub.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	vbox.add_child(sub)
	# The odds go above the pay button. A disclosure the player reaches after
	# deciding is not a disclosure.
	if _is_randomized(pack):
		vbox.add_child(Lagoon.divider())
		_odds_table(vbox, pack)
		vbox.add_child(Lagoon.divider())
	# Only where it is true. On a phone the charge is real, and a leftover
	# "no real charge" under a live StoreKit sheet would be the most expensive
	# sentence in the app.
	if IAP.simulated():
		var note := _popup_row_label("Simulated purchase — no real charge.", UI.F_TINY)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", Lagoon.INK_FAINT)
		vbox.add_child(note)
	var pay := Button.new()
	pay.text = "PAY  %s" % IAP.price_for(pack)
	pay.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(pay, Color(0.28, 0.68, 0.34))
	FX.press_feedback(pay)
	# Pay hands off to IAP and waits. The modal stays up under Apple's own
	# sheet so there is somewhere for a failure to be reported back to, and
	# _on_purchase_ok is what finally closes it.
	pay.pressed.connect(func() -> void:
		if IAP.busy:
			return
		pay.disabled = true
		pay.text = "…"
		IAP.purchase(pack)
	)
	vbox.add_child(pay)

# Pack blurbs quote their coin figure with a %s, since what "25,000 Coins" is
# worth depends entirely on which island you buy it from.
func _pack_sub(pack: Dictionary) -> String:
	var sub := String(pack.get("sub", ""))
	if sub.contains("%s"):
		return sub % _fmt_compact(_scaled(int(pack.get("coins", 0))))
	return sub

# Apple says the money moved. Turn the product id back into the thing that was
# bought, hand it over, and only then tell Apple the transaction is done -- the
# grant writes the save, so finishing before it would risk charging a player
# for coins that never landed.
func _on_purchase_ok(product_id: String) -> void:
	_close_popup()
	var short := product_id.trim_prefix(IAP.PREFIX)
	if short == String(CV.PIGGY_PACK["id"]):
		_break_piggy()
		IAP.finish(product_id)
		return
	var pack := CV.pack_by_id(short)
	if pack.is_empty():
		# An id the build does not know -- a pack pulled from the store while a
		# purchase was in flight, most likely. Say so rather than failing mute.
		#
		# It still gets recorded. There is nothing to grant and never will be in
		# this build, and leaving it unrecorded would park it at the head of the
		# reconcile queue forever, where it would replay this banner every
		# launch and block every real transaction waiting behind it.
		_banner("Purchase received, but this build has no such pack.", Color(0.9, 0.4, 0.4))
		IAP.finish(product_id)
		return
	# A top-up settles up through an ordinary coin-pack id, so this is the only
	# place that can tell the two apart. Cleared before the grant, not after:
	# the grant writes the save, and a record left standing through it would
	# survive a crash mid-grant and pay out twice.
	if String(topup_pending.get("id", "")) == short:
		var exact := int(topup_pending.get("coins", 0))
		topup_pending = {}
		if exact > 0:
			pack = pack.duplicate()
			pack["coins_exact"] = exact
			pack["name"] = "%s Coins" % _fmt_compact(exact)
	_grant_pack(pack)
	IAP.finish(product_id)

# Backing out of Apple's sheet is a decision, not a fault. Take the spinner
# down and say nothing -- the player knows what they just did.
func _on_purchase_cancel(_product_id: String) -> void:
	topup_pending = {}
	_close_popup()

# This is now only reached by genuine failures, so it may be as loud as it
# looks: something the player asked for did not happen.
func _on_purchase_fail(_product_id: String, message: String) -> void:
	topup_pending = {}
	_close_popup()
	Sfx.play("error", -6.0)
	_banner(message, Color(0.9, 0.4, 0.4))

# Apple answered with real products, so every price on screen is now wrong --
# it is still the hardcoded dollar string. Repaint whatever is open.
func _on_products_loaded() -> void:
	# Unconditionally, not just when the shop happens to be open. Rebuilding a
	# hidden page costs nothing, and the alternative is a shop that keeps its
	# dollar placeholders until the player thinks to leave and come back.
	if pages.has("shop"):
		_fill_page("shop")

func _grant_pack(pack: Dictionary) -> void:
	if pack.get("once", false):
		purchased_ids.append(pack["id"])
	# Buying the live offer ends it. Leaving the countdown ticking over a pack
	# the player already owns is the store advertising at someone who just paid.
	if offer_id != "" and String(pack.get("id", "")) == offer_id:
		offer_id = ""
		offer_until = 0.0
		offer_next = _now() + CV.OFFER_COOLDOWN
		_offer_timer_label = null
	spins += int(pack.get("spins", 0))
	# coins_exact is set only by the build-blocked top-up, which has already
	# done its own scaling against the island the shortfall was measured on.
	# Running it through _scaled again would multiply it a second time.
	if pack.has("coins_exact"):
		coins += int(pack["coins_exact"])
	else:
		coins += _scaled(int(pack.get("coins", 0)))
	shields = mini(3, shields + int(pack.get("shields", 0)))
	var pre_complete := {}
	for c in CV.COLLECTIONS:
		pre_complete[c["id"]] = _collection_complete(c)
	var cards := []
	for i in int(pack.get("cards", 0)):
		# the top chest guarantees at least one 5-star card
		var forced := CV.MAX_STAR if pack.get("guarantee5", false) and i == 0 else 0
		cards.append(_grant_chest_card(int(pack.get("tier", 0)), forced))
	var completed := []
	for c in CV.COLLECTIONS:
		if not pre_complete[c["id"]] and _collection_complete(c) and not col_claimed.get(c["id"], false):
			completed.append(c["name"])
	Sfx.play("jackpot", -3.0)
	FX.confetti(self, 44)
	FX.flash(self)
	if cards.is_empty():
		_banner("Purchase complete — %s!" % pack["name"], Color(0.5, 0.9, 0.5), pack["emoji"])
	else:
		_show_chest_result(cards, "Chest Opened!", "", completed)
	_update_badges()
	_refresh()
	# Straight to disk: IAP.finish() records this transaction as granted the
	# moment we return, and a save still sitting in memory when the app dies is
	# a pack the player paid for that no launch will ever hand over again.
	_flush_save()
	if _current_page == pages.get("shop"):
		_fill_page("shop")

# Picks one [collection, index] entry, each candidate weighted by how often
# its collection drops. Ties the chest pool to the same difficulty ladder the
# reels use, so an Easy set's single gold card is the one a chest usually pays
# out and a Hard set's stays a chase.
func _weighted_card(cards: Array) -> Array:
	if cards.is_empty():
		return []
	var total := 0
	for e in cards:
		total += int((e[0] as Dictionary)["weight"])
	if total <= 0:
		return cards.pick_random()
	var roll := randi_range(1, total)
	for e in cards:
		roll -= int((e[0] as Dictionary)["weight"])
		if roll <= 0:
			return e
	return cards[cards.size() - 1]

func _grant_chest_card(tier: int, forced_star := 0) -> Dictionary:
	# roll the star rating first (higher tiers skew rarer), then draw a
	# card of that rarity, favoring ones the player doesn't own yet
	var star := forced_star
	if star <= 0:
		var w: Array = CV.CHEST_STAR_WEIGHTS[tier]
		var total := 0
		for v in w:
			total += int(v)
		var roll := randi_range(1, total)
		star = 1
		for i in w.size():
			roll -= int(w[i])
			if roll <= 0:
				star = i + 1
				break
	var pool := []
	var missing := []
	for c in CV.COLLECTIONS:
		var items: Array = c["items"]
		var owned: Array = col_owned[c["id"]]
		for i in items.size():
			if int(items[i][2]) != star:
				continue
			pool.append([c, i])
			if not owned[i]:
				missing.append([c, i])
	# Which set the card comes from is the set's own drop weight, the same
	# ladder a spin uses. Drawing flat across everything of this rarity was
	# fine while 5-star cards lived only in Hard sets -- the star roll *was*
	# the set roll. Now that every set ends on a gold card, a flat draw would
	# hand Royal Jewels a ninth of every 5-star chest card and collapse a
	# three-week set into an afternoon of opening boxes.
	# Mostly random within that (duplicates are the norm), with a small pity
	# bias toward missing cards so progress never fully stalls.
	var from := missing if not missing.is_empty() and randf() < 0.25 else pool
	var pick: Array = _weighted_card(from)
	if pick.is_empty():
		# No card of this rarity exists anywhere in the season's sets. Not
		# possible with the sets as written, and a crash on the chest-opening
		# path is not the way to find out that somebody edited one.
		return {"emoji": "🃏", "name": "Blank Card", "set": "", "stars": star, "dup": true, "refund": 0, "held": 0}
	var chosen: Dictionary = pick[0]
	var idx: int = pick[1]
	var it: Array = chosen["items"][idx]
	var owned: Array = col_owned[chosen["id"]]
	if owned[idx]:
		_add_dupe(chosen["id"], idx)
		var refund := _scaled(60 * star)
		coins += refund
		return {"emoji": it[0], "name": it[1], "set": chosen["name"], "stars": star,
			"dup": true, "refund": refund, "held": _dupe_count(chosen["id"], idx)}
	owned[idx] = true
	# A first copy is a first copy wherever it came from: the same stars a spin
	# drop would have paid, banked to rank as well as to the wallet. The caller
	# totals the flight and the sound for the whole handful, so this one is
	# silent on purpose.
	_earn_stars(star)
	return {"emoji": it[0], "name": it[1], "set": chosen["name"], "stars": star, "dup": false}

func _show_chest_result(cards: Array, title := "Chest Opened!", bonus_text := "", completed_sets: Array = []) -> void:
	var vbox := _open_popup(title)
	if bonus_text != "":
		var b := _popup_row_label(bonus_text, UI.F_LABEL)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_color_override("font_color", Lagoon.BRASS_LO)
		vbox.add_child(b)
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a, b): return int(a["stars"]) > int(b["stars"]))
	var center := CenterContainer.new()
	vbox.add_child(center)
	var grid := GridContainer.new()
	grid.columns = mini(3, sorted.size())
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	center.add_child(grid)
	for ci in sorted.size():
		var card: Dictionary = sorted[ci]
		var stars := int(card.get("stars", 1))
		var sc: Color = CV.STAR_COLORS[stars - 1]
		var tile := _tinted_card(grid, sc, stars >= 4, Lagoon.R_CHIP + 4)
		tile.custom_minimum_size = Vector2(166, 0)
		var tile_pad := MarginContainer.new()
		for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			tile_pad.add_theme_constant_override(m, 8)
		tile.add_child(tile_pad)
		var colv := VBoxContainer.new()
		colv.alignment = BoxContainer.ALIGNMENT_CENTER
		colv.add_theme_constant_override("separation", 2)
		tile_pad.add_child(colv)
		var e := _emoji_label(card["emoji"], 40)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		colv.add_child(e)
		var nm := Lagoon.label(card["name"], UI.F_TINY, Lagoon.INK, true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		colv.add_child(nm)
		colv.add_child(_star_row(stars, UI.F_TINY))
		var status := Label.new()
		if card["dup"]:
			status.text = "SPARE  x%d" % int(card.get("held", 1))
			status.add_theme_color_override("font_color", Lagoon.INK_FAINT)
		else:
			status.text = "NEW!"
			status.add_theme_color_override("font_color", Lagoon.KELP_LO)
		status.add_theme_font_size_override("font_size", UI.F_TINY)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		colv.add_child(status)
		# staggered reveal, rarest first
		tile.modulate.a = 0.0
		var tw := tile.create_tween()
		tw.tween_interval(0.07 * ci)
		tw.tween_property(tile, "modulate:a", 1.0, 0.22)
	for set_name in completed_sets:
		var done_row := HBoxContainer.new()
		done_row.alignment = BoxContainer.ALIGNMENT_CENTER
		done_row.add_theme_constant_override("separation", 8)
		vbox.add_child(done_row)
		done_row.add_child(_emoji_label("🎉", UI.F_LABEL))
		var done := _popup_row_label("%s complete — claim it in Collections!" % set_name, UI.F_CAPTION)
		done.add_theme_color_override("font_color", Lagoon.KELP_LO)
		done_row.add_child(done)
		FX.pulse_forever(done_row, 1.04, 1.2)

	# What the handful was worth to your standing. Read off the cards rather
	# than passed in, so a chest bought with money, a box bought with stars and
	# the free gift all say it the same way -- and so the spares are visibly
	# the reason the number is not higher.
	var rank_gain := 0
	for c in cards:
		if not c.get("dup", false):
			rank_gain += int(c.get("stars", 0))
	if rank_gain > 0:
		var gain := _popup_row_label("\u2b50  +%d world rank" % rank_gain, UI.F_LABEL)
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gain.add_theme_color_override("font_color", CV.STAR_COLORS[CV.MAX_STAR - 1])
		vbox.add_child(gain)
		FX.pulse_forever(gain, 1.05, 1.1)

	var ok := Button.new()
	ok.text = "COLLECT!"
	ok.custom_minimum_size = Vector2(0, UI.TAP)
	_candy_button(ok, Color(0.45, 0.75, 0.35))
	FX.press_feedback(ok)
	ok.pressed.connect(func() -> void: _close_popup())
	vbox.add_child(ok)

func _fill_quests(vb: VBoxContainer) -> void:
	_ensure_missions()
	_quests_timer_label = null

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	vb.add_child(tabs)
	for period in MISSION_DEFS:
		tabs.add_child(_quests_tab_button(period))

	var info: Dictionary = MISSION_TAB_INFO[quests_tab]
	var defs: Array = MISSION_DEFS[quests_tab]
	var st: Dictionary = mission_state[quests_tab]

	# header: cycle title, reset countdown, overall completion
	var head := _page_card(vb)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 14)
	head.add_child(hrow)
	var hicon := _emoji_label(str(info["emoji"]), 42)
	hrow.add_child(hicon)
	FX.pulse_forever(hicon, 1.09, 1.6)
	var hcol := VBoxContainer.new()
	hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hcol.add_theme_constant_override("separation", 3)
	hrow.add_child(hcol)
	var ht := Lagoon.label("%s  MISSIONS" % info["title"], UI.F_BODY, Lagoon.INK, true)
	hcol.add_child(ht)
	_quests_timer_label = _popup_row_label("", UI.F_CAPTION)
	_quests_timer_label.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	hcol.add_child(_quests_timer_label)
	_update_quests_timer()
	var done := 0
	for m in defs:
		if bool(st["claimed"].get(m["id"], false)):
			done += 1
	var hdone := Lagoon.label("%d/%d" % [done, defs.size()], UI.F_SUBHEAD,
		Lagoon.KELP_LO if done == defs.size() else Lagoon.INK, true)
	hdone.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(hdone)
	var hpb := _styled_progress(Color(info["color"]).lightened(0.15))
	hpb.max_value = defs.size()
	hpb.value = done
	head.add_child(hpb)

	_quests_bonus_card(vb)

	# ready first, then in-progress, claimed sink to the bottom
	var order := []
	for i in defs.size():
		var m: Dictionary = defs[i]
		var rank := 1
		if _mission_ready(quests_tab, m):
			rank = 0
		elif bool(st["claimed"].get(m["id"], false)):
			rank = 2
		order.append({"m": m, "rank": rank * 100 + i})
	order.sort_custom(func(a, b) -> bool: return a["rank"] < b["rank"])
	for i in order.size():
		_quest_card(vb, order[i]["m"], i)

func _quests_tab_button(period: String) -> Button:
	var info: Dictionary = MISSION_TAB_INFO[period]
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, UI.TAP)
	# Selected tab is solid; the others are glass, so "where am I" is a
	# difference in material rather than three saturated colours competing.
	if period == quests_tab:
		_candy_button(b, Color(info["color"]))
	else:
		Lagoon.button(b, "glass")
		Lagoon.button_gloss(b, 22)
	# emoji won't render inside Button text on iOS — compose the face manually
	var face := CenterContainer.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	face.add_child(frow)
	frow.add_child(_emoji_label(str(info["emoji"]), UI.F_LABEL))
	var ft := Lagoon.label(str(info["title"]), UI.F_CAPTION,
		Color.WHITE if period == quests_tab else Lagoon.INK_SOFT, true)
	frow.add_child(ft)
	FX.press_feedback(b)
	b.pressed.connect(func() -> void:
		if quests_tab == period:
			return
		quests_tab = period
		Sfx.play("pop", -10.0)
		_fill_page("quests")
	)
	if period != quests_tab and _period_claimable(period):
		var dot := Panel.new()
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = Lagoon.REEF
		dsb.set_corner_radius_all(9)
		dsb.set_border_width_all(2)
		dsb.border_color = Color.WHITE
		dot.add_theme_stylebox_override("panel", dsb)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
		dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -24.0
		dot.offset_right = -6.0
		dot.offset_top = 6.0
		dot.offset_bottom = 24.0
		FX.pulse_forever(dot, 1.25, 0.9)
	return b

func _reward_chip(emoji: String, text: String, col: Color) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(_emoji_label(emoji, UI.F_CAPTION))
	hb.add_child(Lagoon.label(text, UI.F_CAPTION, col, true))
	return hb

func _update_quests_timer() -> void:
	if _quests_timer_label == null or not is_instance_valid(_quests_timer_label):
		return
	_quests_timer_label.text = "Resets in  %s" % _countdown_text(_period_reset_secs(quests_tab))

func _quests_bonus_card(vb: VBoxContainer) -> void:
	var st: Dictionary = mission_state[quests_tab]
	var b: Dictionary = MISSION_BONUS[quests_tab]
	var claimed_bonus := bool(st.get("bonus", false))
	var ready := _bonus_ready(quests_tab)

	var panel := _tinted_card(vb, Lagoon.BRASS if ready else Color(Lagoon.BRASS.r, Lagoon.BRASS.g, Lagoon.BRASS.b, 0.30), ready)
	if claimed_bonus:
		panel.modulate.a = 0.55
	FX.pop_in(panel, 0.3)
	var margin := MarginContainer.new()
	for mg in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(mg, 14)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	var chest := _emoji_label(str(b["emoji"]), 44)
	row.add_child(chest)
	if ready:
		FX.pulse_forever(chest, 1.15, 0.7)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var t := Lagoon.label("ALL-CLEAR  BONUS", UI.F_LABEL, Lagoon.INK, true)
	col.add_child(t)
	var sub := _popup_row_label("Claim every mission to unlock", UI.F_CAPTION)
	sub.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	col.add_child(sub)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 12)
	col.add_child(rrow)
	rrow.add_child(_reward_chip("💰", "+%s" % _fmt_compact(_bonus_coins(quests_tab)), Lagoon.BRASS_LO))
	rrow.add_child(_reward_chip("🌀", "+%d" % int(b["spins"]), Lagoon.LAGOON_DEEP))
	if claimed_bonus:
		row.add_child(_emoji_label("✅", 34))
	else:
		var btn := Button.new()
		btn.text = "CLAIM"
		btn.custom_minimum_size = Vector2(132, UI.TAP)
		btn.disabled = not ready
		_candy_button(btn, Color(0.95, 0.65, 0.15))
		FX.press_feedback(btn)
		if ready:
			FX.pulse_forever(btn, 1.06, 0.7)
		btn.pressed.connect(func() -> void: _claim_mission_bonus(quests_tab))
		row.add_child(btn)

func _quest_card(vb: VBoxContainer, m: Dictionary, index: int) -> void:
	var st: Dictionary = mission_state[quests_tab]
	var id: String = m["id"]
	var claimed := bool(st["claimed"].get(id, false))
	var ready := _mission_ready(quests_tab, m)
	var prog := mini(int(st["progress"].get(id, 0)), _mission_target(m))
	var icol: Color = MISSION_ICON_COLORS.get(id, Color(0.4, 0.4, 0.6))

	# A claimable mission is rimmed in brass; everything else is plain glass.
	# One difference, applied consistently, so a full page of missions still
	# points straight at the ones worth tapping.
	var panel := _tinted_card(vb, Lagoon.BRASS if ready else Color(Lagoon.LAGOON.r, Lagoon.LAGOON.g, Lagoon.LAGOON.b, 0.35), ready)
	# staggered entrance
	var target_a := 0.5 if claimed else 1.0
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_interval(0.045 * index)
	tw.tween_property(panel, "modulate:a", target_a, 0.22)

	var margin := MarginContainer.new()
	for mg in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(mg, 12)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var tile := Lagoon.token(str(m["emoji"]), 68.0, icol)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tile)
	if ready:
		FX.pulse_forever(tile, 1.08, 0.8)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var d := Lagoon.label(str(m["desc"]), UI.F_LABEL, Lagoon.INK)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	col.add_child(prow)
	var pb := _styled_progress(Lagoon.BRASS if ready or claimed else icol)
	pb.max_value = _mission_target(m)
	pb.value = prog
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(pb)
	prow.add_child(Lagoon.label("%s/%s" % [_fmt_compact(prog), _fmt_compact(_mission_target(m))], UI.F_TINY, Lagoon.INK_SOFT))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	var spin_r := int(m.get("spins", 0))
	if spin_r > 0:
		right.add_child(_reward_chip("🌀", "+%d" % spin_r, Lagoon.LAGOON_DEEP))
	else:
		right.add_child(_reward_chip("🪙", "+%s" % _fmt_compact(_mission_coins(m)), Lagoon.BRASS_LO))
	if claimed:
		var donel := _emoji_label("✅", 30)
		donel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(donel)
	else:
		var claim := Button.new()
		claim.text = "CLAIM"
		claim.custom_minimum_size = Vector2(132, UI.TAP)
		claim.disabled = not ready
		_candy_button(claim, Color(0.45, 0.75, 0.35))
		FX.press_feedback(claim)
		if ready:
			FX.pulse_forever(claim, 1.05, 0.7)
		claim.pressed.connect(_claim_mission.bind(quests_tab, m))
		right.add_child(claim)

func _fill_options(vb: VBoxContainer) -> void:
	var inner := _page_card(vb)
	var mute := Toggle.new("Mute sounds", "Silence every sound in the game")
	mute.set_on(muted)
	mute.switched.connect(func(on: bool) -> void:
		muted = on
		AudioServer.set_bus_mute(0, on)
		_save_game()
	)
	inner.add_child(mute)

	var ncard := _page_card(vb)
	var nhead := HBoxContainer.new()
	nhead.add_theme_constant_override("separation", 8)
	ncard.add_child(nhead)
	nhead.add_child(_emoji_label("🔔", UI.F_BODY))
	var ntitle := _popup_row_label("Notifications", UI.F_BODY)
	ntitle.add_theme_color_override("font_color", Lagoon.INK)
	nhead.add_child(ntitle)

	var master := Toggle.new("Enable notifications", "Master switch for everything below")
	master.set_on(notif_enabled)
	ncard.add_child(master)

	var type_defs := [
		["attack", "Attack alerts", "A rival smashes a building on your island"],
		["steal", "Steal alerts", "A rival takes coins out of your vault"],
		["spins", "Spins refilled", "+%d spins every %d min" % [SPIN_REGEN_AMOUNT, int(SPIN_REGEN_SECS / 60.0)]],
		["gift", "Daily gift", "Your free gift is ready again"],
		["events", "Events ending", "An hour's warning before an offer or a season ends"],
	]
	var per_type: Array[Toggle] = []
	for def in type_defs:
		var key: String = def[0]
		ncard.add_child(Lagoon.divider())
		var row := Toggle.new(def[1], def[2])
		row.set_on(bool(notif_types.get(key, true)))
		row.set_dimmed(not notif_enabled)
		row.switched.connect(func(on: bool) -> void:
			notif_types[key] = on
			_save_game()
		)
		ncard.add_child(row)
		per_type.append(row)

	# Dimming them in place beats rebuilding the page: the master switch gets
	# to finish its own animation instead of being replaced mid-slide.
	master.switched.connect(func(on: bool) -> void:
		notif_enabled = on
		for row in per_type:
			row.set_dimmed(not on)
		_save_game()
		# The plan iOS is holding was built from these switches, so it is stale
		# the moment one moves. Rewritten rather than left to the next
		# backgrounding, which might be a kill.
		Alerts.schedule(_alert_plan(_now()), _now())
	)

	# The switches above decide what the game would like to send. iOS decides
	# whether any of it reaches the lock screen, and it is entirely normal for
	# the two to disagree -- so say which one is currently winning rather than
	# leaving a player with everything switched on wondering why their phone is
	# silent. Not a nag: the only state that gets a button is the one the
	# player can still do something about.
	var perm := Alerts.status()
	if perm == "denied":
		ncard.add_child(Lagoon.divider())
		var off := _popup_row_label("Phone notifications are off for Loot Lagoon in iOS Settings — the alerts above will only appear inside the game.", UI.F_CAPTION)
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		off.add_theme_color_override("font_color", Lagoon.INK_SOFT)
		ncard.add_child(off)
		var settings_btn := Button.new()
		settings_btn.text = "Open iOS Settings"
		settings_btn.custom_minimum_size = Vector2(0, UI.TAP)
		_candy_button(settings_btn, Color(0.35, 0.55, 0.8))
		FX.press_feedback(settings_btn)
		settings_btn.pressed.connect(func() -> void: OS.shell_open("app-settings:"))
		ncard.add_child(settings_btn)
	elif perm == "notDetermined":
		ncard.add_child(Lagoon.divider())
		var ask := Button.new()
		ask.text = "Turn on phone notifications"
		ask.custom_minimum_size = Vector2(0, UI.TAP)
		_candy_button(ask, Color(0.28, 0.68, 0.34))
		FX.press_feedback(ask)
		ask.pressed.connect(func() -> void:
			notif_prompted = true
			_save_game()
			Alerts.request_permission()
		)
		ncard.add_child(ask)

	var acc := _page_card(vb)
	acc.add_child(_popup_row_label("Signed in as:  %s  (%s)" % [profile.get("name", "Guest"), profile.get("provider", "guest")], UI.F_LABEL))
	var signout := Button.new()
	signout.text = "Sign out"
	signout.custom_minimum_size = Vector2(0, UI.TAP)
	_candy_button(signout, Color(0.55, 0.45, 0.65))
	FX.press_feedback(signout)
	signout.pressed.connect(func() -> void:
		profile = {}
		if FileAccess.file_exists("user://profile.json"):
			DirAccess.remove_absolute("user://profile.json")
		# The session has to go too. Clearing only the local profile left the
		# player looking signed out while the game carried on pushing their
		# island to a server under the name they had just removed.
		Cloud.sign_out()
		_show_login()
	)
	acc.add_child(signout)

	# --- connected sign-ins -------------------------------------------------
	#
	# This is the screen that makes "he had Android, now he has an iPhone" work,
	# and it only works if the player uses it BEFORE they lose the old phone.
	# Identity is an explicit row on the server, never an email match -- Apple's
	# Hide My Email makes email matching fail in both directions -- so a second
	# provider has to be attached deliberately, in advance.
	#
	# The list is what CAN BE CONNECTED, which is not the same list as what can
	# be signed in with. They coincide today because Apple's off-platform web
	# flow is not built yet; when it is, Android grows a Connect Apple button
	# without growing an Apple sign-in button.
	if Cloud.linked():
		acc.add_child(Lagoon.divider())
		var link_head := _popup_row_label("Keep your island if you change phone", UI.F_CAPTION)
		link_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		acc.add_child(link_head)
		var link_box := VBoxContainer.new()
		link_box.add_theme_constant_override("separation", 8)
		acc.add_child(link_box)
		var pending := _popup_row_label("Checking…", UI.F_TINY)
		link_box.add_child(pending)
		Cloud.identities(func(list: Array) -> void:
			# The answer arrives from a server; the page it was asked for may
			# have been closed several taps ago.
			if not is_instance_valid(link_box):
				return
			for c in link_box.get_children():
				c.queue_free()
			for prov in _providers_here():
				var id := String(prov["id"])
				if list.has(id):
					var done := _popup_row_label("%s  ·  connected" % String(prov["label"]), UI.F_TINY)
					done.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6))
					link_box.add_child(done)
					continue
				var b := Button.new()
				b.text = "Connect %s" % id.capitalize()
				b.custom_minimum_size = Vector2(0, UI.TAP)
				b.add_theme_font_size_override("font_size", UI.F_CAPTION)
				_candy_button(b, Color(0.35, 0.55, 0.75))
				FX.press_feedback(b)
				b.pressed.connect(func() -> void:
					b.disabled = true
					# The token is written to disk before the sign-in starts,
					# because the sign-in is what replaces this session -- and
					# on Android it opens a browser, which can put the game in
					# the background long enough to be killed.
					Cloud.begin_link(func(ok: bool) -> void:
						if not ok:
							if is_instance_valid(b):
								b.disabled = false
							_banner("Couldn't start — try again in a moment.",
									Color(0.95, 0.55, 0.3))
							return
						_close_popup()
						_start_login(id)
					)
				)
				link_box.add_child(b)
		)

	# Signing in creates an account, and Guideline 5.1.1(v) then requires a way
	# to delete it from inside the app -- not an email address, not a web form.
	# It sits under Sign out, deliberately quieter than it, because the two are
	# one tap apart and only one of them is reversible.
	acc.add_child(Lagoon.divider())
	var wipe := Button.new()
	wipe.text = "Delete account & data"
	wipe.custom_minimum_size = Vector2(0, UI.TAP)
	wipe.add_theme_font_size_override("font_size", UI.F_CAPTION)
	_candy_button(wipe, Color(0.72, 0.32, 0.34))
	FX.press_feedback(wipe)
	wipe.pressed.connect(_confirm_delete_account)
	acc.add_child(wipe)

	vb.add_child(_page_note("Loot Lagoon  •  %s" % BuildID.label(), UI.F_CAPTION))

# Deleting an account has to actually delete something, and the honest list is
# short enough to print: who you signed in as, and the island itself.
#
# That list used to end "and both are on this device, because nothing about this
# player has ever left it". That stopped being true the day cloud.gd landed. A
# signed-in player has a row on a server, and a delete that only cleared the
# phone would leave it there -- so the next sign-in would hand the island
# straight back, and the player would be told they had deleted something they
# had not. Guideline 5.1.1(v) is about the account, not the copy of it that
# happens to be nearest.
#
# So the server goes first and the local wipe only happens if it succeeded. The
# other order is worse than doing nothing: local gone, server intact, and no way
# left to sign in and ask again.
#
# The purchase ledger deliberately survives. It holds Apple's transaction ids
# and nothing about the player, and clearing it would hand the next launch a
# blank slate to reconcile against a StoreKit history that still remembers
# every sale -- see iap.gd. Keeping receipts is also exactly what Apple's own
# carve-out for legal and transaction records covers.
func _confirm_delete_account() -> void:
	var vbox := _open_popup("Delete Account")
	var e := _emoji_label("⚠️", 64)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(e)
	# Two versions, because saying "from this device" to someone whose island is
	# also on a server is a false promise, and saying "and from our servers" to a
	# guest is a claim about data that never existed.
	var where := "from this device and from our servers" if Cloud.linked() else "from this device"
	var body := _popup_row_label("This erases your sign-in and your island — level, coins, spins, cards and collections — %s. It cannot be undone, and purchases already made are not refunded." % where, UI.F_CAPTION)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	var go := Button.new()
	go.text = "DELETE  EVERYTHING"
	go.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(go, Color(0.78, 0.28, 0.3))
	FX.press_feedback(go)
	# The local wipe, unchanged, lifted into a callable so the cloud path can
	# run it after the server has confirmed rather than duplicating it.
	var wipe := func() -> void:
		# Every copy, not just the live one -- _write_save keeps a .bak beside
		# the save and may have left a .tmp behind, and _read_save would happily
		# restore the island from either of them on the very next launch.
		# Anything still queued would write the island straight back out.
		_save_pending = false
		# Cloud.SESSION_PATH is in the list even though delete_account() already
		# clears it on the way through: the guest path never calls that, and a
		# session file left behind by an earlier build would have the next launch
		# quietly adopt an island the player believes they deleted.
		for path in ["user://profile.json", SAVE_PATH, SAVE_BAK, SAVE_TMP, Cloud.SESSION_PATH]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		_close_popup(true)
		# Put the store's signal queue back in front of the gap. The new Main
		# does not connect to IAP until the end of its boot, a couple of
		# seconds away, and IAP has been "started" since this one booted -- so
		# a purchase completing in between would be emitted to nobody, never
		# reach finish(), and never be written to the ledger. Re-arming the
		# queue holds it until the new scene calls begin().
		IAP.rearm()
		# Rebuilding every page against a wiped save by hand is a long list of
		# chances to miss one. Restarting the scene is the same thing a fresh
		# install does, which is the state we just claimed to have produced.
		get_tree().reload_current_scene()

	go.pressed.connect(func() -> void:
		go.disabled = true
		if not Cloud.linked():
			wipe.call()
			return
		go.text = "DELETING…"
		Cloud.delete_account(func(ok: bool) -> void:
			if ok:
				wipe.call()
				return
			# Nothing has been touched yet, which is the point. Re-arm the
			# button and say so plainly -- a player who meant to delete and was
			# told nothing would assume it worked.
			go.disabled = false
			go.text = "DELETE  EVERYTHING"
			_banner("Couldn't reach the server — nothing was deleted. Try again.",
					Color(0.95, 0.4, 0.4))
		)
	)
	vbox.add_child(go)

	var keep := Button.new()
	keep.text = "Keep my account"
	keep.custom_minimum_size = Vector2(0, UI.TAP)
	_candy_button(keep, Color(0.45, 0.55, 0.6))
	FX.press_feedback(keep)
	keep.pressed.connect(func() -> void: _close_popup())
	vbox.add_child(keep)

func _styled_progress(fg_color: Color) -> ProgressBar:
	return Lagoon.progress(fg_color)

# --- collections ---

func _ensure_collections() -> void:
	var now := _now()
	if col_deadline <= 0.0 or now > col_deadline:
		col_owned = {}
		col_dupes = {}
		col_claimed = {}
		col_mega_claimed = false
		col_deadline = now + CV.COLLECTION_SEASON_DAYS * 86400.0
	# This is the only thing that normalizes the card tables, and everything
	# downstream indexes col_owned[id] directly on the strength of it having
	# run. It used to read the saved arrays with typed assignments and bool()
	# / int() casts, so one non-array set -- or one string where a bool
	# belonged -- raised, abandoned the loop, and left every set from that
	# point on with no entry at all. Card drops then stopped, chests returned
	# nothing and the Collections page came up blank, permanently: the bad
	# value was written straight back out on the next autosave, so it survived
	# every restart with no way back. Read defensively instead, per set, so a
	# damaged set costs that set and nothing else.
	for c in CV.COLLECTIONS:
		var id: String = c["id"]
		var n: int = (c["items"] as Array).size()
		var raw_owned = col_owned.get(id, [])
		var raw_dupes = col_dupes.get(id, [])
		var arr: Array = raw_owned if typeof(raw_owned) == TYPE_ARRAY else []
		var dup: Array = raw_dupes if typeof(raw_dupes) == TYPE_ARRAY else []
		var norm := []
		var dnorm := []
		for i in n:
			norm.append(_b(arr[i]) if i < arr.size() else false)
			dnorm.append(maxi(0, _i(dup[i])) if i < dup.size() else 0)
		col_owned[id] = norm
		col_dupes[id] = dnorm
		col_claimed[id] = _b(col_claimed.get(id, false))
	# Sets the build no longer has have no business keeping a slot; leaving
	# them means a renamed collection quietly doubles the save every season.
	for key in col_owned.keys():
		if not CV.COLLECTIONS.any(func(c): return c["id"] == key):
			col_owned.erase(key)
			col_dupes.erase(key)
			col_claimed.erase(key)

# One spare copy of card `idx` in set `id` goes onto the pile.
func _add_dupe(id: String, idx: int) -> void:
	var arr: Array = col_dupes.get(id, [])
	if idx < arr.size():
		arr[idx] = int(arr[idx]) + 1

func _dupe_count(id: String, idx: int) -> int:
	var arr: Array = col_dupes.get(id, [])
	return int(arr[idx]) if idx < arr.size() else 0

func _set_dupe_total(c: Dictionary) -> int:
	var n := 0
	for v in col_dupes.get(c["id"], []):
		n += int(v)
	return n

# Every spare card held, flattened into rows the convert screen can list:
# {set, idx, emoji, name, stars, count}. Rarest first, because that is the
# order the player cares about them in.
func _all_dupes() -> Array:
	var rows := []
	for c in CV.COLLECTIONS:
		var items: Array = c["items"]
		for i in items.size():
			var n := _dupe_count(c["id"], i)
			if n <= 0:
				continue
			rows.append({
				"set": c, "idx": i, "emoji": items[i][0], "name": items[i][1],
				"stars": int(items[i][2]), "count": n,
			})
	rows.sort_custom(func(a, b) -> bool:
		if int(a["stars"]) != int(b["stars"]):
			return int(a["stars"]) > int(b["stars"])
		return int(a["count"]) > int(b["count"]))
	return rows

# What melting the whole pile down would pay: each spare is worth its own
# rarity, exactly as the card was worth when it was new.
func _dupe_star_value() -> int:
	var total := 0
	for row in _all_dupes():
		total += int(row["stars"]) * int(row["count"])
	return total

func _dupe_card_count() -> int:
	var total := 0
	for row in _all_dupes():
		total += int(row["count"])
	return total

func _collection_complete(c: Dictionary) -> bool:
	var owned: Array = col_owned.get(c["id"], [])
	if owned.is_empty():
		return false
	for v in owned:
		if not v:
			return false
	return true

func _maybe_drop_card() -> void:
	if randf() >= CV.CARD_DROP_CHANCE:
		return
	var chosen: Dictionary = CV.COLLECTIONS[0]
	var total_w := 0
	for c in CV.COLLECTIONS:
		total_w += int(c["weight"])
	var roll := randi_range(1, total_w)
	for c in CV.COLLECTIONS:
		roll -= int(c["weight"])
		if roll <= 0:
			chosen = c
			break
	# item roll is weighted by star rarity — high-star cards must stay rare
	# so a season genuinely takes weeks, not minutes
	var items: Array = chosen["items"]
	var total_iw := 0
	for item in items:
		total_iw += int(CV.DROP_STAR_WEIGHTS[int(item[2]) - 1])
	var iroll := randi_range(1, total_iw)
	var idx := 0
	for i in items.size():
		iroll -= int(CV.DROP_STAR_WEIGHTS[int(items[i][2]) - 1])
		if iroll <= 0:
			idx = i
			break
	var it: Array = items[idx]
	var owned: Array = col_owned[chosen["id"]]
	if owned[idx]:
		# A spare, not a dead draw. It goes on the pile the boxes are opened
		# with, and the count is said out loud so the pile is visible from the
		# moment it starts growing.
		_add_dupe(chosen["id"], idx)
		var dup_refund := _scaled(150)
		coins += dup_refund
		Sfx.play("pop", -6.0)
		_banner("Spare card:  %s  x%d" % [it[1], _dupe_count(chosen["id"], idx)],
			Color(0.75, 0.78, 0.9), it[0])
	else:
		owned[idx] = true
		Sfx.play("levelup", -8.0)
		_award_stars(int(it[2]))
		if _collection_complete(chosen) and not col_claimed.get(chosen["id"], false):
			_banner("%s complete!  Claim your reward in Collections" % chosen["name"], Color(1.0, 0.85, 0.3), chosen["icon"])
		else:
			_banner("New card:  %s  (%s)" % [it[1], chosen["name"]], Color(0.78, 0.62, 1.0), it[0])
	_mission_add("cards")
	_update_badges()

func _diff_chip(diff: String) -> Control:
	var colors := {"Easy": Lagoon.KELP, "Medium": Lagoon.BRASS, "Hard": Lagoon.REEF}
	return Lagoon.chip(diff, colors.get(diff, Lagoon.INK_SOFT), UI.F_CAPTION)

# `big` is the set's own page, where a card gets a third of the width instead
# of a fifth and can afford to be looked at rather than counted.
func _collection_item_card(emoji: String, iname: String, owned: bool, rarity := 0, big := false, spare := 0) -> Control:
	# Owned cards are brass-rimmed glass; unowned ones are the same glass with
	# the metal drained out of them, so a set reads as "partly collected" at a
	# glance rather than as two unrelated card designs.
	var p := PanelContainer.new()
	var sb := Lagoon.glass(Lagoon.R_CHIP + 2, 0.92 if owned else 0.55)
	sb.set_border_width_all(3 if owned else 2)
	sb.border_color = Lagoon.BRASS if owned else Color(Lagoon.INK_FAINT.r, Lagoon.INK_FAINT.g, Lagoon.INK_FAINT.b, 0.35)
	sb.shadow_size = 8 if owned else 3
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(0, 196) if big else Vector2(120, 150)
	if big:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	var e := _emoji_label(emoji, 58 if big else 40)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.modulate = Color(1, 1, 1, 1.0) if owned else Color(0.55, 0.65, 0.68, 0.45)
	col.add_child(e)
	var n := Lagoon.label(iname if owned else "???", UI.F_CAPTION if big else UI.F_TINY,
		Lagoon.INK if owned else Lagoon.INK_FAINT, owned)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	col.add_child(n)
	if rarity > 0:
		var sr := _star_row(rarity, UI.F_CAPTION if big else UI.F_TINY)
		sr.modulate = Color(1, 1, 1, 1.0) if owned else Color(1, 1, 1, 0.4)
		col.add_child(sr)
	# Spares sit on the corner of the card they are spares of, in the same
	# purple the melt buttons use, so "I have four of these" is answered where
	# the player is already looking rather than only on the boxes screen.
	if spare > 0:
		var tag := Lagoon.chip("x%d" % (spare + 1), Lagoon.URCHIN, UI.F_TINY)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tag)
		tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		tag.offset_left = -60.0
		tag.offset_right = -4.0
		tag.offset_top = -8.0
		tag.offset_bottom = 26.0
	return p

func _collection_by_id(id: String) -> Dictionary:
	for c in CV.COLLECTIONS:
		if c["id"] == id:
			return c
	return {}

func _collection_owned_count(c: Dictionary) -> int:
	var n := 0
	for v in col_owned.get(c["id"], []):
		if v:
			n += 1
	return n

# Two screens, one nav tab. col_open decides which.
func _fill_collections(vb: VBoxContainer) -> void:
	var open_set := _collection_by_id(col_open)
	if open_set.is_empty():
		col_open = ""
	if col_open.is_empty():
		_fill_collection_shelf(vb)
	else:
		_fill_collection_detail(vb, open_set)

# =============================================================================
#  The shelf
# =============================================================================
#
# Six sets, three across. Every set used to unroll its whole card grid on one
# page, which meant a screen and a half of scrolling before you could see
# whether the set below was worth chasing. A tile only has to answer three
# questions -- what is it, how far in am I, is there a reward waiting -- and
# all six fit above the fold.

func _fill_collection_shelf(vb: VBoxContainer) -> void:
	var head := _page_card(vb)
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 12)
	head.add_child(trow)
	trow.add_child(_emoji_label("🏆", 36))
	trow.add_child(Lagoon.label("GRAND  PRIZE", UI.F_SUBHEAD, Lagoon.INK, true))
	var claimed_n := 0
	for c in CV.COLLECTIONS:
		if col_claimed.get(c["id"], false):
			claimed_n += 1
	var gsub := _popup_row_label("Complete all %d collections:  +%s spins" % [CV.COLLECTIONS.size(), _fmt(CV.COLLECTION_MEGA_SPINS)], UI.F_CAPTION)
	gsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(gsub)
	var gpb := _styled_progress(Lagoon.BRASS)
	gpb.max_value = CV.COLLECTIONS.size()
	gpb.value = claimed_n
	head.add_child(gpb)
	var days_left := maxf(0.0, col_deadline - _now())
	var season := _popup_row_label("Season ends in %dd %dh \u2014 collections reset!" % [int(days_left / 86400.0), int(fmod(days_left, 86400.0) / 3600.0)], UI.F_TINY)
	season.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	season.add_theme_color_override("font_color", Lagoon.INK_FAINT)
	head.add_child(season)
	if col_mega_claimed:
		var done := _popup_row_label("CLAIMED  \u2713", UI.F_LABEL)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.add_theme_color_override("font_color", Lagoon.KELP_LO)
		head.add_child(done)
	elif claimed_n == CV.COLLECTIONS.size():
		var mega := Button.new()
		mega.text = "CLAIM  GRAND  PRIZE!"
		mega.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
		_candy_button(mega, Color(0.45, 0.75, 0.35))
		FX.press_feedback(mega)
		FX.pulse_forever(mega, 1.04, 1.0)
		mega.pressed.connect(_claim_mega)
		head.add_child(mega)

	var spare_all := _dupe_card_count()
	if spare_all > 0:
		vb.add_child(_page_note("Every spin has a chance to drop a card.  You have %d spares — melt them into \u2605 and open boxes." % spare_all, UI.F_CAPTION))
	else:
		vb.add_child(_page_note("Every spin has a chance to drop a card, and every new one is worth \u2605 stars!", UI.F_CAPTION))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for c in CV.COLLECTIONS:
		grid.add_child(_collection_tile(c))

	# The BOXES button floats over the bottom-right of this page, which would
	# otherwise park it permanently on top of the last tile in the grid. A tail
	# of empty space lets that tile scroll out from under it.
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 110)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tail)

func _collection_tile(c: Dictionary) -> Control:
	var id: String = c["id"]
	var items: Array = c["items"]
	var owned_n := _collection_owned_count(c)
	var claimed: bool = col_claimed.get(id, false)
	var ready: bool = owned_n == items.size() and not claimed

	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = Vector2(0, 250)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A tile is a card, not a candy button: same sea glass as everything else,
	# with the brass rim reserved for a set that has something to give you.
	var sb := Lagoon.glass(24, 0.94)
	sb.set_border_width_all(4)
	sb.border_color = Lagoon.CORAL if ready else (Lagoon.KELP if claimed else Lagoon.BRASS_MID)
	sb.shadow_size = 12
	sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.30)
	sb.shadow_offset = Vector2(0, 5)
	for state in ["normal", "hover", "focus"]:
		tile.add_theme_stylebox_override(state, sb)
	var down := sb.duplicate()
	down.bg_color = down.bg_color.darkened(0.06)
	tile.add_theme_stylebox_override("pressed", down)
	FX.press_feedback(tile)
	tile.pressed.connect(func() -> void:
		col_open = id
		_fill_page("collections")
	)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 10)
	tile.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	# the set's emblem, sunk into a pool of its own water
	var well := PanelContainer.new()
	var wsb := Lagoon.glass_well(18)
	wsb.bg_color = Color(Lagoon.LAGOON_DEEP.r, Lagoon.LAGOON_DEEP.g, Lagoon.LAGOON_DEEP.b, 0.16)
	well.add_theme_stylebox_override("panel", wsb)
	well.custom_minimum_size = Vector2(0, 98)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(well)
	var em := _emoji_label(c["icon"], 56)
	em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	well.add_child(em)

	var nm := Lagoon.label(c["name"], UI.F_CAPTION, Lagoon.INK, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(0, 62)
	col.add_child(nm)

	var pb := _styled_progress(Lagoon.KELP if owned_n == items.size() else Lagoon.LAGOON)
	pb.custom_minimum_size = Vector2(0, 18)
	pb.max_value = items.size()
	pb.value = owned_n
	col.add_child(pb)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	var cnt := Lagoon.label("%d/%d" % [owned_n, items.size()], UI.F_TINY, Lagoon.INK_SOFT, true)
	cnt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(cnt)
	var spare_n := _set_dupe_total(c)
	if spare_n > 0:
		foot.add_child(Lagoon.chip("+%d" % spare_n, Lagoon.URCHIN, UI.F_TINY))
	foot.add_child(_diff_chip(c["diff"]))

	# One badge in the corner, and only when the tile has news: a reward waiting
	# to be taken, or a set already banked.
	if ready or claimed:
		var flag := Lagoon.chip("CLAIM!" if ready else "\u2713", Lagoon.CORAL if ready else Lagoon.KELP, UI.F_TINY)
		flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(flag)
		flag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		flag.offset_left = -78.0 if ready else -46.0
		flag.offset_right = -6.0
		flag.offset_top = -10.0
		flag.offset_bottom = 26.0
	if ready:
		FX.pulse_forever(tile, 1.03, 1.0)
	return tile

# =============================================================================
#  One set
# =============================================================================

func _fill_collection_detail(vb: VBoxContainer, c: Dictionary) -> void:
	var id: String = c["id"]
	var items: Array = c["items"]
	var owned: Array = col_owned.get(id, [])
	var owned_n := _collection_owned_count(c)
	var claimed: bool = col_claimed.get(id, false)

	var head := _page_card(vb)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 14)
	head.add_child(hrow)
	var badge := PanelContainer.new()
	var bsb := Lagoon.glass_well(20)
	bsb.bg_color = Color(Lagoon.LAGOON_DEEP.r, Lagoon.LAGOON_DEEP.g, Lagoon.LAGOON_DEEP.b, 0.16)
	badge.add_theme_stylebox_override("panel", bsb)
	badge.custom_minimum_size = Vector2(104, 104)
	hrow.add_child(badge)
	var bem := _emoji_label(c["icon"], 62)
	bem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bem)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(info)
	info.add_child(_popup_row_label(c["name"], UI.F_SUBHEAD))
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 10)
	info.add_child(meta)
	meta.add_child(_diff_chip(c["diff"]))
	meta.add_child(_reward_chip("🌀", "+%s  spins" % _fmt(int(c["reward_spins"])), Lagoon.LAGOON_DEEP))

	var spare_n := _set_dupe_total(c)
	if spare_n > 0:
		meta.add_child(Lagoon.chip("%d SPARE" % spare_n, Lagoon.URCHIN, UI.F_TINY))

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 12)
	head.add_child(prow)
	var pb := _styled_progress(Lagoon.KELP if owned_n == items.size() else Lagoon.LAGOON)
	pb.max_value = items.size()
	pb.value = owned_n
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(pb)
	prow.add_child(_popup_row_label("%d/%d  cards" % [owned_n, items.size()], UI.F_CAPTION))

	if claimed:
		var tag := _popup_row_label("REWARD  CLAIMED  \u2713", UI.F_LABEL)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_color_override("font_color", Lagoon.KELP_LO)
		head.add_child(tag)
	elif owned_n == items.size():
		var claim := Button.new()
		claim.text = "CLAIM  +%s  SPINS" % _fmt(int(c["reward_spins"]))
		claim.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
		_candy_button(claim, Color(0.45, 0.75, 0.35))
		FX.press_feedback(claim)
		FX.pulse_forever(claim, 1.04, 0.9)
		claim.pressed.connect(_claim_collection.bind(c))
		head.add_child(claim)
	else:
		var left := _popup_row_label("%d more to go" % (items.size() - owned_n), UI.F_CAPTION)
		left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_theme_color_override("font_color", Lagoon.INK_SOFT)
		head.add_child(left)

	var card := _page_card(vb)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	card.add_child(grid)
	for i in items.size():
		var it: Array = items[i]
		grid.add_child(_collection_item_card(it[0], it[1], i < owned.size() and owned[i],
			int(it[2]), true, _dupe_count(id, i)))

# =============================================================================
#  Card Boxes
# =============================================================================
#
# Where spare cards go to be useful. Duplicates are unavoidable in any set
# collection -- the odds that make a Hard set take a month are the same odds
# that hand you a fourth Seashell -- so the question was never how to stop them
# but what they should be worth. They melt down for exactly the stars the card
# was worth new, and stars open boxes that draw more cards. A spare is the long
# way round to the card you actually wanted, which is the point.
#
# What is spent here is the wallet, never the standing. Rank counts what you
# have earned, so a box costs you nothing you have already climbed -- the top
# bar does not move when you open one. This screen is therefore the only place
# in the game that shows the spendable balance, and it says which is which.

func _melt_stack(set_id: String, idx: int, count: int) -> int:
	var arr: Array = col_dupes.get(set_id, [])
	if idx >= arr.size():
		return 0
	var take := mini(count, int(arr[idx]))
	if take <= 0:
		return 0
	arr[idx] = int(arr[idx]) - take
	var c := _collection_by_id(set_id)
	var worth := take * int((c["items"] as Array)[idx][2])
	# Wallet only -- deliberately not `_earn_stars`. Rank already paid out for
	# this card the first time it was owned, and melting the spares of a card
	# you own would otherwise let one lucky set be farmed into a standing.
	stars += worth
	return worth

func _melt_and_refresh(gained: int, at: Vector2) -> void:
	if gained <= 0:
		return
	Sfx.play("coins", -6.0)
	FX.rise_label(self, at, "+%d \u2605" % gained, CV.STAR_COLORS[CV.MAX_STAR - 1], 40)
	# To the bank on this page, not to the top bar. The capsule up there is the
	# rank, and melting does not move it -- stars flying into a number that
	# stays put is the animation telling a lie about the rules.
	if _star_bank_label != null and is_instance_valid(_star_bank_label):
		FX.fly_coins(self, at, _star_bank_label.global_position + _star_bank_label.size * 0.5,
			clampi(gained, 4, 12), "star", "\u2b50")
	_update_badges()
	_refresh()
	_save_game()
	_fill_page("boxes")

func _fill_boxes(vb: VBoxContainer) -> void:
	var rows := _all_dupes()
	var pool := _dupe_star_value()

	# --- the bank -----------------------------------------------------------
	var bank := _page_card(vb)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 12)
	bank.add_child(brow)
	var big_star := Glyph.new()
	big_star.kind = "star"
	big_star.custom_minimum_size = Vector2(64, 64)
	big_star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(big_star)
	var amount := Lagoon.label(_fmt(stars), UI.F_DISPLAY, Lagoon.INK, true)
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brow.add_child(amount)
	_star_bank_label = amount
	# Two glyphs on purpose: \u2b50 for the standing, matching the top bar, and
	# the plain \u2605 everywhere else on this page for the balance and the
	# prices. One sentence has to hold both numbers without them reading as the
	# same number twice.
	var bsub := _popup_row_label("Stars to spend. Your ⭐ %s world rank is what you have earned — opening a box never takes from it." % _fmt_compact(rank_stars), UI.F_CAPTION)
	bsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bsub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bsub.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	bank.add_child(bsub)

	# --- the spares ---------------------------------------------------------
	_shop_section(vb, "", "YOUR  SPARE  CARDS")
	if rows.is_empty():
		var none := _page_card(vb)
		var nl := _popup_row_label("No spares yet. Pull a card you already own — on a spin or out of a chest — and it lands here instead of going to waste.", UI.F_CAPTION)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.add_theme_color_override("font_color", Lagoon.INK_SOFT)
		none.add_child(nl)
	else:
		var head := _page_card(vb)
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 10)
		head.add_child(hrow)
		var count_l := Lagoon.label("%d spare cards" % _dupe_card_count(), UI.F_LABEL, Lagoon.INK, true)
		count_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hrow.add_child(count_l)
		hrow.add_child(Lagoon.chip("\u2605 %d" % pool, CV.STAR_COLORS[CV.MAX_STAR - 1], UI.F_CAPTION))
		var melt_all := Button.new()
		melt_all.text = "MELT  EVERYTHING   +%d \u2605" % pool
		melt_all.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
		_candy_button(melt_all, Color(0.72, 0.5, 0.95))
		FX.press_feedback(melt_all)
		melt_all.pressed.connect(func() -> void:
			var gained := 0
			for r in _all_dupes():
				gained += _melt_stack((r["set"] as Dictionary)["id"], int(r["idx"]), int(r["count"]))
			_melt_and_refresh(gained, Vector2(view_size().x * 0.5, view_size().y * 0.42))
		)
		head.add_child(melt_all)

		for r in rows:
			_dupe_row(vb, r)

	# --- the boxes ----------------------------------------------------------
	_shop_section(vb, "", "BOXES")
	vb.add_child(_page_note("Every box draws real cards — the pricier the box, the better the star odds.", UI.F_CAPTION))
	for box in CV.CARD_BOXES:
		_box_card(vb, box)

func _dupe_row(vb: VBoxContainer, r: Dictionary) -> void:
	var set_d: Dictionary = r["set"]
	var idx: int = int(r["idx"])
	var star: int = int(r["stars"])
	var count: int = int(r["count"])
	var sc: Color = CV.STAR_COLORS[star - 1]

	var panel := _tinted_card(vb, sc, star >= 4)
	var pad := MarginContainer.new()
	for m in [["margin_left", 12], ["margin_right", 12], ["margin_top", 10], ["margin_bottom", 10]]:
		pad.add_theme_constant_override(m[0], m[1])
	panel.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var tok := Lagoon.token(str(r["emoji"]), 74.0, sc)
	tok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tok)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	col.add_child(Lagoon.label(str(r["name"]), UI.F_LABEL, Lagoon.INK, true))
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	col.add_child(meta)
	meta.add_child(_star_row(star, UI.F_TINY))
	var setl := Lagoon.label(str(set_d["name"]), UI.F_TINY, Lagoon.INK_FAINT)
	setl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta.add_child(setl)

	var held := Lagoon.label("x%d" % count, UI.F_SUBHEAD, Lagoon.INK, true)
	held.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(held)

	var melt := Button.new()
	melt.text = "+%d \u2605" % (star * count)
	melt.custom_minimum_size = Vector2(150, UI.TAP)
	melt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_candy_button(melt, Color(0.72, 0.5, 0.95))
	FX.press_feedback(melt)
	melt.pressed.connect(func() -> void:
		var gained := _melt_stack(str(set_d["id"]), idx, count)
		_melt_and_refresh(gained, melt.global_position + melt.size * 0.5)
	)
	row.add_child(melt)

func _box_card(vb: VBoxContainer, box: Dictionary) -> void:
	var cost: int = int(box["stars"])
	var cc: Color = box["color"]
	var affordable := stars >= cost

	var panel := _tinted_card(vb, cc, bool(box.get("guarantee5", false)))
	var pad := MarginContainer.new()
	for m in [["margin_left", 14], ["margin_right", 14], ["margin_top", 12], ["margin_bottom", 12]]:
		pad.add_theme_constant_override(m[0], m[1])
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)

	var well := PanelContainer.new()
	var wsb := Lagoon.glass_well(18)
	wsb.bg_color = Color(cc.r, cc.g, cc.b, 0.14)
	well.add_theme_stylebox_override("panel", wsb)
	well.custom_minimum_size = Vector2(124, 116)
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(well)
	var art := _chest_art(box, 58)
	art.custom_minimum_size = Vector2(104, 96)
	well.add_child(art)
	# A box you cannot open yet is drained rather than hidden -- the reason to
	# keep melting spares has to stay on screen.
	if not affordable:
		art.modulate = Color(0.65, 0.7, 0.72, 0.55)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	info.add_child(Lagoon.label(str(box["name"]), UI.F_SUBHEAD, Lagoon.INK, true))
	var sub := Lagoon.label(str(box["sub"]), UI.F_CAPTION, Lagoon.INK_SOFT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sub)
	# A box row is full width, so it can carry the whole table on one line and
	# skip the dialog the paid chests need. Stars are earned rather than sold,
	# so this is honesty rather than Guideline 3.1.1 -- but it is the same
	# table, and a box that hid it while the chest published it would read as
	# the free currency being the rigged one.
	var box_odds := Lagoon.label(_odds_strip(box), UI.F_TINY, Lagoon.INK_FAINT)
	box_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(box_odds)
	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 6)
	info.add_child(price)
	price.add_child(Lagoon.chip("\u2605  %d" % cost, cc, UI.F_CAPTION))
	if not affordable:
		var short := Lagoon.label("%d more to go" % (cost - stars), UI.F_TINY, Lagoon.INK_FAINT)
		short.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price.add_child(short)

	# How close you are, so a box you cannot afford still tells you something.
	if not affordable:
		var pb := _styled_progress(cc)
		pb.max_value = cost
		pb.value = stars
		col.add_child(pb)

	var open := Button.new()
	open.text = "OPEN  BOX" if affordable else "NOT  ENOUGH  STARS"
	open.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	open.disabled = not affordable
	_candy_button(open, Color(0.45, 0.75, 0.35) if affordable else Color(0.6, 0.62, 0.68))
	FX.press_feedback(open)
	if affordable:
		open.pressed.connect(_open_card_box.bind(box))
	col.add_child(open)

func _open_card_box(box: Dictionary) -> void:
	var cost: int = int(box["stars"])
	if stars < cost:
		Sfx.play("error", -6.0)
		return
	stars -= cost

	var pre_complete := {}
	for c in CV.COLLECTIONS:
		pre_complete[c["id"]] = _collection_complete(c)
	var before := stars
	var cards := []
	for i in int(box.get("cards", 0)):
		var forced := CV.MAX_STAR if box.get("guarantee5", false) and i == 0 else 0
		cards.append(_grant_chest_card(int(box.get("tier", 0)), forced))
	var completed := []
	for c in CV.COLLECTIONS:
		if not pre_complete[c["id"]] and _collection_complete(c) and not col_claimed.get(c["id"], false):
			completed.append(c["name"])

	Sfx.play("jackpot", -3.0)
	FX.confetti(self, 40)
	FX.flash(self)
	# New cards pay stars back on the way out, so a good box partly refunds
	# itself. The standing it also bought is said separately, on the result
	# screen, because that half is never spent and should not read as change.
	var earned := stars - before
	var note := "\u2605 %d spent" % cost
	if earned > 0:
		note += "   \u2022   +%d \u2605 back from new cards" % earned
	_show_chest_result(cards, "%s Opened!" % str(box["name"]), note, completed)
	_update_badges()
	_refresh()
	_save_game()
	_fill_page("boxes")

func _claim_collection(c: Dictionary) -> void:
	var id: String = c["id"]
	if col_claimed.get(id, false) or not _collection_complete(c):
		return
	col_claimed[id] = true
	var won := int(c["reward_spins"])
	spins += won
	# A finished set is worth stars as well as spins: the spins send you back to
	# the reels, the stars are what the month of collecting leaves behind. Five
	# a card, so a long Hard set is worth more than two short Easy ones.
	var star_bonus := 5 * (c["items"] as Array).size()
	Sfx.play("jackpot", -2.0)
	FX.confetti(self, 40)
	FX.flash(self)
	FX.fly_coins(self, Vector2(360, 640), _hud_labels[0]["spins"].global_position,
		clampi(won / 120, 6, 12), "bolt", "🌀")
	_award_stars(star_bonus, Vector2(360, 620))
	_banner("%s:  +%s spins  and  +%d \u2605" % [c["name"], _fmt(won), star_bonus], Color(0.6, 0.9, 1.0), c["icon"])
	_update_badges()
	_refresh()
	_save_game()
	_fill_page("collections")

func _claim_mega() -> void:
	if col_mega_claimed:
		return
	for c in CV.COLLECTIONS:
		if not col_claimed.get(c["id"], false):
			return
	col_mega_claimed = true
	spins += CV.COLLECTION_MEGA_SPINS
	_award_stars(250, Vector2(360, 600))
	Sfx.play("levelup", -2.0)
	FX.confetti(self, 80)
	FX.flash(self)
	FX.fly_coins(self, Vector2(360, 620), _hud_labels[0]["spins"].global_position,
		18, "bolt", "🌀")
	_banner("GRAND PRIZE!  +%s spins  and  +250 \u2605" % _fmt(CV.COLLECTION_MEGA_SPINS), Color(0.6, 0.9, 1.0), "🏆")
	_update_badges()
	_refresh()
	_save_game()
	_fill_page("collections")

# A rival's standing, on the same terms as the player's: what they have built
# on the island they hold, plus a full island's worth of stars for every one
# they got through to reach it.
func _npc_stars(npc: Dictionary) -> int:
	var total := 0
	for lv in npc.get("buildings", []):
		var n := clampi(int(lv), 0, CV.MAX_STAR)
		total += n * (n + 1) / 2
	return total + 75 * maxi(0, int(npc.get("island", 1)) - 1)

# The board used to rank on coins, which meant it reshuffled every spin and
# dropped you twenty places the moment you bought a hut -- a table where doing
# the right thing loses you rank is a table nobody reads twice. Then it ranked
# on the star balance, which had the same fault one layer down: opening a card
# box, the one thing stars are for, cost you places.
#
# So it ranks on `rank_stars`, which only ever goes up -- once for every hut
# level built, once for every card the first time it is owned, plus the set and
# grand-prize bonuses. Nothing in the game subtracts from it. The number in the
# top bar is this one, so what a player watches climb all day is the same
# number this table sorts on.
func _open_ranks() -> void:
	var vbox := _open_popup("Leaderboard")
	var head := _popup_row_label("Ranked by \u2b50 stars — build and collect to climb", UI.F_CAPTION)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(head)
	var rows := []
	rows.append({"name": profile.get("name", "You"), "emoji": "😎", "stars": rank_stars, "me": true})
	for n in npcs:
		rows.append({"name": n["name"], "emoji": n["emoji"], "stars": _npc_stars(n), "me": false})
	rows.sort_custom(func(a, b) -> bool: return int(a["stars"]) > int(b["stars"]))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vbox.add_child(row)
		var rank := _popup_row_label("#%d" % (i + 1), UI.F_LABEL)
		rank.custom_minimum_size = Vector2(50, 0)
		row.add_child(rank)
		row.add_child(_emoji_label(r["emoji"], UI.F_SUBHEAD))
		var name_l := _popup_row_label(r["name"])
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if r["me"]:
			name_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		row.add_child(name_l)
		var c := _popup_row_label("\u2605  %s" % _fmt_compact(int(r["stars"])))
		c.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.4) if r["me"] else CV.STAR_COLORS[CV.MAX_STAR - 1])
		row.add_child(c)

func _build_village_page() -> void:
	village_page = Control.new()
	add_child(village_page)
	village_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Sky, then the island, then the chrome. The island keeps the size it was
	# painted at and starts below the notch rather than stretching up into it,
	# so the strip left over at the top is filled with the art's own top edge
	# colour and reads as more of the same sky.
	_village_sky = ColorRect.new()
	_village_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	village_page.add_child(_village_sky)
	_village_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_village_stage = Control.new()
	_village_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	village_page.add_child(_village_stage)
	UI.make_design_stage(_village_stage, view_size(), safe_top(), nav_slab_top())

	_village_bg = _add_background(_village_stage, "village", Color(0.55, 0.8, 0.95), Color(0.45, 0.75, 0.5))

	# The island's name on a brass nameplate, the same object the menu pages and
	# the machine's marquee use -- so "where am I" is answered by one shape
	# everywhere it is asked.
	var name_plate := Lagoon.plaque("Island", 420.0, 76.0, UI.F_SUBHEAD)
	village_page.add_child(name_plate)
	name_plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	name_plate.offset_left = -210.0
	name_plate.offset_right = 210.0
	name_plate.offset_top = 100.0 + safe_top()
	name_plate.offset_bottom = 176.0 + safe_top()
	_island_title = name_plate.get_meta("label")

	village = VillageView.new()
	# The huts are painted onto the island art, so they live on the same stage
	# as it -- one transform for both, and no hut can drift off its patch of
	# grass no matter what shape the phone is.
	_village_stage.add_child(village)
	village.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	village.upgrade_requested.connect(_on_upgrade_requested)
	for slot_dict in village.get("_slots"):
		# Building is the whole point of this page, so its buttons are kelp
		# ("spend, and something good happens") rather than neutral glass --
		# and they grey out on their own when the island's coins run short.
		_candy_button(slot_dict["button"], Lagoon.KELP)

	_add_topbar(village_page)

func _add_background(page: Control, bg_id: String, top_color: Color, bottom_color: Color) -> TextureRect:
	var t := CV.bg_tex(bg_id)
	if t != null:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(tr)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return tr
	else:
		var bg := ColorRect.new()
		var shader := Lagoon.shader("""
shader_type canvas_item;
uniform vec3 top_col;
uniform vec3 bottom_col;
void fragment() {
	COLOR = vec4(mix(top_col, bottom_col, UV.y), 1.0);
}
""")
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("top_col", Vector3(top_color.r, top_color.g, top_color.b))
		mat.set_shader_parameter("bottom_col", Vector3(bottom_color.r, bottom_color.g, bottom_color.b))
		bg.material = mat
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return null

# The HUD is four brass-rimmed glass capsules rather than one dark strip. Each
# resource is its own object you can point at, coins and spins carry a coral
# "+" straight to the shop, and the island capsule makes progress a thing you
# hold alongside the currencies instead of a caption in the corner.
func _add_topbar(page: Control) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	page.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 14.0
	bar.offset_right = -14.0
	bar.offset_top = 16.0 + safe_top()
	bar.offset_bottom = 16.0 + 70.0 + safe_top()

	var labels := {}
	# Third field is the shelf the plus goes to; empty means the counter has no
	# plus at all, which is the shield's case -- shields are not sold.
	for spec in [["coin", "coins", "coins"], ["wheel", "spins", "spins"], ["shield", "shields", ""]]:
		var shelf: String = spec[2]
		var jump := Callable()
		if shelf != "":
			jump = func() -> void: _goto_shop(shelf)
		var cap := Lagoon.capsule(spec[0], "0", jump)
		bar.add_child(cap["root"])
		labels[spec[1]] = cap["value"]

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)

	# Stars ride on the right, next to the island number rather than in with the
	# spendables on the left. That grouping is the whole point: the left of this
	# bar is what you play with, the right is where you have got to.
	var st := Lagoon.capsule("star", "0")
	var st_root := st["root"] as Control
	st_root.tooltip_text = "Stars — your world rank. Earned by building and by every new card; never spent."
	bar.add_child(st_root)
	labels["stars"] = st["value"]
	# The number and the table it decides are the same fact, so the capsule is
	# the way to the leaderboard from every page. The Ranks button only ever
	# existed on the slot screen, which left the island and the collections --
	# the two places the number actually moves -- with no way to go and look.
	# A transparent hit area rather than a `plus_action`, because the coral "+"
	# means "buy more of this" and stars are not for sale.
	var st_tap := Button.new()
	st_tap.flat = true
	st_tap.focus_mode = Control.FOCUS_NONE
	st_tap.pressed.connect(_open_ranks)
	st_root.add_child(st_tap)
	st_tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# FX.press_feedback squashes the button it is given; here the button is the
	# invisible one, so the capsule under it is squashed instead.
	st_root.resized.connect(func() -> void: st_root.pivot_offset = st_root.size * 0.5)
	st_tap.button_down.connect(func() -> void:
		st_root.pivot_offset = st_root.size * 0.5
		st_root.create_tween().tween_property(st_root, "scale", Vector2(0.93, 0.93), 0.06)
	)
	st_tap.button_up.connect(func() -> void:
		st_root.create_tween().tween_property(st_root, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

	var isl := Lagoon.capsule("island", "1")
	bar.add_child(isl["root"])
	labels["island"] = isl["value"]

	_hud_labels.append(labels)

# --- slot logic ---

func _schedule_auto_spin(delay := 0.8) -> void:
	if not auto_spin:
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if not auto_spin or _current_page != slot_page or _raiding() or _popup != null or slot.is_spinning():
			return
		if spins < slot.bet:
			auto_spin = false
			slot.set_auto(false)
			_banner("Auto spin stopped — out of spins", Color(0.9, 0.55, 0.4))
			return
		_on_spin_requested()
	)

func _on_spin_requested() -> void:
	if slot.is_spinning() or _raiding():
		return
	# Every tap that cannot spin gets the offer, every time.
	#
	# It used to get it once every fifteen minutes and a red banner the rest of
	# the time, on the theory that a repeated interrupt trains players to dismiss
	# it. That theory is about interrupts the player did not ask for. This one is
	# a direct answer to a button they just pressed with intent, and the fourth
	# press is the one where the intent is strongest -- so the cooldown was the
	# store being unavailable precisely when it was wanted. Nothing here fires
	# unprompted: no tap, no popup. Auto-spin stops itself before it reaches this
	# branch, so a held spin button cannot machine-gun the modal either.
	if spins < slot.bet:
		Sfx.play("error", -6.0)
		if _popup != null:
			return
		# Ahead of the pack offer, and only ever once: an empty meter is the
		# moment the player most wants to be told when it fills, and the offer
		# will still be there on the very next tap.
		if spins <= 0 and Alerts.can_ask() and not notif_prompted and notif_enabled:
			_ask_for_alerts()
			return
		_offer_out_of_spins(slot.bet)
		return
	_last_bet = slot.bet
	spins -= _last_bet
	Sfx.play("pop", -8.0)
	_piggy_add(CV.PIGGY_PER_SPIN * _last_bet)
	_mission_add("spins")
	if _last_bet >= 2:
		_mission_add("big_bet")
	_refresh()
	slot.start_spin(_roll())

# The win read-out, on the reels.
#
# It used to be a bare number at font 50, floating at a hard-coded y, gone
# three quarters of a second after it arrived. That is fine for a jackpot --
# the confetti and the cabinet sign carry that one -- and useless for the 300
# coins an ordinary spin drops on the way past, which is most of what a player
# actually wins. Those went by too fast and too plain to register at all.
#
# So: a slug rimmed in the colour of whatever was won, dark enough to read
# against any island's art, sitting on the reels where the eye already is, with
# the figure counting up into place rather than arriving finished. Still under
# two seconds from pop to gone.
func _show_win(text: String, color := Color(1.0, 0.85, 0.3), icon_kind := "", count_to := 0) -> void:
	if slot_page == null or slot == null:
		return
	# Only ever one of these. Auto-spin can start the next spin while the last
	# win is still on screen, and two opaque slugs stacked on the same spot is
	# worse than no slug at all.
	if is_instance_valid(_win_slug):
		_win_slug.queue_free()
	var at := slot.reels_center()

	# A centring band the full width of the page: the pill sizes itself to its
	# contents -- and keeps re-sizing while the number counts -- so it has to
	# be centred by a container rather than by arithmetic done once.
	var root := CenterContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 100
	root.size = Vector2(view_size().x, 130.0)
	root.position = Vector2(0.0, at.y - 65.0)
	root.pivot_offset = Vector2(view_size().x * 0.5, 65.0)
	slot_page.add_child(root)
	_win_slug = root

	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.88)
	sb.set_corner_radius_all(36)
	sb.set_border_width_all(5)
	sb.border_color = color
	sb.shadow_size = 20
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	sb.content_margin_left = 26.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 10.0
	pill.add_theme_stylebox_override("panel", sb)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pill)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)

	var icon_t := CV.symbol_tex(icon_kind) if icon_kind != "" else null
	if icon_t != null:
		var ic := TextureRect.new()
		ic.texture = icon_t
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(66, 66)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)

	var l := Lagoon.title(text, UI.F_DISPLAY, color, Lagoon.ABYSS)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)

	root.scale = Vector2(0.4, 0.4)
	root.modulate.a = 0.0
	# The tween belongs to the slug, not to the page.
	#
	# Started on `self` it outlived the thing it was animating: auto-spin puts
	# the next win on screen while the last is still counting up, the line above
	# frees the old slug, and a tween owned by main.gd carried on driving it.
	# The count-up is a tween_method into a lambda holding the label, and a
	# Callable has no object for the engine to notice has gone -- so it kept
	# firing into a freed node, twenty thousand errors deep in a soak of three
	# thousand spins. Owned by `root`, the whole thing dies with it.
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.10)
	tw.parallel().tween_property(root, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if count_to > 0:
		var write := func(v: float) -> void:
			l.text = "+%s" % _fmt_compact(int(round(v)))
		tw.parallel().tween_method(write, float(count_to) * 0.15, float(count_to), 0.42) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# The hold is the whole point of the rewrite -- long enough to read the
	# number, short enough that the next spin is never waiting on it.
	tw.tween_interval(1.15)
	tw.tween_property(root, "position:y", root.position.y - 58.0, 0.46) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(root, "modulate:a", 0.0, 0.46)
	tw.tween_callback(root.queue_free)

# Raid loot arriving in the wallet. The island already showed the player the
# figure and multiplied it in front of them, so this is not another read-out --
# it is the coins physically getting to the counter they are added to, once the
# island has finished sliding out of the way.
func _land_loot(amount: int) -> void:
	if amount <= 0 or _hud_labels.is_empty():
		return
	var tw := create_tween()
	tw.tween_interval(0.38)
	tw.tween_callback(func() -> void:
		Sfx.play("coins", -5.0)
		FX.fly_coins(self, Vector2(view_size().x * 0.5, view_size().y * 0.42),
			_hud_labels[0]["coins"].global_position, clampi(amount / 400, 6, 12))
	)

func _roll() -> Array:
	if randf() < 0.3:
		var triple := _weighted_pick({"hammer": 25, "steal": 22, "coin": 14, "bag": 9, "gem": 12, "shield": 12, "bolt": 6})
		return [triple, triple, triple]
	return [CV.SYMBOLS.pick_random(), CV.SYMBOLS.pick_random(), CV.SYMBOLS.pick_random()]

func _weighted_pick(weights: Dictionary) -> String:
	var total := 0
	for w in weights.values():
		total += w
	var roll := randi_range(1, total)
	for key in weights:
		roll -= weights[key]
		if roll <= 0:
			return key
	return weights.keys()[0]

func _on_spin_finished(result: Array) -> void:
	if result.size() < 3:
		return
	var bet := _last_bet
	var gain := 0
	var triple: bool = result[0] == result[1] and result[1] == result[2]
	if triple:
		match result[0]:
			"coin":
				gain = 1000 * bet
				Sfx.play("jackpot", -4.0)
				_banner("Triple coins!", Color(1.0, 0.85, 0.3))
			"bag":
				gain = 3000 * bet
				Sfx.play("jackpot", -2.0)
				slot.announce("JACKPOT!", Lagoon.BRASS_HI)
				_banner("JACKPOT!", Color(1.0, 0.85, 0.3))
				FX.confetti(self, 44)
				FX.flash(self)
			"gem":
				gain = 2000 * bet
				Sfx.play("jackpot", -3.0)
				_banner("Triple gems!", Color(0.6, 0.85, 1.0))
				FX.confetti(self, 30)
			"hammer":
				_start_visit("attack")
			"steal":
				_start_visit("steal")
			"shield":
				slot.announce("SHIELD  UP!", Color(0.72, 0.88, 1.0))
				shields = mini(3, shields + bet)
				Sfx.play("shield", -6.0)
				_banner("Shield up!  (%d/3)" % shields, Color(0.5, 0.75, 1.0))
				_show_win("+SHIELD", Color(0.5, 0.75, 1.0), "shield")
			"bolt":
				slot.announce("+SPINS!", Color(0.72, 0.94, 1.0))
				var bonus := 12 * bet
				spins += bonus
				Sfx.play("jackpot", -4.0)
				_show_win("+%d  SPINS" % bonus, Color(0.6, 0.9, 1.0), "bolt")
	else:
		for s in result:
			match s:
				"coin": gain += 100 * bet
				"bag": gain += 400 * bet
				"gem": gain += 250 * bet
		if gain > 0:
			Sfx.play("coins", -6.0)
	# Reel prizes are written above at their island-1 price; the wallet gets the
	# island-scaled figure, and so does the coins_won mission (its target scales
	# with it, so the two stay in the same units).
	gain = _scaled(gain)
	if gain > 0:
		coins += gain
		_mission_add("coins_won", gain)
		_show_win("+%s" % _fmt_compact(gain), Color(1.0, 0.85, 0.3), "coin", gain)
		# The coins leave for the wallet only once the read-out has been read,
		# so the number and the coins that are it are not two events at once.
		var fly := create_tween()
		fly.tween_interval(1.25)
		fly.tween_callback(func() -> void:
			FX.fly_coins(self, slot.reels_center(), _hud_labels[0]["coins"].global_position,
				clampi(gain / 250, 4, 10))
		)
	# The card roll is not a raid concern and belongs outside the gate. It sat
	# inside it, and because an attack triple sets up its raid synchronously
	# while a steal triple did not, the two behaved differently: hammers
	# skipped the roll, raccoons got it. Hammers are 7.7% of all spins, so the
	# real drop rate was 23.07% against the 25% the Collections page states
	# for "every spin", and the shortfall fell entirely on one symbol.
	_maybe_drop_card()
	# These two do belong inside it. A counter-raid landing behind the island
	# overlay is invisible, and an auto-spin under it is a spin the player
	# pays for and never sees.
	if not _raiding():
		_maybe_revenge()
		_schedule_auto_spin()
	_refresh()
	_save_game()

# Raids that happen while the app is closed.
#
# The pool is not a set of dummies waiting to be robbed -- rivals come at you
# too, and the fact that they do while you are away is what makes a shield
# worth banking instead of spending. Kept deliberately light: one hit per
# ninety minutes offline, two at most, and an attack only ever knocks a star
# off a building that has one to spare. You never come back to rubble.
#
# WHY THIS IS ROLLED BEFORE THE ABSENCE RATHER THAN AFTER IT
#
# It used to be rolled on the way back: count the hours, throw the dice, apply
# the results. That cannot survive a notification. A backgrounded app does not
# run, so "Kai smashed your Choco Fountain" has to be handed to iOS complete,
# hours before the player reads it -- and if the game then rolls its own dice
# on the way back in, the phone and the island are two independent throws
# saying different things about the same afternoon.
#
# So the dice are thrown here, while the app is still awake, and what comes
# out is a plan: what happens, to whom, and when. The notification quotes it
# and _offline_raids applies it. One throw, one story.
const OFFLINE_RAID_GAP := 5400.0
const OFFLINE_RAID_MAX := 2

func _preroll_raids(from: float) -> void:
	pending_raids = []
	if npcs.is_empty() or _preview_island:
		return
	# Simulated against copies rather than against the live island: the second
	# raid has to see the shield the first one spent and the hut it knocked
	# down, or a pair of attacks can both promise a save the island can only
	# make once.
	var sim_shields := shields
	var sim_buildings := buildings.duplicate()
	var sim_coins := coins
	for i in OFFLINE_RAID_MAX:
		var npc: Dictionary = npcs.pick_random()
		var mode := "attack" if randf() < 0.45 else "steal"
		var ev := {
			"at": from + OFFLINE_RAID_GAP * float(i + 1),
			"npc": String(npc["name"]),
			"emoji": String(npc["emoji"]),
			"type": mode,
		}
		if sim_shields > 0:
			sim_shields -= 1
			ev["kind"] = "blocked"
			ev["text"] = "%s came for your island — your shield held" % npc["name"]
			pending_raids.append(ev)
			continue
		if mode == "attack":
			var standing := []
			for b in sim_buildings.size():
				if int(sim_buildings[b]) >= 2:
					standing.append(b)
			if not standing.is_empty():
				var hit: int = standing.pick_random()
				sim_buildings[hit] = int(sim_buildings[hit]) - 1
				var bname: String = CV.island_theme(island_level)["buildings"][hit]
				ev["kind"] = "smash"
				ev["building"] = hit
				ev["text"] = "%s smashed your %s — down to %d\u2b50" % [npc["name"], bname, sim_buildings[hit]]
				pending_raids.append(ev)
				continue
			# Nothing left standing to hit. Falls through to a robbery rather
			# than to nothing, exactly as the live raid does.
			mode = "steal"
			ev["type"] = "steal"
		var stolen: int = mini(_scaled(500), int(sim_coins * 0.08))
		sim_coins -= stolen
		ev["kind"] = "steal"
		ev["coins"] = stolen
		ev["text"] = "%s raided your vault — %s coins" % [npc["name"], _fmt_compact(stolen)]
		pending_raids.append(ev)

# Applies the pre-rolled raids that have come due, and reports them.
#
# Deferred, not skipped, while an overlay is up. A raid resolving behind the
# island-visit screen used to take two thousand coins and a hut out from under
# a player who was in the middle of taking somebody else's, with the toast
# landing on the same z-index as the overlay -- so the one message explaining
# where the coins went was the one message they could not see. The plan is in
# the save, so waiting a few seconds for the screen to clear costs nothing.
func _offline_raids() -> void:
	if pending_raids.is_empty() or _boot != null:
		return
	if _raiding() or _popup != null:
		return
	var now := _now()
	var events := []
	for ev in pending_raids:
		if typeof(ev) == TYPE_DICTIONARY and float(ev.get("at", 0.0)) <= now:
			events.append(ev)
	# Everything, due or not. The player is holding the phone again, so the
	# rest of the plan was written about an afternoon that is now over; the
	# next trip to the background writes a fresh one.
	pending_raids = []
	if events.is_empty():
		return
	for ev in events:
		match String(ev.get("kind", "")):
			"blocked":
				shields = maxi(0, shields - 1)
			"smash":
				var b := int(ev.get("building", -1))
				if b >= 0 and b < buildings.size():
					buildings[b] = maxi(0, int(buildings[b]) - 1)
			"steal":
				# Clamped against the live wallet. The figure was quoted
				# against the balance at bedtime, and a transaction Apple
				# delivered overnight can have moved it since.
				var take := mini(maxi(0, _i(ev.get("coins", 0))), coins)
				coins -= take
				# The rival is looked up by name rather than held by
				# reference: the pool is restocked between sessions, and a
				# rival who has rotated out simply keeps what they took.
				for n in npcs:
					if String(n.get("name", "")) == String(ev.get("npc", "")):
						n["coins"] = int(n["coins"]) + int(round(take / maxf(_economy_mult(), 1.0)))
						break
		_notify(String(ev.get("type", "steal")), String(ev.get("text", "")), String(ev.get("emoji", "🚨")), false)
	if events.size() == 1:
		_show_toast(String(events[0].get("text", "")), String(events[0].get("emoji", "🚨")))
	else:
		_show_toast("%d rivals hit your island while you were away" % events.size(), "🚨")
	_refresh()
	_save_game()

# --- what the phone says while the game is closed ---------------------------

# The whole plan, in game time, handed to Alerts on the way to the background.
#
# Every row is a promise about what the game will say when it is opened, so
# nothing goes in here that the game cannot honour. "Your spins are full" is
# scheduled off the same accumulator _process ticks and _credit_time_away
# banks; the raid rows quote text that is already sitting in the save waiting
# to be applied. If either of those drifts, the player taps a notification and
# finds it was not true, which is worse than never having been told.
func _alert_plan(from: float) -> Array:
	var out := []
	if not notif_enabled:
		return out
	if bool(notif_types.get("spins", true)) and spins < SPIN_CAP:
		out.append({
			"id": "spins_full", "at": _spins_full_at(from),
			"title": "Your spins are full 🌀",
			"body": "All %d back on the meter. The reels are waiting." % SPIN_CAP,
		})
	for i in pending_raids.size():
		var ev: Dictionary = pending_raids[i]
		var kind := String(ev.get("type", "steal"))
		if not bool(notif_types.get(kind, true)):
			continue
		out.append({
			"id": "raid_%d" % i, "at": float(ev.get("at", 0.0)),
			"title": "%s  %s" % [String(ev.get("emoji", "🚨")),
				"Your island is under attack!" if kind == "attack" else "Someone is in your vault!"],
			"body": String(ev.get("text", "")),
		})
	if bool(notif_types.get("gift", true)):
		out.append({
			"id": "free_gift", "at": shop_free_last + CV.SHOP_FREE_COOLDOWN,
			"title": "Your daily gift is ready 🎁",
			"body": "Coins, spins and a card, waiting in the shop.",
		})
	out.append_array(_event_alerts(from))
	return out

# Anything with a published end time.
#
# This is the seam. Today it is the timed offer and the card season; a cup, a
# weekend tournament or a live event is a row appended here and nothing else --
# no new save field, no new toggle, no change to the scheduler. Keep the id
# stable per event, because it is what iOS cancels and replaces by.
func _event_deadlines() -> Array:
	var out := []
	if offer_id != "" and offer_until > 0.0:
		out.append({"id": "offer", "ends": offer_until, "name": _active_offer_name(),
			"body": "Your limited offer is about to go. Last chance at this price."})
	if col_deadline > 0.0:
		out.append({"id": "season", "ends": col_deadline, "name": "The card season",
			"body": "One hour to finish a set before the season resets."})
	return out

# How long before an event ends the player gets told. An hour: long enough to
# come back and do something about it, short enough that the reminder is still
# about tonight.
const EVENT_WARNING := 3600.0

func _event_alerts(from: float) -> Array:
	var out := []
	if not bool(notif_types.get("events", true)):
		return out
	for d in _event_deadlines():
		out.append({
			"id": "event_%s" % String(d["id"]), "at": float(d["ends"]) - EVENT_WARNING,
			"title": "%s — one hour left ⏳" % String(d["name"]),
			"body": String(d["body"]),
		})
	return out

func _active_offer_name() -> String:
	var live := _active_offer()
	return String(live.get("name", "Your limited offer")) if not live.is_empty() else "Your limited offer"

# The one time the game asks for iOS's permission to reach the player's lock
# screen.
#
# iOS shows its prompt exactly once per install and a refusal can only be
# undone in the Settings app, so the ask is spent at the single moment it
# already means something to the player: the reels have stopped because the
# spins ran out, and the only thing they want to know is when they come back.
# Asked at launch instead -- before the game has given them any reason to say
# yes -- it is a box in the way of playing, and most people close it.
func _ask_for_alerts() -> void:
	notif_prompted = true
	_save_game()
	var vbox := _open_popup("Tell You When?")
	var e := _emoji_label("🔔", 68)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(e)
	var line := _popup_row_label("Your spins come back on their own. Want a nudge when the meter is full — and when a rival comes for your island?", UI.F_BODY)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(line)
	var yes := Button.new()
	yes.text = "Yes, tell me"
	yes.custom_minimum_size = Vector2(0, UI.TAP)
	_candy_button(yes, Color(0.28, 0.68, 0.34))
	FX.press_feedback(yes)
	yes.pressed.connect(func() -> void:
		_close_popup()
		Alerts.request_permission()
	)
	vbox.add_child(yes)
	var no := Button.new()
	no.text = "Not now"
	no.custom_minimum_size = Vector2(0, UI.TAP)
	_candy_button(no, Color(0.55, 0.45, 0.65))
	FX.press_feedback(no)
	no.pressed.connect(func() -> void: _close_popup())
	vbox.add_child(no)

func _maybe_revenge() -> void:
	if not revenge_pending:
		return
	revenge_pending = false
	if _last_raided.is_empty() and npcs.is_empty():
		return
	# Bots hit back, and the one with a reason to is the one you just robbed.
	var npc: Dictionary = _last_raided if not _last_raided.is_empty() else npcs.pick_random()
	var mode := "attack" if randf() < 0.5 else "steal"
	if shields > 0:
		shields -= 1
		Sfx.play("shield", -4.0)
		var verb := "attacked" if mode == "attack" else "tried to steal"
		var blocked_txt := "%s %s — blocked by your shield!" % [npc["name"], verb]
		if not _notify(mode, blocked_txt, npc["emoji"]):
			_banner(blocked_txt, Color(0.5, 0.75, 1.0), npc["emoji"])
	else:
		var stolen: int = mini(_scaled(500), int(coins * 0.1))
		coins -= stolen
		Sfx.play("attack", -4.0)
		FX.shake(slot_page, 10.0, 6)
		var hit_txt: String
		if mode == "attack":
			hit_txt = "%s raided your island!  -%s coins" % [npc["name"], _fmt_compact(stolen)]
		else:
			hit_txt = "%s stole %s coins from you!" % [npc["name"], _fmt_compact(stolen)]
		if not _notify(mode, hit_txt, npc["emoji"]):
			_banner(hit_txt, Color(0.95, 0.4, 0.4), npc["emoji"])

# --- rivals ---
#
# Until there are enough live players for a search to reliably find one, every
# rival is a bot: a pool of them is kept stocked, they hold islands near yours,
# and they hit back. The alternative -- matching a thin launch population
# against itself -- means the same handful of real players getting raided by
# each other all day, which is a worse first week for them than a world that
# looks busy from the start.

# Tops the pool back up to strength with rivals you have not met yet, and
# retires anyone there is nothing left to take: a flattened island with an
# empty vault is not an opponent, it is a chore.
func _stock_rivals() -> void:
	var keep := []
	for n in npcs:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var stars := 0
		for lv in n.get("buildings", []):
			stars += int(lv)
		if stars <= 0 and int(n.get("coins", 0)) < 400:
			continue
		keep.append(n)
	npcs = keep
	var taken := []
	for n in npcs:
		taken.append(n["name"])
	# Whoever is still on the wheel's card has to survive the sweep, or the
	# promise on the card outlives the rival it named.
	if not next_target.is_empty() and not taken.has(next_target.get("name", "")):
		# A COPY, with the server's id taken off it.
		#
		# Two separate bugs live in the obvious one-liner here. Dictionaries are
		# references, so appending next_target puts the very same object in the
		# pool -- and stripping anything from "the pool's copy" would strip it
		# from the rival currently promised on the wheel's card as well.
		#
		# And the id has to go. A rival fetched from the server is a real
		# islander; keeping their id in the local pool means they get saved into
		# this player's save file and drawn again, days later, by the local
		# picker -- and raided again, reported again, straight past the two
		# rules find_target enforces so that a rich island cannot be farmed
		# (not by the same player within a day, not by anyone within ten
		# minutes). What stays behind is a memory of them, not them.
		var keepsake := next_target.duplicate(true)
		keepsake.erase("cloud_id")
		npcs.append(keepsake)
		taken.append(String(keepsake["name"]))
	for fresh in CV.draw_rivals(CV.RIVAL_POOL - npcs.size(), island_level, taken):
		npcs.append(fresh)

# --- island visits (steal / attack) ---

# True from the moment a raid is announced until its payout lands -- the search
# screen counts, so nothing auto-spins or changes page underneath it.
func _raiding() -> bool:
	return _visit != null or _match != null or _raid_pending

# The card above the wheel is a promise: these are the coins at stake and this
# is whose they are. It is drawn before the spin and it does not move during
# one, so the raid can only ever land on the rival it named.
func _pick_next_target() -> void:
	# Whatever happens below, line up the one after this. Doing it here rather
	# than on a timer means the game only ever asks when it has just used one.
	_prefetch_rival()
	# A real islander if the server had one warm. It has been shaped into
	# exactly the dictionary the local pool produces, so nothing downstream --
	# the card, the search, the island, the payout -- can tell the difference,
	# and nothing downstream is allowed to.
	if not _server_rival.is_empty():
		next_target = _server_rival
		_server_rival = {}
		if slot != null:
			slot.set_target(next_target, _economy_mult())
		return
	if npcs.is_empty():
		_stock_rivals()
	if npcs.is_empty():
		return
	var last: String = next_target.get("name", "")
	for attempt in 6:
		next_target = npcs.pick_random()
		if next_target.get("name", "") != last:
			break
	if slot != null:
		slot.set_target(next_target, _economy_mult())

# Ask the server for somebody, and take whatever it gives -- which may be a
# person, may be one of the seeded bots, and never says which. That silence is
# deliberate on both sides; see the note on find_target in migration 0002.
func _prefetch_rival() -> void:
	if not Cloud.linked() or not _server_rival.is_empty():
		return
	Cloud.find_target("steal", func(row: Dictionary) -> void:
		if row.is_empty() or not is_instance_valid(self):
			return
		_server_rival = _rival_from_server(row)
	)

# The server's row, in the shape the rest of the game already speaks.
#
# The one real conversion is the vault. Every coin figure belonging to a rival
# is stored in island-1 units and multiplied by _economy_mult() where it is
# shown or paid out -- so handing the raw server figure straight through would
# have it scaled a second time and quote a vault worth hundreds of times what
# is in it. Dividing by the same multiplier first means what the player reads on
# the card is exactly the number the server is holding.
func _rival_from_server(row: Dictionary) -> Dictionary:
	var mult := maxf(0.001, _economy_mult())
	var b := []
	for v in row.get("buildings", []):
		b.append(clampi(int(v), 0, CV.MAX_STAR))
	while b.size() < 5:
		b.append(0)
	# The seeded bots wear BOT_DEFS faces, so their flag is already known here
	# -- it is simply not worth a column on the server. A real player has none.
	var flag := "🏝"
	for d in CV.BOT_DEFS:
		if String(d["name"]) == String(row.get("name", "")):
			flag = String(d.get("flag", "🏝"))
			break
	return {
		"name": str(row.get("name", "Islander")),
		"emoji": str(row.get("emoji", "🙂")),
		"flag": flag,
		"coins": maxi(0, int(round(float(row.get("coins", 0)) / mult))),
		"buildings": b,
		"shield": int(row.get("shields", 0)) > 0,
		"island": maxi(1, int(row.get("island_level", 1))),
		# What record_raid needs afterwards. Absent on a locally drawn rival,
		# which is exactly how the payout below knows not to report one.
		"cloud_id": str(row.get("id", "")),
	}

# The stake exactly as the chests will hold it, so the card, the search screen
# and the loot are three views of one number.
func _raid_stake(npc: Dictionary) -> int:
	return int(round(int(npc.get("coins", 0)) * _economy_mult())) * _last_bet

# Two raids, two ways in.
#
# A steal has a name on it before the reels even move -- it is on the card, in
# brass, with the vault underneath it, and the player has been staring at it
# all spin. Putting a search in front of that would be a machine pretending to
# look for something it is holding. So the raccoons go straight there.
#
# An attack has no name on it. Nothing on the SPIN page has promised you a
# victim, so the game genuinely has to go and find one, and the search is what
# that looks like.
func _start_visit(mode: String) -> void:
	# One raid at a time, checked before anything is built. A second triple
	# landing while the first raid is still assembling used to overwrite _visit
	# and orphan the overlay it replaced -- a full-screen input blocker with no
	# owner left to dismiss it.
	if _raiding():
		return
	if mode == "steal":
		if next_target.is_empty():
			_pick_next_target()
		if next_target.is_empty():
			return
		_raid_pending = true
		_raid_mult = _last_bet
		_raid_target = next_target
		_announce_raid(mode)
		var go := create_tween()
		go.tween_interval(0.5)
		go.tween_callback(_on_match_found.bind(next_target, mode))
		return

	var npc := _pick_attack_target()
	if npc.is_empty():
		return
	_raid_pending = true
	_raid_mult = _last_bet
	npc["shield"] = randf() < 0.3
	_raid_target = npc
	_announce_raid(mode)
	_match = Matchmaking.new()
	_match.npc = npc
	_match.mode = mode
	_match.stake = _raid_stake(npc)
	_match.stars = _rival_stars(npc)
	_match.z_index = 118
	_match.modulate.a = 0.0
	_match.finished.connect(_on_match_found.bind(mode))
	add_child(_match)
	_match.create_tween().tween_property(_match, "modulate:a", 1.0, 0.18).set_delay(0.35)

func _announce_raid(mode: String) -> void:
	Sfx.play("jackpot", -6.0)
	slot.announce("STEAL!" if mode == "steal" else "ATTACK!", Lagoon.CORAL_HI)
	_banner("Triple %s!" % ("raccoons — STEAL time!" if mode == "steal" else "hammers — ATTACK!"), Color(1.0, 0.85, 0.3))

# Whoever the hammers land on, it is not the rival the raccoons already have
# their mark on -- the two raids are meant to send you to two different
# islands, and the search has to have something to find.
#
# And it is somebody with a hut left standing. A rival whose island has been
# flattened -- by you, over several attacks -- still survives _stock_rivals as
# long as their vault holds 400 coins, because a purse is worth stealing. It is
# not worth *attacking*: the raid screen draws one target button per standing
# building, so an attack on an empty island came up with no buttons on it, no
# way out, and the game frozen behind a full-screen overlay until the app was
# killed. That is the one bug in here that costs a player their session.
#
# The filter is a preference rather than a rule: if literally nobody has a hut
# up, the caller still gets a rival and IslandVisit hands the raid back rather
# than parking on it.
func _pick_attack_target() -> Dictionary:
	if npcs.is_empty():
		_stock_rivals()
	var spared: String = next_target.get("name", "")
	var pool := []
	var any := []
	for n in npcs:
		if n.get("name", "") == spared:
			continue
		any.append(n)
		if _rival_stars(n) > 0:
			pool.append(n)
	if pool.is_empty():
		pool = any
	if pool.is_empty():
		for n in npcs:
			if _rival_stars(n) > 0:
				pool.append(n)
	if pool.is_empty():
		pool = npcs
	if pool.is_empty():
		return {}
	return pool.pick_random()

func _rival_stars(npc: Dictionary) -> int:
	var total := 0
	for lv in npc.get("buildings", []):
		total += int(lv)
	return total

# Tell the server a raid happened, if the rival came from there.
#
# Only the fact and the figure. The server does not open the victim's save and
# does not recompute the payout -- it clamps what is claimed to what the victim
# actually holds and writes an event, which the victim's own game applies under
# its own rules the next time it loads. That is the only place those rules
# exist, and it is also simply how this has to work: the victim is asleep with
# the app shut.
#
# A locally drawn rival has no cloud_id and nothing is reported, because there
# is nobody on the other end to have been robbed.
func _report_raid(npc: Dictionary, mode: String, result: Dictionary) -> void:
	var id := str(npc.get("cloud_id", ""))
	if id == "" or not Cloud.linked():
		return
	if mode == "steal":
		Cloud.record_raid(id, "steal", int(result.get("stolen", 0)))
		return
	# A shield turned it away, so nothing on the other island changed and there
	# is nothing for its owner to apply. Recording it would put an event in
	# their inbox that resolves to no change and no message.
	if bool(result.get("blocked", false)):
		return
	# island_visit calls the hut it hit "target"; the server calls it "hut".
	Cloud.record_raid(id, "attack", 0, int(result.get("target", -1)))

# The search hands back the rival it was given, and that is the island we sail
# to -- _raid_target, not next_target, which by now is free to move on.
func _on_match_found(matched: Dictionary, mode: String) -> void:
	var m := _match
	_match = null
	_raid_pending = false
	# Belt and braces behind the _raiding() guard in _start_visit: if an
	# overlay is somehow still standing, it goes now rather than being left
	# parented and unreferenced over the whole screen.
	if _visit != null:
		if _visit.finished.is_connected(_on_visit_finished):
			_visit.finished.disconnect(_on_visit_finished)
		_visit.queue_free()
		_visit = null
	_visit = IslandVisit.new()
	# Above the popup layer (120). The search screen already set 118 for
	# itself, but the island it hands over to was left at 0 -- so a modal the
	# player opened during the spin (Daily, Alerts: neither is disabled while
	# the reels run) stayed on top of the raid, and every chest and target
	# button underneath it was unreachable.
	_visit.z_index = 130
	_visit.npc = matched
	_visit.mode = mode
	_visit.mult = _raid_mult
	_visit.coin_mult = _economy_mult()
	# Rolled here, not on the island, so the island only ever *shows* a payout
	# it was handed -- same as the chests, which read the rival's own purse.
	_visit.attack_reward = _scaled(600 + randi_range(0, 300))
	_visit.finished.connect(_on_visit_finished)
	# The nav bar outranks the overlay on z, so the rival's island only has to
	# reach the same line ours does -- the slab hides everything under it.
	_visit.reach = nav_slab_top()
	add_child(_visit)
	_visit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visit.position = Vector2(view_size().x, 0)
	# A hand-off, not a cross-fade: the search screen leaves to the left as the
	# island it found arrives from the right, the same way pages move. Fading
	# one out over the other shows the island through the search card and the
	# two read as a glitch rather than a transition.
	_visit.create_tween().tween_property(_visit, "position", Vector2.ZERO, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if m != null:
		var mt := m.create_tween()
		mt.tween_property(m, "position", Vector2(-view_size().x, 0), 0.42) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		mt.tween_callback(m.queue_free)

func _on_visit_finished(result: Dictionary) -> void:
	# An overlay that is no longer the live one has nothing to pay out, and
	# reading .mult off a null _visit is how this used to abort mid-grant --
	# losing the loot and leaving the island stuck across the screen.
	if _visit == null:
		return
	var v := _visit
	var vmult: int = v.mult
	_visit = null
	var tw := create_tween()
	tw.tween_property(v, "position", Vector2(-view_size().x, 0), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(v.queue_free)
	var npc: Dictionary = result["npc"]
	_report_raid(npc, str(result["mode"]), result)
	_mission_add("steals" if result["mode"] == "steal" else "attacks")
	_piggy_add(CV.PIGGY_PER_RAID)
	_raid_target = {}
	_last_raided = npc
	# The island has already shown the player the figure and multiplied it in
	# front of them, so what comes back here is final. All that is left is to
	# put it in the wallet and say whose it was.
	if result["mode"] == "steal":
		var stolen: int = int(result.get("stolen", 0))
		coins += stolen
		# The rival's purse is stored at its island-1 price like every other
		# coin figure in the save, and what we just took is the island-scaled,
		# bet-multiplied version of it. It has to come back down to base units
		# before it is subtracted, or one raid at bet x3 drains a rival three
		# times as hard as it robbed them.
		var base_taken := int(round(float(result.get("base", stolen)) / maxf(0.001, _economy_mult())))
		npc["coins"] = maxi(200, int(npc["coins"]) - base_taken)
		if stolen > 0:
			_banner("You stole %s coins from %s!" % [_fmt_compact(stolen), npc["name"]], Color(1.0, 0.85, 0.3), npc["emoji"])
			_land_loot(stolen)
			if stolen > 2000:
				FX.confetti(self, 36)
		else:
			_banner("All chests were empty...", Color(0.8, 0.8, 0.8))
		if randf() < 0.3:
			revenge_pending = true
	else:
		if result.get("empty", false):
			# The island had nothing left to smash. Not a shield, and saying it
			# was one would credit a rival with a save they never made.
			_banner("%s has nothing left standing." % npc["name"], Color(0.8, 0.8, 0.8), npc["emoji"])
		elif result.get("blocked", false):
			_banner("%s's shield blocked your attack!" % npc["name"], Color(0.5, 0.75, 1.0), npc["emoji"])
		else:
			var reward := int(result.get("reward", _scaled(600 + randi_range(0, 300)) * vmult))
			coins += reward
			_banner("SMASH!  +%s coins" % _fmt_compact(reward), Color(1.0, 0.85, 0.3), npc["emoji"])
			_land_loot(reward)
		if randf() < 0.35:
			revenge_pending = true
	# The card only names the next rival once this one's result has been read.
	# Flipping it the instant the island slides away puts a new name under a
	# banner still crediting the old one, which is the exact confusion the
	# locked target exists to prevent.
	var pick := create_tween()
	pick.tween_interval(1.3)
	pick.tween_callback(func() -> void:
		if _raiding():
			return
		_stock_rivals()
		_pick_next_target()
		_save_game()
	)
	_refresh()
	_save_game()
	_schedule_auto_spin(1.4)

# --- village / island ---

func _apply_island_theme() -> void:
	village.set_island(island_level)
	var bg_t := CV.island_bg_tex(island_level)
	if _village_bg != null and bg_t != null:
		_village_bg.texture = bg_t
	if _village_sky != null:
		_village_sky.color = CV.bg_top_color(CV.bg_image(bg_t), Color(0.55, 0.8, 0.95))
	if _island_title != null:
		_island_title.text = CV.island_theme(island_level)["name"]
	for mat in _page_backdrops:
		Lagoon.tint_backdrop(mat, CV.island_palette(island_level))
	_apply_slot_theme()

# Repaints the SPIN page in the current island's palette: its artwork behind
# the glass, its light color in the rays and the halo, its trim on the logo,
# and the cabinet + hero button via SlotView.
func _apply_slot_theme() -> void:
	var p := CV.island_palette(island_level)
	var mid: Color = p["mid"]
	var glow: Color = p["glow"]

	if _slot_bg != null:
		var bg_t := CV.island_bg_tex(island_level)
		if bg_t != null:
			_slot_bg.texture = bg_t
	if _slot_bg_mat != null:
		# The island tints its own daylight. Blending toward the sky rather
		# than toward the island's "deep" tone is what keeps Volcano Isle and
		# Neon City bright instead of turning the page into a dark room again.
		_slot_bg_mat.set_shader_parameter("haze", _v3(Lagoon.SKY_HI.lerp(glow, 0.30).lerp(mid, 0.14)))
	if _slot_rays_mat != null:
		_slot_rays_mat.set_shader_parameter("ray_col", _v3(Color(1, 1, 1).lerp(glow, 0.55)))
	if _slot_floor_mat != null:
		_slot_floor_mat.set_shader_parameter("floor_col", _v3(Lagoon.LAGOON.lerp(mid, 0.28).lightened(0.42)))
	if _slot_glow_mat != null:
		_slot_glow_mat.set_shader_parameter("glow_col", _v3(glow))
	for d in _slot_decor:
		var node: CanvasItem = d["node"]
		if is_instance_valid(node):
			node.modulate = Color(Color(1, 1, 1).lerp(mid.lightened(0.45), 0.55), d["alpha"])
	if slot != null:
		slot.set_island(island_level)

static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

func _star_costs() -> Array:
	var mult := CV.curve(island_level)
	var out := []
	for c in STAR_COSTS:
		out.append(int(c * mult))
	return out

func _on_upgrade_requested(index: int) -> void:
	if village.is_constructing(index):
		return
	var level: int = buildings[index]
	if level >= CV.MAX_STAR:
		return
	var cost: int = _star_costs()[level]
	if coins < cost:
		Sfx.play("error", -6.0)
		if _popup == null:
			_offer_need_coins(cost - coins)
		return
	# The whole purchase is committed here, before the scaffold goes up: coins
	# out, level in, stars banked, mission ticked, save written.
	#
	# It used to pay the coins now and grant the hut two seconds later, from the
	# tween's callback. Two seconds is plenty of time for iOS to kill a
	# backgrounded app, and every one of those kills charged a player for a
	# building they did not get -- with the coins already saved and the upgrade
	# living only in a tween that no longer exists. What is on screen for those
	# two seconds is a construction animation, not the transaction.
	coins -= cost
	buildings[index] += 1
	# Worth the level it just reached, so upgrades get better the deeper you go
	# and a finished hut has paid out 15 over its life.
	var gained: int = buildings[index]
	_earn_stars(gained)
	_mission_add("builds")
	_update_badges()
	_save_game()
	# start_construction before the refresh, not after: it is what marks the
	# slot as under construction, and village.refresh skips those. The other way
	# round the hut snaps to its new size a frame before the scaffold goes up.
	village.start_construction(index, buildings[index], func() -> void:
		# Only the celebration is left: the stars flying to the counter they
		# were already added to, and the check for a finished island.
		var slot_rect: Rect2 = CV.SLOT_RECTS[index]
		_star_flight(gained, village.global_position + (slot_rect.position + slot_rect.size * 0.4) * village.scale)
		_check_island_complete()
		_refresh()
		_save_game()
	)
	_refresh()

func _check_island_complete() -> void:
	for b in buildings:
		if b < CV.MAX_STAR:
			return
	if _journey_layer != null:
		return
	if _popup != null and is_instance_valid(_popup) and _popup.has_meta("island_complete"):
		return
	_show_island_complete_popup()

const ISLAND_REWARD_COINS := 3000
const ISLAND_REWARD_SPINS := 20

# Celebration popup — the island only advances when the player presses
# the sail button, which launches the journey animation.
func _show_island_complete_popup() -> void:
	_close_popup(true)
	_popup = Control.new()
	_popup.set_meta("island_complete", true)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.z_index = 120
	add_child(_popup)
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_popup.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var sb := Lagoon.glass(Lagoon.R_PANEL, 0.96)
	sb.set_border_width_all(5)
	sb.border_color = Lagoon.BRASS
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
	Lagoon.add_gloss(panel, Lagoon.R_PANEL)
	FX.pop_in(panel, 0.34)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 26)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var trophy := _emoji_label("🏆", 84)
	trophy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(trophy)
	FX.pulse_forever(trophy, 1.12, 0.9)

	var title := Lagoon.title("ISLAND  COMPLETE!", UI.F_TITLE, Lagoon.SAND, Lagoon.BRASS_LO)
	vbox.add_child(title)

	var sub := _popup_row_label("%s is fully built — amazing job!" % CV.island_theme(island_level)["name"], UI.F_LABEL)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var reward := _popup_row_label("Journey rewards:  💰 +%s   🌀 +%d" % [_fmt_compact(_scaled(ISLAND_REWARD_COINS, island_level + 1)), ISLAND_REWARD_SPINS], UI.F_CAPTION)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_color_override("font_color", Lagoon.KELP_LO)
	vbox.add_child(reward)

	var next_name: String = CV.island_theme(island_level + 1)["name"]
	var sail := Button.new()
	sail.text = "⛵  SET SAIL TO %s" % next_name.to_upper()
	sail.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	sail.add_theme_font_size_override("font_size", UI.F_BODY)
	_candy_button(sail, Color(0.25, 0.6, 0.9))
	FX.press_feedback(sail)
	sail.pressed.connect(func() -> void:
		var from_level := island_level
		_close_popup(true)
		island_level = mini(MAX_ISLAND, island_level + 1)
		_rescale_coin_progress()
		_pick_next_target()
		_mission_add("islands")
		buildings = [0, 0, 0, 0, 0]
		coins += _scaled(ISLAND_REWARD_COINS)
		spins += ISLAND_REWARD_SPINS
		_save_game()
		_start_island_journey(from_level)
	)
	vbox.add_child(sail)

	var confetti_timer := Timer.new()
	confetti_timer.wait_time = 1.15
	confetti_timer.autostart = true
	_popup.add_child(confetti_timer)
	confetti_timer.timeout.connect(func() -> void: FX.confetti(self, 16))

	Sfx.play("levelup", -2.0)
	FX.confetti(self, 60)
	FX.flash(self)

# Framed snapshot of an island used on the journey map.
func _journey_island_card(world: Control, level: int, pos: Vector2, side: float) -> Control:
	var root := Control.new()
	root.position = pos
	world.add_child(root)

	var frame := PanelContainer.new()
	var sb := Lagoon.glass(26, 0.95)
	sb.set_border_width_all(6)
	sb.border_color = Lagoon.BRASS
	sb.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(side, side)
	root.add_child(frame)

	var clip := Control.new()
	clip.clip_contents = true
	frame.add_child(clip)
	var tr := TextureRect.new()
	tr.texture = CV.island_bg_tex(level)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	clip.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var nm := Lagoon.title(CV.island_theme(level)["name"], UI.F_BODY, Color.WHITE, Lagoon.ABYSS)
	nm.custom_minimum_size = Vector2(side, 0)
	nm.position = Vector2(0, side + 8)
	root.add_child(nm)
	return root

# Sea-voyage transition: the boat hops between waypoints while the
# camera pans from the finished island to the next one.
func _start_island_journey(from_level: int) -> void:
	var to_level := from_level + 1
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 130
	layer.modulate.a = 0.0
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_journey_layer = layer

	var sky := TextureRect.new()
	var sky_grad := Gradient.new()
	sky_grad.colors = PackedColorArray([Color(0.35, 0.65, 0.95), Color(0.82, 0.93, 1.0)])
	sky_grad.offsets = PackedFloat32Array([0.0, 1.0])
	var sky_tex := GradientTexture2D.new()
	sky_tex.gradient = sky_grad
	sky_tex.fill_from = Vector2(0, 0)
	sky_tex.fill_to = Vector2(0, 1)
	sky.texture = sky_tex
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var sea := TextureRect.new()
	var sea_grad := Gradient.new()
	sea_grad.colors = PackedColorArray([Color(0.16, 0.52, 0.76), Color(0.05, 0.28, 0.52)])
	sea_grad.offsets = PackedFloat32Array([0.0, 1.0])
	var sea_tex := GradientTexture2D.new()
	sea_tex.gradient = sea_grad
	sea_tex.fill_from = Vector2(0, 0)
	sea_tex.fill_to = Vector2(0, 1)
	sea.texture = sea_tex
	sea.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sea.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(sea)
	sea.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sea.offset_top = 560.0

	var sun := _emoji_label("☀️", 58)
	sun.position = Vector2(590, 80)
	layer.add_child(sun)
	FX.pulse_forever(sun, 1.08, 1.6)

	for i in 3:
		var cloud := _emoji_label("☁️", randi_range(42, 64))
		cloud.position = Vector2(randf_range(0, 640), randf_range(70, 320))
		cloud.modulate.a = 0.85
		layer.add_child(cloud)
		var ct := cloud.create_tween().set_loops()
		ct.tween_property(cloud, "position:x", -140.0, randf_range(16, 26)).from(780.0)

	var world := Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(world)

	for i in 5:
		var far := _emoji_label("🏝️", randi_range(20, 30))
		far.position = Vector2(randf_range(400, 2200), randf_range(520, 555))
		far.modulate.a = 0.55
		world.add_child(far)

	var start := Vector2(210, 750)
	var steps := [Vector2(720, 705), Vector2(1160, 785), Vector2(1610, 715), Vector2(2070, 745)]
	var cam_min := -(2400.0 - 720.0)

	var anchors := [start] + steps
	for s in anchors.size() - 1:
		var a: Vector2 = anchors[s]
		var b: Vector2 = anchors[s + 1]
		for f in [0.25, 0.5, 0.75]:
			var dot := Panel.new()
			var dsb := StyleBoxFlat.new()
			dsb.bg_color = Color(1, 1, 1, 0.5)
			dsb.set_corner_radius_all(20)
			dot.add_theme_stylebox_override("panel", dsb)
			dot.size = Vector2(12, 12)
			dot.position = a.lerp(b, f) - Vector2(6, 6) + Vector2(0, -26.0 * sin(f * PI))
			world.add_child(dot)

	var stop_icons := ["🗿", "🌴", "⚓"]
	var stop_nodes: Array[Control] = []
	for s in stop_icons.size():
		var marker := _emoji_label(stop_icons[s], 44)
		marker.position = steps[s] + Vector2(-22, -112)
		marker.resized.connect(func() -> void: marker.pivot_offset = marker.size * 0.5)
		world.add_child(marker)
		FX.float_bob(marker, 7.0, randf_range(1.6, 2.4))
		stop_nodes.append(marker)

	_journey_island_card(world, from_level, Vector2(70, 250), 290.0)
	var dest := _journey_island_card(world, to_level, Vector2(1950, 210), 330.0)
	FX.float_bob(dest, 8.0, 2.2)

	var boat_root := Control.new()
	boat_root.position = start
	world.add_child(boat_root)
	var boat_icon := _emoji_label("⛵", 76)
	boat_icon.position = Vector2(-38, -92)
	boat_icon.resized.connect(func() -> void: boat_icon.pivot_offset = boat_icon.size * 0.5)
	boat_root.add_child(boat_icon)
	var bob := boat_icon.create_tween().set_loops()
	bob.tween_property(boat_icon, "position:y", -100.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(boat_icon, "position:y", -92.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var wake := Timer.new()
	wake.wait_time = 0.12
	wake.autostart = true
	layer.add_child(wake)
	wake.timeout.connect(func() -> void:
		var bubble := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(1, 1, 1, 0.55)
		bsb.set_corner_radius_all(16)
		bubble.add_theme_stylebox_override("panel", bsb)
		var bs := randf_range(6, 13)
		bubble.size = Vector2(bs, bs)
		bubble.position = boat_root.position + Vector2(randf_range(-34, -12), randf_range(-14, 4))
		world.add_child(bubble)
		var bt := bubble.create_tween()
		bt.tween_property(bubble, "modulate:a", 0.0, 0.7)
		bt.tween_callback(bubble.queue_free)
	)

	var welcome := Lagoon.wordmark("Welcome to %s!" % CV.island_theme(to_level)["name"], 46)
	welcome.visible = false
	layer.add_child(welcome)
	welcome.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	welcome.offset_top = 190.0 + safe_top()
	welcome.offset_bottom = 250.0 + safe_top()

	var tw := layer.create_tween()
	tw.tween_property(layer, "modulate:a", 1.0, 0.35)
	tw.tween_interval(0.4)
	for i in steps.size():
		var p: Vector2 = steps[i]
		tw.tween_callback(func() -> void: Sfx.play("pop", -12.0))
		tw.tween_property(boat_root, "position", p, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(world, "position:x", clampf(320.0 - p.x, cam_min, 0.0), 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(boat_icon, "rotation", 0.09 if i % 2 == 0 else -0.09, 0.42)
		if i < stop_nodes.size():
			var sn := stop_nodes[i]
			tw.tween_callback(func() -> void:
				Sfx.play("tick", -6.0)
				var st := sn.create_tween()
				st.tween_property(sn, "scale", Vector2(1.45, 1.45), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				st.tween_property(sn, "scale", Vector2.ONE, 0.2)
			)
			tw.tween_interval(0.28)
	tw.tween_callback(func() -> void:
		wake.stop()
		Sfx.play("levelup", -2.0)
		Sfx.play("jackpot", -4.0)
		FX.flash(layer)
		FX.confetti(layer, 70)
		welcome.visible = true
		FX.pop_in(welcome, 0.4)
		var ht := boat_icon.create_tween()
		ht.tween_property(boat_icon, "rotation", 0.0, 0.2)
		_apply_island_theme()
		_refresh()
	)
	tw.tween_interval(1.25)
	tw.tween_property(layer, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func() -> void:
		layer.queue_free()
		_journey_layer = null
		_banner("Welcome to %s!  +%s coins, +%d spins" % [CV.island_theme(to_level)["name"], _fmt_compact(_scaled(ISLAND_REWARD_COINS, to_level)), ISLAND_REWARD_SPINS], Color(1.0, 0.85, 0.3))
	)

# --- shared UI ---

func _refresh() -> void:
	for labels in _hud_labels:
		labels["coins"].text = _fmt_compact(coins)
		labels["spins"].text = ("%d/%d" % [spins, SPIN_CAP]) if spins <= SPIN_CAP else str(spins)
		labels["shields"].text = str(shields)
		labels["stars"].text = _fmt_compact(rank_stars)
		labels["island"].text = str(island_level)
	village.refresh(buildings, coins, _star_costs())
	if slot != null:
		slot.set_meter(spins, SPIN_CAP, SPIN_REGEN_SECS - _regen_accum, SPIN_REGEN_AMOUNT)
		slot.set_target(next_target, _economy_mult())

func _banner(text: String, color: Color, emoji := "") -> void:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = 110
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 150.0 + safe_top()
	box.offset_bottom = 210.0 + safe_top()
	if emoji != "":
		var e := _emoji_label(emoji, UI.F_SUBHEAD)
		box.add_child(e)
	var lbl := Lagoon.title(text, UI.F_SUBHEAD, color, Lagoon.ABYSS)
	box.add_child(lbl)
	# On the banner rather than on main, so a banner that is freed for any other
	# reason takes its own animation with it. See _show_win.
	var tw := box.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(box, "modulate:a", 0.0, 0.5)
	tw.tween_callback(box.queue_free)

func _fmt(n: int) -> String:
	return UI.fmt(n)

func _fmt_compact(n: int) -> String:
	return UI.fmt_compact(n)

func _emoji_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CV.emoji_font())
	l.add_theme_font_size_override("font_size", size)
	return l

func _hud_value_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UI.F_LABEL)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	return l

# Every button in the game funnels through here. Call sites still name a colour
# ("this one is green"), which Lagoon.kind_for maps onto the five materials --
# so intent survives, but a button can no longer be an arbitrary shade. The
# gloss pass is what makes the face read as moulded rather than printed.
func _candy_button(btn: Button, color: Color) -> void:
	Lagoon.button(btn, Lagoon.kind_for(color))
	Lagoon.button_gloss(btn, 22)

# --- save / load ---

# Every cooldown in the game is a wall-clock stamp compared against
# _now(), and a phone's clock is not monotonic: it
# moves when the player crosses a timezone, when they set it by hand, and on a
# fresh device that boots before it has talked to a time server.
#
# Forward is harmless -- things come due early, which is the same exploit as
# simply setting the clock forward, and no worse. Backward is what breaks: a
# "last claimed" stamp left in the future never satisfies `now - last >= gap`,
# so the daily bonus, the free shop gift and the offer rotation go dark and
# stay dark until real time catches up with whatever the clock was set to.
# Players do not read that as a clock problem, they read it as the game eating
# their bonuses.
#
# So on the way in, a stamp that claims to be in the future is pulled back to
# now (the cooldown restarts, which is the choice that cannot be farmed), and a
# deadline further out than its own maximum span is pulled back to that span.
func _sanitize_clock() -> void:
	var now := _now()
	daily_last = minf(daily_last, now)
	shop_free_last = minf(shop_free_last, now)
	offer_until = minf(offer_until, now + CV.OFFER_DURATION)
	offer_next = minf(offer_next, now + CV.OFFER_COOLDOWN)
	col_deadline = minf(col_deadline, now + CV.COLLECTION_SEASON_DAYS * 86400.0)
	for entry in notif_log:
		if typeof(entry) == TYPE_DICTIONARY:
			entry["ts"] = minf(float(entry.get("ts", now)), now)


# =============================================================================
#  Saving
# =============================================================================
#
# Calling this is cheap and calling it often is correct: every place in the game
# that changes a counter ends with a save, which is what makes progress survive
# a kill. What it must not do is write the file every time.
#
# The save is a few kilobytes of JSON and the write is a stringify, a file
# create, a write, a close and two renames. On the reels that ran once per spin,
# and under auto-spin that is a syscall burst every couple of seconds forever --
# a frame hitch you can feel on an older phone, for no gain, because the state
# it wrote is superseded seconds later anyway.
#
# So a save marks the game dirty and _process flushes it at most every few
# seconds. The two places where a delay is not acceptable -- money changing
# hands, and the app being told it may be about to die -- call _flush_save()
# and get the old behaviour exactly.
const SAVE_FLUSH_GAP := 4.0
var _save_pending := false
var _save_flushed := 0.0

func _save_game() -> void:
	if _preview_island:
		return
	_save_pending = true

# The save, as one dictionary, in one place.
#
# Lifted out of _flush_save because there are now two callers who need exactly
# this and must not drift: the disk write, and claim_player -- which sends the
# island to the server the first time somebody signs in. A second hand-built
# copy of this literal would be a save that is missing whatever was added to the
# other one.
func _save_dict() -> Dictionary:
	return {
		"coins": coins,
		"spins": spins,
		"stars": stars,
		"rank_stars": rank_stars,
		"shields": shields,
		"island_level": island_level,
		"buildings": buildings,
		"revenge": revenge_pending,
		"npcs": npcs,
		"daily_last": daily_last,
		"muted": muted,
		"missions3": mission_state,
		"col_owned": col_owned,
		"col_dupes": col_dupes,
		"col_claimed": col_claimed,
		"col_mega": col_mega_claimed,
		"col_deadline": col_deadline,
		"purchased": purchased_ids,
		"topup_pending": topup_pending,
		"shop_free_last": shop_free_last,
		"piggy": piggy_coins,
		"piggy_promised": piggy_promised,
		"offer_id": offer_id,
		"offer_until": offer_until,
		"offer_next": offer_next,
		"notif_enabled": notif_enabled,
		"notif_types": notif_types,
		"notif_log": notif_log,
		"notif_prompted": notif_prompted,
		# What rivals are part-way through doing. Saved because the absence it
		# was rolled for usually ends with the app having been killed, and a
		# plan that only lived in memory would mean the notification fired and
		# the island it described never happened.
		"pending_raids": pending_raids,
		"ts": _now(),
		# The clock high-water mark. Without it in the save, quitting the game
		# resets it to zero and every backward-clock exploit reopens on launch.
		"clock_hw": clock_hw,
	}

func _flush_save() -> void:
	if _preview_island or _boot != null:
		return
	_save_flushed = float(Time.get_ticks_msec()) / 1000.0
	var data := _save_dict()
	# The dirty flag is cleared by the write succeeding, not by having attempted
	# one. It used to be cleared on the way in, so a write that failed -- a full
	# disk, which is exactly the case _write_save's own comment is about -- left
	# the debounce believing the save was clean. The game then played on and
	# persisted nothing at all, silently, until some later _save_game() marked
	# it dirty again and failed in the same way.
	_save_pending = not _write_save(data)
	if _save_pending:
		_save_fails += 1
		# Once is a hiccup and the debounce will try again shortly. A run of
		# them is a disk that is not going to come back on its own, and the
		# player is entitled to know before they lose an evening's play.
		if _save_fails == SAVE_FAIL_WARN:
			_banner("Can't save right now — check your free space.", Color(0.9, 0.4, 0.4))
	else:
		_save_fails = 0
		# Offered, not sent. note_save marks a copy dirty and returns; cloud.gd
		# batches it at its own much slower cadence, because a radio wake-up per
		# spin is somebody's battery. It does nothing at all when the player is
		# not signed in, which is the common case and not a fault.
		Cloud.note_save(data, rank_stars, island_level, coins, shields, buildings)

# Writing the save is the one operation in the game that can lose everything,
# so it is not allowed to be a single store_string.
#
# The old version opened the real file and wrote into it. Anything that
# interrupts that -- iOS killing a backgrounded app, a battery dying, the OS
# reclaiming memory -- leaves a half-written JSON file on disk, and the next
# launch parses it, gets null, and starts a brand new island. Not a rollback:
# a wipe, silently, with no way back.
#
# So: write the new state to a scratch file and only rename it over the real
# one once it is closed and complete. A rename is atomic, so the save file on
# disk is always a whole save -- either the old one or the new one, never a
# torn one. The previous save is kept beside it as .bak, which is what
# _load_game falls back to if the real file is somehow still unreadable.
# Returns whether the save is now on disk. Every caller needs that answer --
# see _flush_save, which used to assume it.
func _write_save(data: Dictionary) -> bool:
	var text := JSON.stringify(data)
	var f := FileAccess.open(SAVE_TMP, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	# Explicit, and then checked. store_string buffers, and a close that fails
	# on a full disk must not be mistaken for a save that landed.
	f.close()
	if FileAccess.get_open_error() != OK:
		return false
	if not FileAccess.file_exists(SAVE_TMP):
		return false
	var d := DirAccess.open("user://")
	if d == null:
		return false
	# The backup only rotates when this session actually read a save and
	# understood all of it. If the load bailed partway, what is in memory is
	# mostly defaults, and rotating would push the last intact copy out of .bak
	# to make room for it -- turning a load that went wrong once into a wipe
	# with nothing left to recover from. Overwrite the live file, keep the
	# backup where it is.
	if FileAccess.file_exists(SAVE_PATH) and _load_ok:
		d.remove(SAVE_BAK)
		d.rename(SAVE_PATH, SAVE_BAK)
	if d.rename(SAVE_TMP, SAVE_PATH) != OK:
		# The rename failed with the real file possibly already moved aside.
		# Put it back rather than leaving the game with no save at all.
		if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(SAVE_BAK):
			d.rename(SAVE_BAK, SAVE_PATH)
		return false
	return true

# The save as a dictionary, or empty if there is nothing readable. Tries the
# real file, then the backup the last successful write left behind.
func _read_save() -> Dictionary:
	for path in [SAVE_PATH, SAVE_BAK]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY and not (parsed as Dictionary).is_empty():
			return parsed
		push_warning("Save at %s is unreadable; falling back." % path)
	return {}

func _load_game() -> void:
	var data := _read_save()
	if data.is_empty():
		# Nothing on disk to lose, so the backup guard in _write_save has
		# nothing to guard: a first run must be allowed to rotate normally.
		_load_ok = true
		return
	# First, before any other line in this function: _now() answers with the
	# high-water mark, and every cooldown, deadline and elapsed-time figure
	# below is measured against it. Restored one statement too late and the
	# whole load would run against a clock the player is free to have wound
	# back. maxf, so a hand-edited save cannot lower it either.
	clock_hw = maxf(clock_hw, _f(data.get("clock_hw", 0.0)))
	coins = maxi(0, _i(data.get("coins", 1500), 1500))
	spins = maxi(0, _i(data.get("spins", 30), 30))
	shields = clampi(_i(data.get("shields", 0)), 0, 3)
	# Clamped against nonsense, not against progress.
	#
	# It was pinned to CV.ISLANDS.size() on the grounds that island_level
	# indexes the theme, the palette and the building textures -- but every one
	# of those wraps with % ISLANDS.size(), so a level past thirty was always
	# safe to hold. What the tight clamp did instead was silently roll a player
	# who had sailed past the last island back to thirty on their next launch,
	# with the level they earned quietly gone. The economy is what actually had
	# to stop growing, and CV.curve now flattens it at thirty on its own.
	island_level = clampi(_i(data.get("island_level", data.get("village_level", 1)), 1), 1, MAX_ISLAND)
	revenge_pending = _b(data.get("revenge", false))
	daily_last = _f(data.get("daily_last", 0.0))
	muted = _b(data.get("muted", false))
	var lo = data.get("col_owned", {})
	if typeof(lo) == TYPE_DICTIONARY:
		col_owned = lo
	var ld = data.get("col_dupes", {})
	if typeof(ld) == TYPE_DICTIONARY:
		col_dupes = ld
	var lc = data.get("col_claimed", {})
	if typeof(lc) == TYPE_DICTIONARY:
		col_claimed = lc
	col_mega_claimed = _b(data.get("col_mega", false))
	col_deadline = _f(data.get("col_deadline", 0.0))
	var lp = data.get("purchased", [])
	if typeof(lp) == TYPE_ARRAY:
		# Only the strings. Every consumer compares this against a pack id, so
		# a dictionary in here is dead weight at best and a raise at worst.
		purchased_ids = []
		for id in lp:
			if typeof(id) == TYPE_STRING:
				purchased_ids.append(id)
	# Coerced field by field rather than assigned whole: this is read back
	# straight into a purchase-delivery path, and a malformed save must not be
	# able to name an arbitrary product or an arbitrary number of coins.
	topup_pending = {}
	var tp = data.get("topup_pending", {})
	if typeof(tp) == TYPE_DICTIONARY:
		var tp_id := _s(tp.get("id", ""))
		var tp_coins := maxi(0, _i(tp.get("coins", 0)))
		if tp_id != "" and tp_coins > 0 and not CV.pack_by_id(tp_id).is_empty():
			topup_pending = {"id": tp_id, "coins": tp_coins}
	shop_free_last = _f(data.get("shop_free_last", 0.0))
	piggy_coins = maxi(0, _i(data.get("piggy", 0)))
	piggy_promised = maxi(0, _i(data.get("piggy_promised", 0)))
	offer_id = _s(data.get("offer_id", ""))
	offer_until = _f(data.get("offer_until", 0.0))
	offer_next = _f(data.get("offer_next", 0.0))
	notif_enabled = _b(data.get("notif_enabled", true), true)
	notif_prompted = _b(data.get("notif_prompted", false))
	var pr = data.get("pending_raids", [])
	pending_raids = []
	if typeof(pr) == TYPE_ARRAY:
		for ev in pr:
			# Bounded and type-checked like every other list off the save. Each
			# entry drives a coin subtraction and a building index, so a
			# hand-edited one is an out-of-bounds write waiting to happen --
			# _offline_raids clamps both, and this drops the rest on the floor.
			if pending_raids.size() >= OFFLINE_RAID_MAX:
				break
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			pending_raids.append({
				"at": _f(ev.get("at", 0.0)),
				"npc": _s(ev.get("npc", "")),
				"emoji": _s(ev.get("emoji", "🚨"), "🚨"),
				"type": _s(ev.get("type", "steal"), "steal"),
				"kind": _s(ev.get("kind", "")),
				"building": clampi(_i(ev.get("building", -1), -1), -1, CV.BUILDINGS.size() - 1),
				"coins": maxi(0, _i(ev.get("coins", 0))),
				"text": _s(ev.get("text", "")),
			})
	var nt = data.get("notif_types", {})
	if typeof(nt) == TYPE_DICTIONARY:
		for k in notif_types:
			notif_types[k] = _b(nt.get(k, true), true)
	var nl = data.get("notif_log", [])
	if typeof(nl) == TYPE_ARRAY:
		notif_log = []
		for entry in nl:
			# The same cap _notify enforces on the way out. Without it here a
			# save can carry an arbitrarily long log, and _fill_alerts builds
			# about ten Controls per entry with no windowing -- a few hundred
			# thousand rows is an out-of-memory kill on the Alerts page.
			if notif_log.size() >= NOTIF_LOG_MAX:
				break
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			notif_log.append({
				"type": _s(entry.get("type", "spins"), "spins"),
				"text": _s(entry.get("text", "")),
				"emoji": _s(entry.get("emoji", "🔔"), "🔔"),
				"ts": _f(entry.get("ts", 0.0)),
				"read": _b(entry.get("read", true), true),
			})
	# missions2 banked coins_won in island-1 units, from before coin targets rode
	# the island curve. Its progress is quoted against a target 1.6^(level-1)
	# times larger now, so lift it onto the same scale on the way in.
	var lm = data.get("missions3", {})
	var legacy_coin_progress := false
	if typeof(lm) != TYPE_DICTIONARY or lm.is_empty():
		lm = data.get("missions2", {})
		legacy_coin_progress = true
	if typeof(lm) == TYPE_DICTIONARY:
		for period in MISSION_DEFS:
			var pst = lm.get(period, null)
			if typeof(pst) != TYPE_DICTIONARY:
				continue
			var prog := {}
			var pd = pst.get("progress", {})
			if typeof(pd) == TYPE_DICTIONARY:
				for k in pd:
					prog[k] = maxi(0, _i(pd[k]))
					if legacy_coin_progress and k in MISSION_COIN_TARGETS:
						prog[k] = _scaled(maxi(0, _i(pd[k])))
			var cl := {}
			var cd = pst.get("claimed", {})
			if typeof(cd) == TYPE_DICTIONARY:
				for k in cd:
					cl[k] = _b(cd[k])
			mission_state[period] = {"key": _i(pst.get("key", -1), -1), "progress": prog, "claimed": cl, "bonus": _b(pst.get("bonus", false))}
	# Clamped and resized exactly the way the rivals below already are. This
	# array was the one the loader trusted, and it is the player's own: a level
	# of -10 sends village_view's costs[level] out of bounds and the island
	# page then never repaints again, while a sixth entry sends _offline_raids
	# indexing past the five building names every island theme has. Both
	# survive a restart, because the bad value is written straight back out.
	var b = data.get("buildings", [])
	buildings = []
	if typeof(b) == TYPE_ARRAY:
		for v in b:
			buildings.append(clampi(_i(v), 0, CV.MAX_STAR))
	while buildings.size() < CV.BUILDINGS.size():
		buildings.append(0)
	buildings.resize(CV.BUILDINGS.size())
	# What this save can still prove it earned, rebuilt from the things that pay
	# stars and are themselves saved: every hut level standing on the island you
	# hold, a finished island's worth for each one behind you, and every card
	# you own. It is a floor, not a replay -- set and grand-prize bonuses are
	# not recoverable from a save that never wrote them down.
	var earned := 0
	for lv in buildings:
		var n := clampi(_i(lv), 0, CV.MAX_STAR)
		earned += n * (n + 1) / 2
	earned += 75 * maxi(0, island_level - 1)
	for c in CV.COLLECTIONS:
		var have = col_owned.get(c["id"], [])
		if typeof(have) != TYPE_ARRAY:
			continue
		var items: Array = c["items"]
		for i in mini(items.size(), have.size()):
			if have[i]:
				earned += int(items[i][2])

	# Two migrations, in the order they happened. Stars arrived after the
	# earliest saves were written, so those get the reconstruction for both
	# counters -- otherwise the leaderboard opens on day one with a veteran at
	# zero. Rank split off from the balance later, and those saves recorded only
	# what was left after the boxes had taken their cut; rebuilding the standing
	# is the only way to give back what opening a box used to quietly cost.
	# maxi, because melted spares can push a balance above what rank counts.
	stars = maxi(0, _i(data["stars"], earned)) if data.has("stars") else earned
	rank_stars = maxi(0, _i(data["rank_stars"], earned)) if data.has("rank_stars") else maxi(earned, stars)

	_sanitize_clock()

	# Bounded. `ts` is a number in the save file, so "away since 1970" costs an
	# attacker one edit and no clock change at all; a week is longer than any
	# absence the offline systems have anything left to give for.
	var elapsed := clampf(_now() - _f(data.get("ts", 0.0)), 0.0, MAX_AWAY_SECS)
	_credit_time_away(elapsed)
	var raw_npcs = data.get("npcs", [])
	var loaded_npcs: Array = raw_npcs if typeof(raw_npcs) == TYPE_ARRAY else []
	npcs = []
	for n in loaded_npcs:
		# The pool is a fixed size and _stock_rivals only ever tops it up, so a
		# save carrying more than a poolful is either damaged or edited. Every
		# rival is a row on the leaderboard and a card on the raid screen, so
		# an unbounded list is an unbounded number of Controls to build.
		if npcs.size() >= CV.RIVAL_POOL:
			break
		# A save is a file on a device the player owns; it can be edited, and a
		# crash can still leave a stale one behind. A rival that is not a
		# dictionary would take .get() down with it and abort the whole load,
		# which costs the player the island. Skip it instead.
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var nb := []
		var raw_b = n.get("buildings", [])
		if typeof(raw_b) == TYPE_ARRAY:
			for v in raw_b:
				nb.append(clampi(_i(v), 0, CV.MAX_STAR))
		while nb.size() < 5:
			nb.append(1)
		nb.resize(5)
		npcs.append({
			"name": _s(n.get("name", "Rival"), "Rival"),
			"emoji": _s(n.get("emoji", "🧔"), "🧔"),
			"flag": _s(n.get("flag", "??"), "??"),
			# Capped, not just grown. mini() bounded what a single load could
			# add, but nothing bounded the total, and a rival's purse *is* the
			# steal payout -- so force-quit, jump the clock, relaunch, twenty
			# times over, and every rival on the island is worth six figures
			# before the island multiplier and the bet multiplier are applied.
			# The clock high-water mark makes that loop cost a permanently
			# broken clock; the ceiling makes it pointless as well.
			"coins": mini(NPC_COIN_CAP, maxi(0, _i(n.get("coins", 2000), 2000))
				+ mini(8000, int(elapsed / 60.0) * 15)),
			"buildings": nb,
			"shield": _b(n.get("shield", false)),
			# Missing keeps its old meaning -- scatter them -- rather than
			# quietly parking every unlabelled rival on island 1.
			"island": clampi(_i(n.get("island", 0), 0) if _i(n.get("island", 0), 0) > 0 else randi_range(1, CV.ISLANDS.size()), 1, CV.ISLANDS.size()),
		})
	_load_ok = true
