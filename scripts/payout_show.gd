class_name PayoutShow
extends Control

# =============================================================================
#  The payout -- coins and spins arriving, with nothing to unwrap
# =============================================================================
#
# The sibling of ChestOpen, for everything that is not in a box.
#
# A spin pack or a coin pack has no lid. Giving it a chest to open would be a
# lie about what was bought, and Guy said so plainly: gold and spins get their
# own screen, and it is WITHOUT a box. So the theatre here is not an object
# being opened, it is an amount ARRIVING -- the figures sail in from off the
# edge of the frame, land hard, and sit there being large.
#
# Why it is a takeover at all, when a purchase already has a receipt: the old
# version was a popup with two tiles that faded in. Before that it was a banner
# that slid in at the top of the shop page and was gone in two seconds, which
# Guy read on his own phone as the purchase having FAILED -- the worst thing a
# payment can look like. A reward the player paid real money for gets the
# screen. See the note above `_show_pack_result` in main.gd for that history.
#
#     var seq := PayoutShow.play(self, "Purchase complete!", rows)
#     seq.finished.connect(func(): ...)      # fly the counters, then
#
# One signal, because there is nothing to reveal half way: `finished` fires on
# dismiss, and that is when the counters may move -- never before, per the
# held-counter rule.

signal finished

# The same rung as ChestOpen: above the popup that sold it, below the toast
# strip. See the z-index ladder in main.gd.
const Z := 126

var _sky: TakeoverSky
var _dim: ColorRect
var _stage: Control
var _hint: Label
var _tw: Tween
# What each resource sounds like when it lands.
const ARRIVAL_SFX := {"coin": "coins", "spin": "pop", "shield": "shield"}

var _rows: Array = []            # [[glyph_kind, amount, caption, color], ...]
var _state := 0                  # 0 arriving, 1 landed, 2 dismissed


# `rows` is [[glyph_kind, amount_text, caption, color], ...] in the order they
# should arrive. The caller decides what a row says; this decides how it gets
# here.
static func play(parent: Control, title: String, rows: Array) -> PayoutShow:
	var seq := PayoutShow.new()
	seq._rows = rows
	parent.add_child(seq)
	seq.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seq._build(title)
	seq._run()
	return seq


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = Z


