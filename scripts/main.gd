extends Control

const SAVE_PATH := "user://coinvillage_save.json"
const SPIN_CAP := 50
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

var slot_page: Control
# The win read-out currently on the reels, if any. See `_show_win`.
var _win_slug: Control
var village_page: Control
var slot: SlotView
var village: VillageView
var _current_page: Control
var _visit: IslandVisit
var _match: Matchmaking
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
# The live limited-time offer: which pack, when it dies, and the earliest the
# next one may roll. All three persist, so a countdown a player left running
# is still running when they come back.
var offer_id := ""
var offer_until := 0.0
var offer_next := 0.0
# Contextual offers interrupt play, so they are rate-limited hard. Firing one
# on every failed tap would train players to dismiss them on sight.
var _ctx_offer_last := 0.0
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

const NOTIF_LOG_MAX := 30
var notif_enabled := true
var notif_types := {"attack": true, "steal": true, "spins": true}
var notif_log := []
var _toast: Control
var _offline_spins_gained := 0
var _offline_elapsed := 0.0
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
	call_deferred("_check_island_complete")
	if _offline_spins_gained > 0:
		_notify("spins", "While you were away, spins refilled  +%d  (%d/%d)" % [_offline_spins_gained, spins, SPIN_CAP], "🌀")
		_offline_spins_gained = 0
	_offline_raids()
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

func _capture_page(key: String) -> void:
	if pages.has(key):
		_goto(pages[key])
	elif key == "slot":
		_goto(slot_page)
	# Long enough for the page transition and the card art to finish arriving;
	# a screenshot of a half-built shop is worse than none.
	await get_tree().create_timer(2.0).timeout
	var img := get_viewport().get_texture().get_image()
	var path := "user://shot_%s.png" % key
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
	if typeof(d) == TYPE_DICTIONARY:
		profile = d

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
			var s := randf_range(50, 110)
			tr.size = Vector2(s, s)
			# clear of the wordmark and the sign-in column
			tr.position = Vector2(randf_range(20, 630),
				randf_range(80, 470) if i % 2 == 0 else randf_range(860, 1150))
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

	var g_btn := Button.new()
	g_btn.text = "Sign in with Google"
	g_btn.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(g_btn, Color(0.92, 0.92, 0.92))
	FX.press_feedback(g_btn)
	g_btn.pressed.connect(_login_google)
	box.add_child(g_btn)

	var f_btn := Button.new()
	f_btn.text = "Continue with Facebook"
	f_btn.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(f_btn, Color(0.23, 0.35, 0.6))
	FX.press_feedback(f_btn)
	f_btn.pressed.connect(func() -> void:
		_banner("Facebook login requires a Facebook Developer app — coming soon", Color(0.7, 0.8, 1.0))
	)
	box.add_child(f_btn)

	var guest := Button.new()
	guest.text = "Play as Guest"
	guest.custom_minimum_size = Vector2(0, UI.TAP)
	guest.add_theme_font_size_override("font_size", UI.F_CAPTION)
	_candy_button(guest, Color(0.6, 0.6, 0.62))
	# Skipping sign-in is a legitimate choice but not the recommended one, so it
	# recedes rather than competing with the two account options above it.
	guest.modulate = Color(1, 1, 1, 0.72)
	FX.press_feedback(guest)
	guest.pressed.connect(func() -> void:
		profile = {"name": "Guest", "email": "", "provider": "guest"}
		_save_profile()
		_close_login()
	)
	box.add_child(guest)

