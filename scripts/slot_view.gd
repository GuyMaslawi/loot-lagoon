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
signal target_tapped
signal spin_finished(result: Array)
signal auto_toggled(on: bool)

# The ladder the BET button walks. It is longer than the four rungs it used to
# have, because a player sitting on five figures of spins was still feeding them
# in one and two at a time -- the meter grew and the machine did not.
#
# Rungs are GATED by what is held rather than all offered at once: bet_steps()
# only returns the ones this balance can actually pay, so the button never
# cycles onto a wager that fails the moment it is pressed, and a new rung
# appearing is itself the reward for having stacked up.
const BETS := [1, 2, 3, 5, 10, 25, 50, 100]

# A rung is offered once the player could spin it ten times over. Ten is the
# number that keeps the top rung from being a single button press that empties
# the meter -- a bet you can afford exactly once is a dare, not a wager.
const BET_UNLOCK_SPINS := 10
const CARD := Vector2(438, 96)

# How much bare page is left either side of the cabinet.
#
# It used to be 14, which made the machine 692 of 720 and left no gutter at
# all -- so the page's floating buttons had nowhere to go but a band above the
# machine, and that band was paid for out of the machine's own height. Pulling
# the sides in to 66 gives each edge a lane wide enough to hold a 76px disc
# with only its inner rim on the brass, and hands the height that band used to
# occupy back to the reels. The cabinet gets narrower and considerably taller,
# which is the proportion a slot machine wants anyway.
#
# Anything that floats in these lanes is read by main.gd off this constant --
# do not widen it without looking at what lands on the brass.
const CABINET_INSET := 66.0

# =============================================================================
#  How much of the cabinet the reel window is allowed to be
# =============================================================================
#
# The window used to be the column's only expanding child, so it swallowed the
# entire remainder of the machine: every pixel the sign, the meter, the button
# and the hint did not claim went into three cells. On a tall phone that made
# the reel face most of the cabinet and left the brass around it a frame one
# cell wide -- the machine stopped reading as an object with reels in it and
# started reading as a grid with a rim. Guy, 2026-09-04: bring the spinning
# part down in height and pull its sides in.
#
# HEIGHT IS A SHARE, NOT A NUMBER. The cabinet is however tall the phone leaves
# it, so a fixed window height is cropped on a short screen and floating on a
# tall one. The window keeps this fraction of the free space and the rest goes
# back to the brass, split evenly above and below so the window stays optically
# centred between the sign and the meter.
const WINDOW_SHARE := 0.80

# ...and the sides come in by this much on top of the 20 the column already
# holds off the cabinet wall. Wider than this and the three symbols start to
# read as small rather than the window as narrow.
const WINDOW_INSET := 42

# The hero button gets its own gutter for the same reason. It is still the
# first thing on the page the eye lands on at this size -- past a point extra
# area stops saying "important" and starts saying "there was nothing else to
# put here", which is what a full-width 124px slab was doing.
const SPIN_INSET := 30
const SPIN_HEIGHT := 104

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
var _card_cap: Label
var _card_name: Label
var _card_coins: Label
var _meter: ProgressBar
var _meter_label: Label
var _timer_label: Label
var _hint: Label
var _result: Array = []
var _target_name := ""   # avatars are rebuilt only when the rival changes
var _target_coins := 0   # their vault in island-1 units, as main stores it
var _target_mult := 1.0  # the island curve, so the pot can be quoted for real

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
	_cabinet.offset_left = CABINET_INSET
	_cabinet.offset_right = -CABINET_INSET
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

	col.add_child(_brass_gap())
	var frame := MarginContainer.new()
	frame.add_theme_constant_override("margin_left", WINDOW_INSET)
	frame.add_theme_constant_override("margin_right", WINDOW_INSET)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = WINDOW_SHARE
	col.add_child(frame)
	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", _window_style())
	frame.add_child(window)
	var wpad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		wpad.add_theme_constant_override(m, 9)
	window.add_child(wpad)
	reels = Reels.new()
	reels.reel_stopped.connect(_on_reel_stopped)
	wpad.add_child(reels)
	col.add_child(_brass_gap())

	col.add_child(_build_meter())

	var spin_frame := MarginContainer.new()
	spin_frame.add_theme_constant_override("margin_left", SPIN_INSET)
	spin_frame.add_theme_constant_override("margin_right", SPIN_INSET)
	col.add_child(spin_frame)
	spin_button = SpinButton.new()
	spin_button.custom_minimum_size = Vector2(0, SPIN_HEIGHT)
	spin_button.pressed.connect(_on_spin_pressed)
	spin_button.held.connect(func() -> void:
		if not auto_on:
			set_auto(true)
			auto_toggled.emit(true)
	)
	spin_frame.add_child(spin_button)

	# Printed on the cabinet's own brass, which is a mid tone -- sand on it is
	# 3.36 : 1 with nothing to separate the two. Given the rim that every other
	# piece of type on painted material in this game wears.
	_hint = Lagoon.art_label("Hold  for  auto  spin", UI.F_CAPTION)
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

