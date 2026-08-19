class_name FX
extends RefCounted

static func fly_coins(parent: Control, from: Vector2, to: Vector2, count: int) -> void:
	var t := CV.symbol_tex("coin")
	for i in count:
		var node: Control
		if t != null:
			var tr := TextureRect.new()
			tr.texture = t
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.size = Vector2(44, 44)
			node = tr
		else:
			var l := Label.new()
			l.text = "🪙"
			l.add_theme_font_override("font", CV.emoji_font())
			l.add_theme_font_size_override("font_size", 30)
			node = l
		node.position = from + Vector2(randf_range(-40, 40), randf_range(-30, 30))
		node.z_index = 100
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(node)
		var tw := parent.create_tween()
		tw.tween_interval(i * 0.06)
		tw.tween_property(node, "position", to, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(node, "scale", Vector2(0.5, 0.5), 0.55)
		tw.tween_callback(node.queue_free)

static func burst(parent: Control, pos: Vector2, color: Color, count := 14) -> void:
	for i in count:
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(randf_range(-0.1, 0.25))
		sb.set_corner_radius_all(12)
		p.add_theme_stylebox_override("panel", sb)
		var s := randf_range(8, 18)
		p.size = Vector2(s, s)
		p.position = pos
		p.z_index = 90
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(p)
		var dir := Vector2.from_angle(randf() * TAU) * randf_range(60, 220)
		var tw := parent.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", pos + dir, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, 0.5)
		tw.chain().tween_callback(p.queue_free)

static func confetti(parent: Control, count := 40) -> void:
	var colors := [Color(1, 0.8, 0.2), Color(0.9, 0.3, 0.4), Color(0.4, 0.8, 1.0), Color(0.5, 0.9, 0.5), Color(0.8, 0.5, 1.0)]
	for i in count:
		var p := ColorRect.new()
		p.color = colors.pick_random()
		p.size = Vector2(randf_range(8, 14), randf_range(10, 18))
		p.position = Vector2(randf_range(0, 720), randf_range(-120, -20))
		p.rotation = randf() * TAU
		p.z_index = 95
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(p)
		var tw := parent.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position:y", 1400.0, randf_range(1.3, 2.4)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "position:x", p.position.x + randf_range(-140, 140), 2.4)
		tw.tween_property(p, "rotation", p.rotation + randf_range(-7, 7), 2.4)
		tw.chain().tween_callback(p.queue_free)

static func shake(node: Control, amount := 12.0, times := 6) -> void:
	var orig := node.position
	var tw := node.create_tween()
	for i in times:
		tw.tween_property(node, "position", orig + Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.04)
	tw.tween_property(node, "position", orig, 0.05)

static func pulse_forever(node: Control, scale := 1.06, period := 0.8) -> void:
	node.resized.connect(func() -> void: node.pivot_offset = node.size * 0.5)
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "scale", Vector2(scale, scale), period * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE)

static func float_bob(node: Control, amp := 14.0, period := 2.0) -> void:
	var y := node.position.y
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "position:y", y - amp, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "position:y", y + amp, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

static func pop_in(node: Control, dur := 0.3) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.3, 0.3)
	node.create_tween().tween_property(node, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func flash(parent: Control, color := Color(1.0, 0.9, 0.4, 0.35)) -> void:
	var r := ColorRect.new()
	r.color = color
	r.z_index = 105
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := parent.create_tween()
	tw.tween_property(r, "modulate:a", 0.0, 0.45)
	tw.tween_callback(r.queue_free)

static func press_feedback(btn: Button) -> void:
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	btn.button_down.connect(func() -> void:
		btn.pivot_offset = btn.size * 0.5
		btn.create_tween().tween_property(btn, "scale", Vector2(0.93, 0.93), 0.06)
	)
	btn.button_up.connect(func() -> void:
		btn.create_tween().tween_property(btn, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

static func rise_label(parent: Control, pos: Vector2, text: String, color: Color, size := 30) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.position = pos
	l.z_index = 100
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	var tw := parent.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 90.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)
