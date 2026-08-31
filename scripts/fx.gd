class_name FX
extends RefCounted

# Flies a handful of one symbol from a point on screen to the counter it pays
# into. `symbol` picks which: coins to the purse, bolts to the spin meter.
static func fly_coins(parent: Control, from: Vector2, to: Vector2, count: int,
		symbol := "coin", emoji := "🪙") -> void:
	var t := CV.symbol_tex(symbol)
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
			l.text = emoji
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
	# The viewport rather than the 720x1280 the game is drawn for: under
	# stretch/aspect "expand" a wide screen really is wider than the design, and
	# confetti hard-coded to 720 fell down the left-hand side of an iPad.
	var view := parent.get_viewport_rect().size
	var span := maxf(view.x, 720.0)
	var floor_y := maxf(view.y, 1280.0) + 120.0
	for i in count:
		var p := ColorRect.new()
		p.color = colors.pick_random()
		p.size = Vector2(randf_range(8, 14), randf_range(10, 18))
		p.position = Vector2(randf_range(0, span), randf_range(-120, -20))
		p.rotation = randf() * TAU
		p.z_index = 95
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(p)
		var tw := parent.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position:y", floor_y, randf_range(1.3, 2.4)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "position:x", p.position.x + randf_range(-140, 140), 2.4)
		tw.tween_property(p, "rotation", p.rotation + randf_range(-7, 7), 2.4)
		tw.chain().tween_callback(p.queue_free)

# Shakes a node and puts it back exactly where it started.
#
# "Where it started" is the catch. This read node.position at the moment it was
# called, so a second shake arriving while the first was still running captured
# a rattled mid-shake position as the rest state and left the node parked there
# -- and the node it is usually handed is a whole page, which then sits a few
# pixels off for the rest of the session. Two revenge hits in quick succession
# were enough to do it. The true rest position is remembered on the node itself
# and the running tween is killed rather than layered on top of.
const _SHAKE_HOME := "fx_shake_home"
const _SHAKE_RUN := "fx_shake_tween"

static func shake(node: Control, amount := 12.0, times := 6) -> void:
	# A shake already in flight is stopped and undone first, so `orig` below is
	# always the node's true rest position rather than wherever the last rattle
	# happened to leave it.
	if node.has_meta(_SHAKE_RUN):
		var running = node.get_meta(_SHAKE_RUN)
		if running is Tween and (running as Tween).is_valid():
			(running as Tween).kill()
		if node.has_meta(_SHAKE_HOME):
			node.position = node.get_meta(_SHAKE_HOME)
	var orig := node.position
	node.set_meta(_SHAKE_HOME, orig)
	var tw := node.create_tween()
	node.set_meta(_SHAKE_RUN, tw)
	for i in times:
		tw.tween_property(node, "position", orig + Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.04)
	tw.tween_property(node, "position", orig, 0.05)
	tw.tween_callback(func() -> void:
		node.remove_meta(_SHAKE_RUN)
		node.remove_meta(_SHAKE_HOME))

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

# =============================================================================
#  Impact
# =============================================================================
#
# A raid used to be a tap and a number. These are the four pieces that turn it
# into an event: something leaves a hand, something arrives, something gives,
# and something is left burning afterwards. They live here rather than in
# IslandVisit because none of them knows anything about raiding -- they are
# just a thrown thing, a shockwave, a puff and a plume.

# One soft round puff. Smoke, dust and steam are the same shape at different
# sizes and speeds, so they all come from here.
static func _puff(color: Color, diameter: float) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter * 0.5))
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(diameter, diameter)
	p.pivot_offset = Vector2(diameter, diameter) * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# A column of smoke off a damaged building. Puffs are launched over `spill`
# seconds rather than all at once, because smoke that arrives as one shape is a
# cloud sticker; smoke that keeps coming reads as something still burning.
static func smoke(parent: Control, pos: Vector2, count := 9, rise := 210.0,
		tint := Color(0.30, 0.28, 0.28), spill := 0.9, delay := 0.0) -> void:
	for i in count:
		var d := randf_range(34.0, 68.0)
		var p := _puff(Color(tint.r, tint.g, tint.b, randf_range(0.34, 0.55)), d)
		p.position = pos + Vector2(randf_range(-34, 34), randf_range(-10, 16)) - p.size * 0.5
		p.z_index = 92
		parent.add_child(p)
		var drift := randf_range(-70.0, 70.0)
		var tw := parent.create_tween()
		tw.tween_interval(delay + spill * float(i) / maxf(1.0, float(count)))
		tw.set_parallel(true)
		var span := randf_range(1.1, 1.9)
		tw.tween_property(p, "position:y", p.position.y - rise * randf_range(0.7, 1.25), span) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "position:x", p.position.x + drift, span)
		# Smoke expands as it cools. Without this it reads as a swarm of dots.
		tw.tween_property(p, "scale", Vector2(2.4, 2.4), span).set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "modulate:a", 0.0, span).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(p.queue_free)

