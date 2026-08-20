class_name Matchmaking
extends Control

# The search.
#
# A triple of hammers or raccoons used to drop you straight onto somebody's
# island, which reads as the machine handing you a prize rather than the game
# finding you an opponent. This is the half-second of theatre in between: a
# sonar disc sweeping the map, faces and names flicking past under it, a scan
# line that counts islands, and then the one rival it settled on, held up long
# enough to read before you sail over and rob them.
#
# It is theatre with a rule: the rival it lands on is the rival main.gd already
# committed to -- the one whose name and vault have been sitting on the card
# above the wheel since before the reels moved. The flicker is a shuffle of
# other faces, never a re-draw. What the card promised is what the search
# finds, every time.

signal finished(npc: Dictionary)

# The rival main.gd locked in. Nothing in here is allowed to change it.
var npc: Dictionary
var mode := "steal"
# The vault as it will actually pay out -- island curve and bet already applied
# -- so the figure the search quotes is the figure in the chests.
var stake := 0
# Stars standing on their island: what an attack has to knock down. A raid with
# hammers never touches the vault, so quoting coins at it would be a lie.
var stars := 0

const LEAD_SECS := 0.35    # main's "Triple raccoons!" banner, still talking
const SEARCH_SECS := 1.5   # sweeping
const HOLD_SECS := 1.15    # the found rival, held for reading

var _disc: Control
var _sweep: Control
var _rings: Array = []
var _face: Label
var _name_label: Label
var _meta: Control
var _flag: Label
var _home: Label
var _vault: Control
var _bar: ProgressBar
var _status: Label
var _online: Label
var _hint: Label
var _title: Label
var _shield_chip: Control
var _well: Panel

var _found := false
var _closed := false
var _live := false   # taps do nothing until the search is actually on screen
var _run: Tween      # the sweep timer, killed when a tap lands the match early
var _shuffle_accum := 0.0
var _blip_accum := 0.0
var _scanned := 0
var _online_count := 0
var _status_step := 0
var _status_accum := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var view := get_viewport_rect().size
	var top := UI.safe_top(view)
	var bottom := UI.safe_bottom(view)

	var scrim := ColorRect.new()
	scrim.color = Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.95)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# One column down the middle of the safe area. The disc is the anchor and
	# everything else hangs off it, so the layout survives any phone shape.
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = top + 40.0
	col.offset_bottom = -(bottom + 40.0)

	var plate := Lagoon.plaque("FINDING  A  RIVAL", 0.0, 76.0, 40)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(plate)
	_title = plate.get_meta("label")

	_online = Lagoon.label("", UI.F_CAPTION, Color(0.72, 0.88, 0.92))
	_online.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_online)

	_build_disc(col)

	_name_label = Lagoon.title("", UI.F_HEAD, Lagoon.SAND, Lagoon.ABYSS)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name_label)

	_build_meta(col)
	_build_vault(col)

	_bar = Lagoon.progress(Lagoon.LAGOON)
	_bar.custom_minimum_size = Vector2(420, 22)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 100.0
	_bar.value = 0.0
	col.add_child(_bar)

	_status = Lagoon.label("", UI.F_CAPTION, Color(0.66, 0.84, 0.88))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	_hint = Lagoon.label("tap  to  skip", UI.F_TINY, Color(0.55, 0.72, 0.78))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)

	# A believable room, seeded per search and drifting while you watch.
	_online_count = randi_range(2_400, 18_500)
	_scanned = 0
	_tick_status()

	scrim.modulate.a = 0.0
	create_tween().tween_property(scrim, "modulate:a", 1.0, 0.2)
	FX.pop_in(_disc, 0.35)
	Sfx.play("tick", -8.0)

	_run = create_tween()
	var tw := _run
	tw.tween_interval(LEAD_SECS)
	tw.tween_callback(func() -> void: _live = true)
	tw.tween_property(_bar, "value", 100.0, SEARCH_SECS).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_lock_in)