func _login_google() -> void:
	if GoogleAuth.load_config().is_empty():
		_banner("Google login needs a one-time setup — see SETUP_LOGIN.md", Color(1.0, 0.8, 0.4))
		return
	var auth := GoogleAuth.new()
	add_child(auth)
	_banner("Opening Google sign-in in your browser...", Color(0.7, 0.9, 1.0))
	auth.login_finished.connect(func(p: Dictionary) -> void:
		profile = p
		_save_profile()
		_close_login()
		auth.queue_free()
	)
	auth.login_failed.connect(func(reason: String) -> void:
		_banner("Login failed: %s" % reason, Color(0.95, 0.4, 0.4))
		auth.queue_free()
	)
	if not auth.start():
		_banner("Could not start Google login", Color(0.95, 0.4, 0.4))
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
		_regen_accum = 0.0
		if spins < SPIN_CAP:
			var gained := mini(SPIN_REGEN_AMOUNT, SPIN_CAP - spins)
			spins += gained
			_refresh()
			if spins >= SPIN_CAP:
				_notify("spins", "Spins refilled — you're full!  (%d/%d)" % [spins, SPIN_CAP], "🌀")
			else:
				_notify("spins", "+%d spins refilled  (%d/%d)" % [gained, spins, SPIN_CAP], "🌀")
	_ui_tick += delta
	if _ui_tick >= 1.0:
		_ui_tick = 0.0
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

func _notification(what: int) -> void:
	# Quitting mid-load would otherwise write the starting 1500/30 over a real
	# save, since the file has not necessarily been read yet.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _boot == null:
		_save_game()

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
	var glow_sh := Shader.new()
	glow_sh.code = """
shader_type canvas_item;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.3, 1.0, d)) * 0.55;
	COLOR = vec4(1.0, 0.55, 0.40, a);
}
"""
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
	var glow_shader := Shader.new()
	glow_shader.code = """
shader_type canvas_item;
uniform vec3 glow_col = vec3(1.0, 0.85, 0.4);
void fragment() {
	float d = length(UV - 0.5);
	float a = smoothstep(0.5, 0.05, d) * 0.35;
	COLOR = vec4(glow_col, a);
}
"""
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
	var bg_sh := Shader.new()
	bg_sh.code = """
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
"""
	_slot_bg_mat = ShaderMaterial.new()
	_slot_bg_mat.shader = bg_sh
	bg.material = _slot_bg_mat
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_bg = bg

	var rays := ColorRect.new()
	var rays_sh := Shader.new()
	rays_sh.code = """
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
"""
	_slot_rays_mat = ShaderMaterial.new()
	_slot_rays_mat.shader = rays_sh
	rays.material = _slot_rays_mat
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(rays)
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var floor_rect := ColorRect.new()
	var floor_sh := Shader.new()
	floor_sh.code = """
shader_type canvas_item;

uniform vec3 floor_col = vec3(0.55, 0.87, 0.90);

void fragment() {
	// Shallow water washing up to the nav bar. It grounds the bottom of the
	// page the way the old dark floor did, but by getting brighter toward the
	// edge instead of darker -- foam, not shadow.
	float t = smoothstep(0.50, 1.0, UV.y);
	COLOR = vec4(floor_col, t * 0.80);
}
"""
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
	return Time.get_unix_time_from_system() - daily_last >= DAILY_COOLDOWN

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
	if _hud_labels.is_empty() or not _hud_labels[0].has("stars"):
		return
	var to: Vector2 = _hud_labels[0]["stars"].global_position
	var src := from_global if from_global != Vector2.ZERO else Vector2(view_size().x * 0.5, view_size().y * 0.45)
	FX.fly_coins(self, src, to, clampi(n, 3, 10), "star", "\u2b50")
	Sfx.play("levelup", -10.0)

func _economy_mult() -> float:
	return pow(1.6, island_level - 1)

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
	var now := int(Time.get_unix_time_from_system())
	match period:
		"weekly":
			# +3 aligns week boundaries to Monday (unix day 0 was a Thursday)
			return (now / 86400 + 3) / 7
		"monthly":
			var d := Time.get_datetime_dict_from_unix_time(now)
			return int(d["year"]) * 12 + int(d["month"])
	return now / 86400

func _period_reset_secs(period: String) -> int:
	var now := int(Time.get_unix_time_from_system())
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
		var st: Dictionary = mission_state.get(period, {})
		if st.is_empty() or int(st.get("key", -1)) != key:
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
	var place_close := func() -> void:
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
	var tw := create_tween()
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
			daily_last = Time.get_unix_time_from_system()
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
		var left := maxi(0, int(DAILY_COOLDOWN - (Time.get_unix_time_from_system() - daily_last)))
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
	notif_log.push_front({"type": ntype, "text": text, "emoji": emoji, "ts": Time.get_unix_time_from_system(), "read": false})
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
	panel.custom_minimum_size = Vector2(672, 92)
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
	var tw := create_tween()
	tw.tween_property(panel, "position:y", 78.0 + safe_top(), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)

