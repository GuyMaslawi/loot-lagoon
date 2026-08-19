class_name SpinButton
extends Control

# The one control every player taps hundreds of times a session, so it is
# drawn rather than styled: a single canvas_item shader paints the halo, the
# raised candy face, the 3D base it presses into, a chasing rim light, a
# periodic specular sweep and a few twinkles. Colors come from the island
# palette, so the hero button belongs to whichever island you're on.

signal pressed
signal held

const PAD := 30.0      # room outside the body for the halo to bleed into
const DEPTH := 13.0    # how far the face floats above its base
const IDLE_NUDGE := 4.2  # seconds of no taps before the button asks for one
const HOLD := 0.55     # seconds on the button before it starts an auto run

var _vis: ColorRect
var _mat: ShaderMaterial
var _label: Label
var _hit: Button
var _disabled := false
var _press := 0.0
var _idle_t := 0.0
var _spin_col := Lagoon.CORAL
var _glow_col := Lagoon.BRASS_HI

var _down := false
var _hold_t := 0.0
var _was_hold := false

var disabled: bool:
	set(value):
		_disabled = value
		if _hit != null:
			_hit.disabled = value
			# a spin can start while the finger is still down; drop the hold so
			# releasing afterwards cannot fire a stale press or auto toggle
			_down = false
			_was_hold = false
			_mat.set_shader_parameter("enabled", 0.0 if value else 1.0)
			_label.modulate = Color(1, 1, 1, 0.5) if value else Color.WHITE
			_idle_t = 0.0
	get:
		return _disabled

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_vis = ColorRect.new()
	_mat = ShaderMaterial.new()
	_mat.shader = _make_shader()
	_vis.material = _mat
	_vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vis)

	_label = Label.new()
	_label.text = "SPIN"
	_label.add_theme_font_override("font", Lagoon.display_font())
	_label.add_theme_font_size_override("font_size", 54)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_constant_override("outline_size", 13)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_hit = Button.new()
	_hit.flat = true
	_hit.focus_mode = Control.FOCUS_NONE
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_hit.add_theme_stylebox_override(state, clear)
	_hit.button_down.connect(_on_down)
	_hit.button_up.connect(_on_up)
	add_child(_hit)

	resized.connect(_layout)
	_layout()
	apply_palette(CV.island_palette(1))

# The face is coral on every island, always. It used to take the island's own
# "spin" hue, which meant the single most important control in the game was
# magenta on Candy Land, gold on Atlantis and acid green on Spooky Hollow -- a
# player never got to learn what "the button" looks like. The island still
# shows up, but only in the halo and rim light around it.
func apply_palette(p: Dictionary) -> void:
	_spin_col = Lagoon.CORAL
	_glow_col = p["glow"]
	_mat.set_shader_parameter("col_top", _v3(Lagoon.CORAL_HI))
	_mat.set_shader_parameter("col_bot", _v3(Lagoon.CORAL_LO))
	_mat.set_shader_parameter("rim_col", _v3(Color(1, 1, 1).lerp(_glow_col, 0.35)))
	_mat.set_shader_parameter("glow_col", _v3(_glow_col))
	# The bezel is the same metal as the cabinet trim, so the hero button reads
	# as part of the machine rather than a sticker sitting on top of it.
	_mat.set_shader_parameter("bezel_col", _v3(Lagoon.BRASS))
	_label.add_theme_color_override("font_color", Lagoon.SAND)
	_label.add_theme_color_override("font_outline_color", Lagoon.CORAL_LO.darkened(0.35))

static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

func _layout() -> void:
	_vis.position = Vector2(-PAD, -PAD)
	_vis.size = size + Vector2(PAD * 2.0, PAD * 2.0)
	_mat.set_shader_parameter("rect_px", _vis.size)
	_mat.set_shader_parameter("pad", PAD)
	_mat.set_shader_parameter("depth", DEPTH)
	_mat.set_shader_parameter("radius", (size.y - DEPTH) * 0.5)
	_hit.size = size
	_hit.position = Vector2.ZERO
	_label.size = size
	_sync_press()

