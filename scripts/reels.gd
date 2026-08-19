class_name Reels
extends Control

# =============================================================================
#  THE REELS — three physical strips behind one window
# =============================================================================
#
# Each column is a loop of fourteen symbols that scrolls past a window three
# cells tall. Only the middle row pays; the rows above and below it are the
# neighbours on the strip, which is what makes a reel read as a wheel of
# printed symbols rather than a box that swaps pictures. It is also where the
# near miss lives -- a raccoon parked one cell above the payline is the whole
# reason a player watches the third reel land.
#
# The strips are fixed, not shuffled, so the machine is the same object every
# spin. Coin appears three times on each and the rare symbols once, so the
# strip itself telegraphs the odds the way a real reel does.

signal reel_stopped(index: int)

const COLS := 3
const ROWS := 3
const STRIP := 14
const STOP_AT := [0.95, 1.40, 1.90]
const TRAVEL := [3, 4, 5]    # whole strips passed before each reel lands

const STRIPS := [
	["coin", "hammer", "gem", "coin", "steal", "bag", "coin", "shield", "hammer", "gem", "bolt", "coin", "steal", "bag"],
	["gem", "coin", "shield", "hammer", "coin", "bolt", "steal", "coin", "bag", "gem", "hammer", "coin", "steal", "shield"],
	["hammer", "coin", "bag", "steal", "gem", "coin", "bolt", "shield", "coin", "hammer", "gem", "coin", "steal", "bag"],
]

var _pos := PackedFloat32Array([0.0, 0.0, 0.0])
var _from := PackedFloat32Array([0.0, 0.0, 0.0])
var _to := PackedFloat32Array([0.0, 0.0, 0.0])
var _speed := PackedFloat32Array([0.0, 0.0, 0.0])
var _stopped := PackedByteArray([1, 1, 1])
var _t := 0.0
var _spinning := false
var _settle := 0.0
var _win := 0.0
var _glow: Color = Lagoon.BRASS_HI
var _face: Color = Lagoon.SHELL
var _tex := {}
var _shade_top: GradientTexture2D
var _shade_bottom: GradientTexture2D
var _col_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for id in CV.SYMBOLS:
		_tex[id] = CV.symbol_tex(id)
	_col_style = StyleBoxFlat.new()
	_col_style.set_corner_radius_all(16)
	_shade_top = _shade(true)
	_shade_bottom = _shade(false)
	# park each reel on a different symbol so a fresh machine looks rolled, not reset
	for c in COLS:
		_pos[c] = float(c * 3 + 1)

# The window is deeper than it is tall: the strip disappears into shadow top
# and bottom instead of being cut off by a hard edge.
static func _shade(from_top: bool) -> GradientTexture2D:
	var g := Gradient.new()
	var ink := Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.46)
	var clear := Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.0)
	g.set_color(0, ink if from_top else clear)
	g.set_color(1, clear if from_top else ink)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 64
	return t

func apply_palette(p: Dictionary) -> void:
	_glow = p["glow"]
	_face = CV.palette_reel(p)
	queue_redraw()

# What is sitting on the payline right now, top row to bottom row.
func payline_centre(col: int) -> Vector2:
	var cw := size.x / float(COLS)
	return Vector2(cw * (float(col) + 0.5), size.y * 0.5)

# =============================================================================
#  Spinning
# =============================================================================

func is_spinning() -> bool:
	return _spinning

func start_spin(result: Array) -> void:
	_spinning = true
	_t = 0.0
	_settle = 0.0
	_win = 0.0
	for c in COLS:
		_stopped[c] = 0
		_from[c] = _pos[c]
		var strip: Array = STRIPS[c]
		var want: int = int(_pos[c]) + int(TRAVEL[c]) * STRIP
		# roll forward from there to the next cell carrying the rolled symbol
		var landed: int = want
		for k in STRIP:
			if strip[(want + k) % STRIP] == result[c]:
				landed = want + k
				break
		_to[c] = float(landed)
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if not _spinning:
		if _settle > 0.0 or _win > 0.0:
			_settle = maxf(0.0, _settle - delta)
			_win = maxf(0.0, _win - delta / 0.9)
			queue_redraw()
			if _settle == 0.0 and _win == 0.0:
				set_process(false)
		return

	_t += delta
	var all_done := true
	for c in COLS:
		if _stopped[c] == 1:
			continue
		var k := clampf(_t / float(STOP_AT[c]), 0.0, 1.0)
		var prev: float = _pos[c]
		_pos[c] = _from[c] + (_to[c] - _from[c]) * _decel(k)
		_speed[c] = absf(_pos[c] - prev) / maxf(delta, 0.0001)
		if k >= 1.0:
			_stopped[c] = 1
			_pos[c] = _to[c]
			_speed[c] = 0.0
			Sfx.play("tick", -5.0)
			reel_stopped.emit(c)
		else:
			all_done = false
	queue_redraw()
	if all_done:
		_spinning = false
		_settle = 0.5

