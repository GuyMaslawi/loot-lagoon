class_name ChestOpen
extends Control

# =============================================================================
#  The chest opening -- one sequence, every chest, wherever it came from
# =============================================================================
#
# Until now NOTHING in this game ever opened a chest on screen. Six different
# places granted chest rewards and every one of them did it the same way: a
# dialog appeared with the contents already in it. The box the player had been
# staring at on a shelf, filling for forty spins, or paying real money for, was
# never the thing that opened -- it just stopped existing and a list took its
# place.
#
# That is the single biggest piece of reward theatre the game was missing, and
# it is worth more than the art: the fantasy is not "you received three cards",
# it is "the lid came off". So this is a takeover, not a popup. The chest falls
# into frame, lands hard enough to shake the screen, rattles because something
# inside wants out, and then the lid goes up and the light comes with it.
#
# GENERIC ON PURPOSE. The caller says which tier and hands back a node full of
# whatever it won; this file knows nothing about cards, coins, spins or who is
# paying. Every existing grant path can route through it without teaching it
# anything, and a new reward type costs nothing here.
#
#     var seq := ChestOpen.play(self, tier)
#     seq.opened.connect(func():
#         seq.set_contents(my_reward_row))     # whatever was won
#     seq.finished.connect(func(): ...)        # bank it / fly the counters
#
# The two signals are the whole contract. `opened` fires on the frame the lid
# pops, which is when contents should appear; `finished` fires after the player
# dismisses it, which is when rewards should fly to their counters -- never
# before, because of the held-counter rule (a reward lands on its readout as
# the pieces arrive, not while it is still inside a box).

signal opened
signal finished

# Above the popup (120) so a chest can open on top of the shop dialog that sold
# it, below the toast/raid strip (130) which must stay reachable. See the
# z-index ladder documented in main.gd.
const Z := 126

const FALL_TIME := 0.34
const RATTLES := 3

var _tier := 0
var _art: ChestArt
var _dim: ColorRect
var _sky: TakeoverSky
var _stage: Control
var _slot: Control          # where the caller's contents go
var _hint: Label
var _tw: Tween
var _state := 0             # 0 falling/rattling, 1 open, 2 dismissed


# `parent` is normally the page root. The sequence parents itself full-rect and
# frees itself on dismiss, so a caller never owns its lifetime.
static func play(parent: Control, tier: int, title := "") -> ChestOpen:
	var seq := ChestOpen.new()
	seq._tier = clampi(tier, 0, 2)
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

	# The reward's own place, faded up under the dim. A chest used to open over
	# a dimmed copy of the shop page that sold it, which is what kept the whole
	# sequence reading as a popup. See TakeoverSky.
	_sky = TakeoverSky.new()
	_sky.tint = Lagoon.LAGOON_DEEP
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
		plate.position = Vector2(vs.x * 0.5 - plate.size.x * 0.5, vs.y * 0.16)
		plate.modulate.a = 0.0
		create_tween().tween_property(plate, "modulate:a", 1.0, 0.3).set_delay(0.25)

	# The chest itself. Sized off the short edge so it reads the same on a pad
	# and a phone, and pivoted at its BOTTOM centre so the landing squash sits
	# it on the floor instead of scaling it about its middle.
	var box := minf(vs.x * 0.62, vs.y * 0.40)
	_art = ChestArt.new()
	_art.tier = _tier
	_art.custom_minimum_size = Vector2(box, box)
	_art.size = Vector2(box, box)
	_art.pivot_offset = Vector2(box * 0.5, box)
	_stage.add_child(_art)
	_art.position = Vector2(vs.x * 0.5 - box * 0.5, vs.y * 0.46 - box * 0.5)

	# Contents land under the chest once the lid is up.
	_slot = Control.new()
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.modulate.a = 0.0
	_stage.add_child(_slot)
	_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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


