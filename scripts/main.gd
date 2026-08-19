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
var buildings := [0, 0, 0, 0, 0]
var revenge_pending := false
var npcs: Array = []
# Picked before the spin, not after it, so the pot on the machine's card is a
# promise rather than a decoration -- the coins you see are the coins at stake.
var next_target: Dictionary = {}

var slot_page: Control
var village_page: Control
var slot: SlotView
var village: VillageView
var _current_page: Control
var _visit: IslandVisit

var _hud_labels: Array = []
var _regen_accum := 0.0
var _transitioning := false

const DAILY_COOLDOWN := 300.0
var daily_last := 0.0
var muted := false
# Missions run in three reset cycles. "coins" is the base reward at island 1;
# actual payouts scale with the same 1.6^(level-1) curve as star costs, so a
# mission is always worth the same fraction of a building at any island.
const MISSION_DEFS := {
	"daily": [
		{"id": "spins", "emoji": "🌀", "desc": "Spin the wheel", "target": 15, "coins": 500},
		{"id": "coins_won", "emoji": "💰", "desc": "Win coins on spins", "target": 8000, "coins": 600},
		{"id": "attacks", "emoji": "🔨", "desc": "Attack rival islands", "target": 3, "coins": 800},
		{"id": "steals", "emoji": "🦝", "desc": "Steal from rivals", "target": 2, "coins": 700},
		{"id": "builds", "emoji": "🏗️", "desc": "Build star upgrades", "target": 2, "coins": 900},
		{"id": "daily_gift", "emoji": "🎁", "desc": "Claim the daily bonus", "target": 1, "spins": 5},
		{"id": "big_bet", "emoji": "🎯", "desc": "Spin at bet x2 or more", "target": 5, "coins": 550},
		{"id": "cards", "emoji": "🃏", "desc": "Find collection cards", "target": 2, "coins": 650},
	],
	"weekly": [
		{"id": "spins", "emoji": "🌀", "desc": "Spin the wheel", "target": 100, "coins": 2500},
		{"id": "coins_won", "emoji": "💰", "desc": "Win coins on spins", "target": 60000, "coins": 3000},
		{"id": "attacks", "emoji": "🔨", "desc": "Attack rival islands", "target": 15, "coins": 2800},
		{"id": "steals", "emoji": "🦝", "desc": "Steal from rivals", "target": 12, "coins": 2600},
		{"id": "builds", "emoji": "🏗️", "desc": "Build star upgrades", "target": 10, "coins": 3500},
		{"id": "daily_gift", "emoji": "🎁", "desc": "Claim 5 daily bonuses", "target": 5, "coins": 2200},
		{"id": "big_bet", "emoji": "🎯", "desc": "Spin at bet x2 or more", "target": 30, "coins": 2400},
		{"id": "cards", "emoji": "🃏", "desc": "Find collection cards", "target": 10, "coins": 2600},
	],
	"monthly": [
		{"id": "spins", "emoji": "🌀", "desc": "Spin the wheel", "target": 400, "coins": 8000},
		{"id": "coins_won", "emoji": "💰", "desc": "Win coins on spins", "target": 250000, "coins": 9000},
		{"id": "attacks", "emoji": "🔨", "desc": "Attack rival islands", "target": 50, "coins": 8500},
		{"id": "steals", "emoji": "🦝", "desc": "Steal from rivals", "target": 40, "coins": 8000},
		{"id": "builds", "emoji": "🏗️", "desc": "Build star upgrades", "target": 35, "coins": 10000},
		{"id": "islands", "emoji": "⛵", "desc": "Complete an island", "target": 1, "coins": 12000},
		{"id": "daily_gift", "emoji": "🎁", "desc": "Claim 20 daily bonuses", "target": 20, "coins": 7500},
	],
}
# Extra chest for claiming every mission in a cycle (coins scale like above).
const MISSION_BONUS := {
	"daily": {"emoji": "🎁", "coins": 1500, "spins": 10},
	"weekly": {"emoji": "🧰", "coins": 6000, "spins": 30},
	"monthly": {"emoji": "🏆", "coins": 15000, "spins": 60},
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
var _ui_tick := 0.0
var _shop_gift_timer_label: Label
var col_owned := {}
var col_claimed := {}
var col_mega_claimed := false
var col_deadline := 0.0
# The Cards tab is two screens behind one nav button: a shelf of six sets, and
# the set you tapped. Empty means the shelf.
var col_open := ""
var _col_back: Button

const NOTIF_LOG_MAX := 30
var notif_enabled := true
var notif_types := {"attack": true, "steal": true, "spins": true}
var notif_log := []
var _toast: Control
var _offline_spins_gained := 0
# DEMO_ISLAND=17 previews that island's theme without grinding to it. Saving is
# disabled while it's set so a preview can never overwrite real progress.
var _preview_island := false

func _ready() -> void:
	randomize()
	_setup_global_font_fallbacks()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_game()
	if OS.has_environment("DEMO_ISLAND"):
		var preview := int(OS.get_environment("DEMO_ISLAND"))
		if preview >= 1:
			island_level = preview
			_preview_island = true
	_ensure_missions()
	_update_badges()
	# The pages are built inside _setup_global_font_fallbacks(), which runs
	# above _load_game(), so they come up holding default state -- island 1's
	# art and starting counters. Re-apply now that the save is actually in.
	_apply_island_theme()
	_refresh()

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
	if npcs.is_empty():
		for def in CV.NPC_DEFS:
			npcs.append(CV.new_npc(def))
	_ensure_collections()
	_build_slot_page()
	_build_village_page()
	_build_menu_pages()
	village_page.visible = false
	_current_page = slot_page
	_build_nav()
	if muted:
		AudioServer.set_bus_mute(0, true)
	_apply_island_theme()
	_refresh()
	_update_badges()
	call_deferred("_check_island_complete")
	if _offline_spins_gained > 0:
		_notify("spins", "While you were away, spins refilled  +%d  (%d/%d)" % [_offline_spins_gained, spins, SPIN_CAP], "🌀")
		_offline_spins_gained = 0
	_load_profile()
	if profile.is_empty():
		_show_login()
	if OS.has_environment("DEMO_QUESTS"):
		var demo_tab := OS.get_environment("DEMO_QUESTS")
		if MISSION_DEFS.has(demo_tab):
			quests_tab = demo_tab
		call_deferred("_goto", pages["quests"])

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
	logo.offset_top = 240.0
	logo.offset_bottom = 330.0
	FX.pulse_forever(logo, 1.04, 2.2)

	var tagline := Lagoon.title("Spin · Raid · Build your island", UI.F_BODY, Color.WHITE, Lagoon.ABYSS)
	_login_layer.add_child(tagline)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tagline.offset_top = 336.0
	tagline.offset_bottom = 386.0

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_login_layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_left = 130.0
	box.offset_right = -130.0
	box.offset_top = 640.0

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
		if _shop_free_ready():
			# free gift may have just come off cooldown while playing
			if _badges.has("shop_free") and not _badges["shop_free"].visible:
				_update_badges()
				if _current_page == pages.get("shop"):
					_fill_page("shop")
		elif _shop_gift_timer_label != null and is_instance_valid(_shop_gift_timer_label):
			_shop_gift_timer_label.text = "⏳  Next gift in  %s" % _shop_free_countdown_text()
		if _current_page == pages.get("quests"):
			# roll missions over live if a cycle ends while the page is open
			if mission_state.get(quests_tab, {}).is_empty() or int(mission_state[quests_tab]["key"]) != _period_key(quests_tab):
				_ensure_missions()
				_fill_page("quests")
			else:
				_update_quests_timer()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()

# --- page transitions ---

func _page_rank(p: Control) -> int:
	if p == slot_page:
		return 0
	if p == village_page:
		return 1
	var order := ["shop", "collections", "quests", "options"]
	for i in order.size():
		if pages.get(order[i]) == p:
			return 2 + i
	return 0

func _goto(target: Control) -> void:
	if _transitioning or target == _current_page or _visit != null or _journey_layer != null:
		return
	if target != pages.get("collections"):
		col_open = ""
	for key in pages:
		if pages[key] == target:
			_fill_page(key)
	_transitioning = true
	Sfx.play("pop", -10.0)
	var from := _current_page
	_current_page = target
	target.visible = true
	var dir := 1.0 if _page_rank(target) > _page_rank(from) else -1.0
	target.position = Vector2(720.0 * dir, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(from, "position", Vector2(-720.0 * dir, 0), 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
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

# --- bottom navigation bar ---

var _nav_tabs := {}
var _spin_nav: Button
var _spin_glow: ColorRect
var _float_options: Button

const NAV_BAR_H := 118.0
const NAV_ROOT_H := 152.0

func _build_nav() -> void:
	var nav_root := Control.new()
	nav_root.z_index = 50
	nav_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nav_root)
	nav_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav_root.offset_top = -NAV_ROOT_H

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

		# Coral bar over the active tab. Coral means "this is the live one"
		# here for the same reason it means "tap this" on a button.
		var pill := Panel.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Lagoon.CORAL
		psb.set_corner_radius_all(4)
		pill.add_theme_stylebox_override("panel", psb)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.visible = false
		btn.add_child(pill)
		pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		pill.offset_left = -26.0
		pill.offset_right = 26.0
		pill.offset_top = 5.0
		pill.offset_bottom = 13.0

		var icon := Glyph.new()
		icon.kind = t[0]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.resized.connect(func() -> void: icon.pivot_offset = icon.size * 0.5)
		btn.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		icon.offset_top = 16.0
		icon.offset_bottom = 84.0

		var cap := Lagoon.label(t[1], UI.F_CAPTION, Lagoon.INK_SOFT, true)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cap)
		cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		cap.offset_top = -58.0
		cap.offset_bottom = -24.0

		if key == "island":
			btn.pressed.connect(func() -> void: _goto(village_page))
		else:
			btn.pressed.connect(func() -> void: _goto(pages[key]))

		_nav_tabs[key] = {"button": btn, "icon": icon, "cap": cap, "pill": pill}

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
	spin_icon.offset_left = 30.0
	spin_icon.offset_right = -30.0
	spin_icon.offset_top = 16.0
	spin_icon.offset_bottom = 88.0

	var spin_cap := Lagoon.title("SPIN", UI.F_LABEL, Lagoon.SAND, Lagoon.CORAL_LO)
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
	_float_options.position = Vector2(720 - 14 - 66, 96)
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
	badge.offset_left = 14.0
	badge.offset_right = 44.0
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
		var target := Vector2(1.22, 1.22) if is_active else Vector2.ONE
		icon.create_tween().tween_property(icon, "scale", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Inactive tabs wash out toward the glass rather than dimming to grey --
		# on a light bar, "further away" reads better than "switched off".
		icon.modulate = Color.WHITE if is_active else Color(1, 1, 1, 0.45)
		(tab["cap"] as Label).add_theme_color_override("font_color", Lagoon.INK if is_active else Lagoon.INK_SOFT)
		tab["pill"].visible = is_active
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
			randf_range(6, 62) if i % 2 == 0 else randf_range(600, 664),
			randf_range(196, 292))
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
	glow.size = Vector2(800, 700)
	glow.position = Vector2(-40, 372)
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
	logo.offset_top = 92.0
	logo.offset_bottom = 172.0
	FX.pulse_forever(logo, 1.03, 2.4)
	_slot_logo = logo

	slot = SlotView.new()
	slot_page.add_child(slot)
	slot.position = Vector2(0, 316)
	slot.size = Vector2(720, 812)
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
	row.offset_top = 184.0
	row.offset_bottom = 306.0
	_side_button(row, "gift", "Daily", "daily", _open_daily)
	_side_button(row, "bell", "Alerts", "alerts", _open_alerts)
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
	_badges["daily"].visible = _daily_ready()
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
		_badges["shop_free"].visible = _shop_free_ready()

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

# Payouts track the star-cost curve so missions stay worth doing at any island.
func _mission_mult() -> float:
	return pow(1.6, island_level - 1)

func _mission_coins(m: Dictionary) -> int:
	var base := int(m.get("coins", 0))
	if base <= 0:
		return 0
	return int(round(base * _mission_mult() / 10.0)) * 10

func _bonus_coins(period: String) -> int:
	return int(round(int(MISSION_BONUS[period]["coins"]) * _mission_mult() / 10.0)) * 10

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
	return int(st["progress"].get(m["id"], 0)) >= int(m["target"])

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
		claim.text = "CLAIM  +800 coins, +5 spins"
		claim.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
		_candy_button(claim, Color(0.45, 0.75, 0.35))
		FX.press_feedback(claim)
		claim.pressed.connect(func() -> void:
			daily_last = Time.get_unix_time_from_system()
			coins += 800
			# rewards always add — the cap only limits time-based regen
			spins += 5
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
		var left := int(DAILY_COOLDOWN - (Time.get_unix_time_from_system() - daily_last))
		var info := _popup_row_label("Next bonus in %02d:%02d" % [left / 60, left % 60])
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
		FX.rise_label(self, Vector2(270, 560), "+%s" % _fmt(coin_amt), Color(1.0, 0.85, 0.3), 36)
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
	tw.tween_property(panel, "position:y", 78.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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

func _open_alerts() -> void:
	var vbox := _open_popup("Notifications")
	if notif_log.is_empty():
		var empty := _popup_row_label("No notifications yet — you're all caught up!", UI.F_CAPTION)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Lagoon.INK_SOFT)
		vbox.add_child(empty)
	else:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(0, minf(520.0, notif_log.size() * 78.0))
		vbox.add_child(sc)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		sc.add_child(list)
		for entry in notif_log:
			var unread: bool = not bool(entry.get("read", true))
			var card := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.95) if unread else Color(1, 1, 1, 0.62)
			sb.set_corner_radius_all(14)
			sb.set_border_width_all(2)
			sb.border_color = Lagoon.BRASS if unread else Color(Lagoon.INK_FAINT.r, Lagoon.INK_FAINT.g, Lagoon.INK_FAINT.b, 0.3)
			sb.content_margin_left = 12.0
			sb.content_margin_right = 12.0
			sb.content_margin_top = 8.0
			sb.content_margin_bottom = 8.0
			card.add_theme_stylebox_override("panel", sb)
			list.add_child(card)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			card.add_child(row)
			row.add_child(_emoji_label(str(entry.get("emoji", "🔔")), 26))
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 2)
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
		for entry in notif_log:
			entry["read"] = true
		_update_badges()
		_save_game()

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)
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
			_open_alerts()
		)
		btn_row.add_child(clear)
	var settings := Button.new()
	settings.text = "Settings"
	settings.custom_minimum_size = Vector2(0, UI.TAP)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_candy_button(settings, Color(0.55, 0.45, 0.65))
	FX.press_feedback(settings)
	settings.pressed.connect(func() -> void:
		_close_popup()
		_goto(pages["options"])
	)
	btn_row.add_child(settings)

