# What this build believes, and who gets to change its mind.
#
# Every number and switch in this game is compiled in, which is the right
# default -- a constant cannot be unreachable, cannot arrive late and cannot be
# tampered with on the wire. This file is the exception for the handful of them
# that have to be changeable without a binary, because the build that turns out
# to be wrong is never the build that can be told about it. See the migration
# for the table behind it.
#
# THE ONE RULE, and everything else here follows from it:
#
#   AN ABSENT ANSWER IS THE COMPILED ANSWER. No network, no row, no migration,
#   a value of the wrong type, a key this build has never heard of -- every one
#   of those returns the default the caller passed, which is the constant the
#   game shipped with. There is no path through this file that can turn a
#   feature off because something failed. Turning a feature off takes a row
#   that says `false`.
#
# So every call site reads the same way: `if Flags.on("clan_chat")` is true on a
# plane, true on a fresh install, true if this file is deleted, and false only
# because somebody decided it should be.
#
# NOT A SECURITY BOUNDARY, and this matters because of where the save lives.
# The collection and the coin count are client-authoritative -- the server takes
# what the phone reports. A player who can edit the save can already do more
# damage than one who can lie to this file, so nothing here is load-bearing for
# cheating, and nothing economic should ever be enforced ONLY by a flag. A flag
# hides a door; it is not a lock.
extends Node

# Which game. Matches `project_id` in supabase/config.toml, and is sent on every
# fetch so the second game reads its own rows rather than this one's.
const APP := "loot-lagoon"

# Last known good, on disk. A kill switch that only applies after the network
# answers is a switch that lets the broken feature run for the first two seconds
# of every launch -- and on a cold start behind a bad radio, for much longer.
#
# Stale is the correct failure here. A cached `false` that is now wrong costs one
# feature being off until the next successful fetch; a cache that expired itself
# into emptiness costs the outage this file exists to shorten.
const CACHE_PATH := "user://config_cache.json"
const CACHE_TMP := "user://config_cache.json.tmp"

# A flag changed under a page that is already open.
#
# NOTHING LISTENS TO THIS YET, and that is the design rather than an omission.
# Every gate in the game is read at render time, so a page built after a switch
# is thrown already honours it -- which covers the ops case without putting a
# repaint of arbitrary UI on the critical path of a background fetch. The signal
# exists for the one future caller that genuinely needs a live repaint, and the
# day something connects it, it should be a specific page saying "rebuild me",
# never a blanket _fill_page over whatever happens to be open.
signal changed()

var _values: Dictionary = {}
var _fetched := false


func _ready() -> void:
	_load_cache()


# -----------------------------------------------------------------------------
#  Reading
# -----------------------------------------------------------------------------

# Is this feature allowed to run? Absent means yes.
#
# The default is a parameter rather than a hardcoded `true` because two of the
# call sites are the other way round -- a knob that ships OFF and gets turned on
# from the table once it has been proven. Both directions need the same
# "whatever is compiled in, unless a row says otherwise" guarantee.
func on(key: String, fallback := true) -> bool:
	var v = _values.get(key)
	if typeof(v) == TYPE_BOOL:
		return v
	# A number is accepted because a row written as 0/1 is a perfectly ordinary
	# way for somebody to mean false/true, and refusing it would make an ops
	# action silently do nothing at the moment it matters most.
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v) != 0.0
	return fallback