# The half of the leftover height the window gave back, above it and below it.
# Two of these and the window between them come to a whole, so the split is
# read off WINDOW_SHARE rather than tuned separately -- change the share and
# the brass follows it.
func _brass_gap() -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = (1.0 - WINDOW_SHARE) * 0.5
	return gap

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
		var steps := bet_steps()
		var at := steps.find(bet)
		bet = int(steps[0] if at < 0 else steps[(at + 1) % steps.size()])
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

	# THE COUNT RIDES THE BAR, like every other track in the game.
	#
	# It used to sit under the bar in a two-end row -- "50 / 50" hard left, "Spins
	# full" hard right -- with an empty strip above them, so the one gauge the
	# player looks at before every press was three objects saying one thing, none
	# of them in the middle of anything. The wheel comes along: it is there to
	# say WHICH resource the number counts, which is the whole reason it was
	# added, and that only works next to the digits.
	_meter = Lagoon.progress(Lagoon.KELP)
	_meter.custom_minimum_size = Vector2(0, 34)
	stack.add_child(_meter)

	var on_bar := CenterContainer.new()
	on_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.add_child(on_bar)
	on_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	on_bar.add_child(pair)
	# Sized to the cap height of the digits beside it so the pair reads as one
	# object.
	var spin_mark := Glyph.new()
	spin_mark.kind = "wheel"
	spin_mark.custom_minimum_size = Vector2(26, 26)
	spin_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(spin_mark)
	# White over a deep well and a kelp fill alike, which is what the shared
	# track style is built for -- sand was picked when this number sat on the
	# cabinet's brass instead.
	_meter_label = Lagoon.title("0 / 50", UI.F_CAPTION, Color.WHITE, Lagoon.HULL)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pair.add_child(_meter_label)

	# What is left under the bar is the one thing the bar cannot show: when the
	# next free spins land. Centred, because there is nothing to balance it
	# against any more.
	_timer_label = Lagoon.label("", UI.F_TINY, Lagoon.SAND)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_timer_label)
	return row

func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _card_style())
	add_child(_card)
	# THE CARD IS A CONTROL THE PLAYER CAN PRESS NOW.
	#
	# It has always been a promise -- these coins, this island, and the raid
	# lands on exactly who it names. Making it tappable does not weaken that;
	# it is the only place the promise can be CHANGED without breaking it,
	# because everything here happens before a spin is paid for. A chooser
	# after the reels stop would be the machine renegotiating a bet already
	# placed, which is the one thing matchmaking.gd exists to prevent.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			target_tapped.emit()
	)
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
	_card_cap = Lagoon.label("STEAL  TARGET", UI.F_TINY, Lagoon.INK_FAINT, true)
	text.add_child(_card_cap)
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
	var sh := Lagoon.shader("""
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
""")
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
# One per rung, and the ladder climbs in heat. mini() already guards the index,
# but a list this short against eight rungs meant every bet above x5 wore the
# same coat as x5 -- which is the exact thing the colour is there to prevent.
const BET_KINDS := ["brass", "kelp", "urchin", "primary",
	"primary", "primary", "primary", "primary"]

# Which rungs this balance may use. Always at least x1: a player with no spins
# left still has to see a bet on the button, and the out-of-spins offer is what
# answers the press.
func bet_steps() -> Array:
	var out: Array = []
	for b in BETS:
		if int(b) == 1 or _held >= int(b) * BET_UNLOCK_SPINS:
			out.append(int(b))
	return out

# Called whenever the meter moves, so a rung that has just become affordable
# turns up without waiting for the page to be rebuilt -- and, more importantly,
# so a bet the player can no longer pay is stepped back down instead of sitting
# there failing.
func _clamp_bet() -> void:
	var steps := bet_steps()
	if not steps.has(bet):
		var best := 1
		for b in steps:
			if int(b) <= bet:
				best = int(b)
		bet = best
		_style_bet()

func _style_bet() -> void:
	bet_button.text = "BET  x%d" % bet
	Lagoon.button(bet_button, BET_KINDS[mini(BETS.find(bet), BET_KINDS.size() - 1)], 26)
	_style_pot()

func _style_pot() -> void:
	if _card_coins == null:
		return
	_card_coins.text = _fmt(int(round(_target_coins * _target_mult)) * bet)

# =============================================================================
#  State from main.gd
# =============================================================================

