extends Node
# =============================================================================
#  Loot Lagoon -- the style bible's enforcement arm
# =============================================================================
#
# STYLE.md holds the rules; this file holds the ones a machine can check. It
# is deliberately cheap -- no rendering, no tree-walking -- so there is no
# excuse not to run it after touching art or the palette:
#
#     godot --headless --path . res://tools/qa_style.tscn
#
# What it asserts, and the incident behind each check:
#
#  1. RENDERED ART CARRIES NO PLANE EDGE. Every prop and card PNG must be
#     transparent along all four borders. The Cycles shadow catcher is a plane,
#     a plane has an edge, and that edge once landed inside every icon in the
#     game as a grey box -- invisible on the dark board, glaring on a pale
#     shop card. contact_shadow() replaced it; this makes sure nobody puts it
#     back.
#
#  2. RENDERED ART IS SQUARE AND BIG ENOUGH. A non-square render means the
#     resolution override was left half-set; smaller than 256 means somebody
#     shipped an iteration render.
#
#  3. THE CARDS DIRECTORY CONTAINS ONLY WHAT CV CAN LOAD. card_tex() returns
#     null for a missing file and the emoji covers it -- which is the designed
#     incremental path, but it also means a MISNAMED file fails silently
#     forever. Every PNG in assets/art/cards must parse as <set>_<NN>.png or
#     <set>_icon.png for a set id that exists, with NN inside the set's size.
#
#  4. EVERY PROP THE PIPELINE PROMISES EXISTS. The render targets in
#     render_props.py and the textures the game asks prop_tex() for drift
#     apart silently; the file list below is the contract.
#
#  5. NO PALETTE CONSTANT IS FED TO kind_for(). Lagoon.kind_for maps a colour
#     onto a material by HUE BAND, and the bands do not line up with the
#     constants' names: kind_for(Lagoon.BRASS) returns "primary" -- coral, the
#     loudest material there is -- because BRASS's hue is 36 and the primary
#     band ends at 45. Found live on the alerts page's "Clear all", which is
#     the one control that destroys something. A call site that wants a
#     material names a colour inside that material's band.

const PROPS_DIR := "res://assets/art/props"
const CARDS_DIR := "res://assets/art/cards"

# Check 4's contract: what must exist for the game's prop_tex calls to land.
const REQUIRED_PROPS := [
	"gift", "lock",
	"chest_t0", "chest_t1", "chest_t2", "chest_t0_open",
	"piggy_0", "piggy_1", "piggy_2", "piggy_3", "piggy_4", "piggy_5",
	"scaffold",
]

# Drawn before the render pipeline existed; kept only as art history in git.
# They are fallbacks no code path can reach (their replacements always exist,
# check 4 says so) and they intentionally fail the border rule, so they are
# named here rather than silently skipped by pattern.
const LEGACY_EXEMPT := ["chest.png", "chest_open.png"]

var fails := 0
var checks := 0

func _ready() -> void:
	_check_renders(PROPS_DIR, LEGACY_EXEMPT)
	_check_renders(CARDS_DIR, [])
	_check_card_names()
	_check_required_props()
	_check_kind_for_misuse()
	print("")
	if fails == 0:
		print("QA-STYLE: ALL PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		print("QA-STYLE: %d FAILURE(S) in %d checks" % [fails, checks])
		get_tree().quit(1)

func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL  %s" % msg)

func _png_files(dir_path: String) -> Array:
	var out := []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".png"):
			out.append(f)
		f = d.get_next()
	return out

# Checks 1 + 2, one directory at a time. The PNG is read from the source file,
# not the imported texture -- the importer premultiplies and compresses, and
# the question is about what the renderer wrote.
func _check_renders(dir_path: String, exempt: Array) -> void:
	for f in _png_files(dir_path):
		if f in exempt:
			continue
		checks += 1
		var img := Image.new()
		var err := img.load_png_from_buffer(
			FileAccess.get_file_as_bytes(dir_path + "/" + f))
		if err != OK:
			_fail("%s/%s: unreadable PNG" % [dir_path, f])
			continue
		var w := img.get_width()
		var h := img.get_height()
		if w != h:
			_fail("%s: %dx%d is not square" % [f, w, h])
		if w < 256:
			_fail("%s: %dpx is an iteration render, not a shippable one" % [f, w])
		var border := 0
		for x in w:
			border = maxi(border, maxi(_a(img, x, 0), _a(img, x, h - 1)))
		for y in h:
			border = maxi(border, maxi(_a(img, 0, y), _a(img, w - 1, y)))
		if border > 8:
			_fail("%s: border alpha %d -- something (a catcher plane?) reaches the frame edge" % [f, border])

func _a(img: Image, x: int, y: int) -> int:
	return int(img.get_pixel(x, y).a * 255.0)

# Check 3: every card file must be addressable by CV.card_tex / card_set_tex.
func _check_card_names() -> void:
	var sizes := {}
	for c in CV.COLLECTIONS:
		sizes[c["id"]] = (c["items"] as Array).size()
	for f_v in _png_files(CARDS_DIR):
		checks += 1
		# The loop variable is untyped off the Array, so := cannot infer and
		# the whole SCRIPT fails to parse -- which presents as the harness
		# hanging forever, because a scene with no script never quits. Same
		# trap drawn-objects documented; annotate everything derived from it.
		var f: String = f_v
		var base: String = f.trim_suffix(".png")
		var us: int = base.rfind("_")
		if us < 1:
			_fail("cards/%s: not <set>_<NN>.png or <set>_icon.png" % f)
			continue
		var set_id: String = base.substr(0, us)
		var tail: String = base.substr(us + 1)
		if not sizes.has(set_id):
			_fail("cards/%s: no collection named '%s'" % [f, set_id])
			continue
		if tail == "icon":
			continue
		if not tail.is_valid_int():
			_fail("cards/%s: index '%s' is not a number" % [f, tail])
			continue
		var idx: int = tail.to_int()
		if idx < 1 or idx > int(sizes[set_id]):
			_fail("cards/%s: %s has %d cards, there is no #%d" % [f, set_id, sizes[set_id], idx])

func _check_required_props() -> void:
	for p in REQUIRED_PROPS:
		checks += 1
		if not FileAccess.file_exists("%s/%s.png" % [PROPS_DIR, p]):
			_fail("props/%s.png missing -- a prop_tex() call site will fall back or break" % p)

# Check 5: source scan. Narrow on purpose -- only the exact misuse that
# shipped once. kind_for(some_local_colour) is the designed call shape.
func _check_kind_for_misuse() -> void:
	var d := DirAccess.open("res://scripts")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			checks += 1
			var text := FileAccess.get_file_as_string("res://scripts/" + f)
			var lines := text.split("\n")
			for i in lines.size():
				var line := String(lines[i])
				if line.strip_edges().begins_with("#"):
					continue
				if line.contains("kind_for(Lagoon."):
					_fail("scripts/%s:%d feeds a palette constant to kind_for -- name a colour inside the band instead" % [f, i + 1])
		f = d.get_next()