# A number, clamped by the caller if it needs to be.
#
# Anything that is not a number -- a string, an object, a null, a key that was
# never set -- comes back as the default. A config value that could arrive as
# text and be coerced to 0.0 would turn a typo in the table into an event that
# lasts no time at all.
func num(key: String, fallback: float) -> float:
	var v = _values.get(key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return fallback


# Whatever the row holds, for the knobs that are neither a switch nor a number.
# Named `value` and not `get`, which is Object's.
func value(key: String, fallback = null):
	return _values.get(key, fallback)


func has(key: String) -> bool:
	return _values.has(key)


# Everything, for diagnostics and the harness. A copy: a caller that mutated
# this would be editing the answer for every other call site in the game.
func all() -> Dictionary:
	return _values.duplicate(true)


# Whether a fetch has ever landed this session. Only the harness and the Options
# page's diagnostic line care -- no gameplay decision may depend on it, because
# "we have not heard yet" and "there is nothing to hear" must behave the same.
func fetched() -> bool:
	return _fetched


# -----------------------------------------------------------------------------
#  Fetching, and the targeting both config and the calendar are resolved against
# -----------------------------------------------------------------------------
#
# build_number() and platform_tag() are public because schedule.gd asks the same
# two questions of the same two sources. A second copy of either would be a
# second thing to keep in step with the server's resolution rules.

# Called at boot and on a resume from away. Cheap enough to be called on both:
# one small RPC that no other code waits on.
func refresh() -> void:
	if not Cloud.configured():
		return
	Cloud.app_config(APP, build_number(), platform_tag(), func(d: Dictionary) -> void:
		# EMPTY IS NOT AN ANSWER TO STORE. A dead network, a 500 and an
		# unapplied migration all arrive here as {}, and so does a table that
		# genuinely has no rows -- the four are indistinguishable from the
		# client, and three of them are failures.
		#
		# Writing {} over a good cache on any of them would mean a single bad
		# request undoes a live kill switch, which is the one thing this file
		# must not do. So emptying the table is deliberately NOT how a switch
		# gets taken back: set the row to `true`. The migration says the same
		# thing from the other side.
		if d.is_empty():
			return
		_fetched = true
		var before := _values
		_values = d
		_save_cache()
		if before != _values:
			changed.emit()
	)


# This build's number, or 0 for the editor and a desktop run.
#
# LL_FAKE_BUILD overrides it, and that is the only way to see what a specific
# build would be served. The server treats 0 as "dev, show everything", which is
# what makes a row testable before it ships -- but it is also why 0 cannot prove
# that a row aimed at build 150 reaches build 150 and not 149. The harness pins
# a number; a shipped build has no way to.
func build_number() -> int:
	if OS.has_environment("LL_FAKE_BUILD"):
		return int(OS.get_environment("LL_FAKE_BUILD"))
	return int(BuildID.read().get("build", 0))


# 'ios' | 'android' | '' -- and the empty string is correct for a desktop run
# rather than a fault. A row targeted at a platform should not reach the machine
# the game is written on, because that machine is neither platform.
func platform_tag() -> String:
	# LL_FAKE_PLATFORM is the companion to LL_FAKE_BUILD, and it exists for a
	# reason the build override does not cover. A dev build is exempt from every
	# build floor, so a row aimed at build 150 can be previewed on a desktop
	# without lying about anything -- but there is no such exemption for
	# platform, and there should not be: this machine really is neither iOS nor
	# Android, and a row targeted at one must not reach it by accident.
	#
	# That leaves naming the platform as the only way to look at a row aimed at
	# one, which a harness has to be able to do before it ships.
	if OS.has_environment("LL_FAKE_PLATFORM"):
		return OS.get_environment("LL_FAKE_PLATFORM")
	match OS.get_name():
		"iOS": return "ios"
		"Android": return "android"
	return ""


# -----------------------------------------------------------------------------
#  The cache
# -----------------------------------------------------------------------------
#
# Plain JSON and deliberately not encrypted, unlike the save. main.gd's save
# holds what a player owns and is worth tampering with; this holds public
# answers the server hands to anon, so encrypting it would buy nothing and add a
# second way for a boot to fail. See the note at the top about this not being a
# security boundary.

func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	# PARSED THROUGH AN INSTANCE RATHER THAN JSON.parse_string, which is the one
	# difference from how cloud.gd reads supabase.json. parse_string pushes an
	# engine error on malformed input, and malformed input is an EXPECTED state
	# here: this file is rewritten on every successful fetch, so a process killed
	# mid-write leaves a truncated one. A red error in the log on the next boot
	# would be the game reporting a fault about something it handles correctly.
	# parse() returns the error instead of printing it.
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		return
	# Anything unreadable is simply not a cache. No repair, no warning: the game
	# runs on its compiled defaults, which is a correct game.
	if typeof(j.data) == TYPE_DICTIONARY:
		_values = j.data


# Write-then-rename, the same shape as main.gd's save and for the same reason: a
# process killed mid-write must not leave a truncated file that the next boot
# parses as "no config".
func _save_cache() -> void:
	var f := FileAccess.open(CACHE_TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_values))
	f.close()
	DirAccess.rename_absolute(CACHE_TMP, CACHE_PATH)