# --- full menu pages (shop / collections / quests / options) ---

func _build_menu_pages() -> void:
	for spec in [["shop", "Shop"], ["collections", "Cards"], ["quests", "Quests"], ["options", "Options"]]:
		_make_page(spec[0], spec[1])
	# Parented to the page rather than the scrolling body, so it stays put when
	# a long set is scrolled -- a back button you have to scroll up to find is
	# a back button the player uses the system gesture instead of.
	_col_back = Button.new()
	_col_back.custom_minimum_size = Vector2(158, 64)
	_col_back.size = Vector2(158, 64)
	_col_back.focus_mode = Control.FOCUS_NONE
	_col_back.text = "\u25C0   BACK"
	_col_back.add_theme_font_size_override("font_size", UI.F_LABEL)
	Lagoon.button(_col_back, "brass", 32)
	FX.press_feedback(_col_back)
	_col_back.visible = false
	_col_back.pressed.connect(func() -> void:
		col_open = ""
		_fill_page("collections")
	)
	pages["collections"].add_child(_col_back)
	_col_back.position = Vector2(16, 115)

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
	plate.offset_top = 104.0
	plate.offset_bottom = 104.0 + 86.0

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(sc)
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 16.0
	sc.offset_right = -16.0
	sc.offset_top = 208.0
	sc.offset_bottom = -(NAV_ROOT_H + 6.0)

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
		"options": _fill_options(vb)

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

	# one-time starter offer hero banner
	if not purchased_ids.has(CV.STARTER_PACK["id"]):
		_shop_hero_offer(vb)

	_shop_section(vb, "🗝️", "TREASURE  CHESTS")
	var chest_row := HBoxContainer.new()
	chest_row.add_theme_constant_override("separation", 10)
	vb.add_child(chest_row)
	for pack in CV.CHEST_PACKS:
		_chest_card(chest_row, pack)
	vb.add_child(_page_note("Pricier chests hold more cards and better odds for ★★★★★ legendaries", UI.F_TINY))

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
		_shop_tile(cgrid, pack, Color(1.0, 0.78, 0.25), "%s  COINS" % _fmt(int(pack["coins"])))

	_shop_section(vb, "🎁", "FREE  GIFT")
	_free_gift_card(vb)

	vb.add_child(_page_note("Prototype store — purchases are simulated, no real charges.", UI.F_TINY))

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
	var sub := _popup_row_label(pack["sub"], UI.F_CAPTION)
	sub.add_theme_color_override("font_color", Lagoon.INK_SOFT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var once := Lagoon.label("One time only!", UI.F_TINY, Lagoon.CORAL_LO, true)
	col.add_child(once)

	var buy := Button.new()
	buy.text = pack["price"]
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
	odds.text = "5★ GUARANTEED" if guaranteed else ("boosted odds" if int(pack["tier"]) == 1 else "common loot")
	odds.add_theme_font_size_override("font_size", UI.F_TINY)
	odds.add_theme_color_override("font_color", Lagoon.BRASS_LO if guaranteed else Lagoon.INK_FAINT)
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(odds)
	if guaranteed:
		FX.pulse_forever(odds, 1.08, 1.2)

	var buy := Button.new()
	buy.text = pack["price"]
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

	var buy := Button.new()
	buy.text = pack["price"]
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
	var sub := _popup_row_label("Every 24h:  +%s coins,  +%d spins  &  a card" % [_fmt(CV.SHOP_FREE_COINS), CV.SHOP_FREE_SPINS], UI.F_CAPTION)
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
	coins += CV.SHOP_FREE_COINS
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
	_show_chest_result([card], "Free Gift!", "+%s coins    +%d spins" % [_fmt(CV.SHOP_FREE_COINS), CV.SHOP_FREE_SPINS], completed)
	_update_badges()
	_refresh()
	_save_game()
	if _current_page == pages.get("shop"):
		_fill_page("shop")

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
	var sub := _popup_row_label(pack["sub"], UI.F_CAPTION)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	vbox.add_child(sub)
	var note := _popup_row_label("Prototype — simulated purchase, no real charge.", UI.F_TINY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Lagoon.INK_FAINT)
	vbox.add_child(note)
	var pay := Button.new()
	pay.text = "PAY  %s" % pack["price"]
	pay.custom_minimum_size = Vector2(0, UI.TAP_COMFY)
	_candy_button(pay, Color(0.28, 0.68, 0.34))
	FX.press_feedback(pay)
	pay.pressed.connect(func() -> void:
		_close_popup()
		_grant_pack(pack)
	)
	vbox.add_child(pay)

func _grant_pack(pack: Dictionary) -> void:
	if pack.get("once", false):
		purchased_ids.append(pack["id"])
	spins += int(pack.get("spins", 0))
	coins += int(pack.get("coins", 0))
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
	# mostly random draws (duplicates are the norm), with a small pity
	# bias toward missing cards so progress never fully stalls
	var pick: Array = missing.pick_random() if not missing.is_empty() and randf() < 0.25 else pool.pick_random()
	var chosen: Dictionary = pick[0]
	var idx: int = pick[1]
	var it: Array = chosen["items"][idx]
	var owned: Array = col_owned[chosen["id"]]
	if owned[idx]:
		var refund := 60 * star
		coins += refund
		return {"emoji": it[0], "name": it[1], "set": chosen["name"], "stars": star, "dup": true, "refund": refund}
	owned[idx] = true
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
			status.text = "dup  +%d" % int(card.get("refund", 0))
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
	rrow.add_child(_reward_chip("💰", "+%s" % _fmt(_bonus_coins(quests_tab)), Lagoon.BRASS_LO))
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
	var prog := mini(int(st["progress"].get(id, 0)), int(m["target"]))
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
	pb.max_value = int(m["target"])
	pb.value = prog
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(pb)
	prow.add_child(Lagoon.label("%s/%s" % [_fmt(prog), _fmt(int(m["target"]))], UI.F_TINY, Lagoon.INK_SOFT))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	var spin_r := int(m.get("spins", 0))
	if spin_r > 0:
		right.add_child(_reward_chip("🌀", "+%d" % spin_r, Lagoon.LAGOON_DEEP))
	else:
		right.add_child(_reward_chip("🪙", "+%s" % _fmt(_mission_coins(m)), Lagoon.BRASS_LO))
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
		col_claimed = {}
		col_mega_claimed = false
		col_deadline = now + CV.COLLECTION_SEASON_DAYS * 86400.0
	for c in CV.COLLECTIONS:
		var id: String = c["id"]
		var n: int = (c["items"] as Array).size()
		var arr: Array = col_owned.get(id, [])
		var norm := []
		for i in n:
			norm.append(bool(arr[i]) if i < arr.size() else false)
		col_owned[id] = norm
		col_claimed[id] = bool(col_claimed.get(id, false))

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
		coins += 100
		_banner("Duplicate card — +100 coins", Color(0.75, 0.78, 0.9), it[0])
	else:
		owned[idx] = true
		Sfx.play("levelup", -8.0)
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
func _collection_item_card(emoji: String, iname: String, owned: bool, stars := 0, big := false) -> Control:
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
	if stars > 0:
		var sr := _star_row(stars, UI.F_CAPTION if big else UI.F_TINY)
		sr.modulate = Color(1, 1, 1, 1.0) if owned else Color(1, 1, 1, 0.4)
		col.add_child(sr)
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
	if _col_back != null:
		_col_back.visible = not col_open.is_empty()
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

	vb.add_child(_page_note("Every spin has a chance to drop a card!", UI.F_CAPTION))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for c in CV.COLLECTIONS:
		grid.add_child(_collection_tile(c))

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
		grid.add_child(_collection_item_card(it[0], it[1], i < owned.size() and owned[i], int(it[2]), true))

func _claim_collection(c: Dictionary) -> void:
	var id: String = c["id"]
	if col_claimed.get(id, false) or not _collection_complete(c):
		return
	col_claimed[id] = true
	var won := int(c["reward_spins"])
	spins += won
	Sfx.play("jackpot", -2.0)
	FX.confetti(self, 40)
	FX.flash(self)
	FX.fly_coins(self, Vector2(360, 640), _hud_labels[0]["spins"].global_position,
		clampi(won / 120, 6, 12), "bolt", "🌀")
	_banner("%s reward:  +%s spins" % [c["name"], _fmt(won)], Color(0.6, 0.9, 1.0), c["icon"])
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
	Sfx.play("levelup", -2.0)
	FX.confetti(self, 80)
	FX.flash(self)
	FX.fly_coins(self, Vector2(360, 620), _hud_labels[0]["spins"].global_position,
		18, "bolt", "🌀")
	_banner("GRAND PRIZE!  +%s spins!" % _fmt(CV.COLLECTION_MEGA_SPINS), Color(0.6, 0.9, 1.0), "🏆")
	_update_badges()
	_refresh()
	_save_game()
	_fill_page("collections")

func _open_ranks() -> void:
	var vbox := _open_popup("Leaderboard")
	var rows := []
	rows.append({"name": profile.get("name", "You"), "emoji": "😎", "coins": coins, "me": true})
	for n in npcs:
		rows.append({"name": n["name"], "emoji": n["emoji"], "coins": int(n["coins"]), "me": false})
	rows.sort_custom(func(a, b) -> bool: return a["coins"] > b["coins"])
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
		var c := _popup_row_label(str(r["coins"]))
		if r["me"]:
			c.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		row.add_child(c)

func _build_village_page() -> void:
	village_page = Control.new()
	add_child(village_page)
	village_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_village_bg = _add_background(village_page, "village", Color(0.55, 0.8, 0.95), Color(0.45, 0.75, 0.5))

	# The island's name on a brass nameplate, the same object the menu pages and
	# the machine's marquee use -- so "where am I" is answered by one shape
	# everywhere it is asked.
	var name_plate := Lagoon.plaque("Island", 420.0, 76.0, UI.F_SUBHEAD)
	village_page.add_child(name_plate)
	name_plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	name_plate.offset_left = -210.0
	name_plate.offset_right = 210.0
	name_plate.offset_top = 100.0
	name_plate.offset_bottom = 176.0
	_island_title = name_plate.get_meta("label")

	village = VillageView.new()
	village_page.add_child(village)
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
	bar.offset_top = 16.0
	bar.offset_bottom = 16.0 + 70.0

	var to_shop := func() -> void: _goto(pages["shop"])
	var labels := {}
	for spec in [["coin", "coins", true], ["wheel", "spins", true], ["shield", "shields", false]]:
		var cap := Lagoon.capsule(spec[0], "0", to_shop if spec[2] else Callable())
		bar.add_child(cap["root"])
		labels[spec[1]] = cap["value"]

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)

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
		if not auto_spin or _current_page != slot_page or _visit != null or _popup != null or slot.is_spinning():
			return
		if spins < slot.bet:
			auto_spin = false
			slot.set_auto(false)
			_banner("Auto spin stopped — out of spins", Color(0.9, 0.55, 0.4))
			return
		_on_spin_requested()
	)

