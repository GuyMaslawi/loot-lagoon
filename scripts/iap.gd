# Real-money purchases.
#
# One object owns a transaction from tap to grant, whether or not there is an
# App Store on the other end. Everywhere else asks IAP to sell something and
# then waits for a signal; nothing grants a pack straight off a button press
# any more.
#
# That shape is the point. A real purchase is asynchronous, the player can
# cancel it after tapping Pay, it can fail on Apple's side, and it can come
# back minutes later on a different launch. Code written against a function
# that grants instantly has nowhere to put any of those cases, so the store
# has to be built this way from the start rather than retrofitted once the
# paperwork clears.
#
# With no plugin present -- the editor, the desktop build, the simulator -- it
# runs in simulation and grants after a short delay, exactly as the prototype
# store always did. The plugin only exists on a real device.
#
# THE PLUGIN: hrk4649/godot_ios_plugin_iap, which wraps StoreKit 2 in Swift.
# It was chosen because it is the only one that matches all three of Godot 4.7,
# a deployment target of iOS 15, and a GDScript-native API. The official
# godot-ios-plugins has shipped nothing since 2022 and has no Godot 4 build at
# all; the two other maintained plugins both demand iOS 17.
extends Node

# product_id is Apple's, not the pack's own short id.
signal purchase_succeeded(product_id: String)
signal purchase_failed(product_id: String, message: String)
# Backing out of Apple's payment sheet is the single most common outcome of
# tapping Pay, so it gets its own signal. Routing it through purchase_failed
# would answer a deliberate choice with a red banner and an error chime.
signal purchase_cancelled(product_id: String)
# Ask to Buy: sent to a parent, answer unknown, possibly minutes away. Neither
# a success nor a failure, and the one outcome that leaves nothing on screen to
# close unless it is announced.
signal purchase_deferred(product_id: String)
# Fires once Apple has answered with real product data, so open screens can
# repaint their prices in the player's own currency.
signal products_loaded()

const PREFIX := "com.guymaslawi.lootlagoon."

# How long a simulated purchase pretends to talk to Apple. Long enough that the
# spinner is visible and the flow gets exercised, short enough not to annoy.
const SIM_DELAY := 0.7

# Which transactions have already been granted and written to the save.
#
# This file is the whole reason the money cannot go missing -- see the comment
# on _reconcile() for why StoreKit alone is not enough here.
const LEDGER := "user://iap_granted.json"

# True once the store has answered with real products. Until then every price
# on screen is the hardcoded USD string from cv.gd.
var live := false
# One purchase at a time. Apple will happily queue a second, but a store where
# two Pay buttons are in flight has no honest way to report which one failed.
var busy := false

# How long a live purchase may go unanswered before the store reopens itself.
#
# `busy` is only ever cleared by a response, so a request the plugin never
# answers -- a StoreKit error it does not map, the app losing the network
# mid-sheet, a plugin bug -- wedges the store shut for the rest of the session:
# every Pay button in the game silently does nothing and the player has to be
# told to restart the app. Giving up here is safe because it does not cancel
# anything: if Apple does charge, startUpdateTask and the ledger reconcile
# deliver the pack on this launch or the next one.
const PURCHASE_TIMEOUT := 180.0
var _watchdog: SceneTreeTimer = null

var _store: Object = null
var _prices := {}      # product_id -> Apple's localized price string
var _pending := ""
# The transaction id of the purchase currently being granted. finish() commits
# it to the ledger once the game says the save is written.
var _pending_txn := ""
# Signals stay queued until the game says it is ready for them. A purchase
# completed outside the app is replayed the moment the plugin starts, and
# emitting that while the title screen is still up would hand a granted pack to
# a game whose pages do not exist yet.
#
# products_loaded goes through the same queue, and must. Apple usually answers
# the product request within a second or two, while the title screen runs for
# longer -- so the "prices are real now, repaint" signal routinely fires before
# main.gd has connected to it, and without the queue it is simply lost.
var _started := false
var _queue: Array = []
var _granted := {}     # transaction id -> true
var _has_ledger := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_ledger()
	if not Engine.has_singleton("IOSInAppPurchase"):
		return
	_store = Engine.get_singleton("IOSInAppPurchase")
	# Connect before the first request, or a response that arrives immediately
	# is lost. The plugin does not buffer.
	_store.response.connect(_on_response)
	# Picks up transactions completed outside the app -- an Ask to Buy approval
	# coming through hours later, a purchase finished in the App Store app.
	_store.request("startUpdateTask", {})
	_store.request("products", {"productIDs": all_product_ids()})