# The timeline. One tween chain owned by this node, so freeing it kills every
# pending step -- a dismiss during the fall can never fire a landing.
func _run() -> void:
	var vs := get_viewport_rect().size
	var rest := _art.position
	var high := Vector2(rest.x, -_art.size.y * 1.1)
	_art.position = high

	_tw = create_tween()
	_tw.tween_property(_dim, "color:a", 0.66, 0.20)

	# EASE_IN, not OUT: a falling object accelerates. An eased-out drop reads as
	# a thing being lowered on a wire.
	_tw.parallel().tween_property(_art, "position", rest, FALL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.08)
	_tw.tween_callback(_land)

	for i in RATTLES:
		_tw.tween_interval(0.16 if i == 0 else 0.13)
		_tw.tween_callback(_knock.bind(i))
	_tw.tween_interval(0.20)
	_tw.tween_callback(_pop)


func _land() -> void:
	var c := _art.global_position + _art.size * Vector2(0.5, 1.0)
	_art.scale = Vector2(1.26, 0.74)
	var t := create_tween()
	t.tween_property(_art, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	FX.shake(self, 11.0, 5)
	FX.ring(_stage, c, Lagoon.SAND_DEEP, 180.0, 0.42, 7.0)
	FX.smoke(_stage, c, 9, 120.0, Color(0.72, 0.66, 0.54), 1.1)
	FX.haptic(16, 0.45)
	Sfx.play("build", -4.0)


# Something inside wants out. Small, quick, and it gets faster -- the last
# knock is the one that pops the lid, so they read as a build-up rather than
# three identical wobbles.
func _knock(i: int) -> void:
	if _state != 0:
		return
	var amp := 0.05 + 0.03 * float(i)
	_art.scale = Vector2(1.0 + amp, 1.0 - amp)
	var t := create_tween()
	t.tween_property(_art, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
	Sfx.play("tick", -12.0, 0.10, 1.0 + 0.12 * float(i))


func _pop() -> void:
	if _state != 0:
		return
	_state = 1
	_art.open = true

	var c := _art.global_position + _art.size * Vector2(0.5, 0.55)
	_art.scale = Vector2(0.90, 1.14)
	var t := create_tween()
	t.tween_property(_art, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

	# The top tier gets the full fanfare; the wooden box does not, because if
	# every chest celebrates identically then opening the expensive one feels
	# exactly like opening the free one.
	FX.flash(self, Color(1.0, 0.90, 0.52, 0.30 + 0.08 * float(_tier)))
	FX.ring(_stage, c, Lagoon.BRASS_HI, 260.0, 0.52, 9.0)
	FX.burst(_stage, c, Lagoon.BRASS_HI, 14 + 6 * _tier)
	FX.fountain(_stage, c, 12 + 8 * _tier)
	if _tier >= 2:
		FX.confetti(self, 34)
	FX.haptic(26, 0.7)
	Sfx.play("jackpot" if _tier >= 2 else "levelup", -3.0)

	create_tween().tween_property(_slot, "modulate:a", 1.0, 0.28).set_delay(0.12)
	create_tween().tween_property(_hint, "modulate:a", 1.0, 0.35).set_delay(0.85)
	opened.emit()


# The caller's reward display. Added under the chest, centred, after `opened`.
func set_contents(node: Control) -> void:
	if _slot == null or not is_instance_valid(_slot):
		return
	var vs := get_viewport_rect().size
	_slot.add_child(node)
	node.position = Vector2(vs.x * 0.5 - node.size.x * 0.5, vs.y * 0.62)


# THE CARDS COME OUT OF THE BOX.
#
# `set_contents` fades a finished panel in under the chest, which is right for
# a caller that has its own layout to show. It is wrong for the thing the box
# screen is actually for: a box that opens and a handful of cards that do not
# come out of it is still a list appearing next to a prop. Guy called this on
# his own phone -- every action has to be a movement.
#
# So this takes the tiles the caller has already built and throws them out of
# the lid, one after another, on an arc, spinning, into a grid. The box does
# not vanish -- it drifts up and back and dims instead. That way the object the
# player earned is still on screen holding the frame together while the cards
# it paid out become the subject, and the screen never has an empty middle.
#
# The caller owns the tiles' contents and their size; this owns where they land
# and how they get there. Tiles must have `custom_minimum_size` set, because
# they are placed by hand and never see a container.
func burst_out(tiles: Array, tile_size: Vector2, cols := 3) -> void:
	if _slot == null or not is_instance_valid(_slot) or tiles.is_empty():
		return
	var vs := get_viewport_rect().size

	# The box gets out of the way first. Bottom-centre pivot means a plain
	# scale would pull its lid DOWN into the cards, so the position moves with
	# the scale to keep it reading as the box floating back.
	var s := 0.78
	var box := _art.size.x
	var lift := _art.create_tween().set_parallel(true)
	lift.tween_property(_art, "scale", Vector2(s, s), 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lift.tween_property(_art, "position:y",
		vs.y * 0.34 - box + box * s * 0.5, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lift.tween_property(_art, "modulate",
		Color(0.82, 0.88, 0.92, 1.0), 0.34)

	# Everything leaves the lid, not the middle of the box -- the mouth is
	# where a lid that has just come off would let something out.
	var from := Vector2(_art.global_position.x + box * 0.5,
		vs.y * 0.34 - box * s * 0.22)

	var n := tiles.size()
	var per := mini(cols, n)
	var rows := int(ceil(float(n) / float(per)))
	var gap := 10.0
	var grid_w := float(per) * tile_size.x + float(per - 1) * gap
	var grid_h := float(rows) * tile_size.y + float(rows - 1) * gap
	var origin := Vector2(vs.x * 0.5 - grid_w * 0.5,
		vs.y * 0.66 - grid_h * 0.5)

	for i in n:
		var tile: Control = tiles[i]
		if tile == null or not is_instance_valid(tile):
			continue
		_slot.add_child(tile)
		tile.size = tile_size
		tile.pivot_offset = tile_size * 0.5
		var r := i / per
		# The last row is centred under the ones above it, so three cards over
		# two do not come out left-aligned with a hole on the right.
		var in_row := mini(per, n - r * per)
		var row_w := float(in_row) * tile_size.x + float(in_row - 1) * gap
		var target := Vector2(
			vs.x * 0.5 - row_w * 0.5 + float(i % per) * (tile_size.x + gap),
			origin.y + float(r) * (tile_size.y + gap)) + tile_size * 0.5

		tile.scale = Vector2(0.24, 0.24)
		tile.modulate.a = 0.0
		var delay := 0.30 + 0.11 * float(i)

		var tw := tile.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void:
			if not is_instance_valid(tile):
				return
			tile.modulate.a = 1.0
			# Height and spin scale down the further the card has to travel, so
			# a card landing on the near row does not loop over the far one.
			FX.throw_arc(tile, from, target, 150.0 + 40.0 * float(r), 0.52,
				TAU * (0.75 if i % 2 == 0 else -0.75))
			var st := tile.create_tween()
			st.tween_property(tile, "scale", Vector2.ONE, 0.52) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			# Rotation is left at zero by the arc's own spin only if it lands on
			# a whole turn; it does not, so it is settled explicitly.
			st.parallel().tween_property(tile, "rotation", 0.0, 0.30) \
				.set_delay(0.30).set_trans(Tween.TRANS_SINE)
			FX.burst(_stage, from, Lagoon.BRASS_HI, 5)
			Sfx.play("pop", -7.0, 0.0, 1.02 + 0.05 * float(i))
			FX.haptic(9, 0.3))


# Where the chest is, for a caller that wants rewards to fly out of it.
func chest_center() -> Vector2:
	if _art == null or not is_instance_valid(_art):
		return get_viewport_rect().size * 0.5
	return _art.global_position + _art.size * Vector2(0.5, 0.5)


# A tap before the lid pops skips straight to it; a tap after collects. Never
# ignore the first tap -- a player who taps during an animation is telling you
# the animation is too long.
func _on_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.is_pressed()):
		return
	if _state == 0:
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_art.position = Vector2(_art.position.x,
			get_viewport_rect().size.y * 0.46 - _art.size.y * 0.5)
		_pop()
	elif _state == 1:
		_dismiss()


# Finish now, from outside, without a tap.
#
# THIS EXISTS BECAUSE OF THE RAID. A full-screen overlay that only a tap can
# clear is the hazard documented as trap one in the QA notes: headless nothing
# taps it, so it owns the screen for ever and every later check silently runs
# behind a modal. It is not only a test problem -- offline reward processing,
# a forced-update gate and auto-spin all need to be able to get a stuck
# celebration off the screen. `reveal` decides whether the player still gets to
# see what they won or the whole thing is torn down.
func skip(reveal := true) -> void:
	if _state == 2:
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if _state == 0 and reveal:
		_pop()
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
