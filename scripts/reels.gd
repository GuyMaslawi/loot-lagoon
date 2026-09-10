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
# spin, and coin is the densest symbol on all three (four cells of fourteen)
# with bolt the sparsest.
#
# What the strip does NOT do is set the odds, and the comment here used to say
# it did. The outcome is rolled first, in main.gd's _roll(), and start_spin()
# then searches the strip for the symbol it was handed and drives the reel to
# stop there -- so the strip decides what the near misses look like and nothing
# else. Sampling the printed cells would give a triple about 3.5% of the time;
# the real rate is around 31%, because _roll() forces a triple 30% of the time
# outright. Retuning these arrays changes the show, not the payouts. Anyone
# after the payouts wants CV.SYMBOLS and _roll().

signal reel_stopped(index: int)

const COLS := 3
const ROWS := 3
const STRIP := 14
const STOP_AT := [0.95, 1.40, 1.90]
const TRAVEL := [3, 4, 5]    # whole strips passed before each reel lands

# =============================================================================
#  The hold
# =============================================================================
#
# When the first two reels land on the same symbol, the third one does not stop
# on schedule. It keeps running long after the other two have gone quiet, then
# slows to a crawl and creeps onto its cell one detent at a time.
#
# This is the only moment in the machine where the show is worth more than the
# payout, and until now nothing produced it: STOP_AT was three fixed numbers, so
# the third reel took exactly 1.90 seconds whether it was about to pay a jackpot
# or nothing at all.
#
# NOTHING HERE TOUCHES THE OUTCOME. _roll() has already decided all three
# symbols before start_spin is called, and the cell this reel lands on is the
# same cell it would have landed on at the old timing. The hold paces the
# reveal; it does not bend it, and it must never be made to -- a reel that
# creeps past the winning symbol more often than chance put it there is a
# different thing entirely, and not one this game does.
#
# It is spent on the four symbols worth waiting for -- the jackpot, the gems and
# the two that open a raid -- and not on coin, shield or bolt. Held on every
# matching pair it would fire on 40% of spins and stop reading as an event; held
# on these four it lands around one spin in four, which is the rate a player
# still leans in at.
const HOLD_AT := 3.30        # what the third reel's stop time becomes
const HOLD_TRAVEL := 14      # more strip to cover, so it still LEAVES at speed
const HOLD_POWER := 2.6      # the long tail: fast for a second, then a crawl
const HOLD_SYMBOLS := ["bag", "gem", "hammer", "steal"]

# Below this, the strip reads as individual symbols rather than a smear, and
# each cell boundary it crosses gets a detent tick.
const TICK_SPEED := 22.0

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
var _stop_at := PackedFloat32Array([0.95, 1.40, 1.90])
var _held := false
var _heat := 0.0        # how lit the held column is, 0 while it is still a blur
var _tick_cell := -1    # last cell the crawling reel ticked on
var _t := 0.0
var _spinning := false
var _settle := 0.0
var _win := 0.0
var _want := ""         # the held pair's symbol, so the miss can point at it
var _miss := 0.0        # the "it was RIGHT THERE" beat, 0 while quiet
var _miss_up := true    # whether the wanted symbol stopped above the payline
var _near := false      # latched for slot_view to read once, after the stop
var _glow: Color = Lagoon.BRASS_HI
var _face: Color = Lagoon.SHELL
var _tex := {}
var _shade_top: GradientTexture2D
var _shade_bottom: GradientTexture2D
var _sweep_tex: GradientTexture2D
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
	_sweep_tex = _sweep()
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

# True once the other two have landed matching and the third is still running.
# slot_view leans on this for the beat it puts on screen at the same moment.
func is_holding() -> bool:
	return _held

