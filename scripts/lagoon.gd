class_name Lagoon
extends RefCounted

# =============================================================================
#  LOOT LAGOON — "Sea Glass & Brass"
# =============================================================================
#
# One material story, used everywhere, so the game reads as a single object
# rather than a pile of screens:
#
#   THE LAGOON   Every page sits on open water under a bright sky. Light comes
#                from the top; caustics drift on the surface. Nothing in the
#                chrome is dark — depth comes from shadow and refraction, never
#                from a black panel.
#
#   SEA GLASS    Every card, modal and bar is a piece of tumbled sea glass:
#                milky, translucent, cool at the bottom where the water pools
#                under it, with a crisp lit edge along the top. It floats above
#                the page on a soft shadow.
#
#   BRASS        Anything structural or valuable is salvaged ship's brass —
#                warm, polished, with a bright band a third of the way down and
#                bounce light at the base. Brass frames the things that matter
#                (the machine, page titles, the currency you hold) and nothing
#                else, so brass always means "this is important".
#
#   CORAL        Exactly one hue means "tap this". Coral appears on primary
#                actions and nowhere else, which is why the eye finds SPIN
#                instantly on a page full of other controls.
#
#   THE KEYLINE  Every object -- card, capsule, button, chip, token, plaque,
#                well -- is drawn with a rim of deep lagoon water around it.
#                This is the load-bearing rule of the whole system and it was
#                added late, after measuring: a game where the chrome is light
#                and the world behind it is light has no edges, so nothing
#                separates from anything and 245 of 338 pieces of text on
#                screen were below the readable threshold. A dark rim is what
#                lets a bright palette stay bright and still read -- the edge
#                carries the separation so the fills don't have to. Never draw
#                a surface in this game without one.
#
# The island you are on tints the backdrop and the hero button's glow. The
# chrome itself never changes — a constant frame is what makes 30 different
# islands feel like one game.

# --- water & sky -------------------------------------------------------------
const SKY_HI      := Color(0.827, 0.945, 0.988)  # zenith, almost white
const SKY_LO      := Color(0.573, 0.867, 0.937)  # at the horizon
const LAGOON      := Color(0.169, 0.710, 0.788)  # shallow water
const LAGOON_DEEP := Color(0.055, 0.431, 0.525)  # the drop-off
const ABYSS       := Color(0.027, 0.227, 0.286)  # deepest water — used as ink

# --- sand & shell ------------------------------------------------------------
const SHELL       := Color(1.000, 0.988, 0.965)  # panel white
const SAND        := Color(1.000, 0.949, 0.867)
const SAND_DEEP   := Color(0.910, 0.788, 0.604)

# --- brass -------------------------------------------------------------------
const BRASS_HI    := Color(0.976, 0.898, 0.694)  # the polished band
const BRASS       := Color(0.820, 0.604, 0.278)
const BRASS_MID   := Color(0.710, 0.482, 0.180)
const BRASS_LO    := Color(0.478, 0.290, 0.094)  # shadowed edge

# --- coral: the one "tap me" hue --------------------------------------------
const CORAL_HI    := Color(1.000, 0.604, 0.478)
const CORAL       := Color(1.000, 0.420, 0.290)
const CORAL_LO    := Color(0.776, 0.204, 0.122)

# --- support hues ------------------------------------------------------------
# Every one of these carries white display text, so its value is set by that and
# not by how pretty the swatch is on its own. KELP was #3fbf7f and scored 2.34
# against white -- the Build, Claim and price buttons, i.e. most of what the
# player is asked to press. Darkened to clear 3:1 for the display type that sits
# on it; the lighter tone survives as the highlight in KELP_HI so the button is
# no less green, it is just green with somewhere to fall.
const KELP        := Color(0.114, 0.596, 0.373)  # confirm / progress
const KELP_HI     := Color(0.353, 0.831, 0.573)
const KELP_LO     := Color(0.043, 0.353, 0.216)
const URCHIN      := Color(0.502, 0.337, 0.804)  # rare / premium
const URCHIN_LO   := Color(0.286, 0.176, 0.494)
# REEF carries a white numeral on every alert badge in the game -- the "!" on a
# side-rail disc, the unread count on the Shop tab -- and at #e1324c that was
# 4.41 : 1 against white, i.e. ten separate failures of the same three percent.
# Taken down to 4.71 without moving the hue anybody can see.
const REEF        := Color(0.855, 0.180, 0.278)  # alert / danger
const REEF_LO     := Color(0.545, 0.086, 0.145)

# --- the shop's metals -------------------------------------------------------
# The spin ladder and the coin ladder were struck on the same brass card with
# different art on it, and on a phone they are indistinguishable -- Guy,
# 2026-09-03: "in the shop there has to be a difference between the money pack
# and the spins, they are very similar; the spins toward blue and the money
# toward more of a silver colour." So the two shelves are two metals.
#
# BOTH STAY DARK, and that is the part worth writing down. The shop stands on a
# deep board and the tile's typography is built for a dark hold -- white
# numerals, a sand pack name, a metal unit label. A pale silver plate would
# have meant re-inking every line on the tile to buy nothing: silver reads as
# silver from its *rim*, not from its stock, which is why a chromed object
# photographs dark with bright edges. So silver here is graphite under bright
# chrome, and steel is deep water under a lit cyan edge.
const STEEL       := Color(0.055, 0.161, 0.243)  # spin packs: blue steel
const STEEL_MID   := Color(0.078, 0.224, 0.325)
const STEEL_HI    := Color(0.435, 0.749, 0.918)  # the lit edge
const SILVER      := Color(0.141, 0.165, 0.184)  # coin packs: graphite
const SILVER_MID  := Color(0.192, 0.224, 0.247)
const SILVER_HI   := Color(0.847, 0.886, 0.914)  # the chromed edge

# --- the podium --------------------------------------------------------------
# Gold, silver and bronze, and they are one list because they were three copies
# of the same literal in three places -- the tournament board, the world board
# and the end-of-tournament dialog. Bronze used to be #c67e4a, four percent off
# brass, which at the 52px the leaderboard draws a medal is not a different
# metal at all; it is copper now and reads as one.
const PODIUM := [
	Color(0.820, 0.604, 0.278),  # gold -- BRASS
	Color(0.741, 0.784, 0.804),  # silver
	Color(0.694, 0.376, 0.204),  # bronze
]