# Every product the game can sell for money. Card boxes are deliberately absent
# -- they are bought with stars, which are earned and never sold.
static func all_product_ids() -> Array:
	var ids := [product_id(CV.STARTER_PACK), product_id(CV.PIGGY_PACK)]
	for group in [CV.CHEST_PACKS, CV.SPIN_PACKS, CV.COIN_PACKS, CV.BUNDLE_PACKS, CV.TIMED_OFFERS]:
		for pack in group:
			ids.append(product_id(pack))
	return ids

static func product_id(pack: Dictionary) -> String:
	return PREFIX + String(pack.get("id", ""))

# What to print on a Pay button. Apple's localized string wins whenever we have
# it, so a player in Israel sees ₪ and not a dollar figure they cannot act on;
# the cv.gd string is the fallback before the store has answered.
func price_for(pack: Dictionary) -> String:
	return _prices.get(product_id(pack), String(pack.get("price", "")))

# Whether the next purchase would be pretend. purchase() below asks the same
# question, and deliberately asks it through here: the dialog that promises
# "no real charge" and the code that decides whether to charge must never be
# able to disagree about which build this is.
#
# The question is only ever "is there an App Store behind this build" -- the
# editor, the desktop build, the simulator. It used to also be false whenever
# Apple had not answered with prices yet, and that was the most expensive line
# in the app: `live` is false on a real phone launched in airplane mode, or
# while the product request is still in flight, or when the products sit in
# MISSING_METADATA. In any of those states every Pay button in the shop granted
# its pack after a 0.7s pretend delay, for free, with "no real charge" printed
# under it. Launch with the network off and the whole store was a giveaway.
#
# A device with the plugin present is now never simulated. Whether it can be
# sold from is a separate question -- see sellable().
func simulated() -> bool:
	return _store == null

# Whether a purchase can actually be attempted. A real device that has not
# heard back from Apple has a store, but not one with prices, and the only
# honest answers are to wait or to say so. Granting is not on the list.
func sellable() -> bool:
	return _store == null or live

func purchase(pack: Dictionary) -> void:
	if busy:
		return
	var pid := product_id(pack)
	if not sellable():
		# Real StoreKit, no product data. Ask again -- the usual cause is a
		# launch with no network, and by now there may be one -- and tell the
		# player to try in a moment rather than handing them the pack.
		_store.request("products", {"productIDs": all_product_ids()})
		_emit("fail", pid, "The App Store isn't reachable yet. Try again in a moment.")
		return
	busy = true
	_pending = pid
	_pending_txn = ""
	if simulated():
		_simulate(pid)
		return
	_arm_watchdog(pid)
	if int(_store.request("purchase", {"productID": pid})) != 0:
		_fail(pid, "Could not reach the App Store.")

func _arm_watchdog(pid: String) -> void:
	var t := get_tree().create_timer(PURCHASE_TIMEOUT, true, false, true)
	_watchdog = t
	t.timeout.connect(func() -> void:
		if _watchdog != t or not busy or _pending != pid:
			return
		_watchdog = null
		_fail(pid, "The App Store did not answer. If you were charged, the purchase will arrive shortly.")
	)

func _disarm_watchdog() -> void:
	_watchdog = null

# Consumables are never "restored" -- spins already spent are gone -- but this
# asks Apple to re-send anything it thinks is outstanding, which is the honest
# answer to a player who believes a purchase went missing.
func restore() -> void:
	if _store != null:
		_store.request("appStoreSync", {})

func _simulate(pid: String) -> void:
	var t := get_tree().create_timer(SIM_DELAY)
	t.timeout.connect(func() -> void:
		busy = false
		_pending = ""
		_emit("ok", pid, "")
	)

func _fail(pid: String, message: String) -> void:
	busy = false
	_pending = ""
	_pending_txn = ""
	_disarm_watchdog()
	_emit("fail", pid, message)