func _on_spin_requested() -> void:
	if slot.is_spinning() or _visit != null:
		return
	if spins < slot.bet:
		Sfx.play("error", -6.0)
		if spins > 0:
			_banner("Bet x%d needs %d spins!" % [slot.bet, slot.bet], Color(0.9, 0.4, 0.4))
		else:
			_banner("Out of spins!  +%d refill every %d min." % [SPIN_REGEN_AMOUNT, int(SPIN_REGEN_SECS / 60.0)], Color(0.9, 0.4, 0.4))
		return
	_last_bet = slot.bet
	spins -= _last_bet
	Sfx.play("pop", -8.0)
	_mission_add("spins")
	if _last_bet >= 2:
		_mission_add("big_bet")
	_refresh()
	slot.start_spin(_roll())

# big win amount floating above the slot machine
func _show_win(text: String, color := Color(1.0, 0.85, 0.3)) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 50)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.02))
	l.add_theme_constant_override("outline_size", 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 100
	l.size = Vector2(720, 70)
	l.position = Vector2(0, 812)
	l.pivot_offset = Vector2(360, 35)
	l.scale = Vector2(0.3, 0.3)
	slot_page.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.75)
	tw.tween_property(l, "position:y", 758.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)

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
				_show_win("+SHIELD", Color(0.5, 0.75, 1.0))
			"bolt":
				slot.announce("+SPINS!", Color(0.72, 0.94, 1.0))
				var bonus := 12 * bet
				spins += bonus
				Sfx.play("jackpot", -4.0)
				_show_win("+%d  SPINS" % bonus, Color(0.6, 0.9, 1.0))
	else:
		for s in result:
			match s:
				"coin": gain += 100 * bet
				"bag": gain += 400 * bet
				"gem": gain += 250 * bet
		if gain > 0:
			Sfx.play("coins", -6.0)
	if gain > 0:
		coins += gain
		_mission_add("coins_won", gain)
		_show_win("+%s" % _fmt(gain))
		FX.fly_coins(self, Vector2(360, 716), _hud_labels[0]["coins"].global_position, clampi(gain / 250, 3, 9))
	if _visit == null:
		_maybe_drop_card()
		_maybe_revenge()
		_schedule_auto_spin()
	_refresh()
	_save_game()