# --- the keyline -------------------------------------------------------------
# Deep water, used as an edge rather than a fill. It is the same family as ABYSS
# so the rim reads as the lagoon's own shadow and not as a black stroke borrowed
# from somewhere else.
const HULL        := Color(0.031, 0.180, 0.235)  # the rim on every object

# --- ink ---------------------------------------------------------------------
# Every value here is measured against SHELL, which is what text in this game
# almost always lands on. tools/qa_contrast.tscn re-measures them in place --
# on the real panel, over the real backdrop -- and is the only authority.
#
#   INK        13.0 : 1     INK_MUTE    7.1 : 1
#   INK_SOFT    5.3 : 1     INK_FAINT   5.0 : 1
#
# INK_SOFT sat at 4.66 against pure SHELL, which sounds like a pass and is not
# one: card faces carry a gloss and a tint, so the surface under a caption is
# never quite SHELL and the measured ratio came back 4.45 on twenty separate
# rows. A token has to clear the bar on the surface it actually lands on.
#
# INK_FAINT used to be #739ca7 and scored 2.8. It was the game's "tertiary"
# tone and it was on the season timer, the card odds, the piggy bank's progress
# note and the star cost of every box -- so the rule "quieter means paler" had
# quietly taken a fifth of the copy in the game below legible. Tertiary is now
# expressed by size and weight; every ink in the ladder clears AA.
#
# AND THEN THERE WERE THREE. INK_FAINT was raised to 5.0 against SHELL once and
# that was still measuring it against the wrong thing: almost nothing in this
# game lands on bare SHELL. On a tinted card -- the sand of the all-clear bonus,
# the pale glass of an inactive quests tab, the mint of a finished set -- the
# same token came back at 3.7 to 4.2 on the season timer, the tab captions, the
# card odds and the "World ranking" link. A fourth step down the ladder cannot
# be made to clear on every surface it is used on, because the step below
# INK_MUTE is where paleness stops working at all. So the ladder is three inks
# now and INK_FAINT is the same value as INK_MUTE; the distinction that used to
# be carried by tone is carried by size and weight, which is the rule this
# palette already claimed to follow.
const INK         := Color(0.043, 0.227, 0.286)  # primary text on glass
# INK_SOFT came down too, and for the same reason INK_FAINT did: it was 5.3
# against bare SHELL and 4.06 to 4.24 on the surfaces it is actually printed
# on -- a sand bonus card, the pale glass of an inactive tab, the mint of a
# finished set. Every ink in this palette is now measured against tinted stock,
# because a card in this game is never bare paper.
const INK_SOFT    := Color(0.212, 0.388, 0.443)  # secondary text on glass
const INK_MUTE    := Color(0.167, 0.351, 0.408)  # secondary text at caption size
const INK_FAINT   := INK_MUTE                    # tertiary -- size and weight, not tone

# Corner radii. Sea glass is tumbled smooth, so nothing in this game has a
# tight corner; the smallest radius is still generous.
const R_CHIP  := 14
const R_CARD  := 26
const R_PANEL := 34

# =============================================================================
#  Typography
# =============================================================================
#
# Two families, one job each.
#   Baloo 2 (800)  DISPLAY — headlines, currency, hero numbers, the logo.
#                  Chunky and round, so it survives a thick outline.
#   Nunito (600/700) UI — everything that is read as a sentence or a row.
#                  Rounded terminals keep it in the same family of shapes
#                  without competing with the display face.
# Both are SIL OFL; see assets/fonts/OFL-*.txt.

static var _display: Font
static var _ui_bold: Font
static var _ui: Font

static func _weighted(path: String, weight: int) -> Font:
	var base := CV.tex_font(path)
	if base == null:
		return null
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {"wght": weight}
	var extra: Array[Font] = []
	var deja := CV.tex_font("res://assets/fonts/DejaVuSans.ttf")
	if deja != null:
		extra.append(deja)
	var noto := CV.tex_font("res://assets/fonts/NotoColorEmoji.ttf")
	if noto != null:
		extra.append(noto)
	v.fallbacks = extra
	return v

static func display_font() -> Font:
	if _display == null:
		_display = _weighted("res://assets/fonts/Baloo2.ttf", 800)
		if _display == null:
			_display = ThemeDB.fallback_font
	return _display

static func ui_bold_font() -> Font:
	if _ui_bold == null:
		_ui_bold = _weighted("res://assets/fonts/Nunito.ttf", 800)
		if _ui_bold == null:
			_ui_bold = ThemeDB.fallback_font
	return _ui_bold

static func ui_font() -> Font:
	if _ui == null:
		_ui = _weighted("res://assets/fonts/Nunito.ttf", 600)
		if _ui == null:
			_ui = ThemeDB.fallback_font
	return _ui

# Display type is always outlined. On a busy lagoon backdrop an unoutlined
# headline dissolves into the water behind it, so the outline is part of the
# typeface as far as this game is concerned — never set one without it.
static func title(text: String, size := 54, ink := Color.WHITE, outline := ABYSS) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", maxi(6, int(size * 0.22)))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# The game's name. Warm sand face over a near-black brass outline, plus a soft
# drop -- the fill alone is too close to the sky to hold its own up there.
static func wordmark(text: String, size := 64) -> Label:
	var l := title(text, size, SAND, BRASS_LO.darkened(0.45))
	l.add_theme_constant_override("outline_size", int(size * 0.26))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", int(size * 0.09))
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.35))
	return l

# Display type that has to survive being printed straight onto painted art --
# a hut's name over grass, a caption over island water. Nothing here is a flat
# fill it can be measured against, so the letterform is carried entirely by a
# heavy rim and a cast shadow, the way a sign painted on a wall is. title()'s
# default rim is tuned for type on chrome and is about half what this needs:
# the island's building names were drawn with it and could not be read at all.
# White, not sand. The difference is invisible as a colour and it is a fifth of
# a contrast step: this type lands on painted art -- the cabinet's brass frame,
# a green hillside -- and against a warm mid tone sand gives up more than it
# looks like it should. The outline is what does most of the work either way.
static func art_label(text: String, size := UI.F_CAPTION, ink := Color.WHITE) -> Label:
	var l := title(text, size, ink, ABYSS)
	l.add_theme_constant_override("outline_size", maxi(9, int(size * 0.36)))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(3, int(size * 0.12)))
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.45))
	return l