# An expanding shockwave ring. Drawn as a hollow rounded box so it costs one
# node and no shader; at these radii the corner rounding is a circle.
static func ring(parent: Control, center: Vector2, color: Color, to_r: float,
		dur := 0.45, thickness := 9.0, from_r := 10.0) -> void:
	var r := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.0)
	sb.set_border_width_all(int(thickness))
	sb.border_color = color
	sb.set_corner_radius_all(int(to_r))
	r.add_theme_stylebox_override("panel", sb)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 94
	r.size = Vector2(from_r, from_r) * 2.0
	r.position = center - r.size * 0.5
	parent.add_child(r)
	var tw := parent.create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "size", Vector2(to_r, to_r) * 2.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "position", center - Vector2(to_r, to_r), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(r.queue_free)

# Throws `node` from one point to another along a parabola, spinning on the
# way. Straight-line tweens between the same two points read as a laser; the
# arc is the whole reason the throw looks thrown.
static func throw_arc(node: Control, from: Vector2, to: Vector2, height := 240.0,
		dur := 0.55, spin := TAU * 1.5) -> Tween:
	node.pivot_offset = node.size * 0.5
	node.position = from - node.size * 0.5
	var half := node.size * 0.5
	var tw := node.create_tween()
	tw.tween_method(func(u: float) -> void:
		var p := from.lerp(to, u)
		p.y -= sin(u * PI) * height
		node.position = p - half
	, 0.0, 1.0, dur)
	tw.parallel().tween_property(node, "rotation", spin, dur)
	return tw

# =============================================================================
#  Delivery
# =============================================================================
#
# A reward that the player watches arrive, instead of a counter that has
# already changed by the time they look up.
#
# The rule these two enforce together: THE NUMBER MOVES WHEN THE THING LANDS.
# `deliver` calls `on_land` once per item as that item reaches the counter, so
# three shields are three separate events with three separate thumps, and a
# player who looks away for half a second still sees the last of them arrive.
# Adding the total up front and playing an animation of it afterwards is the
# robotic version wearing a costume -- the counter is already right, so the
# flight is decoration and reads as one.
#
# `becomes` is the other half. Handing back an overflowing reward as something
# else is a story with a turn in it -- a shield that cannot fit BECOMES a
# spin -- and the turn has to happen on screen or it is just a different number
# appearing somewhere else. The swap fires at the apex of the arc, where the
# eye is already tracking the object; done at either end it reads as two
# objects rather than one changing.
static func deliver(parent: Control, from: Vector2, to: Vector2, symbol: String,
		count: int, on_land: Callable, becomes := "", arc := 190.0, gap := 0.17) -> void:
	if count <= 0 or parent == null or not is_instance_valid(parent):
		return
	var tex := CV.symbol_tex(symbol)
	var after: Texture2D = CV.symbol_tex(becomes) if becomes != "" else null
	for i in count:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(76, 76)
		tr.pivot_offset = tr.size * 0.5
		tr.z_index = 101
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate.a = 0.0
		parent.add_child(tr)
		var half := tr.size * 0.5
		tr.position = from - half
		# An Array rather than a plain local: the lambda below runs once per
		# frame of the flight and has to remember whether it has already done
		# the swap, and a captured bool is a copy.
		var turned := [false]
		var tw := parent.create_tween()
		tw.tween_interval(float(i) * gap)
		tw.tween_callback(func() -> void:
			tr.modulate.a = 1.0
			tr.scale = Vector2(0.5, 0.5))
		tw.tween_property(tr, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(u: float) -> void:
			if not is_instance_valid(tr):
				return
			var p := from.lerp(to, u)
			p.y -= sin(u * PI) * arc
			tr.position = p - half
			if u > 0.55:
				# Shrinking only on the way down, so it reads as going away
				# into the counter rather than as being thrown small.
				var k: float = lerpf(1.0, 0.42, (u - 0.55) / 0.45)
				tr.scale = Vector2(k, k)
			if after != null and not turned[0] and u >= 0.5:
				turned[0] = true
				tr.texture = after
				tr.scale = Vector2(1.35, 1.35)
				ring(parent, p, Color(0.72, 0.94, 1.0), 62.0, 0.36, 7.0, 10.0)
				Sfx.play("pop", -13.0)
		, 0.0, 1.0, 0.74).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void:
			tr.queue_free()
			on_land.call(i))

# The thump a counter gives when something lands in it. Scaled from its own
# centre, and the pivot is taken fresh every time -- these live in an HBox that
# re-lays out whenever the number beside them changes width.
static func counter_pop(node: Control, tint := Color(1, 1, 1, 0)) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.24, 1.24), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if tint.a > 0.0:
		burst(node.get_parent(), node.position + node.size * 0.5, tint, 7)
