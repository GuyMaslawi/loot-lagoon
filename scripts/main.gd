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

const NOTIF_LOG_MAX := 30
var notif_enabled := true
var notif_types := {"attack": true, "steal": true, "spins": true}
var notif_log := []
var _toast: Control
var _offline_spins_gained := 0

func _ready() -> void:
	randomize()
	_setup_global_font_fallbacks()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_game()
	_ensure_missions()
	_update_badges()

# On iOS the default theme font can't reach system emoji/symbol fonts,
# so glyphs like ★ and inline emoji render blank. Chain bundled fonts
# (DejaVu for symbols, Noto for color emoji) behind the default font.
func _setup_global_font_fallbacks() -> void:
	var extra: Array[Font] = []
	var deja := CV.tex_font("res://assets/fonts/DejaVuSans.ttf")
	if deja != null:
		extra.append(deja)
	var noto := CV.tex_font("res://assets/fonts/NotoColorEmoji.ttf")
	if noto != null:
		extra.append(noto)
	if extra.is_empty():
		return
	var base := ThemeDB.fallback_font
	var v := FontVariation.new()
	v.base_font = base
	v.fallbacks = extra
	ThemeDB.fallback_font = v
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

	var bg := ColorRect.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec3 top = vec3(0.12, 0.07, 0.22);
	vec3 bottom = vec3(0.04, 0.02, 0.1);
	COLOR = vec4(mix(top, bottom, UV.y), 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_login_layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var coin_t := CV.symbol_tex("coin")
	if coin_t != null:
		for i in 6:
			var tr := TextureRect.new()
			tr.texture = coin_t
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var s := randf_range(50, 110)
			tr.size = Vector2(s, s)
			tr.position = Vector2(randf_range(20, 630), randf_range(80, 1150))
			tr.modulate = Color(1, 1, 1, randf_range(0.15, 0.35))
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_login_layer.add_child(tr)
			FX.float_bob(tr, randf_range(12, 28), randf_range(2.0, 3.6))

	var logo := Label.new()
	logo.text = "LOOT  LAGOON"
	logo.add_theme_font_size_override("font_size", 58)
	logo.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
	logo.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0.05))
	logo.add_theme_constant_override("outline_size", 16)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_login_layer.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 240.0
	logo.offset_bottom = 330.0
	FX.pulse_forever(logo, 1.05, 2.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_login_layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(130, 560)
	box.size = Vector2(460, 400)

	var g_btn := Button.new()
	g_btn.text = "Sign in with Google"
	g_btn.custom_minimum_size = Vector2(460, 66)
	_candy_button(g_btn, Color(0.92, 0.92, 0.92))
	g_btn.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25))
	g_btn.add_theme_color_override("font_hover_color", Color(0.2, 0.2, 0.25))
	g_btn.add_theme_color_override("font_pressed_color", Color(0.2, 0.2, 0.25))
	g_btn.add_theme_constant_override("outline_size", 0)
	FX.press_feedback(g_btn)
	g_btn.pressed.connect(_login_google)
	box.add_child(g_btn)

	var f_btn := Button.new()
	f_btn.text = "Continue with Facebook"
	f_btn.custom_minimum_size = Vector2(460, 66)
	_candy_button(f_btn, Color(0.23, 0.35, 0.6))
	FX.press_feedback(f_btn)
	f_btn.pressed.connect(func() -> void:
		_banner("Facebook login requires a Facebook Developer app — coming soon", Color(0.7, 0.8, 1.0))
	)
	box.add_child(f_btn)

	var guest := Button.new()
	guest.text = "Play as Guest"
	guest.custom_minimum_size = Vector2(460, 58)
	_candy_button(guest, Color(0.45, 0.4, 0.55))
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

	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.155, 0.985)
	sb.corner_radius_top_left = 26
	sb.corner_radius_top_right = 26
	sb.border_width_top = 1
	sb.border_color = Color(1, 1, 1, 0.09)
	sb.shadow_size = 16
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_offset = Vector2(0, -4)
	bar.add_theme_stylebox_override("panel", sb)
	nav_root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_top = NAV_ROOT_H - NAV_BAR_H

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	nav_root.add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_top = NAV_ROOT_H - NAV_BAR_H

	var tabs := [
		["🏝️", "Island", "island", 1.0],
		["🛒", "Shop", "shop", 1.0],
		null,  # gap under the raised center Spin button
		["🃏", "Cards", "collections", 1.0],
		["📜", "Quests", "quests", 1.0],
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
		btn.size_flags_stretch_ratio = t[3]
		btn.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		hb.add_child(btn)
		FX.press_feedback(btn)

		var pill := Panel.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(1.0, 0.8, 0.3)
		psb.set_corner_radius_all(3)
		pill.add_theme_stylebox_override("panel", psb)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.visible = false
		btn.add_child(pill)
		pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		pill.offset_left = -22.0
		pill.offset_right = 22.0
		pill.offset_top = 6.0
		pill.offset_bottom = 12.0

		var icon := Label.new()
		icon.text = t[0]
		icon.add_theme_font_override("font", CV.emoji_font())
		icon.add_theme_font_size_override("font_size", 50)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.resized.connect(func() -> void: icon.pivot_offset = icon.size * 0.5)
		btn.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		icon.offset_top = 14.0
		icon.offset_bottom = 78.0

		var cap := Label.new()
		cap.text = t[1]
		cap.add_theme_font_size_override("font_size", 17)
		cap.add_theme_color_override("font_color", Color(0.6, 0.64, 0.78))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cap)
		cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		cap.offset_top = -36.0
		cap.offset_bottom = -10.0

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
	COLOR = vec4(1.0, 0.75, 0.3, a);
}
"""
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = glow_sh
	_spin_glow.material = glow_mat
	_spin_glow.size = Vector2(214, 214)
	_spin_glow.position = Vector2(360 - 107, -42)
	_spin_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_root.add_child(_spin_glow)

	_spin_nav = Button.new()
	_spin_nav.size = Vector2(132, 132)
	_spin_nav.position = Vector2(360 - 66, 0)
	_spin_nav.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var csb := StyleBoxFlat.new()
		match state:
			"hover":
				csb.bg_color = Color(1.0, 0.78, 0.28)
			"pressed":
				csb.bg_color = Color(0.92, 0.62, 0.12)
			_:
				csb.bg_color = Color(1.0, 0.72, 0.18)
		csb.set_corner_radius_all(66)
		csb.set_border_width_all(4)
		csb.border_color = Color(1.0, 0.92, 0.6)
		csb.shadow_size = 12
		csb.shadow_color = Color(1.0, 0.6, 0.1, 0.4)
		_spin_nav.add_theme_stylebox_override(state, csb)
	_spin_nav.pressed.connect(func() -> void: _goto(slot_page))
	nav_root.add_child(_spin_nav)

	var spin_icon := Label.new()
	spin_icon.text = "🎰"
	spin_icon.add_theme_font_override("font", CV.emoji_font())
	spin_icon.add_theme_font_size_override("font_size", 56)
	spin_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin_nav.add_child(spin_icon)
	spin_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	spin_icon.offset_top = 16.0
	spin_icon.offset_bottom = 88.0

	var spin_cap := Label.new()
	spin_cap.text = "SPIN"
	spin_cap.add_theme_font_size_override("font_size", 18)
	spin_cap.add_theme_color_override("font_color", Color(0.35, 0.18, 0.02))
	spin_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin_nav.add_child(spin_cap)
	spin_cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	spin_cap.offset_top = -44.0
	spin_cap.offset_bottom = -16.0

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

	_float_options = Button.new()
	_float_options.size = Vector2(76, 76)
	_float_options.position = Vector2(720 - 16 - 76, 76)
	_float_options.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.08, 0.15, 0.88) if state != "hover" else Color(0.2, 0.14, 0.24, 0.92)
		sb.set_corner_radius_all(38)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.95, 0.75, 0.25)
		sb.shadow_size = 8
		sb.shadow_color = Color(0, 0, 0, 0.35)
		_float_options.add_theme_stylebox_override(state, sb)
	_float_options.text = "⚙️"
	_float_options.add_theme_font_override("font", CV.emoji_font())
	_float_options.add_theme_font_size_override("font_size", 38)
	_float_options.pressed.connect(func() -> void: _goto(pages["options"]))
	FX.press_feedback(_float_options)
	layer.add_child(_float_options)

func _nav_badge(parent: Control, text := "!") -> Panel:
	var badge := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.92, 0.2, 0.25)
	bsb.set_corner_radius_all(15)
	bsb.set_border_width_all(2)
	bsb.border_color = Color.WHITE
	badge.add_theme_stylebox_override("panel", bsb)
	badge.visible = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	badge.offset_left = 14.0
	badge.offset_right = 44.0
	badge.offset_top = 2.0
	badge.offset_bottom = 32.0
	var bang := Label.new()
	bang.text = text
	bang.add_theme_font_size_override("font_size", 18)
	bang.add_theme_color_override("font_color", Color.WHITE)
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
		var icon: Label = tab["icon"]
		icon.pivot_offset = icon.size * 0.5
		var target := Vector2(1.28, 1.28) if is_active else Vector2.ONE
		icon.create_tween().tween_property(icon, "scale", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		icon.modulate = Color.WHITE if is_active else Color(0.72, 0.75, 0.88)
		(tab["cap"] as Label).add_theme_color_override("font_color", Color(1.0, 0.82, 0.32) if is_active else Color(0.6, 0.64, 0.78))
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

	_add_background(slot_page, "slot_room", Color(0.45, 0.12, 0.2), Color(0.25, 0.05, 0.12))

	# floating decorative symbols
	var decor_ids := ["coin", "gem", "bag", "coin", "bolt", "gem", "coin"]
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
		var y := randf_range(150, 330) if i % 2 == 0 else randf_range(830, 1090)
		tr.position = Vector2(randf_range(20, 640), y)
		tr.modulate = Color(1, 1, 1, randf_range(0.35, 0.6))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_page.add_child(tr)
		FX.float_bob(tr, randf_range(10, 24), randf_range(1.8, 3.4))

	# glow behind slot machine
	var glow := ColorRect.new()
	var glow_shader := Shader.new()
	glow_shader.code = """