# The game is tearing its scene down and building a new one. Until that new one
# says begin(), there is nobody connected to these signals, and _emit would
# dispatch straight into the void -- so go back to queueing.
func rearm() -> void:
	_started = false

# Called once the game is built and listening. Nothing is emitted before this.
func begin() -> void:
	if _started:
		return
	_started = true
	for item in _queue:
		_dispatch(item[0], item[1], item[2])
	_queue.clear()
	if _store != null:
		_store.request("transactionAll", {})

func _emit(kind: String, pid: String, message: String) -> void:
	if not _started:
		_queue.append([kind, pid, message])
		return
	_dispatch(kind, pid, message)

func _dispatch(kind: String, pid: String, message: String) -> void:
	match kind:
		"ok": purchase_succeeded.emit(pid)
		"cancel": purchase_cancelled.emit(pid)
		"defer": purchase_deferred.emit(pid)
		"prices": products_loaded.emit()
		_: purchase_failed.emit(pid, message)

# --- the plugin ------------------------------------------------------------

# Every field is read defensively. An event we do not recognise must not strand
# `busy` at true -- that would wedge the store shut for the rest of the session.
func _on_response(response_name: String, data: Dictionary) -> void:
	match response_name:
		"products": _on_products(data)
		"purchase": _on_purchase(data)
		# The whole point of startUpdateTask. Transaction.updates delivers
		# purchases that belong to no Pay button on this screen -- an Ask to Buy
		# a parent approved an hour ago, a purchase finished in the App Store
		# app -- and they used to fall straight through this match and vanish,
		# recoverable only by the next launch's reconcile, if at all.
		"updateTask": _on_external(data)
		"transactionAll": _reconcile(data)
		_:
			# Never silently. An unrecognised name here is money moving with
			# nobody listening, and it is the one thing that must show up in a
			# device log rather than being inferred from a player complaint.
			push_warning("IAP: unhandled store response '%s'" % response_name)

func _on_products(data: Dictionary) -> void:
	if String(data.get("result", "")) != "success":
		return
	var items: Array = data.get("products", [])
	for p in items:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pid := String(p.get("id", ""))
		if pid != "":
			_prices[pid] = String(p.get("displayPrice", ""))
	# At least one price we could actually print, not merely at least one key.
	# A dictionary full of empty strings means the response came back in a
	# shape we do not read correctly, and calling that "live" puts "PAY" with a
	# blank price on every button in the shop.
	live = false
	for v in _prices.values():
		if String(v) != "":
			live = true
			break
	if live:
		_emit("prices", "", "")

func _on_purchase(data: Dictionary) -> void:
	var pid := String(data.get("productID", _pending))
	_disarm_watchdog()
	match String(data.get("result", "")):
		"success":
			busy = false
			_pending = ""
			var tid := _transaction_id(data)
			# The same sale can arrive twice: once as the answer to this Pay
			# button and again through Transaction.updates, which replays what
			# was just bought alongside what came from elsewhere. The ledger is
			# the only thing that can tell the copy from the original, and
			# without this check the second one grants the pack a second time.
			if tid != "" and _granted.has(tid):
				return
			_pending_txn = tid
			_emit("ok", pid, "")
		"userCancelled":
			busy = false
			_pending = ""
			_pending_txn = ""
			_emit("cancel", pid, "")
		"pending":
			# Ask to Buy, awaiting a parent. The sale is neither made nor lost,
			# so the store reopens and startUpdateTask delivers the verdict.
			#
			# It still has to be said out loud. This used to emit nothing, which
			# left the confirm modal up with a disabled Pay button reading "…"
			# and no way to close it -- a child staring at a spinner for a
			# purchase that had already left for a parent's phone.
			busy = false
			_pending = ""
			_emit("defer", pid, "")
		"revoked":
			# Apple refunded this one. Nothing is clawed back -- consumables
			# that have been spent are gone, and the genre does not chase them;
			# what the big titles reserve is the right to close an account, and
			# there are no accounts here to close.
			#
			# The message is only for a purchase this device was actually given.
			# A revocation can arrive for a transaction that was never granted
			# -- refunded before it was ever delivered, or belonging to a build
			# that had no such pack -- and telling that player "your purchase
			# was refunded" is news about a purchase they never received.
			var rtid := _transaction_id(data)
			# Asked before it is recorded: the ledger is what remembers that
			# this transaction was ever handed over, and the line below is
			# about to write to it.
			var was_granted := rtid != "" and _granted.has(rtid)
			if rtid != "":
				_granted[rtid] = true   # so reconcile stops offering it back
				_save_ledger()
			if was_granted:
				_fail(pid, "That purchase was refunded.")
			else:
				busy = false
				_pending = ""
				_pending_txn = ""
				_disarm_watchdog()
		"unverified":
			_fail(pid, "Apple could not verify that purchase.")
		_:
			_fail(pid, String(data.get("error", "The purchase did not go through.")))

