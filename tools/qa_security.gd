extends Node
# Temporary QA harness -- the 2026-08-31 red-team findings, as regressions.
# Not shipped.
#
# Every check below is an exploit that worked. They are here rather than in
# qa_full because they are not about the game being right; they are about the
# game refusing something a player will try.

var fails := 0

func _ready() -> void:
	_t_ledger_sentinel_replay()
	_t_ledger_unwritable_stops_reconcile()
	_t_ledger_real_baseline_still_works()
	await _t_raid_applied_once()
	_t_trusted_clock_falls_back()
	_t_play_signature()
	print("QA-SECURITY: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _chk(name: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1

func _wipe_ledger() -> void:
	var d := DirAccess.open("user://")
	for p in [IAP.LEDGER, IAP.LEDGER_BAK, IAP.LEDGER_TMP]:
		if FileAccess.file_exists(p):
			d.remove(p)
	d.remove(IAP.LEDGER_TMP)   # in case a previous run left a directory

func _reset_iap() -> void:
	IAP._granted = {}
	IAP._has_ledger = false
	IAP._ledger_unreadable = false
	IAP._ledger_unwritable = false
	IAP._ledger_unverified = false
	IAP._pending_txn = ""
	IAP._outstanding.clear()

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

# Apple's Transaction.all, as _reconcile reads it.
func _history(n: int) -> Dictionary:
	var rows := []
	for i in n:
		rows.append({"id": "txn-%d" % i, "productID": "com.guymaslawi.lootlagoon.spins_s"})
	return {"transactions": rows}

func _granted_count() -> int:
	var got := 0
	IAP.purchase_succeeded.connect(func(_p: String) -> void: got += 1)
	return got

# --- the ledger that claims a baseline and records nothing ------------------
#
# Truncating the ledger to `{}` was closed. `{"__baselined": true}` was not: it
# satisfied _has_ledger while naming no transactions, so _reconcile found all of
# Apple's history outstanding and handed it back. Every pack the Apple ID ever
# bought, on every launch, for one line of JSON.
func _t_ledger_sentinel_replay() -> void:
	print("ledger: a baseline that records nothing")
	_wipe_ledger()
	_write(IAP.LEDGER, '{"__baselined":true}')
	_reset_iap()
	IAP._load_ledger()
	_chk("a sentinel-only ledger is recognised as unverified", IAP._ledger_unverified)
	IAP._reconcile(_history(40))
	_chk("forty transactions do not become forty grants",
		 IAP._outstanding.size() <= IAP.RECONCILE_UNVERIFIED_MAX,
		 "outstanding=%d" % IAP._outstanding.size())
	# The honest case this ration exists to preserve: one purchase lost to a
	# kill mid-grant is still recoverable.
	_chk("but the one honest outstanding purchase is still recoverable",
		 IAP._outstanding.size() + (1 if IAP._pending_txn != "" else 0) >= 1,
		 "outstanding=%d pending=%s" % [IAP._outstanding.size(), IAP._pending_txn])

# --- a grant that cannot be written down ------------------------------------
#
# _save_ledger returned silently on failure, so making user://iap_granted.json.tmp
# a DIRECTORY turned a one-off file edit into a standing order: nothing could
# ever be recorded again, so every launch found the same history outstanding and
# granted it, for ever, with no further tampering.
#
# Two halves to the fix and both are checked here. An empty directory in the way
# is now simply cleared, because that is also what a crash mid-rename leaves and
# an honest player should not be stuck behind it. One that cannot be cleared is
# reported rather than swallowed, and a ledger that cannot be recorded stops
# reconcile: a grant we cannot write down is a grant we would make again.
func _t_ledger_unwritable_stops_reconcile() -> void:
	print("ledger: a scratch path that is in the way")
	_wipe_ledger()
	var d := DirAccess.open("user://")
	d.make_dir(IAP.LEDGER_TMP)
	_reset_iap()
	IAP._load_ledger()
	IAP._save_ledger()
	_chk("an empty directory in the scratch path is cleared, not fatal",
		 not IAP._ledger_unwritable and FileAccess.file_exists(IAP.LEDGER))

	print("ledger: a scratch path that cannot be cleared")
	_wipe_ledger()
	d.make_dir(IAP.LEDGER_TMP)
	_write(IAP.LEDGER_TMP + "/pin", "x")   # a non-empty directory will not remove
	_write(IAP.LEDGER, '{"__baselined":true,"__baseline_n":3,"txn-0":true}')
	_reset_iap()
	IAP._load_ledger()
	IAP._save_ledger()
	_chk("a ledger that will not write says so", IAP._ledger_unwritable)
	IAP._reconcile(_history(40))
	_chk("and reconcile grants nothing while it cannot record",
		 IAP._outstanding.is_empty() and IAP._pending_txn == "",
		 "outstanding=%d pending=%s" % [IAP._outstanding.size(), IAP._pending_txn])
	d.remove(IAP.LEDGER_TMP + "/pin")
	d.remove(IAP.LEDGER_TMP)

# --- and none of that broke the ordinary path -------------------------------
func _t_ledger_real_baseline_still_works() -> void:
	print("ledger: the ordinary path")
	_wipe_ledger()
	_reset_iap()
	IAP._load_ledger()
	_chk("a fresh install has no ledger", not IAP._has_ledger)
	# First launch takes a baseline and grants nothing.
	IAP._reconcile(_history(5))
	_chk("the first launch baselines instead of granting", IAP._outstanding.is_empty())
	_chk("and writes down how many it saw", int(IAP._granted.get(IAP.BASELINE_COUNT, -1)) == 5,
		 str(IAP._granted.get(IAP.BASELINE_COUNT, -1)))
	_chk("the ledger reached the disk", FileAccess.file_exists(IAP.LEDGER))
	_chk("and it is not unwritable", not IAP._ledger_unwritable)
	# A sixth purchase arrives later. That one IS owed.
	IAP._outstanding.clear()
	IAP._reconcile(_history(6))
	_chk("a genuinely new transaction is still granted", IAP._outstanding.size() == 1
		 or IAP._pending_txn == "txn-5",
		 "outstanding=%d pending=%s" % [IAP._outstanding.size(), IAP._pending_txn])
	# Reloading it must not read as unverified -- it names a baseline count.
	IAP._granted = {}
	IAP._ledger_unverified = false
	IAP._load_ledger()
	_chk("a real baseline reloads as verified", not IAP._ledger_unverified)
	_wipe_ledger()

# --- the same raid, twice ----------------------------------------------------
#
# unseen_raids keeps returning a raid until ack_raids marks it seen, and the ack
# is a separate request that can fail. Applying was unconditional, so a dropped
# ack cost the player the same coins again on every launch.
func _t_raid_applied_once() -> void:
	print("raids: an ack that never landed")
	var m: Control = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(3.0).timeout
	m.coins = 100000
	m.applied_raids = []
	var raid := [{"id": "raid-1", "mode": "steal", "coins": 5000}]
	m._on_cloud_raids(raid)
	var after_first: int = m.coins
	_chk("the first delivery is applied", after_first == 95000, "coins=%d" % after_first)
	# The ack did not land, so the server sends it again.
	m._on_cloud_raids(raid)
	_chk("the same raid arriving again costs nothing", m.coins == after_first,
		 "coins=%d" % m.coins)
	m._on_cloud_raids(raid)
	_chk("and again", m.coins == after_first, "coins=%d" % m.coins)
	# A different raid still lands.
	m._on_cloud_raids([{"id": "raid-2", "mode": "steal", "coins": 1000}])
	_chk("a genuinely new raid is still applied", m.coins == after_first - 1000,
		 "coins=%d" % m.coins)
	# And it survives a save/load, which is the launch the replay used to happen on.
	m._flush_save()
	var m2: Control = load("res://scripts/main.gd").new()
	add_child(m2)
	await get_tree().create_timer(3.0).timeout
	_chk("the applied list survives the launch",
		 m2.applied_raids.has("raid-1") and m2.applied_raids.has("raid-2"),
		 str(m2.applied_raids))
	m.queue_free()
	m2.queue_free()

# --- the trusted clock ------------------------------------------------------
#
# Not signed in means no anchor, and no anchor must mean the old behaviour
# exactly -- an island that never reaches the server never reaches the
# leaderboard either.
func _t_trusted_clock_falls_back() -> void:
	print("clock: the fallback when nobody is signed in")
	_chk("there is no anchor without a session", not Cloud.time_anchored())
	_chk("and server_now() has no opinion", Cloud.server_now() == 0.0)
	var m: Control = load("res://scripts/main.gd").new()
	add_child(m)
	_chk("so the trusted clock is the local one",
		 absf(m._trusted_now() - m._now()) < 1.0,
		 "%f vs %f" % [m._trusted_now(), m._now()])
	m.queue_free()

# --- a purchase that did not come from Google -------------------------------
#
# _take_play_purchase read a product id and a token out of a dictionary handed
# over by a process on the player's phone and granted the pack. Replacing that
# process is what the patched-billing tools exist to do, and it made every pack
# in the shop free. Google signs the real thing; this checks the signature.
func _t_play_signature() -> void:
	print("play: a purchase that did not come from Google")
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var payload := '{"orderId":"GPA.1","productId":"com.guymaslawi.lootlagoon.spins_s"}'
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(payload.to_utf8_buffer())
	var sig := crypto.sign(HashingContext.HASH_SHA1, ctx.finish(), key)

	# No key configured: the check does not run, and must not block a sale.
	IAP._play_key = null
	IAP._play_key_checked = true
	_chk("with no key configured a purchase is not blocked",
		 IAP._play_signature_ok({"original_json": payload,
								 "signature": Marshalls.raw_to_base64(sig)}))

	# The public half only -- exactly what the Play Console prints.
	var pub := CryptoKey.new()
	pub.load_from_string(key.save_to_string(true), true)
	IAP._play_key = pub

	_chk("a genuinely signed purchase verifies",
		 IAP._play_signature_ok({"original_json": payload,
								 "signature": Marshalls.raw_to_base64(sig)}))
	_chk("the same signature over a DIFFERENT product is refused",
		 not IAP._play_signature_ok({
			"original_json": payload.replace("spins_s", "spins_xl"),
			"signature": Marshalls.raw_to_base64(sig)}))
	_chk("a forged signature is refused",
		 not IAP._play_signature_ok({"original_json": payload,
									 "signature": Marshalls.raw_to_base64("nonsense".to_utf8_buffer())}))
	_chk("and a purchase carrying no signature at all is refused",
		 not IAP._play_signature_ok({"original_json": payload, "signature": ""}))
	IAP._play_key = null
