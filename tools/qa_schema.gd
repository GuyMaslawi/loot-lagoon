extends Node
# Temporary QA harness -- the save-shape guard. Not shipped.
#
# WHAT THIS IS DEFENDING, because the failure is silent and permanent.
#
# The save is a JSON file this build reads with a hand-written whitelist
# (`_save_dict`) and normalises with a routine that deletes any card set it does
# not recognise (`_sanitize_collections`). Both are correct against a
# hand-edited file. Both are catastrophic against a save written by a LATER
# build, which arrives through the ordinary cloud path the moment a player has
# two phones and only updates one.
#
# The old build would load the new save, drop the fields and sets it had never
# heard of, write the result to disk, and push it -- and `push_save` on the
# server takes it, because its only test is that `rank_stars` has not gone
# backwards, and deleting a card collection does not lower rank_stars. Nobody
# has to do anything wrong. Install, don't update, open once.
#
# So every check here is about a save stamped with a HIGHER `schema` than this
# build writes, and the rule is the same in each: preserve, and stop writing.

var m: Control
var fails := 0

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	_t_unknown_keys_survive_a_round_trip()
	_t_future_save_blocks_the_push()
	_t_future_save_keeps_unknown_card_sets()
	_t_future_save_keeps_a_grown_set()
	_t_future_save_keeps_its_stamp_across_a_save()
	_t_an_ordinary_save_is_untouched()
	_t_the_latch_lets_go()
	_t_held_survives_a_claim()
	_t_a_grown_set_still_claims()
	print("QA-SCHEMA: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _chk(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])

# A save as a build from next year would have left it: this build's fields, plus
# a field and a card set that do not exist here yet, stamped one ahead.
func _future_save() -> Dictionary:
	var d: Dictionary = m._save_dict()
	d["schema"] = m.SAVE_SCHEMA + 1
	d["a_field_from_the_future"] = {"nested": [1, 2, 3]}
	d["col_owned"] = (d["col_owned"] as Dictionary).duplicate(true)
	(d["col_owned"] as Dictionary)["set_that_does_not_exist_yet"] = [true, true, false]
	return d

# Puts the harness back to a build that has read nothing unusual, so one check
# cannot decide the next one.
func _reset() -> void:
	m.save_schema_seen = 0
	m.save_is_from_future = false
	m._save_extra = {}
	Cloud.block_push(false)

# --- the cheap half: unknown fields are carried, not dropped -----------------
#
# This one holds even when the stamps agree, and it is the fix for the whole
# class of "a build two fields behind quietly deleted them".
func _t_unknown_keys_survive_a_round_trip() -> void:
	print("a field this build has never heard of")
	_reset()
	m._adopt_schema(_future_save())
	var out: Dictionary = m._save_dict()
	_chk("is carried into the next save", out.has("a_field_from_the_future"))
	_chk("with its value intact",
		typeof(out.get("a_field_from_the_future")) == TYPE_DICTIONARY
			and (out["a_field_from_the_future"] as Dictionary).get("nested") == [1, 2, 3])
	# The order of the merge is the part that is easy to get backwards: the
	# preserved copy must lose to the field this build actually owns, or a stale
	# `coins` off the file would overwrite the one the player just earned.
	m.coins = 4242
	_chk("and never wins over a field this build owns", int(m._save_dict()["coins"]) == 4242,
		"coins=%d" % int(m._save_dict()["coins"]))

# --- the other half: an older build takes itself out of the writing seat -----
func _t_future_save_blocks_the_push() -> void:
	print("a save stamped ahead of this build")
	_reset()
	_chk("does not block the push before it is seen", not Cloud.push_blocked())
	m._adopt_schema(_future_save())
	_chk("is recognised as being from the future", m.save_is_from_future)
	_chk("and stops this device pushing to the server", Cloud.push_blocked())
	# The state has to be able to say "held" rather than "error": nothing
	# failed, and sending somebody to check their wifi would be a lie.
	_chk("and says so as a state of its own, not as a failure",
		Cloud.state() == "held", Cloud.state())

func _t_future_save_keeps_unknown_card_sets() -> void:
	print("a card set this build does not have")
	_reset()
	var save: Dictionary = _future_save()
	m._adopt_schema(save)
	m.col_owned = (save["col_owned"] as Dictionary).duplicate(true)
	m.col_dupes = {}
	m.col_new = {}
	m.col_claimed = {}
	m._ensure_collections()
	_chk("is still there after the normaliser has run",
		m.col_owned.has("set_that_does_not_exist_yet"))
	# The mirror of it: on a save this build understands, tidying is still the
	# right behaviour and must not have been switched off for everybody.
	_reset()
	m.col_owned = {"set_that_does_not_exist_yet": [true]}
	m._ensure_collections()
	_chk("but a retired set on an ordinary save is still tidied away",
		not m.col_owned.has("set_that_does_not_exist_yet"))

func _t_future_save_keeps_a_grown_set() -> void:
	print("an existing set that grew by one card in a later release")
	_reset()
	var c: Dictionary = CV.COLLECTIONS[0]
	var id: String = c["id"]
	var n: int = (c["items"] as Array).size()
	m._adopt_schema(_future_save())
	# Longer than this build's copy of the set by one, with the extra card owned
	# -- which is exactly what a phone that had the release would have written.
	var grown := []
	for i in n + 1:
		grown.append(true)
	m.col_owned = {id: grown}
	m.col_dupes = {}
	m.col_new = {}
	m.col_claimed = {}
	m._ensure_collections()
	_chk("keeps the card past the end of what this build knows",
		(m.col_owned[id] as Array).size() >= n + 1,
		"%d of %d" % [(m.col_owned[id] as Array).size(), n + 1])

# The mark has to outlive the session that noticed it. If the stamp were written
# back as this build's own number, the first autosave would erase the evidence
# and the NEXT launch would take the tidy-up path and delete the sets.
func _t_future_save_keeps_its_stamp_across_a_save() -> void:
	print("the stamp on a save from the future")
	_reset()
	m._adopt_schema(_future_save())
	var written: Dictionary = m._save_dict()
	_chk("is not lowered to this build's own number",
		int(written["schema"]) == m.SAVE_SCHEMA + 1, "schema=%s" % str(written["schema"]))
	# And reading that written copy back still trips the guard, which is the
	# whole point of not lowering it.
	_reset()
	m._adopt_schema(written)
	_chk("so the guard is still armed on the next launch", m.save_is_from_future)

func _t_an_ordinary_save_is_untouched() -> void:
	print("a save from this build, or from before stamps existed")
	_reset()
	var plain: Dictionary = m._save_dict()
	m._adopt_schema(plain)
	_chk("is not treated as being from the future", not m.save_is_from_future)
	_chk("and does not block the push", not Cloud.push_blocked())
	_reset()
	var unstamped: Dictionary = m._save_dict()
	unstamped.erase("schema")
	m._adopt_schema(unstamped)
	_chk("and neither is one with no stamp at all", not m.save_is_from_future)
	_reset()

# --- the release half of the latch ------------------------------------------
#
# Found by an adversarial review of the first version of this feature, which
# only ever ARMED. `save_schema_seen` was raised with maxi and nothing anywhere
# lowered it, so a phone that had once read a future save and then restored an
# ordinary island through the "Two islands" dialog stayed held for ever: never
# pushed again, season rollover skipped at every turn, and the next autosave
# stamped the future number onto a save that no longer had anything future in
# it -- which the next launch read back and re-armed on. The only exit was an
# app update that happened to raise SAVE_SCHEMA.
func _t_the_latch_lets_go() -> void:
	print("a future save, and then an ordinary one adopted over it")
	_reset()
	m._adopt_schema(_future_save())
	_chk("arms on the future save", m.save_is_from_future and Cloud.push_blocked())
	# Exactly what _adopt_remote does: the file underneath is replaced, then
	# _load_game re-reads it. No _reset() here -- that is the whole point.
	var ordinary: Dictionary = m._save_dict()
	ordinary["schema"] = m.SAVE_SCHEMA
	ordinary.erase("a_field_from_the_future")
	m._adopt_schema(ordinary)
	_chk("and lets go when the island underneath is one it understands",
		not m.save_is_from_future)
	_chk("so the device starts backing up again", not Cloud.push_blocked())
	_chk("and stops stamping a number it cannot write",
		int((m._save_dict() as Dictionary)["schema"]) == m.SAVE_SCHEMA,
		"schema=%s" % str((m._save_dict() as Dictionary)["schema"]))
	_chk("and the sync label is no longer stuck on held", Cloud.state() != "held",
		Cloud.state())
	_reset()

# The claim that runs at boot ends with an unconditional _set_state("synced"),
# and boot holds the device BEFORE it. So the Options card said "Backed up" in
# green on a phone dropping every push, while the strip on the same screen said
# backing up was paused.
func _t_held_survives_a_claim() -> void:
	print("the sync label on a held device")
	_reset()
	m._adopt_schema(_future_save())
	_chk("says held once the guard is armed", Cloud.state() == "held", Cloud.state())
	Cloud._set_state("synced")
	_chk("and nothing else can paint over it", Cloud.state() == "held", Cloud.state())
	_reset()

# The tail this feature keeps made two counters disagree: one walked the stored
# array, the other compared against the set size. Complete-but-longer gave a set
# with no CLAIM button at all; incomplete-but-longer gave a button that refused
# itself on every press.
func _t_a_grown_set_still_claims() -> void:
	print("a set that grew by one card, on the build that does not have it")
	_reset()
	var c: Dictionary = CV.COLLECTIONS[0]
	var id: String = c["id"]
	var n: int = (c["items"] as Array).size()
	m._adopt_schema(_future_save())

	# Every card this build knows owned, plus a kept tail entry that is NOT.
	var all_but_new := []
	for i in n:
		all_but_new.append(true)
	all_but_new.append(false)
	m.col_owned = {id: all_but_new}
	m.col_dupes = {}
	m.col_new = {}
	m.col_claimed = {}
	m._ensure_collections()
	_chk("counts only the cards this build has", m._collection_owned_count(c) == n,
		"%d of %d" % [m._collection_owned_count(c), n])
	# The two have to agree, or the button is drawn by one and refused by the
	# other. This is the case that produced a dead CLAIM button.
	_chk("and agrees with the completeness test", m._collection_complete(c),
		"complete=%s" % str(m._collection_complete(c)))

	# The mirror: the new card owned too, which used to read "10 / 9 cards" and
	# hide the claim button on a set that was finished.
	var all_owned := []
	for i in n + 1:
		all_owned.append(true)
	m.col_owned = {id: all_owned}
	m._ensure_collections()
	_chk("never counts past the end of the set", m._collection_owned_count(c) == n,
		"%d of %d" % [m._collection_owned_count(c), n])
	_chk("and still reads as complete", m._collection_complete(c))

	# And a genuinely unfinished set is still unfinished -- the bound must not
	# have turned the test into "always true".
	var missing_one := []
	for i in n:
		missing_one.append(i != 0)
	m.col_owned = {id: missing_one}
	m._ensure_collections()
	_chk("but an unfinished set is still unfinished", not m._collection_complete(c))
	_reset()