# A number that means treasure -- a star count, a coin total, a score. Gold on
# its own is a light hue, so on this game's pale glass it measures about 1.4 : 1
# and the star column of the world board was, row for row, the least readable
# thing in the game. Gold is not a fill here; it is a fill inside a deep rim,
# which is how every coin number in this genre is drawn and the only way a warm
# light colour survives on a warm light surface.
static func gold_value(text: String, size := UI.F_LABEL, fill := BRASS_HI) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fill)
	l.add_theme_color_override("font_outline_color", HULL)
	l.add_theme_constant_override("outline_size", maxi(5, int(size * 0.20)))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

static func label(text: String, size := UI.F_LABEL, ink := INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ui_bold_font() if bold else ui_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink)
	return l

# =============================================================================
#  Sea glass
# =============================================================================

# The workhorse surface: milky, lit along its top edge, rimmed in deep water.
# `opacity` leans opaque for anything holding text, translucent for decorative
# layers.
#
# The rim used to be white at 0.85 and the fill 0.90, which is a light edge
# around a light surface sitting on a light lagoon -- three values within a few
# percent of each other and therefore no edge at all. The card's own shape was
# being carried by nothing but a soft shadow. The lit top edge is not lost: the
# gloss overlay draws it *inside* the rim, which is where it belongs on a piece
# of glass anyway, and the dark rim outside it is what the shape is read from.
static func glass(radius := R_CARD, opacity := 0.95) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SHELL.r, SHELL.g, SHELL.b, opacity)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(3)
	sb.border_color = Color(HULL.r, HULL.g, HULL.b, 0.88 * maxf(opacity, 0.45))
	sb.shadow_size = 14
	sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.32)
	sb.shadow_offset = Vector2(0, 6)
	return sb

# =============================================================================
#  Paper
# =============================================================================
#
# The card the board carries. Sea glass is right when it floats over the world
# and you are meant to see the water through it; on a deep board there is
# nothing to see through to, and a translucent white panel on dark water is
# just a grey rectangle. So a menu card is paper: warm, opaque, edged in deep
# water, with the light catching its top edge and a shadow under its bottom.
#
# The warmth is the point. A pure white sheet on a teal board is a screen; sand
# on a teal board is an object somebody handed you, and it is the same sand the
# brass plaques are engraved in, so the two belong to each other.
static func sheet(radius := R_CARD, tone := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHELL.lerp(SAND, 0.55 + tone)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(3)
	sb.border_color = HULL
	sb.shadow_size = 16
	sb.shadow_color = Color(0, 0, 0, 0.42)
	sb.shadow_offset = Vector2(0, 7)
	return sb

# A sheet with a coloured band across the top of it, and the card's name
# engraved in the band.
#
# This is the difference between a page of cards and a page of rectangles. A
# title set in dark ink at the top of a cream card is a paragraph with a bold
# first line; the same title in white on a band of colour is a *label on an
# object*, and it lets a page say what each card is for from across the room --
# which is what the games this one is aimed at do on every single card.
#
# Returns the body to fill; the band is already built.
static func header_card(parent: Node, heading: String, band := LAGOON_DEEP,
		radius := R_CARD, pad := 16) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sheet(radius))
	panel.clip_contents = true
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var head := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = band
	hsb.corner_radius_top_left = radius - 3
	hsb.corner_radius_top_right = radius - 3
	hsb.border_width_bottom = 3
	hsb.border_color = band.lerp(HULL, 0.55)
	hsb.content_margin_left = 18.0
	hsb.content_margin_right = 18.0
	hsb.content_margin_top = 8.0
	hsb.content_margin_bottom = 9.0
	head.add_theme_stylebox_override("panel", hsb)
	col.add_child(head)

	var lbl := title(heading, UI.F_SUBHEAD, Color.WHITE, band.lerp(HULL, 0.72))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(lbl)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, pad)
	margin.add_theme_constant_override("margin_top", pad - 2)
	margin.add_theme_constant_override("margin_bottom", pad)
	col.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	return body

# The section header a shelf of cards sits under: a ribbon, not a pill between
# two hairlines.
#
# The old one was a small brass plaque with a faded rule out to each side. It
# said "here is a heading" quietly and politely, in the middle of a page whose
# whole problem was that nothing on it spoke up. A ribbon spans the column,
# carries its title in white, and has a notch cut out of each end so it reads
# as a strip of something rather than as another rounded rectangle.
static func banner(text: String, fill := LAGOON_DEEP, height := 58.0) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(0, height)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var strip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3)
	sb.border_color = fill.lerp(HULL, 0.60)
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.36)
	sb.shadow_offset = Vector2(0, 4)
	strip.add_theme_stylebox_override("panel", sb)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.offset_left = 26.0
	strip.offset_right = -26.0

	# The notch. Two small pieces of the board, punched into each end, which is
	# what turns a bar into a ribbon.
	for side in [0.0, 1.0]:
		var notch := Panel.new()
		var nsb := StyleBoxFlat.new()
		nsb.bg_color = Color(0, 0, 0, 0.42)
		nsb.set_corner_radius_all(6)
		notch.add_theme_stylebox_override("panel", nsb)
		notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(notch)
		notch.set_anchors_and_offsets_preset(
			Control.PRESET_CENTER_LEFT if side == 0.0 else Control.PRESET_CENTER_RIGHT)
		notch.custom_minimum_size = Vector2(18, height * 0.34)
		notch.size = notch.custom_minimum_size
		notch.offset_top = -notch.size.y * 0.5
		notch.offset_bottom = notch.size.y * 0.5
		if side == 0.0:
			notch.offset_left = 20.0
			notch.offset_right = 38.0
		else:
			notch.offset_left = -38.0
			notch.offset_right = -20.0

	var lbl := title(text, UI.F_LABEL, Color.WHITE, fill.lerp(HULL, 0.75))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(lbl)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return root

# A darker piece of glass, for wells that content sits *inside* rather than on
# top of — the reel window, progress tracks, inset rows.
# =============================================================================
#  Shader programs
# =============================================================================
#
# One compiled program per distinct piece of shader source, for the whole run.
#
# Every gloss, every brass fitting and every button face in the game asked for
# a `Shader.new()` of its own and pasted the same source into it. The source is
# genuinely identical -- radius, tint and rect_px are uniforms set on the
# *material*, which is still per-node -- so what that bought was a fresh shader
# RID and a fresh pipeline compile per card and per button. Opening the shop
# minted 57 of them and cost 48ms on a desktop; on a phone that is the hitch
# you feel when the page appears, and it came back on every rebuild.
#
# Keyed on the source itself, so a caller cannot forget to register a new one
# and there is no name to keep in sync.
static var _shaders := {}

