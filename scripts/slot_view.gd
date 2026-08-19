class_name SlotView
extends Control

# =============================================================================
#  THE MACHINE
# =============================================================================
#
# A brass cabinet standing on the water: riveted body, a sign across the top
# that calls the result, a recessed window with three reels behind it, the
# meter that tells you what a spin costs and when the next ones arrive, and
# one coral button.
#
# Colour does the work of separating the parts. Three values, in this order of
# area: brass for everything structural, shell-cream for the reel faces the
# symbols are printed on, and deep lagoon for the sign and the recesses. Coral
# appears once, on SPIN, which is why the eye finds it before anything else.
#
# The card riding on top of the cabinet is who you rob if the raccoons line
# up. Showing the pot before the spin is what turns a steal from a payout into
# a wager -- you already know what is on the table.

signal spin_requested
signal spin_finished(result: Array)
signal auto_toggled(on: bool)

const BETS := [1, 2, 3, 5]
const CARD := Vector2(438, 96)

var spin_button: SpinButton
var bet_button: Button
var auto_on := false
var bet := 1

var reels: Reels
var _cabinet: PanelContainer
var _ribbon: Ribbon
var _ribbon_label: Label
var _ribbon_home := ""
var _card: PanelContainer
var _card_avatar: Control
var _card_slot: Control
var _card_name: Label
var _card_coins: Label
var _meter: ProgressBar
var _meter_label: Label
var _timer_label: Label
var _hint: Label
var _result: Array = []
var _target_name := ""   # avatars are rebuilt only when the rival changes

# =============================================================================
#  The sign
# =============================================================================
#
# A ribbon rather than a plaque, because the one thing on the cabinet that
# changes mid-spin should not look like it is bolted down. The tails fold back
# behind the plate and carry the shadowed side of the same cloth.

class Ribbon:
	extends Control
	var plate: Color = Lagoon.LAGOON_DEEP

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_plate(c: Color) -> void:
		plate = c
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var w := size.x
		var cy := h * 0.5
		var th := h * 0.30
		var inset := h * 0.92
		var back := plate.darkened(0.34)
		for side in 2:
			var out := 0.0 if side == 0 else w
			var inn := inset + 14.0 if side == 0 else w - inset - 14.0
			var notch := 20.0 if side == 0 else w - 20.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(out, cy - th), Vector2(inn, cy - th),
				Vector2(inn, cy + th), Vector2(out, cy + th),
				Vector2(notch, cy)]), back)
		var plate_rect := Rect2(inset, 0, w - inset * 2.0, h)
		var sb := StyleBoxFlat.new()
		sb.bg_color = plate
		sb.set_corner_radius_all(int(h * 0.26))
		sb.set_border_width_all(4)
		sb.border_color = Lagoon.BRASS
		sb.shadow_size = 7
		sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.35)
		sb.shadow_offset = Vector2(0, 4)
		draw_style_box(sb, plate_rect)
		# the crease where each tail folds under the plate
		for x in [inset, w - inset]:
			draw_line(Vector2(x, cy - th), Vector2(x, cy + th),
				Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.30), 3.0)

# =============================================================================

func _ready() -> void:
	_build_cabinet()
	_build_card()
	_style_bet()
	set_auto(false)

