class_name UI
extends RefCounted

# Type & touch scale.
#
# The game renders into a 720x1280 canvas with stretch/aspect = "expand", so
# every value below is multiplied by the device scale factor -- still
# min(W/720, H/1280), the difference being that under "expand" the axis that
# loses the min() grows the viewport instead of growing a black bar:
#
#   Galaxy S24  (360x780)  -> 0.50      iPhone 15   (393x852)  -> 0.55
#   iPhone SE3  (375x667)  -> 0.52      Pixel 8     (412x915)  -> 0.57
#
# Sizes are picked so the *worst* case (0.50) still clears the platform floors:
#   Apple HIG    11pt text minimum, 44x44pt touch target
#   Material 3   12sp body-small minimum, 48x48dp touch target
#   WCAG 2.2     SC 2.5.8 target size (AA), SC 2.5.5 target size (AAA)
#
# Rule of thumb: a value here, halved, is the pt/dp it renders at on the
# smallest supported phone.

# --- type ramp ---
const F_TINY    := 22   # 11pt  badges, micro-meta -- the absolute floor
const F_CAPTION := 26   # 13pt  captions under icons, secondary rows
const F_LABEL   := 30   # 15pt  button text, list rows
const F_BODY    := 34   # 17pt  sentences meant to be read
const F_SUBHEAD := 38   # 19pt  section heads, modal titles
const F_TITLE   := 46   # 23pt
const F_HEAD    := 54   # 27pt
const F_DISPLAY := 64   # 32pt  hero numbers and logos

# --- touch targets (height, or side for square controls) ---
const TAP       := 88   # 44pt  Apple HIG minimum -- never go below this
const TAP_COMFY := 96   # 48dp  Material minimum, prefer for primary actions
const TAP_HERO  := 132  # 66pt  the raised centre SPIN control

# --- icon boxes ---
const ICON_SM := 28
const ICON_MD := 40
const ICON_LG := 56

# =============================================================================
#  FITTING THE SCREEN
# =============================================================================
#
# The game is drawn for 720x1280. No phone made this decade is that shape, so
# the viewport stretches to the device's real aspect and we get the whole
# screen instead of a letterbox. Two things follow, and every layout in the
# game is an answer to one of them.
#
# The extra height has to land somewhere on purpose. Chrome stays welded to the
# edge it belongs to, the cabinet on the SPIN page takes up the slack, and an
# island -- art plus every hut standing on it -- moves as one piece, so a hut
# can never drift off its patch of grass.
#
# And the ends of the screen are not ours: the notch and the home indicator sit
# over the viewport now. Backgrounds run under both, because that is the whole
# point of an edge-to-edge screen; anything you have to read or press is inset
# by the safe area the system reports.

const DESIGN := Vector2(720.0, 1280.0)

# The system's insets, in viewport units rather than the device pixels
# DisplayServer deals in: x is the top, y the bottom. Desktop reports the whole
# window as safe, so both come back zero there and every layout below collapses
# to the one it has always been.
static func safe_insets(view: Vector2) -> Vector2:
	var win := Vector2(DisplayServer.window_get_size())
	if win.y <= 0.0 or view.y <= 0.0:
		return Vector2.ZERO
	var area := DisplayServer.get_display_safe_area()
	if area.size.y <= 0:
		return Vector2.ZERO
	var k := view.y / win.y
	return Vector2(
		maxf(0.0, float(area.position.y) * k),
		maxf(0.0, (win.y - float(area.position.y + area.size.y)) * k))

static func safe_top(view: Vector2) -> float:
	return safe_insets(view).x

static func safe_bottom(view: Vector2) -> float:
	return safe_insets(view).y

# Hangs a 720x1280 composition -- the island pages, art and huts together -- on
# a taller screen: it keeps the size it was drawn at and starts below the
# notch, rather than being zoomed until it fills.
#
# Zooming it to cover was the first thing tried and it looks fine for about a
# second, until you notice it has taken a bite out of both ends of every Build
# button. The huts are art and can be cropped; the buttons under them cannot,
# and a control that runs off the side of the screen is a bug however good the
# grass looks.
#
# `reach` is the y the composition still has to come down to, which is the top
# of the nav bar's slab: the art has to get at least that far or a band of bare
# sky opens up above the bar. On every iPhone the design already reaches it
# unaided and the scale stays exactly 1. Only a phone taller than about 20:9
# makes this bite, and then zooming a little -- and losing a little off the
# sides -- beats leaving a gap.
static func make_design_stage(c: Control, view: Vector2, top: float, reach: float) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.size = DESIGN
	var k := maxf(view.x / DESIGN.x, (reach - top) / DESIGN.y)
	c.scale = Vector2(k, k)
	c.position = Vector2((view.x - DESIGN.x * k) * 0.5, top)


# --- money ---
#
# Coin values ride a 1.6x-per-island curve, so a build that costs 400 on Green
# Meadows costs 332,306,995 on the last island. Grouped digits stay for numbers
# being spent or compared -- a price, a wallet on the leaderboard -- and every
# transient payout pops compact, because "+1.25B" is a number a player reads at
# a glance and 1,246,151,262 is a wall they don't.
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out

const _SUFFIX := ["", "K", "M", "B", "T", "Q"]

static func fmt_compact(n: int) -> String:
	var neg := n < 0
	var v := float(absi(n))
	if v < 100_000.0:
		return fmt(n)
	var tier := 0
	while v >= 1000.0 and tier < _SUFFIX.size() - 1:
		v /= 1000.0
		tier += 1
	# three significant digits, then trim the trailing zeros a round payout gets
	var txt := ("%.2f" % v) if v < 10.0 else (("%.1f" % v) if v < 100.0 else ("%.0f" % v))
	if txt.contains("."):
		txt = txt.rstrip("0").rstrip(".")
	return ("-" if neg else "") + txt + _SUFFIX[tier]