func _time_ago(ts: float) -> String:
	var d := int(Time.get_unix_time_from_system() - ts)
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

func _fill_page(key: String) -> void:
	var vb: VBoxContainer = _page_bodies[key]
	for c in vb.get_children():
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

	_shop_section(vb, "🐷", "PIGGY  BANK")
	_piggy_card(vb)

	_shop_section(vb, "🧳", "BUNDLES")
	for pack in CV.BUNDLE_PACKS:
		_bundle_card(vb, pack)
	vb.add_child(_page_note("Bundles cost less than the same spins, coins and cards bought apart", UI.F_TINY))

	_shop_section(vb, "🗝️", "TREASURE  CHESTS")
	var chest_row := HBoxContainer.new()
	chest_row.add_theme_constant_override("separation", 10)
	vb.add_child(chest_row)
	for pack in CV.CHEST_PACKS:
		_chest_card(chest_row, pack)
	vb.add_child(_page_note("Pricier chests hold more cards and better odds — every chest shows its full odds table before you pay", UI.F_TINY))

	_shop_section(vb, "🎰", "SPIN  PACKS")
	var sgrid := GridContainer.new()
	sgrid.columns = 2
	sgrid.add_theme_constant_override("h_separation", 10)
	sgrid.add_theme_constant_override("v_separation", 10)
	vb.add_child(sgrid)
	for pack in CV.SPIN_PACKS:
		_shop_tile(sgrid, pack, Color(0.35, 0.75, 1.0), "%d  SPINS" % int(pack["spins"]))

	_shop_section(vb, "💰", "COIN  PACKS")
	var cgrid := GridContainer.new()
	cgrid.columns = 2
	cgrid.add_theme_constant_override("h_separation", 10)
	cgrid.add_theme_constant_override("v_separation", 10)
	vb.add_child(cgrid)
	for pack in CV.COIN_PACKS:
		_shop_tile(cgrid, pack, Color(1.0, 0.78, 0.25), "%s  COINS" % _fmt_compact(_scaled(int(pack["coins"]))))

	_shop_section(vb, "🎁", "FREE  GIFT")
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
func _shop_section(vb: VBoxContainer, _emoji: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
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

func _radial_glow(color: Color, diameter: float) -> ColorRect:
	var glow := ColorRect.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 glow_col : source_color = vec4(1.0, 0.8, 0.3, 1.0);
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.1, 1.0, d)) * 0.5 * glow_col.a;
	COLOR = vec4(glow_col.rgb, a);
}
"""
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
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	float band = fract(TIME * 0.22);
	float x = (UV.x + UV.y * 0.35) / 1.35;
	float a = smoothstep(0.1, 0.0, abs(x - band)) * 0.14;
	COLOR = vec4(tint.rgb, a);
}
"""
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
	var sub := Lagoon.label(_pack_sub(pack), UI.F_CAPTION, Lagoon.INK_SOFT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sub)

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
	var place_fill := func() -> void:
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
	if pack.has("tag"):
		head.add_child(_tag_chip(pack["tag"], pack["tag_color"], 11))

	var sub := Lagoon.label(_pack_sub(pack), UI.F_CAPTION, Lagoon.INK_SOFT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
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
	var sub := _popup_row_label(_pack_sub(pack), UI.F_CAPTION)
	sub.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
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

	col.add_child(_star_row(int(pack["star_cap"]), UI.F_CAPTION))

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
func _shop_tile(grid: GridContainer, pack: Dictionary, accent: Color, amount_text: String) -> void:
	var panel := _tinted_card(grid, accent)
	panel.custom_minimum_size = Vector2(338, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)

	# fixed-height tag slot (empty when the pack has no tag) so every tile
	# in the grid keeps the exact same content height as its siblings
	var tag_wrap := CenterContainer.new()
	tag_wrap.custom_minimum_size = Vector2(0, 36)
	col.add_child(tag_wrap)
	if pack.has("tag"):
		tag_wrap.add_child(_tag_chip(pack["tag"], pack.get("tag_color", Color(0.88, 0.28, 0.38)), 11))

	var e := _emoji_label(pack["emoji"], 42)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(e)
	FX.pulse_forever(e, 1.06, 2.4)

	var amount := Lagoon.label(amount_text, UI.F_LABEL, Lagoon.INK, true)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(amount)

	var nm := Lagoon.label(pack["name"], UI.F_TINY, Lagoon.INK_FAINT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	# What climbing the ladder actually buys, said out loud. The bottom rung
	# gets a blank line rather than "+0%" -- it is the thing being compared
	# against, and the tiles have to stay the same height either way.
	var bonus := CV.bonus_pct(pack)
	var value := Lagoon.label("+%d%%  MORE  PER  $" % bonus if bonus > 0 else "", UI.F_TINY, Lagoon.KELP_LO, true)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(value)

	var buy := Button.new()
	buy.text = IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(0, UI.TAP)
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	col.add_child(buy)

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
	return Time.get_unix_time_from_system() - shop_free_last >= CV.SHOP_FREE_COOLDOWN

func _shop_free_countdown_text() -> String:
	var left := maxi(0, int(CV.SHOP_FREE_COOLDOWN - (Time.get_unix_time_from_system() - shop_free_last)))
	return "%02d:%02d:%02d" % [left / 3600, (left % 3600) / 60, left % 60]

func _claim_shop_gift() -> void:
	if not _shop_free_ready():
		return
	shop_free_last = Time.get_unix_time_from_system()
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

func _break_piggy() -> void:
	var got := piggy_coins
	if got <= 0:
		return
	piggy_coins = 0
	coins += got
	Sfx.play("jackpot", -3.0)
	FX.confetti(self, 52)
	FX.flash(self)
	_banner("Piggy smashed — +%s coins!" % _fmt_compact(got), Color(1.0, 0.62, 0.72), "🐷")
	_update_badges()
	_refresh()
	_save_game()
	if _current_page == pages.get("shop"):
		_fill_page("shop")

# --- limited-time offer -------------------------------------------------
#
# One offer at a time, live for two hours, then five hours of nothing. The dark
# stretch is deliberate: an offer that is always on the shelf is just a price,
# and the countdown only means something if the player has seen it run out.
func _offer_tick() -> void:
	var now := Time.get_unix_time_from_system()
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
	if offer_id == "" or Time.get_unix_time_from_system() >= offer_until:
		return {}
	for o in CV.TIMED_OFFERS:
		if String(o["id"]) == offer_id:
			return o
	return {}

func _offer_countdown_text() -> String:
	var left := maxi(0, int(offer_until - Time.get_unix_time_from_system()))
	return "%d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]

# --- contextual offers --------------------------------------------------
#
# The moment a player is stopped by a number is the moment the number is worth
# most to them, and every game in this genre sells into it -- Monopoly GO puts
# a cash offer in front of you the instant a building costs more than you have.
# Loot Lagoon used to answer both of those moments with an error beep.
#
# The guard rail is the cooldown. These fire on failure, and failure repeats;
# without a long gap between them the offer becomes wallpaper and the player
# learns to swipe it away before reading it.
const CTX_OFFER_COOLDOWN := 900.0

func _ctx_offer_ready() -> bool:
	return Time.get_unix_time_from_system() - _ctx_offer_last >= CTX_OFFER_COOLDOWN

# Shown when the reels are asked to spin with an empty meter. Leads with the
# free refill that is already coming, because burying it would make the popup a
# paywall -- the pack is the shortcut, not the only road.
func _offer_out_of_spins() -> void:
	_ctx_offer_last = Time.get_unix_time_from_system()
	var live := _active_offer()
	var pack: Dictionary = live if not live.is_empty() else CV.SPIN_PACKS[1]
	var vbox := _open_popup("Out of Spins")
	var e := _emoji_label("🌀", 68)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(e)
	var wait := _popup_row_label("+%d spins free in %d min" % [SPIN_REGEN_AMOUNT, int(SPIN_REGEN_SECS / 60.0)], UI.F_BODY)
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(wait)
	var or_row := _popup_row_label("— or keep the run going —", UI.F_CAPTION)
	or_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_row.add_theme_color_override("font_color", Lagoon.INK_FAINT)
	vbox.add_child(or_row)
	_ctx_offer_card(vbox, pack, not live.is_empty())
	_ctx_offer_footer(vbox)

# Shown when an upgrade costs more than the vault holds. Names the shortfall,
# then offers the cheapest pack that actually covers it -- an offer for less
# than the missing amount is worse than no offer, because it does not unblock.
func _offer_need_coins(shortfall: int) -> void:
	_ctx_offer_last = Time.get_unix_time_from_system()
	var pack: Dictionary = CV.COIN_PACKS[CV.COIN_PACKS.size() - 1]
	for p in CV.COIN_PACKS:
		if _scaled(int(p["coins"])) >= shortfall:
			pack = p
			break
	var vbox := _open_popup("Not Enough Coins")
	var e := _emoji_label("🏗️", 68)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(e)
	var need := _popup_row_label("You're %s coins short" % _fmt_compact(shortfall), UI.F_BODY)
	need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(need)
	if piggy_coins > 0:
		var pig := _popup_row_label("🐷  %s coins waiting in your piggy bank" % _fmt_compact(piggy_coins), UI.F_CAPTION)
		pig.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pig.add_theme_color_override("font_color", Color(1.0, 0.62, 0.72))
		vbox.add_child(pig)
	_ctx_offer_card(vbox, pack, false)
	_ctx_offer_footer(vbox)

# The pack tile inside a contextual popup: what you get, then the price.
func _ctx_offer_card(vbox: VBoxContainer, pack: Dictionary, timed: bool) -> void:
	var card := _tinted_card(vbox, Lagoon.BRASS if timed else Lagoon.KELP, timed)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 12)
	card.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)
	if timed:
		var chip_wrap := CenterContainer.new()
		col.add_child(chip_wrap)
		chip_wrap.add_child(_tag_chip("⏳  %s  LEFT" % _offer_countdown_text(), Lagoon.REEF))
	var nm := Lagoon.label(pack["name"], UI.F_BODY, Lagoon.INK, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)
	var sub := Lagoon.label(_pack_sub(pack), UI.F_CAPTION, Lagoon.INK_SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var buy := Button.new()
	buy.text = "GET  IT  —  %s" % IAP.price_for(pack)
	buy.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	buy.add_theme_font_size_override("font_size", UI.F_LABEL)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(func() -> void:
		_close_popup()
		_confirm_purchase(pack)
	)
	col.add_child(buy)

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
	_grant_pack(pack)
	IAP.finish(product_id)

# Backing out of Apple's sheet is a decision, not a fault. Take the spinner
# down and say nothing -- the player knows what they just did.
func _on_purchase_cancel(_product_id: String) -> void:
	_close_popup()

# This is now only reached by genuine failures, so it may be as loud as it
# looks: something the player asked for did not happen.
func _on_purchase_fail(_product_id: String, message: String) -> void:
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
		offer_next = Time.get_unix_time_from_system() + CV.OFFER_COOLDOWN
		_offer_timer_label = null
	spins += int(pack.get("spins", 0))
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
	_save_game()
	if _current_page == pages.get("shop"):
		_fill_page("shop")

# Picks one [collection, index] entry, each candidate weighted by how often
# its collection drops. Ties the chest pool to the same difficulty ladder the
# reels use, so an Easy set's single gold card is the one a chest usually pays
# out and a Hard set's stays a chase.
func _weighted_card(cards: Array) -> Array:
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

	# Dimming the three in place beats rebuilding the page: the master switch
	# gets to finish its own animation instead of being replaced mid-slide.
	master.switched.connect(func(on: bool) -> void:
		notif_enabled = on
		for row in per_type:
			row.set_dimmed(not on)
		_save_game()
	)

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
		_show_login()
	)
	acc.add_child(signout)

	vb.add_child(_page_note("Loot Lagoon  •  prototype", UI.F_CAPTION))