func _build_cabinet() -> void:
	_cabinet = PanelContainer.new()
	_cabinet.add_theme_stylebox_override("panel", _cabinet_style())
	add_child(_cabinet)
	_cabinet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cabinet.offset_left = 14.0
	_cabinet.offset_right = -14.0
	_cabinet.offset_top = CARD.y * 0.5
	var body := _cabinet_material()
	var metal := ColorRect.new()
	metal.material = body
	metal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cabinet.add_child(metal)
	metal.resized.connect(func() -> void: body.set_shader_parameter("rect_px", metal.size))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	# the card overhangs the top of the cabinet, so the sign starts below it
	pad.add_theme_constant_override("margin_top", int(CARD.y * 0.62))
	pad.add_theme_constant_override("margin_bottom", 14)
	_cabinet.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	_ribbon = Ribbon.new()
	_ribbon.custom_minimum_size = Vector2(0, 72)
	col.add_child(_ribbon)
	_ribbon_label = Lagoon.title("LOOT  LAGOON", UI.F_TITLE, Lagoon.SAND, Lagoon.ABYSS)
	_ribbon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ribbon.add_child(_ribbon_label)
	_ribbon_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", _window_style())
	window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(window)
	var wpad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		wpad.add_theme_constant_override(m, 9)
	window.add_child(wpad)
	reels = Reels.new()
	reels.reel_stopped.connect(_on_reel_stopped)
	wpad.add_child(reels)

	col.add_child(_build_meter())

	spin_button = SpinButton.new()
	spin_button.custom_minimum_size = Vector2(0, 124)
	spin_button.pressed.connect(_on_spin_pressed)
	spin_button.held.connect(func() -> void:
		if not auto_on:
			set_auto(true)
			auto_toggled.emit(true)
	)
	col.add_child(spin_button)

	_hint = Lagoon.label("Hold  for  auto  spin", UI.F_CAPTION, Lagoon.SAND, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.custom_minimum_size = Vector2(0, 24)
	col.add_child(_hint)

	var studs := Control.new()
	studs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cabinet.add_child(studs)
	for corner in [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT,
			Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]:
		var rivet := Glyph.new()
		rivet.kind = "rivet"
		rivet.custom_minimum_size = Vector2(24, 24)
		rivet.size = rivet.custom_minimum_size
		studs.add_child(rivet)
		rivet.set_anchors_and_offsets_preset(corner)
		var left: bool = corner in [Control.PRESET_TOP_LEFT, Control.PRESET_BOTTOM_LEFT]
		var top: bool = corner in [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT]
		rivet.offset_left += 18.0 if left else -42.0
		rivet.offset_top += 18.0 if top else -42.0
		rivet.offset_right = rivet.offset_left + 24.0
		rivet.offset_bottom = rivet.offset_top + 24.0

# BET on the left, then how many spins you are holding and when the next
# refill lands -- the two numbers that decide whether you press the button.
func _build_meter() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 66)

	bet_button = Button.new()
	bet_button.custom_minimum_size = Vector2(158, 66)
	bet_button.focus_mode = Control.FOCUS_NONE
	bet_button.add_theme_font_size_override("font_size", UI.F_LABEL)
	bet_button.pressed.connect(func() -> void:
		bet = BETS[(BETS.find(bet) + 1) % BETS.size()]
		_style_bet()
		Sfx.play("pop", -12.0)
	)
	FX.press_feedback(bet_button)
	row.add_child(bet_button)

	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", Lagoon.glass_well(20))
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(well)
	var wpad := MarginContainer.new()
	wpad.add_theme_constant_override("margin_left", 12)
	wpad.add_theme_constant_override("margin_right", 12)
	wpad.add_theme_constant_override("margin_top", 7)
	wpad.add_theme_constant_override("margin_bottom", 5)
	well.add_child(wpad)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	wpad.add_child(stack)

	_meter = Lagoon.progress(Lagoon.KELP)
	_meter.custom_minimum_size = Vector2(0, 26)
	stack.add_child(_meter)

	var readout := HBoxContainer.new()
	readout.add_theme_constant_override("separation", 8)
	stack.add_child(readout)
	_meter_label = Lagoon.title("0 / 50", UI.F_TINY, Lagoon.SAND, Lagoon.ABYSS)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	readout.add_child(_meter_label)
	_timer_label = Lagoon.label("", UI.F_TINY, Lagoon.SAND)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.add_child(_timer_label)
	return row

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _card_style())
	add_child(_card)
	_card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_card.offset_left = (720.0 - CARD.x) * 0.5
	_card.offset_right = -(720.0 - CARD.x) * 0.5
	_card.offset_top = 0.0
	_card.offset_bottom = CARD.y
	Lagoon.add_gloss(_card, 44)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	_card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	_card_avatar = Control.new()
	_card_avatar.custom_minimum_size = Vector2(74, 74)
	_card_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_card_avatar)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var cap := Lagoon.label("NEXT  TARGET", UI.F_TINY, Lagoon.INK_FAINT, true)
	text.add_child(cap)
	_card_name = Lagoon.label("—", UI.F_LABEL, Lagoon.INK, true)
	text.add_child(_card_name)

	_card_coins = Lagoon.title("0", UI.F_SUBHEAD, Lagoon.SAND, Lagoon.BRASS_LO.darkened(0.3))
	var pot := PanelContainer.new()
	pot.add_theme_stylebox_override("panel", _pot_style())
	pot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pot)
	var ppad := MarginContainer.new()
	ppad.add_theme_constant_override("margin_left", 14)
	ppad.add_theme_constant_override("margin_right", 14)
	ppad.add_theme_constant_override("margin_top", 4)
	ppad.add_theme_constant_override("margin_bottom", 5)
	pot.add_child(ppad)
	ppad.add_child(_card_coins)

	# The raccoon is pinned to the card's corner rather than laid out in the
	# row, so the pot reads as loot on the table and not a leaderboard entry.
	_card_slot = Control.new()
	_card_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_slot)
	var mark := TextureRect.new()
	mark.texture = CV.symbol_tex("steal")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_slot.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mark.offset_left = -14.0
	mark.offset_top = 42.0
	mark.offset_right = 42.0
	mark.offset_bottom = 98.0

