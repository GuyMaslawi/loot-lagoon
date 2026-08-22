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
const KELP        := Color(0.247, 0.749, 0.498)  # confirm / progress
const KELP_LO     := Color(0.086, 0.478, 0.302)
const URCHIN      := Color(0.573, 0.427, 0.851)  # rare / premium
const URCHIN_LO   := Color(0.353, 0.235, 0.588)
const REEF        := Color(0.945, 0.310, 0.404)  # alert / danger
const REEF_LO     := Color(0.667, 0.145, 0.220)

# --- ink ---------------------------------------------------------------------
const INK         := Color(0.043, 0.227, 0.286)  # primary text on glass
const INK_SOFT    := Color(0.290, 0.475, 0.529)  # secondary text on glass
const INK_MUTE    := Color(0.167, 0.351, 0.408)  # secondary text at caption size
const INK_FAINT   := Color(0.451, 0.612, 0.655)  # tertiary / disabled

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

# The workhorse surface: milky, translucent, lit along its top edge. `opacity`
# leans opaque for anything holding text, translucent for decorative layers.
static func glass(radius := R_CARD, opacity := 0.90) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SHELL.r, SHELL.g, SHELL.b, opacity)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.shadow_size = 12
	sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.26)
	sb.shadow_offset = Vector2(0, 6)
	return sb

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

static func glass_well(radius := R_CARD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(LAGOON_DEEP.r, LAGOON_DEEP.g, LAGOON_DEEP.b, 0.30)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(2)
	sb.border_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.22)
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
static func card(parent: Node, radius := R_CARD, pad := 18, opacity := 0.90) -> VBoxContainer:
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
	// dark chamfer right at the outline keeps the shape crisp on any backdrop
	c = mix(c, lo * 0.55, smoothstep(-3.5, -0.5, d));
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

	var lbl := title(text, font_size, SAND, BRASS_LO.darkened(0.25))
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
	sb.border_color = BRASS
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

	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(r)
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		sb.content_margin_left = 22.0
		sb.content_margin_right = 22.0
		match state:
			"hover":
				sb.bg_color = face.lightened(0.10)
				sb.border_width_bottom = 7
			"pressed":
				# the face travels down into its bevel rather than just darkening
				sb.bg_color = face.darkened(0.10)
				sb.border_width_bottom = 2
				sb.content_margin_top = 15.0
				sb.content_margin_bottom = 5.0
			"disabled":
				# Dark enough that the white label still reads. A pale grey face
				# with pale text is the most common way a disabled button ends
				# up illegible rather than merely inactive.
				sb.bg_color = Color(0.51, 0.59, 0.62, 0.92)
				sb.border_width_bottom = 5
			_:
				sb.bg_color = face
				sb.border_width_bottom = 7
		sb.border_color = bevel if state != "disabled" else Color(0.33, 0.40, 0.43, 0.92)
		sb.shadow_size = 8
		sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.22)
		sb.shadow_offset = Vector2(0, 4)
		btn.add_theme_stylebox_override(state, sb)

	btn.add_theme_font_override("font", display_font())
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", UI.F_LABEL)
	var outline: Color = bevel.darkened(0.25) if ink.get_luminance() > 0.5 else Color(1, 1, 1, 0.55)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(c, ink)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.88))
	btn.add_theme_color_override("font_outline_color", outline)
	btn.add_theme_constant_override("outline_size", 6)
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
	sb.bg_color = Color(1, 1, 1, 0.88)
	sb.set_corner_radius_all(28)
	sb.set_border_width_all(3)
	sb.border_color = BRASS
	sb.shadow_size = 7
	sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.28)
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0 if plus_action.is_null() else 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	root.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(hb)

	var icon := Glyph.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)

	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", display_font())
	val.add_theme_font_size_override("font_size", UI.F_LABEL)
	val.add_theme_color_override("font_color", INK)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(val)

	var out := {"root": root, "value": val}
	if not plus_action.is_null():
		var plus := Button.new()
		plus.custom_minimum_size = Vector2(46, 46)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed"]:
			var psb := StyleBoxFlat.new()
			psb.bg_color = CORAL if state != "hover" else CORAL_HI
			psb.set_corner_radius_all(23)
			psb.border_width_bottom = 4
			psb.border_color = CORAL_LO
			plus.add_theme_stylebox_override(state, psb)
		plus.pressed.connect(plus_action)
		hb.add_child(plus)
		var pg := Glyph.new()
		pg.kind = "plus"
		pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plus.add_child(pg)
		pg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pg.offset_left = 11.0
		pg.offset_right = -11.0
		pg.offset_top = 11.0
		pg.offset_bottom = -13.0
		out["plus"] = plus
	return out

# A small colored tag ("BEST VALUE", "NEW"). Flat, no gloss — tags are labels
# printed on the object, not objects themselves.
static func chip(text: String, color := CORAL, font_size := UI.F_TINY) -> PanelContainer:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(12)
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
	c.add_child(l)
	return c

# Progress track: a glass well with a coral (or given) fill and a lit top edge.
static func progress(fill := KELP) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 26)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(LAGOON_DEEP.r, LAGOON_DEEP.g, LAGOON_DEEP.b, 0.28)
	bg.set_corner_radius_all(13)
	bg.set_border_width_all(2)
	bg.border_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.18)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(13)
	fg.border_width_top = 3
	fg.border_color = fill.lightened(0.35)
	bar.add_theme_stylebox_override("fill", fg)
	return bar

# Content emoji — collection items, chest art, mission markers — can't all be
# hand-drawn, but they can be *framed*. Dropping each into a brass-rimmed glass
# token turns a row of mixed-provenance emoji into a row of game pieces, which
# is the difference between "placeholder" and "collectible".
static func token(emoji: String, diameter := 76.0, rim := BRASS) -> Control:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(diameter, diameter)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.92)
	sb.set_corner_radius_all(int(diameter * 0.5))
	sb.set_border_width_all(4)
	sb.border_color = rim
	sb.shadow_size = 6
	sb.shadow_color = Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.25)
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