static func shader(code: String) -> Shader:
	var sh: Shader = _shaders.get(code)
	if sh == null:
		sh = Shader.new()
		sh.code = code
		_shaders[code] = sh
	return sh

# A well is a hole, so it has to be darker than what it is cut into -- at 0.30
# over a white card it was lighter than the card's own shadow and read as a
# smudge. Deep enough now that a fill sitting in it is unmistakably a fill, and
# that white text written across it survives.
static func glass_well(radius := R_CARD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(LAGOON_DEEP.r, LAGOON_DEEP.g, LAGOON_DEEP.b, 0.62)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(2)
	sb.border_color = Color(HULL.r, HULL.g, HULL.b, 0.70)
	return sb

# Overlay that turns a flat fill into a piece of glass: a crisp lit edge across
# the top, cool water pooling at the bottom. Add as the last child of a panel.
static func gloss(radius := R_CARD, tint := LAGOON) -> ColorRect:
	var r := ColorRect.new()
	var sh := shader("""
shader_type canvas_item;

uniform vec2 rect_px = vec2(100.0, 100.0);
uniform float radius = 26.0;
uniform vec3 tint = vec3(0.17, 0.71, 0.79);

// signed distance to a rounded rectangle, in pixels
float rr(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_px;
	float d = rr(p, rect_px * 0.5, radius);
	float inside = 1.0 - smoothstep(-1.5, 0.5, d);

	// lit edge: a bright band hugging the top rim, fading fast
	float rim = smoothstep(-6.0, -1.0, d) * smoothstep(0.45, 0.0, UV.y);
	// broad sheen over the upper third
	float sheen = smoothstep(0.38, 0.0, UV.y) * 0.30;
	// water pooling under the glass
	float pool = smoothstep(0.50, 1.0, UV.y) * 0.28;

	vec3 col = mix(vec3(1.0), tint, pool / max(sheen + rim + pool, 0.001));
	float a = max(max(sheen, rim * 0.55), pool) * inside;
	COLOR = vec4(col, a);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("radius", float(radius))
	mat.set_shader_parameter("tint", _v3(tint))
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.resized.connect(func() -> void: mat.set_shader_parameter("rect_px", r.size))
	return r

# Attaches gloss to a panel and keeps it sized to it.
static func add_gloss(panel: Control, radius := R_CARD, tint := LAGOON) -> ColorRect:
	var g := gloss(radius, tint)
	panel.add_child(g)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return g

# A finished sea-glass card: panel + gloss + inner margin, returns the VBox to
# fill. This is the default container for anything in the game.
static func card(parent: Node, radius := R_CARD, pad := 18, opacity := 0.95) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", glass(radius, opacity))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, pad)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)
	add_gloss(panel, radius)
	return vb

# =============================================================================
#  Brass
# =============================================================================

# Polished metal: darker at the very top, a bright band a third of the way
# down, shadow through the belly, and bounce light along the bottom edge.
# That four-stop read is what separates brass from "a yellow rectangle".
static func brass_material(radius := R_CHIP) -> ShaderMaterial:
	var sh := shader("""
shader_type canvas_item;

uniform vec2 rect_px = vec2(100.0, 40.0);
uniform float radius = 14.0;
uniform vec3 hi  = vec3(0.976, 0.898, 0.694);
uniform vec3 mid = vec3(0.820, 0.604, 0.278);
uniform vec3 lo  = vec3(0.478, 0.290, 0.094);
uniform vec3 rim = vec3(0.086, 0.145, 0.161);

float rr(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_px;
	float d = rr(p, rect_px * 0.5, radius);
	float inside = 1.0 - smoothstep(-1.0, 0.5, d);

	float y = UV.y;
	vec3 c = mix(mid, lo, smoothstep(0.0, 0.22, 0.22 - y));   // shaded top lip
	c = mix(c, hi, smoothstep(0.46, 0.24, y));                 // the polished band
	c = mix(c, lo, smoothstep(0.58, 0.94, y));                 // belly falls into shadow
	c = mix(c, hi, smoothstep(0.99, 0.90, y) * 0.40);          // bounce off the base
	// The rim. Every object in this game is edged in deep water, and brass is
	// no exception -- a plaque whose outermost pixel is still brass has the
	// same value as the sand it is cast against and loses its own silhouette.
	c = mix(c, rim, smoothstep(-5.0, -1.0, d));
	COLOR = vec4(c, inside);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("radius", float(radius))
	return mat

# A brass plaque — the game's header shape. Page titles, the machine's sign and
# section heads all sit on one of these, which is what ties the screens
# together. `rivets` studs the ends like a riveted ship's nameplate.
static func plaque(text: String, width := 0.0, height := 78.0, font_size := 44, rivets := true) -> Control:
	var root := Control.new()
	if width <= 0.0:
		# measure the engraved text and cast a plate that fits it, so a plaque
		# can hold "Shop" or "Treasure Chests" without either being padded wrong
		width = display_font().get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + height * 1.25
	root.custom_minimum_size = Vector2(width, height)
	root.size = Vector2(width, height)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var metal := ColorRect.new()
	var radius := height * 0.42
	var mat := brass_material(int(radius))
	metal.material = mat
	metal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(metal)
	metal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	metal.resized.connect(func() -> void: mat.set_shader_parameter("rect_px", metal.size))

	# Engraved, so the letterform is carried by the cut and not by the fill:
	# sand on brass is 1.8 : 1 on its own and the rim is doing all the work.
	# Deeper and heavier than title()'s default for that reason.
	var lbl := title(text, font_size, SAND, BRASS_LO.darkened(0.55))
	lbl.add_theme_constant_override("outline_size", maxi(7, int(font_size * 0.26)))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(lbl)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left = height * 0.5
	lbl.offset_right = -height * 0.5
	root.set_meta("label", lbl)

	if rivets:
		for side in [0.0, 1.0]:
			var rivet := Glyph.new()
			rivet.kind = "rivet"
			rivet.custom_minimum_size = Vector2(height * 0.26, height * 0.26)
			rivet.size = rivet.custom_minimum_size
			root.add_child(rivet)
			rivet.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if side == 0.0 else Control.PRESET_CENTER_RIGHT)
			var inset := height * 0.30
			if side == 0.0:
				rivet.offset_left = inset - rivet.size.x * 0.5
			else:
				rivet.offset_left = -inset - rivet.size.x * 0.5
			rivet.offset_top = -rivet.size.y * 0.5
	return root

# A brass ring, used to frame round things (side buttons, avatars, the reels).
static func brass_ring(thickness := 7.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(int(thickness))
	sb.border_color = BRASS.lerp(HULL, 0.30)
	sb.set_corner_radius_all(200)
	return sb

# =============================================================================
#  Buttons
# =============================================================================
#
# One button shape, four meanings. Every button is a lozenge with a hard bottom
# bevel it presses into, a specular arc across the top and an outlined label —
# the same physical object in different materials, so the player learns one
# affordance instead of five.
#
#   "primary"  coral   — the single most important action on the screen
#   "brass"    brass   — valuable / confirm-a-purchase
#   "kelp"     green   — claim, collect, confirm
#   "glass"    milky   — secondary, cancel, toggles that are off
#   "danger"   reef    — destructive or "close"

const BUTTON_KINDS := {
	"primary": [CORAL, CORAL_LO, Color.WHITE],
	"brass":   [BRASS, BRASS_LO, SAND],
	"kelp":    [KELP, KELP_LO, Color.WHITE],
	"urchin":  [URCHIN, URCHIN_LO, Color.WHITE],
	"danger":  [REEF, REEF_LO, Color.WHITE],
	"glass":   [Color(1, 1, 1, 0.82), Color(LAGOON_DEEP.r, LAGOON_DEEP.g, LAGOON_DEEP.b, 0.55), INK],
}

static func button(btn: Button, kind := "primary", radius := 0) -> void:
	var spec: Array = BUTTON_KINDS.get(kind, BUTTON_KINDS["primary"])
	button_custom(btn, spec[0], spec[1], spec[2], radius)

# The same moulded button, told its colours outright instead of picking them
# from the house palette. Sign-in buttons need this: Apple black, Facebook
# blue and Google white are prescribed by the people whose names are on them,
# and are the one place in the game that does not get to be lagoon-coloured.
static func button_custom(btn: Button, face: Color, bevel: Color, ink: Color, radius := 0) -> void:
	var r := radius if radius > 0 else 22
	# The rim. A button used to be edged only along its bottom -- that is the
	# bevel it presses into -- so its left, right and top edges were the face
	# colour meeting whatever was behind it. On a bright lagoon that is a mid
	# tone meeting a light one, and the button lost its own outline. Rimming all
	# four sides in deep water is what makes it a moulded object; the bottom
	# stays thicker because that is still the edge it travels down into.
	var rim := bevel.lerp(HULL, 0.55)

	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(r)
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		sb.content_margin_left = 22.0
		sb.content_margin_right = 22.0
		sb.set_border_width_all(3)
		match state:
			"hover":
				sb.bg_color = face.lightened(0.10)
				sb.border_width_bottom = 8
			"pressed":
				# the face travels down into its bevel rather than just darkening
				sb.bg_color = face.darkened(0.10)
				sb.border_width_bottom = 3
				sb.content_margin_top = 15.0
				sb.content_margin_bottom = 5.0
			"disabled":
				# NOT YET IS A SHAPE, NOT A COLOUR.
				#
				# Two wrong answers were tried here first. A grey slab, which is
				# what a broken control looks like -- the quests page was a
				# column of them where every CLAIM was merely unearned, and that
				# reads as an app that has stopped working. Then the button's
				# own hue desaturated, which turns kelp into olive and brass
				# into dusty pink: quieter, but also uglier, and still guessing.
				#
				# The affordance the player actually uses is height. Every live
				# button in this game is a raised lozenge with a bevel under it
				# that it travels down into when pressed. So an inactive one is
				# the same lozenge lying flat: no bevel, nothing to press into,
				# a cool pane of the game's own glass with the rim it always
				# had. It is legible, it is not broken, and it is not a colour
				# anybody has to like.
				sb.bg_color = Color(0.847, 0.898, 0.910, 0.96)
			_:
				sb.bg_color = face
				sb.border_width_bottom = 8
		sb.border_color = rim if state != "disabled" else Color(HULL.r, HULL.g, HULL.b, 0.45)
		if state == "disabled":
			# Flat. No bevel to travel into is the whole signal.
			sb.border_width_bottom = 3
		sb.shadow_size = 9
		sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.18 if state == "disabled" else 0.28)
		sb.shadow_offset = Vector2(0, 4)
		btn.add_theme_stylebox_override(state, sb)

	btn.add_theme_font_override("font", display_font())
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", UI.F_LABEL)
	# The label is read off its outline as much as its fill, so the outline is
	# always the dark one. White-on-kelp measured 2.34 with a pale rule behind
	# it; the same white over a deep rim clears 3:1 without the green having to
	# turn into a colour nobody wants on a Build button.
	var outline: Color = rim.darkened(0.15) if ink.get_luminance() > 0.5 else Color(1, 1, 1, 0.70)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(c, ink)
	# Dark on the pale inactive face. It shares one outline colour with every
	# other state, which is dark too -- on a disabled button that simply reads
	# as a heavier letterform, and heavy dark type on cool glass is the most
	# readable thing on the page. An unearned reward is still information.
	btn.add_theme_color_override("font_disabled_color", INK_MUTE)
	btn.add_theme_color_override("font_outline_color", outline)
	btn.add_theme_constant_override("outline_size", 7)
	btn.focus_mode = Control.FOCUS_NONE

# Adds the specular arc that makes a button look moulded rather than printed.
# Kept separate because it needs a live size, so only call it on buttons that
# are already in the tree.
static func button_gloss(btn: Button, radius := 22) -> ColorRect:
	var r := ColorRect.new()
	var sh := shader("""
shader_type canvas_item;

uniform vec2 rect_px = vec2(100.0, 40.0);
uniform float radius = 22.0;

float rr(vec2 p, vec2 half_size, float rad) {
	vec2 q = abs(p) - half_size + vec2(rad);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rad;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_px;
	float d = rr(p, rect_px * 0.5, radius);
	float inside = 1.0 - smoothstep(-2.0, 0.0, d);
	// specular arc across the top half, inset from the rim
	float arc = smoothstep(0.46, 0.02, UV.y) * smoothstep(-10.0, -4.0, d);
	// contact shadow along the bottom rim so the face reads as raised
	float base = smoothstep(0.72, 1.0, UV.y) * 0.22;
	COLOR = vec4(vec3(1.0), arc * 0.38 * inside);
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), base);
	COLOR.a = max(COLOR.a, base * inside);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("radius", float(radius))
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(r)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.resized.connect(func() -> void: mat.set_shader_parameter("rect_px", r.size))
	return r

# =============================================================================
#  Backdrop
# =============================================================================

# Sky over open water, with drifting caustics and a sun bloom overhead. Islands
# tint it, but the light always comes from the same place — the constant light
# direction is most of why the chrome reads as one material system.
static func backdrop(page: Control) -> ShaderMaterial:
	var bg := ColorRect.new()
	var sh := shader("""
shader_type canvas_item;

uniform vec3 sky_hi   = vec3(0.827, 0.945, 0.988);
uniform vec3 sky_lo   = vec3(0.573, 0.867, 0.937);
uniform vec3 water    = vec3(0.169, 0.710, 0.788);
uniform vec3 water_lo = vec3(0.055, 0.431, 0.525);
uniform float horizon = 0.40;

void fragment() {
	float y = UV.y;
	vec3 sky = mix(sky_hi, sky_lo, smoothstep(0.0, horizon, y));

	float t = clamp((y - horizon) / (1.0 - horizon), 0.0, 1.0);
	vec3 sea = mix(water, water_lo, t * t);
	// two slow interfering wave trains -> a caustic net on the surface, densest
	// near the horizon where the light is skimming across it
	float a = sin(UV.x * 7.0  + TIME * 0.23 + t * 8.0);
	float b = sin(UV.x * 13.0 - TIME * 0.16 + t * 5.0);
	float caustic = pow(max((a * 0.5 + 0.5) * (b * 0.5 + 0.5), 0.0), 2.2);
	sea += vec3(0.30, 0.42, 0.38) * caustic * (1.0 - t * 0.7) * 0.50;

	// The horizon is a band, not a cut: a hard line reads as two flat rectangles
	// stacked, which is exactly what the old menu backgrounds looked like.
	vec3 c = mix(sky, sea, smoothstep(horizon - 0.05, horizon + 0.05, y));

	// sun bloom above the top edge, deliberately short of clipping to white --
	// the HUD capsules have to stay readable against it
	float d = length((UV - vec2(0.5, 0.04)) * vec2(1.0, 1.7));
	c += vec3(1.0, 0.95, 0.80) * smoothstep(0.62, 0.0, d) * 0.16;
	// corner vignette, barely there — keeps the chrome off the page edges
	c *= mix(0.94, 1.0, 1.0 - smoothstep(0.55, 1.05, length(UV - vec2(0.5))));
	COLOR = vec4(c, 1.0);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return mat

# =============================================================================
#  The board
# =============================================================================
#
# THE MENUS DO NOT STAND ON THE SKY.
#
# Every page in the game used to sit on the same bright lagoon: sky at the top,
# turquoise water below. That is right for the two pages that ARE the world --
# the machine and the island -- and it is why everything else looked amateur.
# A cream card on a bright cyan gradient has nowhere to cast a shadow and
# nothing to be brighter than, so six menus' worth of content floated in a wash.
#
# A menu is not a place in the world. It is a board you have been handed, and
# in every game this one is aimed at, a board is dark: the shop, the card
# album, the leaderboard and the event panel all sit on deep water or deep
# wood, and the colour is spent on the goods rather than on the ground. Dark
# ground is also what buys the accessibility -- once the page is deep, cream
# paper is a 14 : 1 surface and the coral, kelp and brass on top of it stop
# competing with a lit sky for attention.
#
# DEEP, NOT BLACK. The first version ran to #031F31 at the foot of the page,
# which is dark enough that the board stops being water and starts being an
# absence -- and a page that swings from near-white paper to near-black ground
# is tiring to read for the same reason a white page on a black desktop is. It
# sits in the mid-dark now: the paper still carries every bit of its contrast,
# and the eye has somewhere to rest between the cards.
#
# So: the world is bright, the board is deep, and the game reads as one object
# because the same light falls on both from the same place.
static func board(page: Control) -> ShaderMaterial:
	var bg := ColorRect.new()
	var sh := shader("""
shader_type canvas_item;

uniform vec3 top    = vec3(0.078, 0.286, 0.361);
uniform vec3 bottom = vec3(0.031, 0.145, 0.204);
uniform vec3 lamp   = vec3(1.000, 0.820, 0.480);

void fragment() {
	// Depth down the board, eased so the top third stays open and the bottom
	// closes in. A linear ramp reads as a printed gradient; this reads as water.
	float y = smoothstep(0.0, 1.0, UV.y);
	vec3 c = mix(top, bottom, y);

	// The lamp. One warm source above the page, the same direction the light
	// comes from on the bright pages, so the two grounds are lit alike.
	float d = length((UV - vec2(0.5, -0.06)) * vec2(0.92, 1.20));
	c = mix(c, lamp, smoothstep(0.86, 0.0, d) * 0.22);

	// Caustics, at a tenth of the strength they have on open water -- enough
	// that the board is a surface rather than a fill, not enough to read as
	// pattern behind text.
	float t = UV.y;
	float a = sin(UV.x * 6.0  + TIME * 0.19 + t * 7.0);
	float b = sin(UV.x * 11.0 - TIME * 0.13 + t * 4.0);
	float caustic = pow(max((a * 0.5 + 0.5) * (b * 0.5 + 0.5), 0.0), 2.6);
	c += vec3(0.10, 0.20, 0.20) * caustic * (1.0 - y * 0.55) * 0.22;

	// Corner vignette, so the content column is the brightest part of the page
	// and the chrome never touches a lit edge.
	// A column of light down the middle, where the cards are, and the corners
	// falling away. Gentle -- a hard vignette draws a ring, which is worse than
	// no vignette at all.
	c *= mix(0.88, 1.05, 1.0 - smoothstep(0.30, 1.12, length((UV - vec2(0.5)) * vec2(1.15, 0.70))));
	COLOR = vec4(c, 1.0);
}
""")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return mat

# The island's identity, pushed into a board. Much weaker than it is pushed
# into the sky: a board is deep water and it has to stay deep water, or Ancient
# Egypt's gold turns the shop into a brown room.
static func tint_board(mat: ShaderMaterial, p: Dictionary) -> void:
	if mat == null:
		return
	var mid: Color = p["mid"]
	# Very little. At 0.20 a green island turned the board olive, which is not a
	# colour deep water comes in -- the island is meant to be a hint of where you
	# are, not the material the board is made of.
	mat.set_shader_parameter("top", _v3(Color(0.078, 0.286, 0.361).lerp(mid, 0.10)))
	mat.set_shader_parameter("bottom", _v3(Color(0.031, 0.145, 0.204).lerp(mid, 0.05)))

# Pushes an island's identity into a backdrop without letting it go dark: the
# island accent warms the sky, its deep tone steers the water. Luminance floors
# keep even Volcano Isle and Neon City reading as daylight.
static func tint_backdrop(mat: ShaderMaterial, p: Dictionary) -> void:
	if mat == null:
		return
	var accent: Color = p["accent"]
	var mid: Color = p["mid"]
	# Deliberately small blends. Pushed further, Ancient Egypt's gold turns the
	# sky green and Neon City's cyan turns it grey -- the island should colour
	# the light, not replace it.
	mat.set_shader_parameter("sky_hi", _v3(SKY_HI.lerp(accent, 0.07)))
	mat.set_shader_parameter("sky_lo", _v3(SKY_LO.lerp(accent, 0.14)))
	mat.set_shader_parameter("water", _v3(LAGOON.lerp(mid, 0.24)))
	mat.set_shader_parameter("water_lo", _v3(LAGOON_DEEP.lerp(mid, 0.30)))

static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

# =============================================================================
#  Small parts
# =============================================================================

# The HUD currency capsule: a brass-rimmed glass pill holding an icon and a
# number, optionally with a coral "+" that opens the shop. Coin, spins and
# shields all use it, so the three read as one row of held resources.
static func capsule(icon_kind: String, value := "0", plus_action := Callable()) -> Dictionary:
	var root := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# DEEP, NOT WHITE.
	#
	# A white pill is the brightest object on any screen it is on, and these
	# eight pills are chrome -- they are on every screen in the game, they are
	# never the thing you are looking at, and they were out-shouting the goods
	# on every page. Every game this one is aimed at holds its currencies in a
	# dark capsule with a metal rim and a bright numeral, for exactly this
	# reason: dark chrome makes the content the brightest thing, which is what
	# stops a UI reading as a settings screen with pictures on it.
	sb.bg_color = Color(LAGOON_DEEP.r * 0.62, LAGOON_DEEP.g * 0.62, LAGOON_DEEP.b * 0.62, 0.94)
	sb.set_corner_radius_all(28)
	sb.set_border_width_all(4)
	# BRASS at 3px, on a sky this bright, is a mid tone on a light one -- the
	# capsules had no outline and floated. BRASS_LO is the shadowed edge of the
	# same metal, so the pill still reads as brass-rimmed, but it is now a dark
	# ring the sky cannot swallow. This is the row the player checks first and
	# most often; it has to survive being over the sun bloom.
	sb.border_color = BRASS_LO
	sb.shadow_size = 8
	sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.34)
	sb.shadow_offset = Vector2(0, 3)
	# 7 rather than 8 a side, and the icon below is 38 rather than 44. Both came
	# down on 2026-09-02 when the HUD moved up level with the cutout: a Dynamic
	# Island covers 245..475 of 720, and every unit the capsules give back is a
	# unit of counter that is not under the hardware. It buys 14 on each side --
	# enough to take the star capsule fully clear of the island's right edge,
	# and to pull the shield's right-hand end most of the way out of its left.
	sb.content_margin_left = 7.0
	# 7, not 4, when there is a plus. The coral disc has to clear the capsule's
	# own corner arc, and at 4 it did so by a single pixel -- geometrically
	# inside, visually bursting out of the pill. See the note on the button.
	sb.content_margin_right = 7.0 if plus_action.is_null() else 6.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	root.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(hb)

	var icon := Glyph.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(38, 38)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)

	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", display_font())
	val.add_theme_font_size_override("font_size", UI.F_LABEL)
	# Sand on deep water, and rimmed -- these numbers sit over the sun bloom on
	# the bright pages and over the board's lamp on the dark ones, so they carry
	# their own separation rather than relying on either.
	val.add_theme_color_override("font_color", SAND)
	val.add_theme_color_override("font_outline_color", Color(0.008, 0.055, 0.078))
	val.add_theme_constant_override("outline_size", 5)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(val)

	var out := {"root": root, "value": val}
	if not plus_action.is_null():
		# 42 across, and the number is not free. The capsule is 70 tall with a
		# 3px border and a 28px corner radius, so its right end is an arc whose
		# centre sits 31px in from the edge with 25px of inner radius. A 46px
		# disc at a 4px margin put its own centre 30px in -- one pixel proud of
		# that arc centre -- leaving 25 - (1 + 23) = 1px of clearance. It never
		# technically overflowed, which is why it survived review, but a disc
		# tangent to the pill it sits in reads as broken alignment. At 42 with a
		# 7px margin the two centres coincide and there are 4px all round.
		var plus := Button.new()
		plus.custom_minimum_size = Vector2(42, 42)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus.focus_mode = Control.FOCUS_NONE
		# The pressed face has to be its own colour, not the normal one. Only
		# "hover" was ever distinct here, and a finger never hovers -- so on a
		# phone this button looked identical held down as it did untouched, and
		# a tap that lands on a shelf you are already reading came back with no
		# sign it had been received at all. Same sink as every moulded button
		# in the game: the face darkens and travels down into its own bevel.
		for state in ["normal", "hover", "pressed"]:
			var psb := StyleBoxFlat.new()
			match state:
				"hover": psb.bg_color = CORAL_HI
				"pressed": psb.bg_color = CORAL.darkened(0.14)
				_: psb.bg_color = CORAL
			psb.set_corner_radius_all(21)
			psb.border_width_bottom = 1 if state == "pressed" else 4
			psb.border_color = CORAL_LO
			plus.add_theme_stylebox_override(state, psb)
		FX.press_feedback(plus)
		plus.pressed.connect(plus_action)
		hb.add_child(plus)
		# Glyph.fill, not a hand-anchored Glyph. It clears the 40x40 minimum
		# that would otherwise beat these insets and push the "+" down and
		# right of centre, and it insets all four sides equally so the box
		# stays square; the long version of why is on Glyph.fill itself.
		out["plus"] = plus
		Glyph.fill(plus, "plus", 10.0)
	return out

# A small colored tag ("BEST VALUE", "NEW"). Flat, no gloss — tags are labels
# printed on the object, not objects themselves. Rimmed and outlined all the
# same: a chip is small and it lands on card faces, brass and open water alike,
# and "SAVE 78%" in bare white on coral measured 2.07.
static func chip(text: String, color := CORAL, font_size := UI.F_TINY) -> PanelContainer:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# THE FILL IS THE HUE TAKEN DOWN, THE RIM IS THE HUE ITSELF.
	#
	# A chip is white type at 22px on a saturated fill, which is the hardest
	# combination in the palette: kelp measured 3.68 against white, brass 3.82,
	# coral 4.41 -- so "Easy" on five collection tiles, "SAVE 78%" on three
	# shop cards and "250% VALUE" on the starter were all under the line at
	# once, and the SAVE tags were additionally brass printed on brass. Taking
	# the fill 40% toward deep water clears 4.5 on every hue the chip is used
	# in and costs nothing legible: the rim is now the pure colour, lit, so the
	# chip reads as MORE of its own hue rather than less.
	sb.bg_color = color.lerp(HULL, 0.40)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = color
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 4.0
	c.add_theme_stylebox_override("panel", sb)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ui_bold_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", HULL)
	l.add_theme_constant_override("outline_size", 4)
	c.add_child(l)
	return c

# A value STAMPED ONTO THE GOODS: a deep plate with bright numerals on it.
#
# The shop's two loudest numbers -- what you save and how long the offer has --
# were both printed straight onto whatever card they landed on, and the shop
# has four different card stocks. "SAVE 25%" was brass type on a brass tile
# (invisible), then white on brass at 3.82; the countdown was coral on brass at
# 2.80, the single worst-measuring text in the game. Neither is fixable by
# picking a better ink, because the surface underneath changes from shelf to
# shelf.
#
# So they stop being printed and start being stamped. A deep plate carries its
# own contrast wherever it is put down -- brass, steel, silver, cream or open
# water -- which is the same argument as the keyline, one step up: an object,
# not a colour. Bright ink on it clears 7 : 1 on every one of those.
# The empty plate, for the callers that put more than one thing on it -- the
# struck price and its saving are two labels and a drawn rule, and they belong
# to one stamp.
static func stamp_plate(ink := KELP_HI) -> PanelContainer:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HULL.r, HULL.g, HULL.b, 0.94)
	sb.set_corner_radius_all(11)
	sb.set_border_width_all(2)
	sb.border_color = Color(ink.r, ink.g, ink.b, 0.45)
	sb.content_margin_left = 11.0
	sb.content_margin_right = 11.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 5.0
	c.add_theme_stylebox_override("panel", sb)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c

static func stamp(text: String, ink := KELP_HI, font_size := UI.F_TINY) -> PanelContainer:
	var c := stamp_plate(ink)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ui_bold_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", ink)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c

# Progress track: a dark well with a bright fill and a lit top edge.
#
# It was a pale wash in a paler well -- 0.28 of deep water over a white card --
# so an empty bar and a full one were the same object and neither said anything.
# A track only reads if the hole is unmistakably a hole; then even a few percent
# of fill is visible, which is the whole job of the control.
static func progress(fill := KELP) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 30)
	var bg := StyleBoxFlat.new()
	# Opaque, and deeper than the drop-off. It was LAGOON_DEEP at 0.72, which on
	# a cream card comes out a mid teal -- and now that every track in the game
	# carries its own count, that mid teal is what the count has to be read
	# against. White on it measured 4.17. A track is a hole; a hole is not
	# translucent.
	bg.bg_color = HULL
	bg.set_corner_radius_all(15)
	bg.set_border_width_all(3)
	bg.border_color = Color(HULL.r, HULL.g, HULL.b, 0.80)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(15)
	fg.border_width_top = 4
	# The lit edge along the top of the fill. For a kelp bar this is exactly the
	# brighter green the token used to be before it was darkened to carry white
	# text -- so nothing got less green, the green moved to where it reads.
	fg.border_color = KELP_HI if fill == KELP else fill.lightened(0.40)
	bar.add_theme_stylebox_override("fill", fg)
	return bar