# =============================================================================
#  Materials
# =============================================================================

# The cabinet is one piece of cast brass the height of the page, so it cannot
# take the small-plate treatment the plaques use -- a highlight band tuned for
# a 78px sign becomes a pale stripe across half a machine. It is shaded by the
# rounded-rect distance field instead: a lit top rim, a shadowed base, and the
# sides falling away so the front face bows toward the player.
static func _cabinet_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec2  rect_px = vec2(692.0, 764.0);
uniform float radius = 44.0;
uniform vec3  hi  = vec3(0.976, 0.898, 0.694);
uniform vec3  mid = vec3(0.820, 0.604, 0.278);
uniform vec3  lo  = vec3(0.478, 0.290, 0.094);

float rr(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = rect_px * 0.5;
	vec2 p = (UV - vec2(0.5)) * rect_px;
	float d = rr(p, half_size, radius);
	float inside = 1.0 - smoothstep(-1.0, 0.5, d);

	// the face: warm mid brass, lit from above, sinking toward the base
	vec3 c = mix(mid, mix(mid, hi, 0.34), smoothstep(0.34, 0.0, UV.y));
	c = mix(c, mix(mid, lo, 0.52), smoothstep(0.48, 1.0, UV.y));
	// the sides roll away, which is what stops a big panel reading as paper
	float u = abs(p.x) / half_size.x;
	c = mix(c, lo, smoothstep(0.74, 1.0, u) * 0.42);

	// bevel: the top rim catches the light, the bottom rim carries the shadow
	float rim = smoothstep(-18.0, -2.0, d);
	vec2 n = normalize(p / half_size + vec2(0.0, 0.0001));
	c = mix(c, hi, rim * max(-n.y, 0.0) * 0.62);
	c = mix(c, lo, rim * max(n.y, 0.0) * 0.50);
	// dark chamfer right at the outline so the silhouette stays crisp
	c = mix(c, lo * 0.5, smoothstep(-5.0, -0.5, d));

	COLOR = vec4(c, inside);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat

func _cabinet_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)     # the brass plate underneath paints it
	sb.set_corner_radius_all(44)
	sb.set_border_width_all(7)
	sb.border_color = Lagoon.BRASS_LO
	sb.shadow_size = 26
	sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.42)
	sb.shadow_offset = Vector2(0, 11)
	return sb

# The window is a hole cut in the cabinet, not a panel stuck on it: dark, with
# the metal's own shadow falling into the top of it.
func _window_style(water := Lagoon.LAGOON_DEEP) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(water.r * 0.5, water.g * 0.5, water.b * 0.5, 0.96)
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(6)
	sb.border_color = Lagoon.BRASS_MID
	sb.border_width_top = 9
	return sb

func _card_style() -> StyleBoxFlat:
	var sb := Lagoon.glass(44, 0.96)
	sb.set_border_width_all(5)
	sb.border_color = Lagoon.BRASS
	sb.shadow_size = 16
	sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.40)
	sb.shadow_offset = Vector2(0, 7)
	return sb

func _pot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Lagoon.BRASS_MID
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.border_color = Lagoon.BRASS_LO
	return sb

# Bet steps up through four materials rather than four arbitrary colours, so
# the stake is legible from the button's substance: brass, kelp, urchin, coral.
const BET_KINDS := ["brass", "kelp", "urchin", "primary"]