func set_island(level: int) -> void:
	var p := CV.island_palette(level)
	reels.apply_palette(p)
	spin_button.apply_palette(p)
	_ribbon_home = CV.island_name(level).to_upper()
	_ribbon.set_plate(Lagoon.LAGOON_DEEP.lerp(p["mid"], 0.30))
	_set_sign(_ribbon_home, Lagoon.SAND)

# Who the raccoons would send you to, and what is in their vault.
#
# The pot is quoted the way the raid will actually pay it -- their vault times
# the island curve times the stake you are playing -- so raising the bet visibly
# raises what is on the table, and the number you read here is the number that
# comes out of the chests.
# `owes` is set when this rival is on main.gd's grudge list -- they have taken
# something off this island and not paid for it. The card says so, because the
# card is the only place the player sees who is next BEFORE they commit a spin
# to it, and "the machine happened to pick somebody" and "the machine picked
# the person who robbed you last night" are not the same offer.
func set_target(npc: Dictionary, coin_mult := 1.0, owes := false) -> void:
	if npc.is_empty():
		return
	_target_coins = int(npc.get("coins", 0))
	_target_mult = coin_mult
	_style_pot()
	# Ahead of the name check below, not after it: the same rival can go from
	# stranger to owing you while their name is still on the card, and an early
	# return would leave the caption a spin behind the list.
	if _card_cap != null and is_instance_valid(_card_cap):
		_card_cap.text = "THEY  OWE  YOU" if owes else "STEAL  TARGET"
		_card_cap.add_theme_color_override("font_color",
			Lagoon.CORAL_LO if owes else Lagoon.INK_FAINT)
	var who: String = npc.get("name", "—")
	if who == _target_name:
		return
	_target_name = who
	_card_name.text = who
	for c in _card_avatar.get_children():
		c.queue_free()
	var token := Lagoon.token(npc.get("emoji", "🏴"), 74.0, Lagoon.BRASS)
	_card_avatar.add_child(token)

var _held := 0

# Where the spin count sits on screen, for rewards that fly to it.
func meter_center() -> Vector2:
	if _meter_label != null and is_instance_valid(_meter_label):
		return _meter_label.global_position + _meter_label.size * 0.5
	return global_position + size * 0.5

# `tide` is CV's Spin Tide: for four hours the meter refills at double rate.
# It is said on this label rather than anywhere else on the page because this
# is the one piece of chrome whose only job is to answer "when do I get more
# spins", and during a Tide that answer is the event.
func set_meter(held: int, cap: int, secs_to_refill: float, refill: int, tide := false) -> void:
	_held = held
	_clamp_bet()
	_meter.max_value = float(cap)
	_meter.value = float(mini(held, cap))
	# Over the cap the "/ 50" is not a limit any more, it is a smaller number
	# sitting next to a bigger one, and "64 / 50" reads as arithmetic that has
	# gone wrong. Bolts and spin packs both push the meter past the cap on
	# purpose -- the cap only ever governs the free refill -- so above it the
	# meter says what is held and nothing else. The top bar has always done
	# this; the machine had not.
	# Compact above four figures. A spin pack or a run of bolt triples puts five
	# and six digits in here, and the label sits in a fixed-width well next to
	# the BET button -- the raw number ran under the timer text and then off the
	# end of the machine. 12.5K says the same thing and always fits.
	_meter_label.text = ("%d / %d" % [held, cap]) if held <= cap else UI.fmt_compact(held)
	if held >= cap:
		_timer_label.text = "Spins full"
	else:
		var s := maxi(0, int(ceil(secs_to_refill)))
		_timer_label.text = ("\U01F30A  +%d in  %d:%02d" if tide else "+%d spins in  %d:%02d") \
			% [refill, s / 60, s % 60]
	# Coral while the Tide runs. The label is otherwise the quietest text on the
	# cabinet, which is right for a countdown nobody is waiting on and wrong for
	# four hours somebody should be spending here.
	_timer_label.add_theme_color_override("font_color",
		Lagoon.CORAL_HI if (tide and held < cap) else Lagoon.SAND)

# The sign calls the result. It is the one part of the cabinet that talks, so
# it goes back to the island's name a couple of seconds later.
# Where the reels actually ended up on screen. The win read-out lands on top of
# them rather than at a hard-coded y, because that is where the player's eye
# already is when the last reel stops -- and because the cabinet's height is
# whatever the phone leaves over, so a fixed y drifts off it.
# =============================================================================
#  The steal, handed over by the thing that has been advertising it
# =============================================================================
#
# An attack earns the search screen honestly: three hammers do not say who they
# are going to land on, so watching the game look for somebody is the truth of
# what is happening. A steal has had the answer pinned to the top of the
# cabinet since before the spin -- face, name and pot -- so searching for it
# would be theatre. That is why it never got one, and what it got instead was
# half a second of nothing, which is not a beat either.
#
# So it gets the card coming off the machine. The raccoon that has been sitting
# on the corner of it all along lunges first, the card unseats itself and rises
# off the brass, and a ring goes out from under it. The raid arrives out of the
# object the player was already reading -- which is the one thing the attack's
# version cannot do, and the reason this is not just the search screen with a
# different word on it.
#
# Returns how long the caller has to wait before taking the screen.
const STEAL_TAKEOFF := 0.95