shader_type canvas_item;
void fragment() {
	float d = length(UV - 0.5);
	float a = smoothstep(0.5, 0.05, d) * 0.35;
	COLOR = vec4(1.0, 0.85, 0.4, a);
}
"""
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = glow_shader
	glow.material = glow_mat
	glow.size = Vector2(720, 700)
	glow.position = Vector2(0, 240)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_page.add_child(glow)
	FX.pulse_forever(glow, 1.05, 1.6)

	# logo
	var logo := Label.new()
	logo.text = "LOOT  LAGOON"
	logo.add_theme_font_size_override("font_size", 52)
	logo.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
	logo.add_theme_color_override("font_outline_color", Color(0.35, 0.12, 0.05))
	logo.add_theme_constant_override("outline_size", 14)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_page.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 88.0
	logo.offset_bottom = 160.0
	FX.pulse_forever(logo, 1.04, 2.2)

	slot = SlotView.new()
	slot_page.add_child(slot)
	slot.position = Vector2(30, 320)
	slot.size = Vector2(660, 505)
	slot.spin_requested.connect(_on_spin_requested)
	slot.spin_finished.connect(_on_spin_finished)
	slot.auto_toggled.connect(func(on: bool) -> void:
		auto_spin = on
		if on:
			_schedule_auto_spin(0.25)
	)

	# symbol legend
	var legend := HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 18)
	slot_page.add_child(legend)
	legend.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	legend.offset_top = 850.0
	legend.offset_bottom = 950.0
	for pair in [["steal", "Steal"], ["hammer", "Attack"], ["shield", "Shield"], ["bolt", "Spins"]]:
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		legend.add_child(box)
		var t := CV.symbol_tex(pair[0])
		if t != null:
			var tr := TextureRect.new()
			tr.texture = t
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(56, 56)
			box.add_child(tr)
		else:
			var e := _emoji_label(CV.SYMBOL_EMOJI[pair[0]], 34)
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(e)
		var cap := Label.new()
		cap.text = "x3 = " + pair[1]
		cap.add_theme_font_size_override("font_size", 14)
		cap.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(cap)

	_add_topbar(slot_page)
	_add_side_buttons(slot_page)

# --- side menu buttons ---

func _add_side_buttons(page: Control) -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	page.add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	left.position = Vector2(14, 170)
	_side_button(left, "🎁", "Daily", "daily", _open_daily)
	_side_button(left, "🔔", "Alerts", "alerts", _open_alerts)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	page.add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	right.position = Vector2(720 - 14 - 84, 170)
	_side_button(right, "🏆", "Ranks", "ranks", _open_ranks)

func _side_button(container: VBoxContainer, emoji: String, caption: String, badge_key: String, action: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	container.add_child(box)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(84, 84)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.08, 0.15, 0.88) if state != "hover" else Color(0.2, 0.14, 0.24, 0.92)
		sb.set_corner_radius_all(42)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.95, 0.75, 0.25)
		sb.shadow_size = 5
		sb.shadow_color = Color(0, 0, 0, 0.3)
		btn.add_theme_stylebox_override(state, sb)
	btn.text = emoji
	btn.add_theme_font_override("font", CV.emoji_font())
	btn.add_theme_font_size_override("font_size", 38)
	btn.pressed.connect(action)
	FX.press_feedback(btn)
	box.add_child(btn)

	var badge := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.92, 0.2, 0.25)
	bsb.set_corner_radius_all(13)
	bsb.set_border_width_all(2)
	bsb.border_color = Color.WHITE
	badge.add_theme_stylebox_override("panel", bsb)
	badge.size = Vector2(26, 26)
	badge.position = Vector2(62, -4)
	badge.visible = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge)
	var bang := Label.new()
	bang.text = "!"
	bang.add_theme_font_size_override("font_size", 16)
	bang.add_theme_color_override("font_color", Color.WHITE)
	bang.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bang.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bang)
	bang.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badges[badge_key] = badge

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	cap.add_theme_constant_override("outline_size", 5)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_popup.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.09, 0.18, 0.98)
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.95, 0.75, 0.25)
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
	FX.pop_in(panel, 0.32)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 28)
	tl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tl)
	var x := Button.new()
	x.text = "✕"
	x.custom_minimum_size = Vector2(46, 46)
	_candy_button(x, Color(0.75, 0.3, 0.3))
	x.pressed.connect(func() -> void: _close_popup())
	header.add_child(x)

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

func _popup_row_label(text: String, size := 19) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
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
		claim.custom_minimum_size = Vector2(0, 58)
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
	sb.bg_color = Color(0.1, 0.08, 0.16, 0.96)
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
	panel.custom_minimum_size = Vector2(672, 62)
	panel.position = Vector2(24, -90)
	panel.z_index = 130
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_toast = panel

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)
	hb.add_child(_emoji_label(emoji, 26))
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	hb.add_child(_emoji_label("🔔", 20))

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
		var empty := _popup_row_label("No notifications yet — you're all caught up!", 17)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
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
			sb.bg_color = Color(0.2, 0.15, 0.1, 0.95) if unread else Color(0.08, 0.06, 0.13, 0.9)
			sb.set_corner_radius_all(14)
			sb.set_border_width_all(2)
			sb.border_color = Color(1.0, 0.8, 0.3) if unread else Color(1, 1, 1, 0.07)
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
			txt.add_theme_font_size_override("font_size", 16)
			txt.add_theme_color_override("font_color", Color.WHITE if unread else Color(1, 1, 1, 0.75))
			txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(txt)
			var when := Label.new()
			when.text = _time_ago(float(entry.get("ts", 0.0)))
			when.add_theme_font_size_override("font_size", 13)
			when.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
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
		clear.custom_minimum_size = Vector2(0, 50)
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
	settings.custom_minimum_size = Vector2(0, 50)
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
	_make_page("shop", "Shop", Color(0.2, 0.1, 0.24), Color(0.1, 0.05, 0.14))
	_make_page("collections", "Collections", Color(0.09, 0.13, 0.26), Color(0.05, 0.06, 0.15))
	_make_page("quests", "Quests", Color(0.08, 0.18, 0.16), Color(0.04, 0.09, 0.1))
	_make_page("options", "Options", Color(0.16, 0.14, 0.2), Color(0.08, 0.07, 0.12))

func _make_page(key: String, title: String, top_col: Color, bottom_col: Color) -> void:
	var page := Control.new()
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false

	_add_background(page, "", top_col, bottom_col)

	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 40)
	tl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
	tl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	tl.add_theme_constant_override("outline_size", 10)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(tl)
	tl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tl.offset_top = 84.0
	tl.offset_bottom = 140.0

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(sc)
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 16.0
	sc.offset_right = -16.0
	sc.offset_top = 152.0
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
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.16, 0.92)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.08)
	panel.add_theme_stylebox_override("panel", sb)
	vb.add_child(panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	panel.add_child(margin)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	margin.add_child(inner)
	return inner

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
	var hint := _popup_row_label("Pricier chests hold more cards and better odds for ★★★★★ legendaries", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.78, 0.62, 1.0, 0.85))
	vb.add_child(hint)

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

	var note := _popup_row_label("Prototype store — purchases are simulated, no real charges.", 12)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	vb.add_child(note)

# decorated section header:  ───  🗝️ TITLE  ───
func _shop_section(vb: VBoxContainer, emoji: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	row.add_child(_section_line())
	row.add_child(_emoji_label(emoji, 22))
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 21)
	t.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("outline_size", 6)
	row.add_child(t)
	row.add_child(_section_line())

func _section_line() -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.84, 0.35, 0.25)
	sb.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(10, 3)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

func _tag_chip(text: String, color: Color, font_size := 12) -> PanelContainer:
	var chip := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = color
	csb.set_corner_radius_all(11)
	csb.content_margin_left = 10.0
	csb.content_margin_right = 10.0
	csb.content_margin_top = 2.0
	csb.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", csb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cl := Label.new()
	cl.text = text
	cl.add_theme_font_size_override("font_size", font_size)
	cl.add_theme_color_override("font_color", Color.WHITE)
	chip.add_child(cl)
	return chip

# row of 5 stars, `lit` of them colored by rarity, the rest dim
func _star_row(lit: int, size := 14) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 1)
	var col: Color = CV.STAR_COLORS[clampi(lit, 1, CV.MAX_STAR) - 1]
	for i in CV.MAX_STAR:
		var s := Label.new()
		s.text = "★"
		s.add_theme_font_size_override("font_size", size)
		s.add_theme_color_override("font_color", col if i < lit else Color(1, 1, 1, 0.16))
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
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.11, 0.05, 0.97)
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(3)
	sb.border_color = Color(1.0, 0.8, 0.3)
	sb.shadow_size = 10
	sb.shadow_color = Color(1.0, 0.7, 0.2, 0.25)
	panel.add_theme_stylebox_override("panel", sb)
	vb.add_child(panel)
	panel.add_child(_shine_overlay(Color(1.0, 0.9, 0.6)))

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
	var nm := _popup_row_label(pack["name"], 23)
	nm.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	name_row.add_child(nm)
	name_row.add_child(_tag_chip(pack["tag"], Color(0.88, 0.28, 0.38)))
	var sub := _popup_row_label(pack["sub"], 14)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var once := _popup_row_label("One time only!", 12)
	once.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 0.8))
	col.add_child(once)

	var buy := Button.new()
	buy.text = pack["price"]
	buy.custom_minimum_size = Vector2(126, 56)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_font_size_override("font_size", 21)
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
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.14, 0.96).lerp(Color(cc.r, cc.g, cc.b, 0.96), 0.13)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3 if guaranteed else 2)
	sb.border_color = Color(cc.r, cc.g, cc.b, 0.85)
	sb.shadow_size = 8
	sb.shadow_color = Color(cc.r, cc.g, cc.b, 0.22)
	panel.add_theme_stylebox_override("panel", sb)
	row.add_child(panel)
	if guaranteed:
		panel.add_child(_shine_overlay(Color(0.9, 0.75, 1.0)))

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
	tag_wrap.custom_minimum_size = Vector2(0, 26)
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
		var spark := _emoji_label("✨", 20)
		art.add_child(spark)
		spark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		spark.offset_left = 22.0
		spark.offset_right = 52.0
		spark.offset_top = -46.0
		spark.offset_bottom = -16.0
		FX.pulse_forever(spark, 1.25, 1.1)

	var nm := Label.new()
	nm.text = pack["name"]
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	nm.add_theme_constant_override("outline_size", 5)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", 5)
	col.add_child(cards_row)
	cards_row.add_child(_emoji_label("🃏", 16))
	var cn := Label.new()
	cn.text = "x%d CARDS" % int(pack["cards"])
	cn.add_theme_font_size_override("font_size", 13)
	cn.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	cards_row.add_child(cn)

	col.add_child(_star_row(int(pack["star_cap"]), 15))

	var odds := Label.new()
	odds.text = "5★ GUARANTEED" if guaranteed else ("boosted odds" if int(pack["tier"]) == 1 else "common loot")
	odds.add_theme_font_size_override("font_size", 11)
	odds.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25) if guaranteed else Color(1, 1, 1, 0.5))
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(odds)
	if guaranteed:
		FX.pulse_forever(odds, 1.08, 1.2)

	var buy := Button.new()
	buy.text = pack["price"]
	buy.custom_minimum_size = Vector2(0, 50)
	buy.add_theme_font_size_override("font_size", 19)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	col.add_child(buy)

# square tile used for spin & coin packs (2-column grid)
func _shop_tile(grid: GridContainer, pack: Dictionary, accent: Color, amount_text: String) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(338, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.14, 0.95).lerp(Color(accent.r, accent.g, accent.b, 0.95), 0.1)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	panel.add_theme_stylebox_override("panel", sb)
	grid.add_child(panel)

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
	tag_wrap.custom_minimum_size = Vector2(0, 26)
	col.add_child(tag_wrap)
	if pack.has("tag"):
		tag_wrap.add_child(_tag_chip(pack["tag"], pack.get("tag_color", Color(0.88, 0.28, 0.38)), 11))

	var e := _emoji_label(pack["emoji"], 42)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(e)
	FX.pulse_forever(e, 1.06, 2.4)

	var amount := Label.new()
	amount.text = amount_text
	amount.add_theme_font_size_override("font_size", 21)
	amount.add_theme_color_override("font_color", Color.WHITE)
	amount.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	amount.add_theme_constant_override("outline_size", 5)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(amount)

	var nm := Label.new()
	nm.text = pack["name"]
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	var buy := Button.new()
	buy.text = pack["price"]
	buy.custom_minimum_size = Vector2(0, 48)
	buy.add_theme_font_size_override("font_size", 18)
	_candy_button(buy, Color(0.28, 0.68, 0.34))
	FX.press_feedback(buy)
	buy.pressed.connect(_confirm_purchase.bind(pack))
	col.add_child(buy)

func _free_gift_card(vb: VBoxContainer) -> void:
	var ready := _shop_free_ready()
	var cc := Color(0.3, 0.85, 0.6)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.14, 0.11, 0.97)
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(3)
	sb.border_color = cc if ready else Color(cc.r, cc.g, cc.b, 0.35)
	if ready:
		sb.shadow_size = 10
		sb.shadow_color = Color(cc.r, cc.g, cc.b, 0.3)
	panel.add_theme_stylebox_override("panel", sb)
	vb.add_child(panel)
	if ready:
		panel.add_child(_shine_overlay(Color(0.7, 1.0, 0.85)))

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
	var title := _popup_row_label("FREE  GIFT", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if ready else Color(1, 1, 1, 0.7))
	col.add_child(title)
	var sub := _popup_row_label("Every 24h:  +%s coins,  +%d spins  &  a card" % [_fmt(CV.SHOP_FREE_COINS), CV.SHOP_FREE_SPINS], 14)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	if not ready:
		var timer := _popup_row_label("⏳  Next gift in  %s" % _shop_free_countdown_text(), 17)
		timer.add_theme_color_override("font_color", Color(0.55, 0.95, 0.75))
		col.add_child(timer)
		_shop_gift_timer_label = timer

	if ready:
		var claim := Button.new()
		claim.text = "CLAIM"
		claim.custom_minimum_size = Vector2(126, 56)
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.add_theme_font_size_override("font_size", 20)
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
	var nm := _popup_row_label(pack["name"], 24)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(nm)
	var sub := _popup_row_label(pack["sub"], 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	vbox.add_child(sub)
	var note := _popup_row_label("Prototype — simulated purchase, no real charge.", 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	vbox.add_child(note)
	var pay := Button.new()
	pay.text = "PAY  %s" % pack["price"]
	pay.custom_minimum_size = Vector2(0, 58)
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
		var b := _popup_row_label(bonus_text, 19)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
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
		var tile := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.06, 0.13, 0.95).lerp(Color(sc.r, sc.g, sc.b, 0.95), 0.14)
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(2)
		sb.border_color = sc
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		tile.add_theme_stylebox_override("panel", sb)
		tile.custom_minimum_size = Vector2(166, 0)
		grid.add_child(tile)
		var colv := VBoxContainer.new()
		colv.alignment = BoxContainer.ALIGNMENT_CENTER
		colv.add_theme_constant_override("separation", 2)
		tile.add_child(colv)
		var e := _emoji_label(card["emoji"], 40)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		colv.add_child(e)
		var nm := Label.new()
		nm.text = card["name"]
		nm.add_theme_font_size_override("font_size", 13)
		nm.add_theme_color_override("font_color", Color.WHITE)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		colv.add_child(nm)
		colv.add_child(_star_row(stars, 13))
		var status := Label.new()
		if card["dup"]:
			status.text = "dup  +%d" % int(card.get("refund", 0))
			status.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		else:
			status.text = "NEW!"
			status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		status.add_theme_font_size_override("font_size", 12)
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
		done_row.add_child(_emoji_label("🎉", 18))
		var done := _popup_row_label("%s complete — claim it in Collections!" % set_name, 16)
		done.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		done_row.add_child(done)
		FX.pulse_forever(done_row, 1.04, 1.2)
	var ok := Button.new()
	ok.text = "COLLECT!"
	ok.custom_minimum_size = Vector2(0, 54)
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
	var ht := Label.new()
	ht.text = "%s  MISSIONS" % info["title"]
	ht.add_theme_font_size_override("font_size", 25)
	ht.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	ht.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	ht.add_theme_constant_override("outline_size", 6)
	hcol.add_child(ht)
	_quests_timer_label = _popup_row_label("", 14)
	_quests_timer_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	hcol.add_child(_quests_timer_label)
	_update_quests_timer()
	var done := 0
	for m in defs:
		if bool(st["claimed"].get(m["id"], false)):
			done += 1
	var hdone := Label.new()
	hdone.text = "%d/%d" % [done, defs.size()]
	hdone.add_theme_font_size_override("font_size", 26)
	hdone.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6) if done == defs.size() else Color.WHITE)
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
	b.custom_minimum_size = Vector2(0, 54)
	if period == quests_tab:
		_candy_button(b, Color(info["color"]))
	else:
		_candy_button(b, Color(0.2, 0.18, 0.28))
	# emoji won't render inside Button text on iOS — compose the face manually
	var face := CenterContainer.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	face.add_child(frow)
	frow.add_child(_emoji_label(str(info["emoji"]), 18))
	var ft := Label.new()
	ft.text = str(info["title"])
	ft.add_theme_font_size_override("font_size", 17)
	ft.add_theme_color_override("font_color", Color.WHITE if period == quests_tab else Color(1, 1, 1, 0.55))
	ft.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
	ft.add_theme_constant_override("outline_size", 4)
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
		dsb.bg_color = Color(0.92, 0.2, 0.25)
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
	hb.add_child(_emoji_label(emoji, 15))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	hb.add_child(l)
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

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.11, 0.05, 0.95) if ready else Color(0.12, 0.1, 0.18, 0.92)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3)
	sb.border_color = Color(1.0, 0.84, 0.3) if ready else Color(1.0, 0.84, 0.3, 0.25)
	if ready:
		sb.shadow_size = 10
		sb.shadow_color = Color(1.0, 0.8, 0.2, 0.3)
	panel.add_theme_stylebox_override("panel", sb)
	if claimed_bonus:
		panel.modulate.a = 0.55
	vb.add_child(panel)
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
	var t := Label.new()
	t.text = "ALL-CLEAR  BONUS"
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("outline_size", 5)
	col.add_child(t)
	var sub := _popup_row_label("Claim every mission to unlock", 14)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	col.add_child(sub)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 12)
	col.add_child(rrow)
	rrow.add_child(_reward_chip("💰", "+%s" % _fmt(_bonus_coins(quests_tab)), Color(1.0, 0.85, 0.4)))
	rrow.add_child(_reward_chip("🌀", "+%d" % int(b["spins"]), Color(0.6, 0.9, 1.0)))
	if claimed_bonus:
		row.add_child(_emoji_label("✅", 34))
	else:
		var btn := Button.new()
		btn.text = "CLAIM"
		btn.custom_minimum_size = Vector2(110, 50)
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

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.1, 0.07, 0.95) if ready else Color(0.1, 0.08, 0.16, 0.92)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3 if ready else 2)
	sb.border_color = Color(1.0, 0.84, 0.3, 0.9) if ready else Color(1, 1, 1, 0.08)
	if ready:
		sb.shadow_size = 8
		sb.shadow_color = Color(1.0, 0.8, 0.2, 0.25)
	panel.add_theme_stylebox_override("panel", sb)
	vb.add_child(panel)
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

	var tile := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = icol.darkened(0.35)
	tsb.set_corner_radius_all(16)
	tsb.set_border_width_all(2)
	tsb.border_color = icol.lightened(0.2)
	tile.add_theme_stylebox_override("panel", tsb)
	tile.custom_minimum_size = Vector2(64, 64)
	row.add_child(tile)
	var icon := _emoji_label(str(m["emoji"]), 32)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(icon)
	if ready:
		FX.pulse_forever(tile, 1.08, 0.8)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var d := Label.new()
	d.text = str(m["desc"])
	d.add_theme_font_size_override("font_size", 19)
	d.add_theme_color_override("font_color", Color.WHITE)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	col.add_child(prow)
	var pb := _styled_progress(Color(1.0, 0.84, 0.3) if ready or claimed else icol.lightened(0.1))
	pb.max_value = int(m["target"])
	pb.value = prog
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(pb)
	var ptxt := Label.new()
	ptxt.text = "%s/%s" % [_fmt(prog), _fmt(int(m["target"]))]
	ptxt.add_theme_font_size_override("font_size", 13)
	ptxt.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	prow.add_child(ptxt)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	var spin_r := int(m.get("spins", 0))
	if spin_r > 0:
		right.add_child(_reward_chip("🌀", "+%d" % spin_r, Color(0.6, 0.9, 1.0)))
	else:
		right.add_child(_reward_chip("🪙", "+%s" % _fmt(_mission_coins(m)), Color(1.0, 0.85, 0.4)))
	if claimed:
		var donel := _emoji_label("✅", 30)
		donel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(donel)
	else:
		var claim := Button.new()
		claim.text = "CLAIM"
		claim.custom_minimum_size = Vector2(112, 46)
		claim.disabled = not ready
		_candy_button(claim, Color(0.45, 0.75, 0.35))
		FX.press_feedback(claim)
		if ready:
			FX.pulse_forever(claim, 1.05, 0.7)
		claim.pressed.connect(_claim_mission.bind(quests_tab, m))
		right.add_child(claim)

func _fill_options(vb: VBoxContainer) -> void:
	var inner := _page_card(vb)
	var mute := CheckButton.new()
	mute.text = "Mute sounds"
	mute.button_pressed = muted
	mute.add_theme_font_size_override("font_size", 20)
	mute.add_theme_color_override("font_color", Color.WHITE)
	mute.toggled.connect(func(on: bool) -> void:
		muted = on
		AudioServer.set_bus_mute(0, on)
		_save_game()
	)
	inner.add_child(mute)

	var ncard := _page_card(vb)
	var nhead := HBoxContainer.new()
	nhead.add_theme_constant_override("separation", 8)
	ncard.add_child(nhead)
	nhead.add_child(_emoji_label("🔔", 24))
	var ntitle := _popup_row_label("Notifications", 22)
	ntitle.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	nhead.add_child(ntitle)

	var master := CheckButton.new()
	master.text = "Enable notifications"
	master.button_pressed = notif_enabled
	master.add_theme_font_size_override("font_size", 20)
	master.add_theme_color_override("font_color", Color.WHITE)
	master.toggled.connect(func(on: bool) -> void:
		notif_enabled = on
		_save_game()
		_fill_page("options")
	)
	ncard.add_child(master)

	var type_defs := [
		["attack", "Attack alerts — a rival raids your island"],
		["steal", "Steal alerts — a rival steals your coins"],
		["spins", "Spins refilled — +%d spins every %d min" % [SPIN_REGEN_AMOUNT, int(SPIN_REGEN_SECS / 60.0)]],
	]
	for def in type_defs:
		var key: String = def[0]
		var cb := CheckButton.new()
		cb.text = def[1]
		cb.button_pressed = bool(notif_types.get(key, true))
		cb.disabled = not notif_enabled
		cb.add_theme_font_size_override("font_size", 17)
		cb.add_theme_color_override("font_color", Color.WHITE if notif_enabled else Color(1, 1, 1, 0.45))
		cb.toggled.connect(func(on: bool) -> void:
			notif_types[key] = on
			_save_game()
		)
		ncard.add_child(cb)

	var acc := _page_card(vb)
	acc.add_child(_popup_row_label("Signed in as:  %s  (%s)" % [profile.get("name", "Guest"), profile.get("provider", "guest")], 18))
	var signout := Button.new()
	signout.text = "Sign out"
	signout.custom_minimum_size = Vector2(0, 52)
	_candy_button(signout, Color(0.55, 0.45, 0.65))
	FX.press_feedback(signout)
	signout.pressed.connect(func() -> void:
		profile = {}
		if FileAccess.file_exists("user://profile.json"):
			DirAccess.remove_absolute("user://profile.json")
		_show_login()
	)
	acc.add_child(signout)

	var credit := _popup_row_label("Loot Lagoon  •  prototype", 14)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	vb.add_child(credit)

func _styled_progress(fg_color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 14)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(1, 1, 1, 0.12)
	pb_bg.set_corner_radius_all(7)
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = fg_color
	pb_fg.set_corner_radius_all(7)
	pb.add_theme_stylebox_override("background", pb_bg)
	pb.add_theme_stylebox_override("fill", pb_fg)
	return pb

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
	var colors := {"Easy": Color(0.3, 0.68, 0.35), "Medium": Color(0.92, 0.6, 0.18), "Hard": Color(0.88, 0.28, 0.38)}
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = colors.get(diff, Color(0.5, 0.5, 0.5))
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = diff
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	return p

func _collection_item_card(emoji: String, iname: String, owned: bool, stars := 0) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if owned:
		sb.bg_color = Color(0.3, 0.22, 0.08, 0.95)
		sb.border_color = Color(1.0, 0.8, 0.3)
	else:
		sb.bg_color = Color(0.07, 0.06, 0.12, 0.9)
		sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(110, 116)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	var e := _emoji_label(emoji, 40)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.modulate = Color(1, 1, 1, 1.0) if owned else Color(1, 1, 1, 0.2)
	col.add_child(e)
	var n := Label.new()
	n.text = iname if owned else "???"
	n.add_theme_font_size_override("font_size", 12)
	n.add_theme_color_override("font_color", Color(1, 1, 1, 0.85) if owned else Color(1, 1, 1, 0.35))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	col.add_child(n)
	if stars > 0:
		var sr := _star_row(stars, 10)
		sr.modulate = Color(1, 1, 1, 1.0) if owned else Color(1, 1, 1, 0.45)
		col.add_child(sr)
	return p

func _fill_collections(vb: VBoxContainer) -> void:
	# grand prize header
	var head := _page_card(vb)
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 12)
	head.add_child(trow)
	trow.add_child(_emoji_label("🏆", 36))
	var gp := _popup_row_label("GRAND  PRIZE", 28)
	gp.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	trow.add_child(gp)
	var claimed_n := 0
	for c in CV.COLLECTIONS:
		if col_claimed.get(c["id"], false):
			claimed_n += 1
	var gsub := _popup_row_label("Complete all %d collections:  +%d coins  +%d spins" % [CV.COLLECTIONS.size(), CV.COLLECTION_MEGA_COINS, CV.COLLECTION_MEGA_SPINS], 16)
	gsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(gsub)
	var gpb := _styled_progress(Color(1.0, 0.78, 0.25))
	gpb.max_value = CV.COLLECTIONS.size()
	gpb.value = claimed_n
	head.add_child(gpb)
	var days_left := maxf(0.0, col_deadline - Time.get_unix_time_from_system())
	var season := _popup_row_label("Season ends in %dd %dh — collections reset!" % [int(days_left / 86400.0), int(fmod(days_left, 86400.0) / 3600.0)], 14)
	season.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	season.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	head.add_child(season)
	if col_mega_claimed:
		var done := _popup_row_label("CLAIMED  ✓", 20)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		head.add_child(done)
	elif claimed_n == CV.COLLECTIONS.size():
		var mega := Button.new()
		mega.text = "CLAIM  GRAND  PRIZE!"
		mega.custom_minimum_size = Vector2(0, 60)
		_candy_button(mega, Color(0.45, 0.75, 0.35))
		FX.press_feedback(mega)
		FX.pulse_forever(mega, 1.04, 1.0)
		mega.pressed.connect(_claim_mega)
		head.add_child(mega)

	# hint how cards are earned
	var hint := _popup_row_label("Spin the wheel — every spin has a chance to drop a card!", 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.78, 0.62, 1.0))
	vb.add_child(hint)

	for c in CV.COLLECTIONS:
		var id: String = c["id"]
		var items: Array = c["items"]
		var owned: Array = col_owned.get(id, [])
		var owned_n := 0
		for v in owned:
			if v:
				owned_n += 1
		var inner := _page_card(vb)

		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 10)
		inner.add_child(hrow)
		hrow.add_child(_emoji_label(c["icon"], 34))
		var nm := _popup_row_label(c["name"], 24)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(nm)
		hrow.add_child(_diff_chip(c["diff"]))

		var rw_text := "Reward:  %d coins" % c["reward_coins"]
		if int(c["reward_spins"]) > 0:
			rw_text += "  +  %d spins" % c["reward_spins"]
		var rw := _popup_row_label(rw_text, 15)
		rw.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 0.9))
		inner.add_child(rw)

		var center := CenterContainer.new()
		inner.add_child(center)
		var grid := GridContainer.new()
		grid.columns = ceili(items.size() / 2.0)
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		center.add_child(grid)
		for i in items.size():
			var it: Array = items[i]
			grid.add_child(_collection_item_card(it[0], it[1], i < owned.size() and owned[i], int(it[2])))

		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 12)
		inner.add_child(prow)
		var pb := _styled_progress(Color(0.55, 0.75, 1.0))
		pb.max_value = items.size()
		pb.value = owned_n
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		prow.add_child(pb)
		prow.add_child(_popup_row_label("%d/%d" % [owned_n, items.size()], 17))
		if col_claimed.get(id, false):
			var tag := _popup_row_label("CLAIMED  ✓", 17)
			tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			prow.add_child(tag)
		elif owned_n == items.size():
			var claim := Button.new()
			claim.text = "CLAIM"
			claim.custom_minimum_size = Vector2(130, 50)
			_candy_button(claim, Color(0.45, 0.75, 0.35))
			FX.press_feedback(claim)
			FX.pulse_forever(claim, 1.05, 0.9)
			claim.pressed.connect(_claim_collection.bind(c))
			prow.add_child(claim)

func _claim_collection(c: Dictionary) -> void:
	var id: String = c["id"]
	if col_claimed.get(id, false) or not _collection_complete(c):
		return
	col_claimed[id] = true
	coins += int(c["reward_coins"])
	spins += int(c["reward_spins"])
	Sfx.play("jackpot", -2.0)
	FX.confetti(self, 40)
	FX.flash(self)
	FX.fly_coins(self, Vector2(360, 640), _hud_labels[0]["coins"].global_position, 8)
	var btxt := "%s reward:  +%s coins" % [c["name"], _fmt(int(c["reward_coins"]))]
	if int(c["reward_spins"]) > 0:
		btxt += "  +%d spins" % int(c["reward_spins"])
	_banner(btxt, Color(1.0, 0.85, 0.3), c["icon"])
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
	coins += CV.COLLECTION_MEGA_COINS
	spins += CV.COLLECTION_MEGA_SPINS
	Sfx.play("levelup", -2.0)
	FX.confetti(self, 80)
	FX.flash(self)
	FX.fly_coins(self, Vector2(360, 620), _hud_labels[0]["coins"].global_position, 14)
	_banner("GRAND PRIZE!  +%s coins  +%d spins!" % [_fmt(CV.COLLECTION_MEGA_COINS), CV.COLLECTION_MEGA_SPINS], Color(1.0, 0.85, 0.3), "🏆")
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
		var rank := _popup_row_label("#%d" % (i + 1), 21)
		rank.custom_minimum_size = Vector2(50, 0)
		row.add_child(rank)
		row.add_child(_emoji_label(r["emoji"], 26))
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

	_island_title = Label.new()
	_island_title.add_theme_font_size_override("font_size", 22)
	_island_title.add_theme_color_override("font_color", Color.WHITE)
	_island_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_island_title.add_theme_constant_override("outline_size", 7)
	_island_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_island_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	village_page.add_child(_island_title)
	_island_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_island_title.offset_top = 74.0
	_island_title.offset_bottom = 110.0

	village = VillageView.new()
	village_page.add_child(village)
	village.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	village.upgrade_requested.connect(_on_upgrade_requested)
	for slot_dict in village.get("_slots"):
		_candy_button(slot_dict["button"], Color(0.35, 0.62, 0.9))

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

func _add_topbar(page: Control) -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.15, 0.85)
	sb.set_corner_radius_all(16)
	sb.shadow_size = 6
	sb.shadow_color = Color(0, 0, 0, 0.25)
	bar.add_theme_stylebox_override("panel", sb)
	page.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 12.0
	bar.offset_right = -12.0
	bar.offset_top = 10.0
	bar.offset_bottom = 64.0

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)

	var labels := {}
	for pair in [["🪙", "coins"], ["🌀", "spins"], ["🛡️", "shields"]]:
		hb.add_child(_emoji_label(pair[0], 19))
		var val := _hud_value_label("0")
		hb.add_child(val)
		labels[pair[1]] = val
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(8, 0)
		hb.add_child(gap)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	var vil := _hud_value_label("Island 1")
	hb.add_child(vil)
	labels["island"] = vil
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
	l.add_theme_font_size_override("font_size", 54)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.02))
	l.add_theme_constant_override("outline_size", 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 100
	l.size = Vector2(720, 70)
	l.position = Vector2(0, 244)
	l.pivot_offset = Vector2(360, 35)
	l.scale = Vector2(0.3, 0.3)
	slot_page.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.75)
	tw.tween_property(l, "position:y", 190.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
				shields = mini(3, shields + bet)
				Sfx.play("shield", -6.0)
				_banner("Shield up!  (%d/3)" % shields, Color(0.5, 0.75, 1.0))
				_show_win("+SHIELD", Color(0.5, 0.75, 1.0))
			"bolt":
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
		FX.fly_coins(self, Vector2(330, 540), _hud_labels[0]["coins"].global_position, clampi(gain / 250, 3, 9))
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

func _start_visit(mode: String) -> void:
	var npc: Dictionary = npcs.pick_random()
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
		_island_title.text = "Island %d  —  %s" % [island_level, CV.island_theme(island_level)["name"]]

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
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_popup.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.09, 0.18, 0.98)
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(4)
	sb.border_color = Color(0.95, 0.75, 0.25)
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
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

	var title := Label.new()
	title.text = "ISLAND  COMPLETE!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)

	var sub := _popup_row_label("%s is fully built — amazing job!" % CV.island_theme(island_level)["name"], 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var reward := _popup_row_label("Journey rewards:  💰 +%s   🌀 +%d" % [_fmt(ISLAND_REWARD_COINS), ISLAND_REWARD_SPINS], 17)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	vbox.add_child(reward)

	var next_name: String = CV.island_theme(island_level + 1)["name"]
	var sail := Button.new()
	sail.text = "⛵  SET SAIL TO %s" % next_name.to_upper()
	sail.custom_minimum_size = Vector2(0, 62)
	sail.add_theme_font_size_override("font_size", 22)
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.22, 0.95)
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(5)
	sb.border_color = Color(0.95, 0.75, 0.25)
	sb.shadow_size = 12
	sb.shadow_color = Color(0, 0, 0, 0.35)
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

	var nm := Label.new()
	nm.text = CV.island_theme(level)["name"]
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	nm.add_theme_constant_override("outline_size", 7)
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

	var welcome := Label.new()
	welcome.text = "Welcome to %s!" % CV.island_theme(to_level)["name"]
	welcome.visible = false
	welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	welcome.add_theme_font_size_override("font_size", 42)
	welcome.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	welcome.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	welcome.add_theme_constant_override("outline_size", 9)
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
		labels["coins"].text = str(coins)
		labels["spins"].text = ("%d/%d" % [spins, SPIN_CAP]) if spins <= SPIN_CAP else str(spins)
		labels["shields"].text = str(shields)
		labels["island"].text = "Island %d" % island_level
	village.refresh(buildings, coins, _star_costs())

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
		var e := _emoji_label(emoji, 28)
		box.add_child(e)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 8)
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

func _emoji_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CV.emoji_font())
	l.add_theme_font_size_override("font_size", size)
	return l

func _hud_value_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	return l

func _candy_button(btn: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(14)
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		match state:
			"hover":
				sb.bg_color = color.lightened(0.12)
			"pressed":
				sb.bg_color = color.darkened(0.1)
			"disabled":
				sb.bg_color = Color(0.55, 0.52, 0.5)
			_:
				sb.bg_color = color
		sb.border_width_bottom = 6
		sb.border_color = sb.bg_color.darkened(0.32)
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
	btn.add_theme_constant_override("outline_size", 4)

# --- save / load ---

func _save_game() -> void:
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
