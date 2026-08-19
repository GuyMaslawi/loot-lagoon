class_name SlotView
extends Control

signal spin_requested
signal spin_finished(result: Array)
signal auto_toggled(on: bool)

var spin_button: Button
var auto_button: Button
var bet_button: Button
var auto_on := false
var bet := 1

const BETS := [1, 2, 3, 5]

var _cells: Array = []
var _bulbs: Array = []
var _bulb_t := 0.0
var _bulb_phase := false
var _result: Array = []
var _spinning := false
var _t := 0.0
var _flicker := 0.0
var _stop_times := [0.7, 1.15, 1.6]
var _stopped := [true, true, true]

func _ready() -> void:
	# cabinet
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.09, 0.23)
	sb.set_corner_radius_all(36)
	sb.set_border_width_all(9)
	sb.border_color = Color(0.98, 0.78, 0.25)
	sb.shadow_size = 20
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_offset = Vector2(0, 8)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	frame.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# marquee sign with running lights
	var marquee := PanelContainer.new()
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.98, 0.76, 0.2)
	msb.set_corner_radius_all(16)
	msb.set_border_width_all(3)
	msb.border_color = Color(0.6, 0.4, 0.08)
	msb.content_margin_top = 6.0
	msb.content_margin_bottom = 8.0
	marquee.add_theme_stylebox_override("panel", msb)
	vbox.add_child(marquee)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 3)
	marquee.add_child(mv)
	var bulb_row := HBoxContainer.new()
	bulb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bulb_row.add_theme_constant_override("separation", 34)
	mv.add_child(bulb_row)
	for i in 12:
		var bulb := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(1.0, 0.96, 0.75)
		bsb.set_corner_radius_all(6)
		bsb.shadow_size = 4
		bsb.shadow_color = Color(1.0, 0.85, 0.3, 0.7)
		bulb.add_theme_stylebox_override("panel", bsb)
		bulb.custom_minimum_size = Vector2(11, 11)
		bulb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bulb_row.add_child(bulb)
		_bulbs.append(bulb)
	var mtitle := Label.new()
	mtitle.text = "★  SPIN  &  WIN  ★"
	mtitle.add_theme_font_size_override("font_size", 26)
	mtitle.add_theme_color_override("font_color", Color(0.42, 0.24, 0.02))
	mtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mtitle)

	# reels window (inset dark glass)
	var window := PanelContainer.new()
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.06, 0.04, 0.11)
	wsb.set_corner_radius_all(22)
	wsb.set_border_width_all(4)
	wsb.border_color = Color(0.4, 0.3, 0.55)
	window.add_theme_stylebox_override("panel", wsb)
	vbox.add_child(window)

	var wm := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		wm.add_theme_constant_override(m, 14)
	window.add_child(wm)

	var reels := HBoxContainer.new()
	reels.add_theme_constant_override("separation", 12)
	reels.alignment = BoxContainer.ALIGNMENT_CENTER
	wm.add_child(reels)

	for i in 3:
		var cell := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(1.0, 0.97, 0.9)
		csb.set_corner_radius_all(16)
		csb.set_border_width_all(3)
		csb.border_color = Color(0.75, 0.55, 0.2)
		csb.border_width_bottom = 6
		cell.add_theme_stylebox_override("panel", csb)
		cell.custom_minimum_size = Vector2(170, 170)
		reels.add_child(cell)

		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(tr)

		var lbl := Label.new()
		lbl.add_theme_font_override("font", CV.emoji_font())
		lbl.add_theme_font_size_override("font_size", 84)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(lbl)

		_cells.append({"panel": cell, "tex": tr, "label": lbl})
		_set_cell(i, CV.SYMBOLS[i * 2])

	# payline arrows + glass sheen overlay
	for pair in [["▶", Control.PRESET_CENTER_LEFT, 6.0], ["◀", Control.PRESET_CENTER_RIGHT, -22.0]]:
		var arrow := Label.new()
		arrow.text = pair[0]
		arrow.add_theme_font_size_override("font_size", 24)
		arrow.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
		arrow.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0.0))
		arrow.add_theme_constant_override("outline_size", 5)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		window.add_child(arrow)
		arrow.set_anchors_and_offsets_preset(pair[1])
		arrow.offset_left += pair[2]

	var sheen := ColorRect.new()
	var sheen_sh := Shader.new()
	sheen_sh.code = """
shader_type canvas_item;
void fragment() {
	float g = smoothstep(0.45, 0.0, UV.y);
	COLOR = vec4(1.0, 1.0, 1.0, g * 0.08);
}
"""
	var sheen_mat := ShaderMaterial.new()
	sheen_mat.shader = sheen_sh
	sheen.material = sheen_mat
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(sheen)
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# big SPIN button
	spin_button = Button.new()
	spin_button.text = "SPIN"
	spin_button.custom_minimum_size = Vector2(0, 88)
	spin_button.focus_mode = Control.FOCUS_NONE
	spin_button.add_theme_font_size_override("font_size", 40)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var ssb := StyleBoxFlat.new()
		match state:
			"hover":
				ssb.bg_color = Color(1.0, 0.42, 0.32)
			"pressed":
				ssb.bg_color = Color(0.82, 0.25, 0.2)
			"disabled":
				ssb.bg_color = Color(0.5, 0.42, 0.45)
			_:
				ssb.bg_color = Color(0.95, 0.32, 0.26)
		ssb.set_corner_radius_all(44)
		ssb.border_width_bottom = 9
		ssb.border_color = ssb.bg_color.darkened(0.35)
		ssb.shadow_size = 10
		ssb.shadow_color = Color(0.95, 0.35, 0.2, 0.35)
		spin_button.add_theme_stylebox_override(state, ssb)
	spin_button.add_theme_color_override("font_color", Color.WHITE)
	spin_button.add_theme_color_override("font_hover_color", Color.WHITE)
	spin_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	spin_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	spin_button.add_theme_color_override("font_outline_color", Color(0.35, 0.05, 0.02))
	spin_button.add_theme_constant_override("outline_size", 8)
	spin_button.pressed.connect(func() -> void: spin_requested.emit())
	FX.press_feedback(spin_button)
	FX.pulse_forever(spin_button, 1.02, 1.5)
	vbox.add_child(spin_button)

	# bet multiplier + auto-spin row
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 14)
	vbox.add_child(controls)

	bet_button = Button.new()
	bet_button.custom_minimum_size = Vector2(150, 46)
	bet_button.focus_mode = Control.FOCUS_NONE
	bet_button.add_theme_font_size_override("font_size", 18)
	bet_button.pressed.connect(func() -> void:
		bet = BETS[(BETS.find(bet) + 1) % BETS.size()]
		_style_bet()
		Sfx.play("pop", -12.0)
	)
	FX.press_feedback(bet_button)
	controls.add_child(bet_button)
	_style_bet()

	auto_button = Button.new()
	auto_button.custom_minimum_size = Vector2(230, 46)
	auto_button.focus_mode = Control.FOCUS_NONE
	auto_button.add_theme_font_size_override("font_size", 17)
	auto_button.pressed.connect(func() -> void:
		set_auto(not auto_on)
		auto_toggled.emit(auto_on)
	)
	FX.press_feedback(auto_button)
	controls.add_child(auto_button)
	_style_auto()

