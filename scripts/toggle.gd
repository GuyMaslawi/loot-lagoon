class_name Toggle
extends Button

# =============================================================================
#  A SETTINGS SWITCH
# =============================================================================
#
# Godot's CheckButton draws its knob from the theme's icons, and this game has
# no icon set -- so every setting rendered as a white caption and a four-pixel
# dot on white glass, which is to say as nothing at all.
#
# This is the switch the rest of the game's materials imply: a sea-glass well
# that fills with kelp when it is on, and a shell knob with a brass rim riding
# in it. The whole row is the target, not just the switch, because a 104px
# control on the right of a 470px card is a needle to thread on a phone.

signal switched(on: bool)

const TRACK := Vector2(104.0, 56.0)
const KNOB := 46.0
const INSET := 5.0
const ROW_H := 96.0

var _title: Label
var _sub: Label
var _k := 0.0        # knob travel, 0 off .. 1 on
var _tw: Tween

func _init(title := "", subtitle := "") -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, ROW_H)
	# The button paints nothing: the row lives inside a glass card that already
	# has a surface, and a second one stacked on it just muddies the card.
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, clear)
	text = ""

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6.0
	box.offset_right = -(TRACK.x + 26.0)

	_title = Lagoon.label(title, UI.F_LABEL, Lagoon.INK, true)
	box.add_child(_title)
	_sub = Lagoon.label(subtitle, UI.F_CAPTION, Lagoon.INK_SOFT)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.visible = not subtitle.is_empty()
	box.add_child(_sub)

	toggled.connect(_on_toggled)

# Set the starting state without animating it -- a page that opens with four
# switches all sliding at once looks like it is loading, not like it is ready.
func set_on(on: bool) -> void:
	set_pressed_no_signal(on)
	if _tw != null and _tw.is_running():
		_tw.kill()
	_k = 1.0 if on else 0.0
	queue_redraw()

func set_dimmed(off: bool) -> void:
	disabled = off
	_title.add_theme_color_override("font_color", Lagoon.INK_FAINT if off else Lagoon.INK)
	_sub.add_theme_color_override("font_color", Lagoon.INK_FAINT if off else Lagoon.INK_SOFT)
	queue_redraw()

func _on_toggled(on: bool) -> void:
	Sfx.play("pop", -14.0)
	if _tw != null and _tw.is_running():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_method(func(v: float) -> void:
		_k = v
		queue_redraw()
	, _k, 1.0 if on else 0.0, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	switched.emit(on)

func _draw() -> void:
	var fade := 0.40 if disabled else 1.0
	var origin := Vector2(size.x - TRACK.x - 6.0, (size.y - TRACK.y) * 0.5)

	var track := StyleBoxFlat.new()
	track.set_corner_radius_all(int(TRACK.y * 0.5))
	track.bg_color = Color(Lagoon.LAGOON_DEEP.r, Lagoon.LAGOON_DEEP.g, Lagoon.LAGOON_DEEP.b, 0.20) \
		.lerp(Lagoon.KELP, _k)
	track.bg_color.a = maxf(track.bg_color.a, 0.20 + 0.80 * _k) * fade
	track.set_border_width_all(3)
	track.border_color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.22 * fade) \
		.lerp(Color(Lagoon.KELP_LO.r, Lagoon.KELP_LO.g, Lagoon.KELP_LO.b, fade), _k)
	draw_style_box(track, Rect2(origin, TRACK))

	# the knob sits proud of the well, so the state is readable from its shadow
	# alone in bright sun on a phone screen
	var travel := TRACK.x - KNOB - INSET * 2.0
	var c := origin + Vector2(INSET + KNOB * 0.5 + travel * _k, TRACK.y * 0.5)
	draw_circle(c + Vector2(0, 3), KNOB * 0.5, Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.30 * fade))
	draw_circle(c, KNOB * 0.5, Color(Lagoon.SHELL.r, Lagoon.SHELL.g, Lagoon.SHELL.b, fade))
	draw_arc(c, KNOB * 0.5 - 1.5, 0.0, TAU, 32, Color(Lagoon.BRASS.r, Lagoon.BRASS.g, Lagoon.BRASS.b, fade), 3.0, true)
	# a crescent of light on the upper left, the same lamp as every other piece
	draw_arc(c, KNOB * 0.5 - 8.0, PI * 0.80, PI * 1.80, 20,
		Color(1, 1, 1, 0.5 * fade), 4.0, true)