func start_spin(result: Array) -> void:
	_spinning = true
	_t = 0.0
	_settle = 0.0
	_win = 0.0
	_miss = 0.0
	_near = false
	_heat = 0.0
	_tick_cell = -1
	# Decided here, off the roll, because the reel needs its extra strip from
	# the first frame -- a reel told to keep going only once the second one
	# lands has nowhere left to travel and would have to stall in place.
	_held = result.size() >= 2 and result[0] == result[1] \
		and HOLD_SYMBOLS.has(String(result[0]))
	_want = String(result[0]) if _held else ""
	for c in COLS:
		_stop_at[c] = HOLD_AT if (_held and c == 2) else float(STOP_AT[c])
		_stopped[c] = 0
		# Wrapped back onto the strip before anything is measured from it.
		#
		# A reel travels three to five whole strips per spin and _pos only ever
		# went up, so on a save that has been played for months it is a number
		# in the millions -- and these are 32-bit floats, whose spacing at a
		# million is already a sixteenth of a cell. The scroll quantises, the
		# blur reads wrong, and far enough out the reel cannot represent a
		# fractional position at all and starts jumping between symbols. Nothing
		# downstream cares about the absolute value: _draw takes posmod of it.
		_pos[c] = fposmod(_pos[c], float(STRIP))
		_from[c] = _pos[c]
		var strip: Array = STRIPS[c]
		var strips: int = HOLD_TRAVEL if (_held and c == 2) else int(TRAVEL[c])
		var want: int = int(_pos[c]) + strips * STRIP
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
		if _settle > 0.0 or _win > 0.0 or _heat > 0.0 or _miss > 0.0:
			_settle = maxf(0.0, _settle - delta)
			_win = maxf(0.0, _win - delta / 0.9)
			# Slower than the win: the miss is read, not celebrated, and the
			# eye needs a beat longer to find a cell it was not looking at.
			_miss = maxf(0.0, _miss - delta / 1.3)
			# Faster than the settle, so the column has cooled by the time a
			# win takes the payline over and the two glows never stack.
			_heat = maxf(0.0, _heat - delta * 3.2)
			queue_redraw()
			if _settle == 0.0 and _win == 0.0 and _heat == 0.0 and _miss == 0.0:
				set_process(false)
		return

	_t += delta
	var all_done := true
	for c in COLS:
		if _stopped[c] == 1:
			continue
		var holding: bool = _held and c == 2
		var k := clampf(_t / _stop_at[c], 0.0, 1.0)
		var prev: float = _pos[c]
		_pos[c] = _from[c] + (_to[c] - _from[c]) * (_crawl(k) if holding else _decel(k))
		_speed[c] = absf(_pos[c] - prev) / maxf(delta, 0.0001)
		if holding:
			_heat = clampf((k - 0.45) / 0.45, 0.0, 1.0)
			_detent()
		if k >= 1.0:
			_stopped[c] = 1
			_pos[c] = _to[c]
			_speed[c] = 0.0
			# The hold that came to nothing gets its own read-out. The player
			# just watched this reel crawl for a second and a half; if the symbol
			# they were waiting for stopped one cell off the payline, saying
			# nothing is the machine pretending the crawl was about nothing. The
			# cell is rimmed where it actually landed -- above or below -- so the
			# miss is shown, not asserted. Detected off the strip the reel really
			# stopped on, so it can only fire when it is true.
			if holding and _want != "":
				var strip2: Array = STRIPS[2]
				var landed_on := String(strip2[posmod(int(_to[2]), STRIP)])
				var above := String(strip2[posmod(int(_to[2]) + 1, STRIP)])
				var below := String(strip2[posmod(int(_to[2]) - 1, STRIP)])
				if landed_on != _want and (above == _want or below == _want):
					_miss = 1.0
					_miss_up = above == _want
					_near = true
			Sfx.play("tick", -5.0)
			reel_stopped.emit(c)
		else:
			all_done = false
	queue_redraw()
	if all_done:
		_spinning = false
		_settle = 0.5

# The held reel's curve. It leaves at the same speed the other two did -- the
# extra strips in HOLD_TRAVEL are what buy that, so the hold never reads as a
# reel that started slow -- and then bleeds off for the rest of its run, so the
# last half second is a visible creep from one cell to the next.
#
# No overshoot and no bounce, unlike _decel: a reel arriving at two cells a
# second has no momentum to bounce with, and giving it one looks like a nudge.
func _crawl(k: float) -> float:
	return 1.0 - pow(1.0 - k, HOLD_POWER)

# One click per cell once the held reel is slow enough for the symbols to read,
# pitched up as it runs out of travel. About seven of these land in the last
# second -- the sound of a reel being watched, rather than one being waited on.
func _detent() -> void:
	if _speed[2] > TICK_SPEED:
		_tick_cell = -1        # still a smear; there is nothing to click yet
		return
	var cell := int(floor(_pos[2]))
	if _tick_cell < 0:
		_tick_cell = cell      # arm on the cell it was in, do not tick for it
		return
	if cell == _tick_cell:
		return
	_tick_cell = cell
	var climb := 1.0 - clampf(_speed[2] / TICK_SPEED, 0.0, 1.0)
	Sfx.play("tick", -13.0 + 5.0 * climb, 0.04, 1.0 + 0.55 * climb)

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