func _sync_press() -> void:
	_mat.set_shader_parameter("press", _press)
	_label.position = Vector2(0.0, -DEPTH * 0.5 + DEPTH * _press)

func _process(delta: float) -> void:
	if _disabled:
		return
	# Holding the hero button is how an auto run starts, so the finger never has
	# to leave the one control the whole page is built around.
	if _down:
		_hold_t += delta
		if not _was_hold and _hold_t >= HOLD:
			_was_hold = true
			Sfx.play("pop", -8.0)
			FX.burst(self, size * 0.5, _glow_col, 14)
			held.emit()
		return
	_idle_t += delta
	if _idle_t >= IDLE_NUDGE:
		_idle_t = 0.0
		_nudge()

# A short lean-and-settle. Cheaper on the eye than a permanent pulse, and it
# reads as the button inviting the next tap instead of vibrating forever.
func _nudge() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.045, 0.955), 0.13).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector2(0.985, 1.03), 0.12).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_down() -> void:
	_idle_t = 0.0
	_down = true
	_hold_t = 0.0
	_was_hold = false
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_press = v
		_sync_press()
	, _press, 1.0, 0.07)

func _on_up() -> void:
	_down = false
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_press = v
		_sync_press()
	, _press, 0.0, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _disabled:
		FX.burst(self, size * 0.5, _glow_col, 10)
		_ring_pop()
		if not _was_hold:
			pressed.emit()

# A single expanding ring of the island's glow color — the visual "clunk"
# that tells you the machine took the tap.
func _ring_pop() -> void:
	var ring := ColorRect.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec3 col;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float band = smoothstep(0.62, 0.92, d) * smoothstep(1.0, 0.9, d);
	COLOR = vec4(col, band * 0.75);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("col", _v3(_glow_col))
	ring.material = mat
	ring.size = size * 0.7
	ring.position = size * 0.5 - ring.size * 0.5
	ring.pivot_offset = ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.z_index = -1
	add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.1, 2.6), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.42)
	tw.chain().tween_callback(ring.queue_free)

static func _make_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec2 rect_px = vec2(660.0, 156.0);
uniform float pad = 30.0;
uniform float depth = 13.0;
uniform float radius = 42.0;
uniform float press : hint_range(0.0, 1.0) = 0.0;
uniform float enabled : hint_range(0.0, 1.0) = 1.0;
uniform vec3 col_top = vec3(1.0, 0.45, 0.33);
uniform vec3 col_bot = vec3(0.71, 0.22, 0.10);
uniform vec3 rim_col = vec3(1.0, 0.94, 0.82);
uniform vec3 glow_col = vec3(1.0, 0.82, 0.40);
uniform vec3 bezel_col = vec3(0.95, 0.77, 0.24);
uniform float bezel_w = 7.5;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Four-point glint: two crossed gaussian streaks.
float glint(vec2 q, float r) {
	float a = exp(-pow(q.x / (r * 0.16), 2.0) - pow(q.y / r, 2.0));
	float b = exp(-pow(q.y / (r * 0.16), 2.0) - pow(q.x / r, 2.0));
	return max(a, b);
}