func _maybe_revenge() -> void:
	if not revenge_pending:
		return
	revenge_pending = false
	var npc: Dictionary = npcs.pick_random()
	var mode := "attack" if randf() < 0.5 else "steal"
	if shields > 0:
		shields -= 1
		Sfx.play("shield", -4.0)
		var verb := "attacked" if mode == "attack" else "tried to steal"
		var blocked_txt := "%s %s — blocked by your shield!" % [npc["name"], verb]
		if not _notify(mode, blocked_txt, npc["emoji"]):
			_banner(blocked_txt, Color(0.5, 0.75, 1.0), npc["emoji"])
	else:
		var stolen: int = mini(500, int(coins * 0.1))
		coins -= stolen
		Sfx.play("attack", -4.0)
		FX.shake(slot_page, 10.0, 6)
		var hit_txt: String
		if mode == "attack":
			hit_txt = "%s raided your island!  -%d coins" % [npc["name"], stolen]
		else:
			hit_txt = "%s stole %d coins from you!" % [npc["name"], stolen]
		if not _notify(mode, hit_txt, npc["emoji"]):
			_banner(hit_txt, Color(0.95, 0.4, 0.4), npc["emoji"])

# --- island visits (steal / attack) ---

func _pick_next_target() -> void:
	if npcs.is_empty():
		return
	next_target = npcs.pick_random()
	if slot != null:
		slot.set_target(next_target)

