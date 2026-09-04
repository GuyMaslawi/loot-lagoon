extends Node
# =============================================================================
#  Loot Lagoon -- unicode escapes that do not say what they look like
# =============================================================================
#
# GDScript's \U escape takes SIX hex digits, not eight.
#
# So "\U0001F437" is not a pig. It is "\U0001F4" -- U+01F4, the Latin capital
# G with acute -- followed by the literal characters "3" and "7", and it prints
# as `Ǵ37`. The parser never complains, because every part of that is a legal
# thing to have written.
#
# THIS WAS NOT HYPOTHETICAL AND IT WAS NOT NEW. Seven of these were in shipped
# code when this file was written, and one of them was the piggy bank's own
# icon: everybody who opened the shop was shown `Ǵ37` where the pig goes. Two
# more were the alerts bell and three were the card boxes. Every one had
# survived every screenshot, every QA pass and several store submissions,
# because an eye reads `Ǵ37` as a font that failed to load rather than as a
# string that was never right.
#
# It was caught from the other end in the end: a new card printed `dzDD`, which
# is U+01F3 (`ǳ`) plus "DD", and that one happened to be on a card somebody was
# looking at. The correct form of all of them is \U01F437 -- or the character
# typed in directly, which is what most of this codebase already does.
#
# The lint is deliberately narrow. It does NOT ask whether a glyph exists in
# the font: that question has no single answer here, because emoji come from
# the bundled Noto while symbols like U+2605 come from the UI font, and asking
# the emoji font about a star reports a false alarm. It checks the one thing
# that is unambiguously a mistake -- an escape carrying more digits than the
# escape has.
#
# Run: godot --headless --path . res://tools/qa_emoji.tscn

# \u wants exactly four hex digits, \U wants up to six. Past that, the extra
# digits stop being part of the escape and start being text.
const LIMITS := {"u": 4, "U": 6}

func _ready() -> void:
	var bad := []
	var scanned := 0
	for path_v in _scripts():
		var path := String(path_v)
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		scanned += 1
		bad.append_array(_scan(path, text))

	print("QA-EMOJI: %d scripts scanned" % scanned)
	if bad.is_empty():
		print("QA-EMOJI: ALL PASS -- every \\u and \\U escape is the length it claims")
		get_tree().quit(0)
		return

	for row in bad:
		print("  %s:%d" % [row["file"], row["line"]])
		print("      wrote   %s" % row["wrote"])
		print("      means   %s   (%s)" % [row["means"], row["cps"]])
		print("      want    %s" % row["want"])
	print("")
	print("QA-EMOJI: %d BROKEN ESCAPE(S). Each prints as one letter followed by" % bad.size())
	print("the leftover hex digits as plain text. Trim it to six digits, or type")
	print("the character in directly.")
	get_tree().quit(1)

# Every \u / \U in one file, with what it actually resolves to.
#
# Line at a time, and comment lines are skipped: a broken escape inside a `#`
# is a broken escape nobody prints, and this file's own header quotes one as
# the example of what to look for. Skipping them cannot hide a real defect --
# a defect has to be in a string the game evaluates, and that is code.
func _scan(path: String, text: String) -> Array:
	var out := []
	var lines := text.split("\n")
	for line_no in lines.size():
		var line := String(lines[line_no])
		if line.strip_edges().begins_with("#"):
			continue
		out.append_array(_scan_line(path, line, line_no + 1))
	return out

func _scan_line(path: String, text: String, line_no: int) -> Array:
	var out := []
	var i := 0
	var n := text.length()
	while i < n - 1:
		if text[i] != "\\":
			i += 1
			continue
		# A doubled backslash is an escaped backslash: the character after it
		# is content, and reading it as an escape introducer would report a
		# regex or a Windows path as a broken emoji.
		if text[i + 1] == "\\":
			i += 2
			continue
		var kind := text[i + 1]
		if not LIMITS.has(kind):
			i += 2
			continue
		var limit: int = LIMITS[kind]
		var digits := ""
		var j := i + 2
		while j < n and _is_hex(text[j]):
			digits += text[j]
			j += 1
		if digits.length() > limit:
			var taken := digits.substr(0, limit)
			var left := digits.substr(limit)
			var cp := taken.hex_to_int()
			out.append({
				"file": path.get_file(),
				"line": line_no,
				"wrote": "\\%s%s" % [kind, digits],
				"means": "%s%s" % [char(cp), left],
				"cps": "U+%04X then the text \"%s\"" % [cp, left],
				# The last `limit` digits, which is the fix in every real case:
				# the extra ones are always leading zeros somebody padded to
				# eight out of habit from other languages.
				"want": "\\%s%s" % [kind, digits.substr(digits.length() - limit)],
			})
		i = maxi(j, i + 2)
	return out

func _is_hex(c: String) -> bool:
	return (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")

func _scripts() -> Array:
	var out := []
	for dir in ["res://scripts", "res://tools"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".gd"):
				out.append("%s/%s" % [dir, f])
			f = d.get_next()
		d.list_dir_end()
	return out