# Flat out for most of the run, then a hard brake and a short bounce as the
# reel drops onto the detent.
func _decel(k: float) -> float:
	if k < 0.82:
		var u := k / 0.82
		return (1.0 - pow(1.0 - u, 3.2)) * 1.028
	var u2 := (k - 0.82) / 0.18
	return 1.028 - 0.028 * (1.0 - pow(1.0 - u2, 3.0))

# Three of a kind on the payline gets its own beat.
func celebrate() -> void:
	_win = 1.0
	set_process(true)
	queue_redraw()

# =============================================================================
#  Drawing
# =============================================================================

func _draw() -> void:
	var cw := size.x / float(COLS)
	var ch := size.y / float(ROWS)
	var cy := size.y * 0.5
	var sym := minf(cw, ch) * 0.86
	var pay := Rect2(0, cy - ch * 0.5, size.x, ch)

	for c in COLS:
		var x := cw * float(c)
		var strip: Array = STRIPS[c]
		var p: float = _pos[c]

		# the printed strip face, brighter across the payline row
		_col_style.bg_color = _face
		draw_style_box(_col_style, Rect2(x + 5.0, -4.0, cw - 10.0, size.y + 8.0))
		draw_rect(Rect2(x + 5.0, pay.position.y, cw - 10.0, ch),
			Color(1, 1, 1, 0.55))

		# Fast reels smear: the symbol stretches along the strip and thins out,
		# which is what stops a spinning reel from looking like a slide show.
		var blur: float = clampf(_speed[c] / 26.0, 0.0, 1.0)
		var alpha := 1.0 - 0.45 * blur
		var stretch := 1.0 + 1.1 * blur
		var base := int(floor(p))
		for k in 6:
			var i := base - 2 + k
			var y := (p - float(i)) * ch + cy
			if y < -ch or y > size.y + ch:
				continue
			var id: String = strip[posmod(i, STRIP)]
			var t: Texture2D = _tex.get(id)
			if t == null:
				continue
			var w := sym
			var h := sym * stretch
			draw_texture_rect(t, Rect2(x + (cw - w) * 0.5, y - h * 0.5, w, h), false,
				Color(1, 1, 1, alpha))

		# the strip runs off into shadow rather than ending at a cut edge
		draw_texture_rect(_shade_top, Rect2(x + 5.0, 0.0, cw - 10.0, ch * 0.80), false)
		draw_texture_rect(_shade_bottom, Rect2(x + 5.0, size.y - ch * 0.80, cw - 10.0, ch * 0.80), false)

		if _win > 0.0:
			var r := Rect2(x + 5.0, pay.position.y, cw - 10.0, ch).grow(-3.0 + 9.0 * (1.0 - _win))
			draw_rect(r, Color(_glow.r, _glow.g, _glow.b, _win * 0.9), false, 5.0)

	# column gutters, so three strips read as three reels
	for c in range(1, COLS):
		var gx := cw * float(c)
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), Color(Lagoon.ABYSS.r, Lagoon.ABYSS.g, Lagoon.ABYSS.b, 0.30), 3.0)

	# the payline itself: two brass rails the eye can rest on
	var rail := Lagoon.BRASS
	draw_line(Vector2(0, pay.position.y), Vector2(size.x, pay.position.y), rail, 3.0)
	draw_line(Vector2(0, pay.end.y), Vector2(size.x, pay.end.y), rail, 3.0)