func _style_bet() -> void:
	bet_button.text = "BET  x%d" % bet
	var col: Color
	match bet:
		1: col = Color(0.35, 0.4, 0.6)
		2: col = Color(0.3, 0.65, 0.4)
		3: col = Color(0.92, 0.6, 0.18)
		_: col = Color(0.88, 0.28, 0.38)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var bsb := StyleBoxFlat.new()
		match state:
			"hover":
				bsb.bg_color = col.lightened(0.12)
			"pressed":
				bsb.bg_color = col.darkened(0.12)
			"disabled":
				bsb.bg_color = col.darkened(0.3)
			_:
				bsb.bg_color = col
		bsb.set_corner_radius_all(23)
		bsb.border_width_bottom = 5
		bsb.border_color = col.darkened(0.35)
		bet_button.add_theme_stylebox_override(state, bsb)
	bet_button.add_theme_color_override("font_color", Color.WHITE)
	bet_button.add_theme_color_override("font_hover_color", Color.WHITE)
	bet_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	bet_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	bet_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	bet_button.add_theme_constant_override("outline_size", 4)

func set_auto(on: bool) -> void:
	auto_on = on
	_style_auto()

func _style_auto() -> void:
	auto_button.text = "AUTO  SPIN:  ON" if auto_on else "AUTO  SPIN:  OFF"
	for state in ["normal", "hover", "pressed"]:
		var asb := StyleBoxFlat.new()
		if auto_on:
			asb.bg_color = Color(1.0, 0.75, 0.2) if state != "hover" else Color(1.0, 0.82, 0.32)
			asb.border_color = Color(0.6, 0.4, 0.05)
		else:
			asb.bg_color = Color(1, 1, 1, 0.07) if state != "hover" else Color(1, 1, 1, 0.13)
			asb.border_color = Color(1, 1, 1, 0.18)
		asb.set_corner_radius_all(23)
		asb.set_border_width_all(2)
		auto_button.add_theme_stylebox_override(state, asb)
	var fcol := Color(0.4, 0.23, 0.02) if auto_on else Color(1, 1, 1, 0.75)
	auto_button.add_theme_color_override("font_color", fcol)
	auto_button.add_theme_color_override("font_hover_color", fcol)
	auto_button.add_theme_color_override("font_pressed_color", fcol)

func is_spinning() -> bool:
	return _spinning

func start_spin(result: Array) -> void:
	_result = result
	_spinning = true
	_t = 0.0
	_flicker = 0.0
	_stopped = [false, false, false]
	spin_button.disabled = true
	bet_button.disabled = true

func _process(delta: float) -> void:
	# marquee lights chase (faster while spinning)
	_bulb_t += delta
	if _bulb_t >= (0.14 if _spinning else 0.45):
		_bulb_t = 0.0
		_bulb_phase = not _bulb_phase
		for i in _bulbs.size():
			var bright := (i % 2 == 0) == _bulb_phase
			_bulbs[i].modulate = Color(1, 1, 1, 1.0) if bright else Color(1, 1, 1, 0.25)

	if not _spinning:
		return
	_t += delta
	_flicker += delta
	var do_flicker := _flicker >= 0.07
	if do_flicker:
		_flicker = 0.0
	var all_done := true
	for i in 3:
		if _stopped[i]:
			continue
		if _t >= _stop_times[i]:
			_stopped[i] = true
			_set_cell(i, _result[i])
			_pop_cell(i)
			Sfx.play("tick", -4.0)
		else:
			all_done = false
			if do_flicker:
				_set_cell(i, CV.SYMBOLS.pick_random())
	if all_done:
		_spinning = false
		spin_button.disabled = false
		bet_button.disabled = false
		spin_finished.emit(_result)

func _set_cell(i: int, symbol: String) -> void:
	var cell: Dictionary = _cells[i]
	var t := CV.symbol_tex(symbol)
	cell["tex"].visible = t != null
	cell["label"].visible = t == null
	if t != null:
		cell["tex"].texture = t
	else:
		cell["label"].text = CV.SYMBOL_EMOJI[symbol]

func _pop_cell(i: int) -> void:
	var panel: PanelContainer = _cells[i]["panel"]
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(1.18, 1.18)
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