func _styled_progress(fg_color: Color) -> ProgressBar:
	return Lagoon.progress(fg_color)

# --- collections ---

func _ensure_collections() -> void:
	var now := Time.get_unix_time_from_system()
	if col_deadline <= 0.0 or now > col_deadline:
		col_owned = {}
		col_dupes = {}
		col_claimed = {}
		col_mega_claimed = false
		col_deadline = now + CV.COLLECTION_SEASON_DAYS * 86400.0
	for c in CV.COLLECTIONS:
		var id: String = c["id"]
		var n: int = (c["items"] as Array).size()
		var arr: Array = col_owned.get(id, [])
		var dup: Array = col_dupes.get(id, [])
		var norm := []
		var dnorm := []
		for i in n:
			norm.append(bool(arr[i]) if i < arr.size() else false)
			dnorm.append(maxi(0, int(dup[i])) if i < dup.size() else 0)
		col_owned[id] = norm
		col_dupes[id] = dnorm
		col_claimed[id] = bool(col_claimed.get(id, false))

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
	var days_left := maxf(0.0, col_deadline - Time.get_unix_time_from_system())
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
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
uniform vec3 top_col;
uniform vec3 bottom_col;
void fragment() {
	COLOR = vec4(mix(top_col, bottom_col, UV.y), 1.0);
}
"""
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

	var to_shop := func() -> void: _goto(pages["shop"])
	var labels := {}
	for spec in [["coin", "coins", true], ["wheel", "spins", true], ["shield", "shields", false]]:
		var cap := Lagoon.capsule(spec[0], "0", to_shop if spec[2] else Callable())
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
	if spins < slot.bet:
		Sfx.play("error", -6.0)
		if spins > 0:
			_banner("Bet x%d needs %d spins!" % [slot.bet, slot.bet], Color(0.9, 0.4, 0.4))
		elif _ctx_offer_ready() and _popup == null:
			_offer_out_of_spins()
		else:
			_banner("Out of spins!  +%d refill every %d min." % [SPIN_REGEN_AMOUNT, int(SPIN_REGEN_SECS / 60.0)], Color(0.9, 0.4, 0.4))
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
	var tw := create_tween()
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
	if not _raiding():
		_maybe_drop_card()
		_maybe_revenge()
		_schedule_auto_spin()
	_refresh()
	_save_game()

# Raids that happened while the app was closed.
#
# The pool is not a set of dummies waiting to be robbed -- rivals come at you
# too, and the fact that they do while you are away is what makes a shield
# worth banking instead of spending. Kept deliberately light: one hit per
# ninety minutes offline, two at most, and an attack only ever knocks a star
# off a building that has one to spare. You never come back to rubble.
func _offline_raids() -> void:
	if _offline_elapsed < 1800.0 or npcs.is_empty():
		return
	var count := mini(2, int(_offline_elapsed / 5400.0))
	_offline_elapsed = 0.0
	if count <= 0:
		return
	var events := []
	for i in count:
		var npc: Dictionary = npcs.pick_random()
		var mode := "attack" if randf() < 0.45 else "steal"
		if shields > 0:
			shields -= 1
			events.append({"type": mode, "npc": npc,
				"text": "%s came for your island — your shield held" % npc["name"]})
			continue
		if mode == "attack":
			var standing := []
			for b in buildings.size():
				if int(buildings[b]) >= 2:
					standing.append(b)
			if not standing.is_empty():
				var hit: int = standing.pick_random()
				buildings[hit] = int(buildings[hit]) - 1
				var bname: String = CV.island_theme(island_level)["buildings"][hit]
				events.append({"type": "attack", "npc": npc,
					"text": "%s smashed your %s — down to %d\u2b50" % [npc["name"], bname, buildings[hit]]})
				continue
			mode = "steal"
		var stolen: int = mini(_scaled(500), int(coins * 0.08))
		coins -= stolen
		npc["coins"] = int(npc["coins"]) + int(round(stolen / maxf(_economy_mult(), 1.0)))
		events.append({"type": "steal", "npc": npc,
			"text": "%s raided your vault — %s coins" % [npc["name"], _fmt_compact(stolen)]})
	for e in events:
		_notify(e["type"], e["text"], e["npc"]["emoji"], false)
	var first: Dictionary = events[0]
	if events.size() == 1:
		_show_toast(first["text"], first["npc"]["emoji"])
	else:
		_show_toast("%d rivals hit your island while you were away" % events.size(), "🚨")
	_refresh()
	_save_game()

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
		npcs.append(next_target)
		taken.append(next_target["name"])
	for fresh in CV.draw_rivals(CV.RIVAL_POOL - npcs.size(), island_level, taken):
		npcs.append(fresh)

# --- island visits (steal / attack) ---

# True from the moment a raid is announced until its payout lands -- the search
# screen counts, so nothing auto-spins or changes page underneath it.
func _raiding() -> bool:
	return _visit != null or _match != null

# The card above the wheel is a promise: these are the coins at stake and this
# is whose they are. It is drawn before the spin and it does not move during
# one, so the raid can only ever land on the rival it named.
func _pick_next_target() -> void:
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
	if mode == "steal":
		if next_target.is_empty():
			_pick_next_target()
		if next_target.is_empty():
			return
		_raid_target = next_target
		_announce_raid(mode)
		var go := create_tween()
		go.tween_interval(0.5)
		go.tween_callback(_on_match_found.bind(next_target, mode))
		return

	var npc := _pick_attack_target()
	if npc.is_empty():
		return
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
func _pick_attack_target() -> Dictionary:
	if npcs.is_empty():
		_stock_rivals()
	var spared: String = next_target.get("name", "")
	var pool := []
	for n in npcs:
		if n.get("name", "") != spared:
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

# The search hands back the rival it was given, and that is the island we sail
# to -- _raid_target, not next_target, which by now is free to move on.
func _on_match_found(matched: Dictionary, mode: String) -> void:
	var m := _match
	_match = null
	_visit = IslandVisit.new()
	_visit.npc = matched
	_visit.mode = mode
	_visit.mult = _last_bet
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
	var v := _visit
	var vmult: int = v.mult
	_visit = null
	var tw := create_tween()
	tw.tween_property(v, "position", Vector2(-720, 0), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(v.queue_free)
	var npc: Dictionary = result["npc"]
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
		if result.get("blocked", false):
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
	var mult := pow(1.6, island_level - 1)
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
		if _ctx_offer_ready() and _popup == null:
			_offer_need_coins(cost - coins)
		return
	coins -= cost
	_refresh()
	_save_game()
	village.start_construction(index, level + 1, func() -> void:
		buildings[index] += 1
		# Worth the level it just reached, so upgrades get better the deeper you
		# go and a finished hut has paid out 15 over its life.
		var slot_rect: Rect2 = CV.SLOT_RECTS[index]
		_award_stars(buildings[index],
			village.global_position + (slot_rect.position + slot_rect.size * 0.4) * village.scale)
		_mission_add("builds")
		_check_island_complete()
		_refresh()
		_save_game()
	)

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
		island_level += 1
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
	var tw := create_tween()
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

func _save_game() -> void:
	if _preview_island:
		return
	var data := {
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
		"shop_free_last": shop_free_last,
		"piggy": piggy_coins,
		"offer_id": offer_id,
		"offer_until": offer_until,
		"offer_next": offer_next,
		"notif_enabled": notif_enabled,
		"notif_types": notif_types,
		"notif_log": notif_log,
		"ts": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data == null or typeof(data) != TYPE_DICTIONARY:
		return
	coins = int(data.get("coins", 1500))
	spins = int(data.get("spins", 30))
	shields = int(data.get("shields", 0))
	island_level = int(data.get("island_level", data.get("village_level", 1)))
	revenge_pending = bool(data.get("revenge", false))
	daily_last = float(data.get("daily_last", 0.0))
	muted = bool(data.get("muted", false))
	var lo = data.get("col_owned", {})
	if typeof(lo) == TYPE_DICTIONARY:
		col_owned = lo
	var ld = data.get("col_dupes", {})
	if typeof(ld) == TYPE_DICTIONARY:
		col_dupes = ld
	var lc = data.get("col_claimed", {})
	if typeof(lc) == TYPE_DICTIONARY:
		col_claimed = lc
	col_mega_claimed = bool(data.get("col_mega", false))
	col_deadline = float(data.get("col_deadline", 0.0))
	var lp = data.get("purchased", [])
	if typeof(lp) == TYPE_ARRAY:
		purchased_ids = lp
	shop_free_last = float(data.get("shop_free_last", 0.0))
	piggy_coins = int(data.get("piggy", 0))
	offer_id = String(data.get("offer_id", ""))
	offer_until = float(data.get("offer_until", 0.0))
	offer_next = float(data.get("offer_next", 0.0))
	notif_enabled = bool(data.get("notif_enabled", true))
	var nt = data.get("notif_types", {})
	if typeof(nt) == TYPE_DICTIONARY:
		for k in notif_types:
			notif_types[k] = bool(nt.get(k, true))
	var nl = data.get("notif_log", [])
	if typeof(nl) == TYPE_ARRAY:
		notif_log = []
		for entry in nl:
			if typeof(entry) == TYPE_DICTIONARY:
				notif_log.append(entry)
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
					prog[k] = int(pd[k])
					if legacy_coin_progress and k in MISSION_COIN_TARGETS:
						prog[k] = _scaled(int(pd[k]))
			var cl := {}
			var cd = pst.get("claimed", {})
			if typeof(cd) == TYPE_DICTIONARY:
				for k in cd:
					cl[k] = bool(cd[k])
			mission_state[period] = {"key": int(pst.get("key", -1)), "progress": prog, "claimed": cl, "bonus": bool(pst.get("bonus", false))}
	var b = data.get("buildings", [0, 0, 0, 0, 0])
	buildings = []
	for v in b:
		buildings.append(int(v))
	while buildings.size() < 5:
		buildings.append(0)
	# What this save can still prove it earned, rebuilt from the things that pay
	# stars and are themselves saved: every hut level standing on the island you
	# hold, a finished island's worth for each one behind you, and every card
	# you own. It is a floor, not a replay -- set and grand-prize bonuses are
	# not recoverable from a save that never wrote them down.
	var earned := 0
	for lv in buildings:
		var n := clampi(int(lv), 0, CV.MAX_STAR)
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
	stars = int(data["stars"]) if data.has("stars") else earned
	rank_stars = int(data["rank_stars"]) if data.has("rank_stars") else maxi(earned, stars)

	var elapsed := Time.get_unix_time_from_system() - float(data.get("ts", 0))
	if elapsed > 0 and spins < SPIN_CAP:
		var regen := int(elapsed / SPIN_REGEN_SECS) * SPIN_REGEN_AMOUNT
		if regen > 0:
			_offline_spins_gained = mini(regen, SPIN_CAP - spins)
			spins += _offline_spins_gained
	var loaded_npcs = data.get("npcs", [])
	npcs = []
	for n in loaded_npcs:
		var nb := []
		for v in n.get("buildings", [1, 1, 1, 1, 1]):
			nb.append(int(v))
		while nb.size() < 5:
			nb.append(1)
		npcs.append({
			"name": n.get("name", "Rival"),
			"emoji": n.get("emoji", "🧔"),
			"flag": n.get("flag", "??"),
			"coins": int(n.get("coins", 2000)) + mini(8000, int(maxf(elapsed, 0.0) / 60.0) * 15),
			"buildings": nb,
			"shield": bool(n.get("shield", false)),
			"island": int(n.get("island", randi_range(1, CV.ISLANDS.size()))),
		})
	_offline_elapsed = maxf(elapsed, 0.0)