func _style_bet() -> void:
	bet_button.text = "BET  x%d" % bet
	Lagoon.button(bet_button, BET_KINDS[mini(BETS.find(bet), BET_KINDS.size() - 1)], 26)

# =============================================================================
#  State from main.gd
# =============================================================================

func set_island(level: int) -> void:
	var p := CV.island_palette(level)
	reels.apply_palette(p)
	spin_button.apply_palette(p)
	_ribbon_home = CV.island_theme(level)["name"].to_upper()
	_ribbon.set_plate(Lagoon.LAGOON_DEEP.lerp(p["mid"], 0.30))
	_set_sign(_ribbon_home, Lagoon.SAND)

# Who the raccoons would send you to, and what is in their vault.
func set_target(npc: Dictionary) -> void:
	if npc.is_empty():
		return
	_card_coins.text = _fmt(int(npc.get("coins", 0)))
	var who: String = npc.get("name", "—")
	if who == _target_name:
		return
	_target_name = who
	_card_name.text = who
	for c in _card_avatar.get_children():
		c.queue_free()
	var token := Lagoon.token(npc.get("emoji", "🏴"), 74.0, Lagoon.BRASS)
	_card_avatar.add_child(token)

func set_meter(held: int, cap: int, secs_to_refill: float, refill: int) -> void:
	_meter.max_value = float(cap)
	_meter.value = float(mini(held, cap))
	_meter_label.text = "%d / %d" % [held, cap]
	if held >= cap:
		_timer_label.text = "Spins full"
	else:
		var s := maxi(0, int(ceil(secs_to_refill)))
		_timer_label.text = "+%d spins in  %d:%02d" % [refill, s / 60, s % 60]

# The sign calls the result. It is the one part of the cabinet that talks, so
# it goes back to the island's name a couple of seconds later.
func announce(text: String, ink := Lagoon.BRASS_HI) -> void:
	_set_sign(text, ink)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(func() -> void: _set_sign(_ribbon_home, Lagoon.SAND))

func _set_sign(text: String, ink: Color) -> void:
	_ribbon_label.text = text
	_ribbon_label.add_theme_color_override("font_color", ink)
	var fs := UI.F_TITLE
	var avail := _ribbon.size.x - _ribbon.size.y * 2.4
	while fs > 22 and Lagoon.display_font().get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 2
	_ribbon_label.add_theme_font_size_override("font_size", fs)
	_ribbon_label.pivot_offset = _ribbon_label.size * 0.5
	_ribbon_label.scale = Vector2(1.18, 1.18)
	_ribbon_label.create_tween().tween_property(_ribbon_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_auto(on: bool) -> void:
	auto_on = on
	_hint.text = "Auto  spin  on  —  tap  to  stop" if on else "Hold  for  auto  spin"
	_hint.add_theme_color_override("font_color", Color(0.72, 1.0, 0.84) if on else Lagoon.SAND)

func is_spinning() -> bool:
	return reels != null and reels.is_spinning()

func start_spin(result: Array) -> void:
	_result = result
	spin_button.disabled = true
	bet_button.disabled = true
	reels.start_spin(result)

# Where a win should launch from.
func payline_pos() -> Vector2:
	return reels.global_position - global_position + reels.payline_centre(1)

func _on_spin_pressed() -> void:
	# During an auto run the hero button is the stop button; asking a player to
	# find a different control to cancel what this one started is a trap.
	if auto_on:
		set_auto(false)
		auto_toggled.emit(false)
		Sfx.play("pop", -12.0)
		return
	spin_requested.emit()

func _on_reel_stopped(index: int) -> void:
	# Two matching on the payline with one reel still running is the moment the
	# whole machine exists for.
	if index == 1 and _result.size() >= 2 and _result[0] == _result[1]:
		Sfx.play("pop", -6.0)
		FX.burst(self, payline_pos(), Lagoon.BRASS_HI, 10)
	if index < 2:
		return
	spin_button.disabled = false
	bet_button.disabled = false
	if _result.size() == 3 and _result[0] == _result[1] and _result[1] == _result[2]:
		reels.celebrate()
	spin_finished.emit(_result)

static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out