func _build(title: String) -> void:
	var vs := get_viewport_rect().size

	_dim = ColorRect.new()
	_dim.color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Shallower water than the chest screen, and that difference is deliberate:
	# a chest is dredged up from the deep, a purchase is handed over at the
	# surface. Same room, different depth, so the two screens are recognisably
	# a pair without being the same picture.
	_sky = TakeoverSky.new()
	_sky.tint = Lagoon.LAGOON
	_sky.modulate.a = 0.0
	add_child(_sky)
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky.create_tween().tween_property(_sky, "modulate:a", 1.0, 0.26)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if title != "":
		var plate := Lagoon.plaque(title, 0.0, 72.0, UI.F_SUBHEAD)
		_stage.add_child(plate)
		plate.position = Vector2(vs.x * 0.5 - plate.size.x * 0.5, vs.y * 0.17)
		plate.modulate.a = 0.0
		plate.scale = Vector2(0.88, 0.88)
		plate.pivot_offset = plate.size * 0.5
		var pt := plate.create_tween().set_parallel(true)
		pt.tween_property(plate, "modulate:a", 1.0, 0.28).set_delay(0.12)
		pt.tween_property(plate, "scale", Vector2.ONE, 0.34).set_delay(0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_hint = Label.new()
	_hint.text = "tap to collect"
	_hint.add_theme_font_size_override("font_size", UI.F_TINY)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.modulate.a = 0.0
	_stage.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.position.y = vs.y - 96.0

	gui_input.connect(_on_input)


func _run() -> void:
	var vs := get_viewport_rect().size
	_tw = create_tween()
	_tw.tween_property(_dim, "color:a", 0.62, 0.20)

	var n := _rows.size()
	var tile := Vector2(minf(vs.x * 0.74, 420.0), 150.0)
	var gap := 16.0
	var total := float(n) * tile.y + float(n - 1) * gap
	var top := vs.y * 0.52 - total * 0.5

	for i in n:
		var r: Array = _rows[i]
		var card := _tile(r, tile)
		_stage.add_child(card)
		card.size = tile
		card.pivot_offset = tile * 0.5
		var rest := Vector2(vs.x * 0.5 - tile.x * 0.5,
			top + float(i) * (tile.y + gap))
		# Alternating sides. Every row entering from the same edge reads as a
		# list being scrolled in; alternating reads as separate things being
		# handed over, which is what a multi-item pack is.
		var from_left := i % 2 == 0
		card.position = Vector2(
			-tile.x - 40.0 if from_left else vs.x + 40.0, rest.y)
		card.modulate.a = 0.0
		# Where a tap during the arrival should put it. Held on the node rather
		# than captured in a closure so `_snap` can settle rows it did not build.
		card.set_meta("rest", rest)

		var delay := 0.30 + 0.22 * float(i)
		var ct := card.create_tween()
		ct.tween_interval(delay)
		ct.tween_callback(func() -> void:
			if not is_instance_valid(card):
				return
			var t := card.create_tween().set_parallel(true)
			t.tween_property(card, "modulate:a", 1.0, 0.14)
			# BACK on the way in, so it overshoots its resting place and settles
			# -- an amount that slides to a dead stop reads as a UI element
			# animating, not as something landing.
			t.tween_property(card, "position", rest, 0.46) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.chain().tween_callback(func() -> void:
				if not is_instance_valid(card):
					return
				FX.shake(card, 6.0, 3)
				FX.burst(_stage, rest + tile * 0.5, r[3] as Color, 9)
				FX.haptic(14, 0.4)
				# Each resource lands with its own sound, mapped explicitly:
				# a fallback that says "shield" for everything that is not a
				# coin is how the spin row came to thump like armour.
				Sfx.play(ARRIVAL_SFX.get(String(r[0]), "pop"),
					-6.0, 0.04, 1.0 + 0.05 * float(i))))

	_tw.tween_interval(0.30 + 0.22 * float(n) + 0.40)
	_tw.tween_callback(_landed)


func _landed() -> void:
	if _state != 0:
		return
	_state = 1
	FX.flash(self, Color(1.0, 0.95, 0.70, 0.16))
	create_tween().tween_property(_hint, "modulate:a", 1.0, 0.35)


# One row: the icon, the figure, and what the figure is. The figure is the
# biggest thing on the screen because it is the only thing the player is
# checking -- the caption is there so a number with no context never appears.
func _tile(r: Array, tile: Vector2) -> Control:
	var col: Color = r[3]
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.16, col.g * 0.16 + 0.04, col.b * 0.20 + 0.06, 0.94)
	sb.set_corner_radius_all(Lagoon.R_CARD)
	sb.set_border_width_all(4)
	sb.border_color = col
	# The rim every object in this game carries -- see the keyline pass.
	sb.shadow_size = 14
	sb.shadow_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.44)
	sb.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", sb)

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(m, 22)
	for m in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 16)
	panel.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(row)

	var icon := Glyph.new()
	icon.kind = String(r[0])
	icon.tint = col
	icon.custom_minimum_size = Vector2(86, 86)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	# The icon breathes while it is on screen. Two seconds is slow enough that
	# it never competes with the arrival it is part of.
	FX.float_bob(icon, 5.0, 2.1)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var amount := Lagoon.label(String(r[1]), UI.F_DISPLAY, Lagoon.SHELL, true)
	text.add_child(amount)
	var cap := Lagoon.label(String(r[2]), UI.F_CAPTION,
		Color(col.r, col.g, col.b, 0.92), true)
	text.add_child(cap)

	return panel


# Never ignore the first tap: a player tapping through an animation is telling
# you the animation is too long. A tap while the rows are still arriving snaps
# them home rather than skipping the reward.
func _on_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.is_pressed()):
		return
	if _state == 0:
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_snap()
		_landed()
	elif _state == 1:
		_dismiss()


# Every row straight to its resting place, no arrival animation left pending.
func _snap() -> void:
	for c in _stage.get_children():
		if c is Panel and c.has_meta("rest"):
			(c as Panel).position = c.get_meta("rest")
			(c as Panel).modulate.a = 1.0


# Finish now, from outside, without a tap. Exists for the same reason
# ChestOpen.skip does: a full-screen overlay only a tap can clear owns the
# screen for ever headless, and offline processing and auto-spin both need to
# be able to take it back. See trap one in the QA notes.
func skip(_reveal := true) -> void:
	if _state == 2:
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_dismiss()


func _dismiss() -> void:
	if _state == 2:
		return
	_state = 2
	set_deferred("mouse_filter", Control.MOUSE_FILTER_IGNORE)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.24)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free())