# A transaction that arrived on its own, from Transaction.updates rather than
# from a Pay button: an Ask to Buy a parent approved after the sheet closed, a
# purchase completed in the App Store app, anything StoreKit decides to replay.
#
# It deliberately does not touch `busy`, `_pending` or the watchdog. Those
# belong to whatever purchase the player may be in the middle of making right
# now, and an unrelated delivery tearing them down would report someone else's
# transaction as the answer to the sheet still on screen. It joins the same
# outstanding queue the launch reconcile uses and is handed over when the
# grant path is free.
func _on_external(data: Dictionary) -> void:
	if String(data.get("result", "")) != "success":
		return
	var pid := String(data.get("productID", ""))
	var tid := _transaction_id(data)
	if pid == "" or tid == "" or _granted.has(tid):
		return
	for entry in _outstanding:
		if String(entry[0]) == tid:
			return
	_outstanding.append([tid, pid])
	# Only start it if nothing is already being granted; finish() drains the
	# rest. Two grants in flight would mean two popups fighting for the screen.
	if _pending_txn == "":
		_grant_next()

# The purchase response carries Apple's own transaction JSON; the id lives in
# there rather than in a field of its own.
func _transaction_id(data: Dictionary) -> String:
	var raw := String(data.get("json", ""))
	if raw == "":
		return ""
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	return String(parsed.get("transactionId", ""))

# --- not losing the money --------------------------------------------------

# The plugin calls transaction.finish() itself, the instant StoreKit verifies
# the purchase and *before* the game is told anything. So by the time this
# object hears about a sale, Apple already considers it closed, and the usual
# safety net -- replaying unfinished transactions on the next launch -- is
# empty by construction. Kill the app in the sliver between Apple charging the
# card and _save_game() returning, and the player has paid for nothing that
# anyone will ever hand them.
#
# Apple keeps consumables in the transaction history even after they are
# finished, so the hole can be closed from the other side: remember which
# transactions were granted, and on every launch grant anything Apple lists
# that the ledger does not.
#
# The first run only takes a baseline. Transaction.all reaches back over every
# purchase the Apple ID ever made in this app, so granting on a fresh install
# would re-gift years of spin packs to anyone who reinstalls -- which is also
# exactly what consumables are not supposed to do.
func _reconcile(data: Dictionary) -> void:
	# A ledger we could not read means we do not know what has been granted.
	# Baselining would write off real debts and granting would pay them twice,
	# so this launch does neither.
	if _ledger_unreadable:
		push_warning("IAP: ledger unreadable; skipping reconcile this launch.")
		return
	# Only a response that actually carried the list. An empty array is a real
	# answer ("nothing outstanding"); a missing key is a response we misread,
	# and baselining off one would mark the whole history granted on the
	# strength of a payload we never saw.
	if typeof(data.get("transactions")) != TYPE_ARRAY:
		return
	var rows: Array = data.get("transactions", [])
	if not _has_ledger:
		for t in rows:
			if typeof(t) == TYPE_DICTIONARY:
				_granted[String(t.get("id", ""))] = true
		_has_ledger = true
		_save_ledger()
		return
	_outstanding.clear()
	for t in rows:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var tid := String(t.get("id", ""))
		var pid := String(t.get("productID", ""))
		if tid == "" or pid == "" or _granted.has(tid):
			continue
		if t.has("revocationDate"):
			_granted[tid] = true   # refunded; record it so it stops coming back
			continue
		_outstanding.append([tid, pid])
	if not _outstanding.is_empty():
		_save_ledger()   # the revocations recorded above
		_grant_next()