# The number written across the middle of a track. A bar without one tells the
# player they are "some of the way" and nothing else; the reference games this
# game is aimed at never draw a track without its count on it. White with a
# deep outline, so it reads over the empty end and the filled end alike.
static func progress_value(bar: ProgressBar, text: String, size := UI.F_CAPTION) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", HULL)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return l

# Content emoji — collection items, chest art, mission markers — can't all be
# hand-drawn, but they can be *framed*. Dropping each into a brass-rimmed glass
# token turns a row of mixed-provenance emoji into a row of game pieces, which
# is the difference between "placeholder" and "collectible".
static func token(emoji: String, diameter := 76.0, rim := BRASS) -> Control:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(diameter, diameter)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.96)
	sb.set_corner_radius_all(int(diameter * 0.5))
	sb.set_border_width_all(5)
	# A token is a game piece and it lands on card faces, on water and on grass.
	# A brass ring at brass's own value disappears against sand and against the
	# lagoon both; the ring is darkened toward deep water so the piece has an
	# edge wherever it is put down, while still reading as its own metal.
	sb.border_color = rim.lerp(HULL, 0.45)
	sb.shadow_size = 7
	sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.32)
	sb.shadow_offset = Vector2(0, 3)
	root.add_theme_stylebox_override("panel", sb)

	var l := Label.new()
	l.text = emoji
	l.add_theme_font_override("font", CV.emoji_font())
	l.add_theme_font_size_override("font_size", int(diameter * 0.52))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	add_gloss(root, int(diameter * 0.5))
	return root

# Maps a legacy colour to the closest material in the system. Call sites that
# still speak in colours ("this button is green") keep working and come out in
# the right material, so meaning survives the redesign without 20 edits.
static func kind_for(c: Color) -> String:
	if c.s < 0.22:
		return "glass"
	var h := c.h * 360.0
	if h < 18.0 or h >= 340.0:
		return "danger" if c.v < 0.85 else "primary"
	if h < 45.0:
		return "primary"
	if h < 70.0:
		return "brass"
	if h < 165.0:
		return "kelp"
	if h < 250.0:
		return "glass"
	return "urchin"

# Section divider used inside pages: a brass hairline that fades at both ends,
# so sections separate without drawing a hard line across the glass.
static func divider() -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BRASS.r, BRASS.g, BRASS.b, 0.45)
	sb.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(10, 3)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p