var _takeoff: Tween
var _takeoff_home := Vector2.ZERO
var _takeoff_scale := Vector2.ONE

func steal_takeoff() -> float:
	if _card == null or not is_instance_valid(_card):
		return 0.35
	# Home is remembered rather than assumed, and a takeoff already in flight is
	# undone before the new one reads it. Without that, a second send-off
	# arriving mid-lift captures a raised, enlarged card as the rest state and
	# parks it there for the rest of the session -- exactly the bug FX.shake
	# carries a comment about, and naming it there while reproducing it here
	# would be worse than not knowing.
	if _takeoff != null and _takeoff.is_valid():
		_takeoff.kill()
		_card.position = _takeoff_home
		_card.scale = _takeoff_scale
		_card.modulate.a = 1.0
	var home_pos := _card.position
	var home_scale := _card.scale
	_takeoff_home = home_pos
	_takeoff_scale = home_scale
	_card.pivot_offset = _card.size * 0.5
	_card.z_index = 6

	# The raccoon goes first, and he goes by squashing rather than turning.
	# Flat art that rotates reads as a sticker being waggled, so the lunge is
	# built out of weight: he crouches, then throws himself up and forward.
	if _card_slot != null and is_instance_valid(_card_slot):
		var mark := _card_slot.get_child(0) as Control
		if mark != null:
			mark.pivot_offset = Vector2(mark.size.x * 0.5, mark.size.y)
			var lunge := mark.create_tween()
			lunge.tween_property(mark, "scale", Vector2(1.18, 0.82), 0.10).set_trans(Tween.TRANS_SINE)
			lunge.tween_property(mark, "scale", Vector2(0.92, 1.26), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			lunge.parallel().tween_property(mark, "position:x", mark.position.x - 16.0, 0.13)
			lunge.tween_property(mark, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)
			lunge.parallel().tween_property(mark, "position:x", mark.position.x, 0.16)

	Sfx.play("pop", -8.0)
	var tw := create_tween()
	_takeoff = tw
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void:
		Sfx.play("raid", -6.0)
		FX.ring(self, _card.position + _card.size * 0.5, Lagoon.CORAL_HI, 250.0, 0.5, 8.0, 40.0))
	# Unseating: up and out, with the overshoot doing the work of "lifted"
	# rather than "slid".
	tw.parallel().tween_property(_card, "position:y", home_pos.y - 34.0, 0.34) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	tw.parallel().tween_property(_card, "scale", home_scale * 1.12, 0.34) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	# Held at the top of the lift for long enough to read the name and the pot
	# one last time, because that is what the player is about to go and take.
	tw.tween_interval(0.30)
	tw.tween_property(_card, "scale", home_scale * 1.26, 0.19).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_card, "modulate:a", 0.0, 0.19)
	# Put back under the overlay that has taken the screen by now, so the
	# machine is whole again the moment the raid lets go of it.
	tw.tween_callback(func() -> void:
		_card.position = home_pos
		_card.scale = home_scale
		_card.modulate.a = 1.0
		_card.z_index = 0
		_takeoff = null)
	return STEAL_TAKEOFF

func reels_center() -> Vector2:
	if reels == null or not reels.is_inside_tree():
		return global_position + size * 0.5
	return reels.global_position + reels.size * 0.5

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
	# White at rest, not sand. This line lands on the cabinet's brass frame and
	# art_label defaults to white for exactly that reason -- but this override
	# runs on every auto toggle and was quietly putting sand back every time.
	_hint.add_theme_color_override("font_color", Color(0.72, 1.0, 0.84) if on else Color.WHITE)

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
	#
	# When the pair is one of the four the third reel HOLDS for, this beat is
	# not a flourish on the way to a stop that was coming anyway -- it opens a
	# second and a half of the reel still running. It gets the bigger hit, so
	# the sound and the sparks are telling the truth about how long to watch.
	if index == 1 and _result.size() >= 2 and _result[0] == _result[1]:
		if reels.is_holding():
			Sfx.play("pop", -2.0, 0.03, 1.18)
			FX.burst(self, payline_pos(), Lagoon.BRASS_HI, 22)
		else:
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