func _build_disc(col: VBoxContainer) -> void:
	_disc = Control.new()
	_disc.custom_minimum_size = Vector2(400, 400)
	_disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_disc)
	_disc.pivot_offset = Vector2(200, 200)

	# Water inside the outermost ring, so the sweep has something to sweep.
	_well = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Lagoon.LAGOON_DEEP.r, Lagoon.LAGOON_DEEP.g, Lagoon.LAGOON_DEEP.b, 0.42)
	sb.set_corner_radius_all(200)
	sb.set_border_width_all(0)
	_well.add_theme_stylebox_override("panel", sb)
	_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.add_child(_well)
	_well.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for d in [400.0, 292.0, 184.0]:
		var ring := Panel.new()
		var rs := Lagoon.brass_ring(4.0)
		rs.border_color = Color(Lagoon.BRASS.r, Lagoon.BRASS.g, Lagoon.BRASS.b, 0.55 if d < 400.0 else 0.95)
		ring.add_theme_stylebox_override("panel", rs)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.size = Vector2(d, d)
		ring.position = Vector2(200.0 - d * 0.5, 200.0 - d * 0.5)
		ring.pivot_offset = Vector2(d, d) * 0.5
		_disc.add_child(ring)
		_rings.append(ring)

	# The sonar hand: a beam pinned at the centre, fading out towards the rim,
	# spun by _process. A rectangle rather than a wedge -- against the rings it
	# reads as a sweep either way, and it costs one texture.
	_sweep = Control.new()
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.position = Vector2(200, 200)
	_disc.add_child(_sweep)

	var grad := Gradient.new()
	grad.set_color(0, Color(Lagoon.LAGOON.r, Lagoon.LAGOON.g, Lagoon.LAGOON.b, 0.0))
	grad.set_color(1, Color(Lagoon.LAGOON.r, Lagoon.LAGOON.g, Lagoon.LAGOON.b, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 8
	gt.height = 190
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var beam := TextureRect.new()
	beam.texture = gt
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.size = Vector2(8, 190)
	beam.position = Vector2(-4, -190)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.add_child(beam)

	# The face in the middle of the dish. During the search it is whoever the
	# beam is passing over; when the search lands it becomes the rival.
	var token := Lagoon.token("?", 148.0, Lagoon.BRASS)
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.add_child(token)
	token.position = Vector2(126, 126)
	token.size = Vector2(148, 148)
	for c in token.get_children():
		if c is Label:
			_face = c
			break

func _build_meta(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate.a = 0.0
	col.add_child(row)
	_meta = row

	var region := Lagoon.chip("", Lagoon.LAGOON_DEEP, UI.F_TINY)
	row.add_child(region)
	for c in region.get_children():
		if c is Label:
			_flag = c
			break

	_home = Lagoon.label("", UI.F_LABEL, Color(0.78, 0.9, 0.94))
	row.add_child(_home)

	_shield_chip = Lagoon.chip("SHIELDED", Lagoon.LAGOON, UI.F_TINY)
	_shield_chip.visible = false
	row.add_child(_shield_chip)

func _build_vault(col: VBoxContainer) -> void:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	col.add_child(box)
	_vault = box

	var pot := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Lagoon.BRASS_MID
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.border_color = Lagoon.BRASS_LO
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 6.0
	pot.add_theme_stylebox_override("panel", sb)
	box.add_child(pot)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	pot.add_child(inner)
	if mode == "attack":
		var star := Label.new()
		star.text = "⭐"
		star.add_theme_font_override("font", CV.emoji_font())
		star.add_theme_font_size_override("font_size", UI.F_LABEL)
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(star)
		inner.add_child(Lagoon.title("%d to smash" % stars, UI.F_SUBHEAD, Lagoon.SAND, Lagoon.BRASS_LO.darkened(0.3)))
	else:
		var mark := TextureRect.new()
		mark.texture = CV.symbol_tex("coin")
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(38, 38)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(mark)
		inner.add_child(Lagoon.title(UI.fmt_compact(stake), UI.F_SUBHEAD, Lagoon.SAND, Lagoon.BRASS_LO.darkened(0.3)))

# --- the search ---

func _process(delta: float) -> void:
	if _found:
		return
	_sweep.rotation += delta * TAU * 1.15

	# Faces and names flick past at reading speed -- fast enough to look like a
	# list going by, slow enough that you catch one or two of them.
	_shuffle_accum += delta
	if _shuffle_accum >= 0.085:
		_shuffle_accum = 0.0
		var def: Dictionary = CV.BOT_DEFS.pick_random()
		_face.text = def["emoji"]
		_name_label.text = def["name"]

	_blip_accum += delta
	if _blip_accum >= 0.11:
		_blip_accum = 0.0
		_blip()

	_status_accum += delta
	if _status_accum >= 0.5:
		_status_accum = 0.0
		_status_step += 1
		_tick_status()

	_scanned += int(round(delta * randf_range(900.0, 1500.0)))
	_online_count += randi_range(-3, 5)
	_online.text = "%s islands online" % UI.fmt(maxi(0, _online_count))

# A contact under the beam: it appears where the hand is pointing and fades,
# which is what sells the sweep as a thing that is finding something.
func _blip() -> void:
	var dot := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.72, 1.0, 0.86, 0.95)
	sb.set_corner_radius_all(8)
	dot.add_theme_stylebox_override("panel", sb)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := randf_range(96.0, 186.0)
	var a := _sweep.rotation - PI * 0.5 + randf_range(-0.22, 0.0)
	var s := randf_range(9.0, 15.0)
	dot.size = Vector2(s, s)
	dot.position = Vector2(200, 200) + Vector2(cos(a), sin(a)) * r - Vector2(s, s) * 0.5
	_disc.add_child(dot)
	var tw := dot.create_tween()
	tw.tween_property(dot, "modulate:a", 0.0, 0.75)
	tw.parallel().tween_property(dot, "scale", Vector2(1.6, 1.6), 0.75)
	tw.tween_callback(dot.queue_free)

const STATUS_LINES := [
	"Opening the raid net…",
	"Scanning %s islands…",
	"Reading vaults…",
	"Checking who has a shield up…",
	"Picking your rival…",
]

func _tick_status() -> void:
	var line: String = STATUS_LINES[mini(_status_step, STATUS_LINES.size() - 1)]
	_status.text = line % UI.fmt(_scanned) if line.contains("%s") else line

# --- the match ---

func _lock_in() -> void:
	if _found:
		return
	_found = true
	set_process(false)
	if _run != null and _run.is_valid():
		_run.kill()
	_bar.value = 100.0

	# The beam parks on the rival and the dish goes quiet.
	var st := _sweep.create_tween()
	st.tween_property(_sweep, "modulate:a", 0.0, 0.25)
	for ring in _rings:
		var rs: StyleBoxFlat = ring.get_theme_stylebox("panel")
		rs.border_color = Lagoon.BRASS_HI
		ring.create_tween().tween_property(ring, "scale", Vector2.ONE, 0.3).from(Vector2(1.06, 1.06)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# The dish takes on the colour of the island it settled on, so the water
	# inside the rings is already the water you are about to sail into.
	var p := CV.island_palette(int(npc.get("island", 1)))
	var ws: StyleBoxFlat = _well.get_theme_stylebox("panel")
	var tint: Color = p["mid"]
	ws.bg_color = Color(tint.r, tint.g, tint.b, 0.52)

	# The track has nothing left to measure once the search is over.
	_bar.create_tween().tween_property(_bar, "modulate:a", 0.0, 0.2)

	_title.text = "RIVAL  FOUND"
	_face.text = npc.get("emoji", "🏴")
	_name_label.text = str(npc.get("name", "Rival"))
	_name_label.add_theme_color_override("font_color", Lagoon.BRASS_HI)
	_flag.text = str(npc.get("flag", "??"))
	_home.text = CV.island_theme(int(npc.get("island", 1)))["name"]
	_shield_chip.visible = mode == "attack" and bool(npc.get("shield", false))
	_status.text = "Ready to %s" % ("steal" if mode == "steal" else "attack")
	_hint.text = "tap  to  go"

	_face.pivot_offset = _face.size * 0.5
	_face.scale = Vector2(1.5, 1.5)
	_face.create_tween().tween_property(_face, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_meta.create_tween().tween_property(_meta, "modulate:a", 1.0, 0.22)
	_vault.create_tween().tween_property(_vault, "modulate:a", 1.0, 0.22).set_delay(0.08)
	FX.pop_in(_vault, 0.3)
	FX.burst(self, _disc.get_global_rect().get_center() - global_position, Lagoon.BRASS_HI, 16)
	Sfx.play("jackpot", -8.0)

	var tw := create_tween()
	tw.tween_interval(HOLD_SECS)
	tw.tween_callback(_close)

func _close() -> void:
	if _closed:
		return
	_closed = true
	finished.emit(npc)

# One tap moves the search along: during the sweep it lands the match, on the
# match it sails. Players who have seen the animation forty times should never
# have to sit through it.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventMouseButton):
		return
	if not event.is_pressed():
		return
	accept_event()
	if not _live:
		return
	if _found:
		_close()
	else:
		_lock_in()