func _start_visit(mode: String) -> void:
	var npc: Dictionary = next_target if not next_target.is_empty() else npcs.pick_random()
	if mode == "attack":
		npc["shield"] = randf() < 0.3
	_visit = IslandVisit.new()
	_visit.npc = npc
	_visit.mode = mode
	_visit.mult = _last_bet
	_visit.finished.connect(_on_visit_finished)
	add_child(_visit)
	_visit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visit.position = Vector2(720, 0)
	Sfx.play("jackpot", -6.0)
	slot.announce("STEAL!" if mode == "steal" else "ATTACK!", Lagoon.CORAL_HI)
	_banner("Triple %s!" % ("raccoons — STEAL time!" if mode == "steal" else "hammers — ATTACK!"), Color(1.0, 0.85, 0.3))
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(_visit, "position", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_visit_finished(result: Dictionary) -> void:
	var v := _visit
	var vmult: int = v.mult
	_visit = null
	var tw := create_tween()
	tw.tween_property(v, "position", Vector2(-720, 0), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(v.queue_free)
	var npc: Dictionary = result["npc"]
	_mission_add("steals" if result["mode"] == "steal" else "attacks")
	_pick_next_target()
	if result["mode"] == "steal":
		var stolen: int = result.get("stolen", 0)
		coins += stolen
		npc["coins"] = maxi(200, int(npc["coins"]) - stolen)
		if stolen > 0:
			_banner("You stole %s coins from %s!" % [_fmt(stolen), npc["name"]], Color(1.0, 0.85, 0.3), npc["emoji"])
			_show_win("+%s" % _fmt(stolen))
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
			var reward := (400 + island_level * 150 + randi_range(0, 200)) * vmult
			coins += reward
			FX.fly_coins(self, Vector2(360, 500), _hud_labels[0]["coins"].global_position, 6)
			_banner("SMASH!  +%s coins" % _fmt(reward), Color(1.0, 0.85, 0.3), npc["emoji"])
			_show_win("+%s" % _fmt(reward))
		if randf() < 0.35:
			revenge_pending = true
	_refresh()
	_save_game()
	_schedule_auto_spin(1.4)

# --- village / island ---

func _apply_island_theme() -> void:
	village.set_island(island_level)
	var bg_t := CV.island_bg_tex(island_level)
	if _village_bg != null and bg_t != null:
		_village_bg.texture = bg_t
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
		return
	coins -= cost
	_refresh()
	_save_game()
	village.start_construction(index, func() -> void:
		buildings[index] += 1
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

	var reward := _popup_row_label("Journey rewards:  💰 +%s   🌀 +%d" % [_fmt(ISLAND_REWARD_COINS), ISLAND_REWARD_SPINS], UI.F_CAPTION)
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
		_mission_add("islands")
		buildings = [0, 0, 0, 0, 0]
		coins += ISLAND_REWARD_COINS
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
	welcome.offset_top = 190.0
	welcome.offset_bottom = 250.0

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
		_banner("Welcome to %s!  +%s coins, +%d spins" % [CV.island_theme(to_level)["name"], _fmt(ISLAND_REWARD_COINS), ISLAND_REWARD_SPINS], Color(1.0, 0.85, 0.3))
	)

# --- shared UI ---

func _refresh() -> void:
	for labels in _hud_labels:
		labels["coins"].text = _fmt_compact(coins)
		labels["spins"].text = ("%d/%d" % [spins, SPIN_CAP]) if spins <= SPIN_CAP else str(spins)
		labels["shields"].text = str(shields)
		labels["island"].text = str(island_level)
	village.refresh(buildings, coins, _star_costs())
	if slot != null:
		slot.set_meter(spins, SPIN_CAP, SPIN_REGEN_SECS - _regen_accum, SPIN_REGEN_AMOUNT)
		slot.set_target(next_target)

func _banner(text: String, color: Color, emoji := "") -> void:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = 110
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 150.0
	box.offset_bottom = 210.0
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
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out

# Coins run to eight digits late in the game, which would blow the HUD capsule
# out past the island marker. Full precision stays everywhere it's being spent
# or awarded; only the always-on counter abbreviates.
func _fmt_compact(n: int) -> String:
	if n >= 100_000_000:
		return "%.0fM" % (n / 1_000_000.0)
	if n >= 10_000_000:
		return "%.1fM" % (n / 1_000_000.0)
	if n >= 1_000_000:
		return "%.2fM" % (n / 1_000_000.0)
	return _fmt(n)

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
		"shields": shields,
		"island_level": island_level,
		"buildings": buildings,
		"revenge": revenge_pending,
		"npcs": npcs,
		"daily_last": daily_last,
		"muted": muted,
		"missions2": mission_state,
		"col_owned": col_owned,
		"col_claimed": col_claimed,
		"col_mega": col_mega_claimed,
		"col_deadline": col_deadline,
		"purchased": purchased_ids,
		"shop_free_last": shop_free_last,
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
	var lc = data.get("col_claimed", {})
	if typeof(lc) == TYPE_DICTIONARY:
		col_claimed = lc
	col_mega_claimed = bool(data.get("col_mega", false))
	col_deadline = float(data.get("col_deadline", 0.0))
	var lp = data.get("purchased", [])
	if typeof(lp) == TYPE_ARRAY:
		purchased_ids = lp
	shop_free_last = float(data.get("shop_free_last", 0.0))
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
	var lm = data.get("missions2", {})
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
			"coins": int(n.get("coins", 2000)) + mini(8000, int(maxf(elapsed, 0.0) / 60.0) * 15),
			"buildings": nb,
			"shield": bool(n.get("shield", false)),
			"island": int(n.get("island", randi_range(1, CV.ISLANDS.size()))),
		})