# Whether the spin that just ended held the third reel and missed by one cell.
# Read-once, because the machine's sign should call it exactly once per spin --
# a flag that stays up would say SO CLOSE again on the next refresh.
func consume_near_miss() -> bool:
	var n := _near
	_near = false
	return n

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

		# The printed strip face, brighter across the payline row -- and warmer
		# still on the held reel, which heats up as it runs out of travel.
		# Handed straight over to the win glow the moment celebrate() fires, so
		# the two rings are never on screen together.
		var heat: float = _heat if (c == 2 and _win == 0.0) else 0.0
		_col_style.bg_color = _face.lerp(Lagoon.BRASS_HI, 0.20 * heat)
		draw_style_box(_col_style, Rect2(x + 5.0, -4.0, cw - 10.0, size.y + 8.0))
		draw_rect(Rect2(x + 5.0, pay.position.y, cw - 10.0, ch),
			Color(1, 1, 1, 0.55 + 0.30 * heat))

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

		# The rim on the cell the held reel is creeping towards. Drawn over the
		# shadow, because the point of it is to say where to look.
		if heat > 0.0:
			draw_rect(Rect2(x + 5.0, pay.position.y, cw - 10.0, ch).grow(1.0),
				Color(_glow.r, _glow.g, _glow.b, 0.85 * heat), false, 2.0 + 3.0 * heat)

		# The miss, on the cell the wanted symbol actually stopped in. Coral,
		# not the island glow -- the glow is the colour of things going right on
		# this machine, and borrowing it for a miss would teach the player it
		# means nothing. Drawn over the shade for the same reason the heat rim
		# is: the whole point is to drag the eye one cell off the payline.
		if c == 2 and _miss > 0.0:
			var mr := Rect2(x + 5.0, pay.position.y + (-ch if _miss_up else ch),
				cw - 10.0, ch)
			draw_rect(mr, Color(Lagoon.CORAL_HI.r, Lagoon.CORAL_HI.g,
				Lagoon.CORAL_HI.b, 0.20 * _miss))
			draw_rect(mr.grow(-2.0), Color(Lagoon.CORAL_HI.r, Lagoon.CORAL_HI.g,
				Lagoon.CORAL_HI.b, 0.9 * _miss), false, 4.0)

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

	# =========================================================================
	#  The winning LINE, not three winning cells
	# =========================================================================
	#
	# celebrate() used to light each column's payline cell on its own, and three
	# separate rings around three separate cells is a win told three times in a
	# whisper. What pays is the line, so the line is what lights: the rails come
	# up in the island's glow for the whole width of the window, one bright pass
	# sweeps along the row the way a finger would trace it, and a handful of
	# glints ride the rails while it cools. The per-cell rings stay -- they say
	# WHICH cells -- this says THAT THEY ARE ONE THING.
	if _win > 0.0:
		var rc := Color(_glow.r, _glow.g, _glow.b, _win * 0.9)
		draw_line(Vector2(0, pay.position.y), Vector2(size.x, pay.position.y), rc, 6.0)
		draw_line(Vector2(0, pay.end.y), Vector2(size.x, pay.end.y), rc, 6.0)
		var u := 1.0 - _win
		var su := clampf(u / 0.5, 0.0, 1.0)
		if su < 1.0 and _sweep_tex != null:
			var bw := cw * 0.9
			draw_texture_rect(_sweep_tex,
				Rect2(lerpf(-bw, size.x, su), pay.position.y + 2.0, bw, ch - 4.0),
				false, Color(1.0, 1.0, 1.0, 0.35 + 0.5 * _win))
		# Fixed seats and phases, never randf: _draw runs every frame of the
		# fade, and dice rolled in a draw call are static noise, not sparkle.
		for i in _WIN_STARS.size():
			var st: Array = _WIN_STARS[i]
			var sc := Vector2(size.x * float(st[0]), cy + ch * float(st[1]))
			var sa := _win * (0.35 + 0.65 * absf(sin(u * 9.0 + float(i) * 1.7)))
			_star(sc, float(st[2]) * (0.7 + 0.6 * _win), Color(1.0, 1.0, 1.0, sa))

# Where the glints sit along the payline: x as a share of the width, y as a
# share of the cell height off the line, and a radius. Odd spacings on purpose
# so five of them do not read as a picket fence.
const _WIN_STARS := [[0.10, -0.30, 7.0], [0.28, 0.26, 5.5], [0.50, -0.22, 8.0],
	[0.72, 0.28, 5.5], [0.90, -0.26, 7.0]]

# A four-point glint, same construction as the prop art uses.
func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + PI * float(i) / 4.0
		var rr := r if i % 2 == 0 else r * 0.32
		pts.append(c + Vector2(cos(a) * rr, sin(a) * rr))
	draw_colored_polygon(pts, col)

# The bright pass the win sweeps along the payline: soft-edged white, built
# once. A ColorRect cannot fade at its ends and a shader is a pipeline for what
# one gradient texture already is.
static func _sweep() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.5, Color(1, 1, 1, 1.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0)
	t.width = 128
	t.height = 8
	return t