# Backlog from _reconcile, granted one at a time because each grant ends in a
# popup the player has to see. finish() pulls the next one.
#
# They used to be dropped after the first, on the theory that "the next launch
# picks up any others" -- but a player with three outstanding transactions
# (an Ask to Buy batch approved at once, a run of kills mid-grant) then had to
# relaunch the game three times to be given what they had already paid for,
# with nothing on screen saying so.
var _outstanding: Array = []

func _grant_next() -> void:
	while not _outstanding.is_empty():
		var entry: Array = _outstanding.pop_front()
		var tid := String(entry[0])
		if _granted.has(tid):
			continue
		# Grant it through the ordinary path, which ends in finish() writing
		# this same id to the ledger.
		_pending_txn = tid
		_emit("ok", String(entry[1]), "")
		return

# Called once the pack has been granted and the save written. The plugin has
# already closed the transaction with Apple, so nothing is sent anywhere -- what
# this records is that our side of the bargain is now on disk.
func finish(_product_id_str: String) -> void:
	if _pending_txn == "":
		return
	_granted[_pending_txn] = true
	_pending_txn = ""
	_save_ledger()
	# Whatever else Apple still owes this player, handed over now rather than on
	# some future launch. Deferred, not called: this runs inside the grant it
	# is finishing (finish() is called from _on_purchase_ok, which _grant_next
	# itself set going), so calling directly would nest one whole grant --
	# confetti, popup and all -- inside the previous one, as deep as the
	# backlog is long.
	if not _outstanding.is_empty():
		_grant_next.call_deferred()

# Set when a ledger file is on disk but could not be read. That is not the same
# thing as a fresh install, and treating it as one is how a player loses a
# purchase: _reconcile would take a baseline, mark everything Apple has ever
# charged for as already handed over, and quietly write off whatever was
# genuinely still owed. When the ledger is unreadable the right move is to do
# nothing at all this launch and keep the file for the next one.
var _ledger_unreadable := false

# A ledger's keys are Apple transaction ids, so a reserved key can live among
# them. Its presence is what distinguishes "this install has taken its baseline
# and has simply granted nothing since" from "there is no ledger here".
const LEDGER_BAK := "user://iap_granted.json.bak"
const LEDGER_TMP := "user://iap_granted.json.tmp"
const BASELINE_KEY := "__baselined"

func _load_ledger() -> void:
	var found := false
	for path in [LEDGER, LEDGER_BAK]:
		if not FileAccess.file_exists(path):
			continue
		found = true
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_granted = parsed
		# A dictionary that is merely empty does not count as a baseline. An
		# empty ledger used to be the most valuable file on the device: it sent
		# _reconcile straight past the baseline branch and into the grant loop,
		# where Transaction.all -- every purchase this Apple ID has ever made in
		# this app -- was handed over again, one per launch, for as long as the
		# player kept truncating the file. Non-empty is grandfathered so that
		# ledgers written before this key existed still read as baselined.
		_has_ledger = _granted.has(BASELINE_KEY) or not _granted.is_empty()
		return
	# Every copy on disk failed to parse. Say so rather than looking fresh.
	_ledger_unreadable = found

func _save_ledger() -> void:
	_granted[BASELINE_KEY] = true
	# Same discipline as the save file, for the same reason: a half-written
	# ledger is indistinguishable from no ledger, and _reconcile answers "no
	# ledger" by writing off every outstanding purchase. Scratch file first,
	# rename over the real one only once it is closed and whole.
	var f := FileAccess.open(LEDGER_TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_granted))
	f.close()
	if FileAccess.get_open_error() != OK:
		return
	var d := DirAccess.open("user://")
	if d == null:
		return
	if FileAccess.file_exists(LEDGER):
		d.remove(LEDGER_BAK)
		d.rename(LEDGER, LEDGER_BAK)
	if d.rename(LEDGER_TMP, LEDGER) != OK and FileAccess.file_exists(LEDGER_BAK):
		d.rename(LEDGER_BAK, LEDGER)