void fragment() {
	vec2 px = UV * rect_px;
	vec2 p = px - rect_px * 0.5;
	vec2 hb = vec2(rect_px.x * 0.5 - pad, max(rect_px.y * 0.5 - pad - depth * 0.5, 4.0));
	float r = min(radius, min(hb.x, hb.y));

	// The face floats `depth` above a fixed base and sinks into it on press.
	vec2 face_c = vec2(0.0, -depth * 0.5 + press * depth);
	vec2 base_c = vec2(0.0, depth * 0.5);
	float d_face = sd_box(p - face_c, hb, r);
	float d_base = sd_box(p - base_c, hb, r);

	float aa = 1.3;
	float m_face = 1.0 - smoothstep(-aa, aa, d_face);
	float m_base = 1.0 - smoothstep(-aa, aa, d_base);

	// --- breathing halo ---
	float breathe = 0.70 + 0.30 * sin(TIME * 2.0);
	float halo = exp(-max(d_face, 0.0) / (16.0 + 9.0 * breathe)) * 0.55 * breathe;
	halo *= mix(0.12, 1.0, enabled);

	vec3 col = glow_col;
	float a = halo * (1.0 - m_base);

	// --- base: the chunk the face presses into ---
	col = mix(col, col_bot * 0.40, m_base);
	a = max(a, m_base);

	// --- raised face ---
	float ly = clamp((p.y - face_c.y) / (hb.y * 2.0) + 0.5, 0.0, 1.0);
	vec3 body = mix(col_top, col_bot, pow(ly, 1.15));

	// tight gloss arc over the top third, pinched in at both ends
	float arc = smoothstep(0.34, 0.02, ly) * pow(1.0 - smoothstep(0.30, 0.98, abs(p.x) / hb.x), 0.7);
	body += vec3(1.0) * arc * 0.26;
	// keep the lower half deep so the hero color stays a hero color
	body *= 1.0 - smoothstep(0.52, 1.0, ly) * 0.22;
	body *= 1.0 - press * 0.10;

	// --- specular sweep: fast pass, long pause ---
	float travel = fract(TIME / 2.6) / 0.26;
	float band_p = mix(-0.35, 1.35, clamp(travel, 0.0, 1.0));
	float u = px.x / rect_px.x + (px.y / rect_px.y - 0.5) * 0.5;
	float band = exp(-pow((u - band_p) / 0.075, 2.0)) * step(travel, 1.0) * enabled;
	body += vec3(1.0) * band * 0.40;

	// --- twinkles ---
	vec2 q = p - face_c;
	float tw = glint(q - vec2(-hb.x * 0.58, -hb.y * 0.30), 14.0) * (0.5 + 0.5 * sin(TIME * 3.1));
	tw += glint(q - vec2(hb.x * 0.54, hb.y * 0.28), 11.0) * (0.5 + 0.5 * sin(TIME * 2.3 + 1.9));
	tw += glint(q - vec2(hb.x * 0.20, -hb.y * 0.52), 8.0) * (0.5 + 0.5 * sin(TIME * 4.1 + 3.4));
	body += vec3(1.0) * clamp(tw, 0.0, 1.0) * 0.55 * enabled;

	// --- metal bezel around the rim, with a highlight chasing round it ---
	float inner = 1.0 - smoothstep(-aa, aa, d_face + bezel_w);
	float bez = clamp(m_face - inner, 0.0, 1.0);
	float ang = atan(p.y - face_c.y, p.x);
	float chase = 0.5 + 0.5 * sin(ang * 5.0 - TIME * 2.4);
	vec3 metal = bezel_col * (0.55 + 0.75 * (1.0 - ly));
	metal = mix(metal, rim_col, chase * 0.55 * enabled);
	// the bezel casts a shadow down onto the face, so the face sits inside it
	float cast_sh = (1.0 - smoothstep(0.0, 7.0, abs(d_face + bezel_w + 3.5))) * smoothstep(0.78, 0.12, ly);
	body *= 1.0 - cast_sh * 0.30;

	vec3 face = mix(body, metal, bez);

	// push saturation up while live, drain it entirely while disabled
	float lum = dot(face, vec3(0.299, 0.587, 0.114));
	face = clamp(mix(vec3(lum), face, mix(1.0, 1.20, enabled)), vec3(0.0), vec3(1.7));
	face = mix(mix(vec3(lum), col_top, 0.42) * 0.92, face, enabled);

	col = mix(col, face, m_face);
	a = max(a, m_face);
	COLOR = vec4(col, a);
}
"""
	return sh
