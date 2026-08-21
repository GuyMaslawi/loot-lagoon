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

func purchase(pack: Dictionary) -> void:
	if busy:
		return
	var pid := product_id(pack)
	busy = true
	_pending = pid
	_pending_txn = ""
	if _store == null or not live:
		_simulate(pid)
		return
	if int(_store.request("purchase", {"productID": pid})) != 0:
		_fail(pid, "Could not reach the App Store.")

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
	_emit("fail", pid, message)

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
		_: purchase_failed.emit(pid, message)

# --- the plugin ------------------------------------------------------------

# Every field is read defensively. An event we do not recognise must not strand
# `busy` at true -- that would wedge the store shut for the rest of the session.
func _on_response(response_name: String, data: Dictionary) -> void:
	match response_name:
		"products": _on_products(data)
		"purchase": _on_purchase(data)
		"transactionAll": _reconcile(data)

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
	live = not _prices.is_empty()
	if live:
		products_loaded.emit()

func _on_purchase(data: Dictionary) -> void:
	var pid := String(data.get("productID", _pending))
	match String(data.get("result", "")):
		"success":
			busy = false
			_pending = ""
			_pending_txn = _transaction_id(data)
			_emit("ok", pid, "")
		"userCancelled":
			busy = false
			_pending = ""
			_pending_txn = ""
			_emit("cancel", pid, "")
		"pending":
			# Ask to Buy, awaiting a parent. The sale is neither made nor lost,
			# so the store reopens and startUpdateTask delivers the verdict.
			busy = false
			_pending = ""
		"revoked":
			_fail(pid, "That purchase was refunded.")
		"unverified":
			_fail(pid, "Apple could not verify that purchase.")
		_:
			_fail(pid, String(data.get("error", "The purchase did not go through.")))

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
	var rows: Array = data.get("transactions", [])
	if not _has_ledger:
		for t in rows:
			if typeof(t) == TYPE_DICTIONARY:
				_granted[String(t.get("id", ""))] = true
		_has_ledger = true
		_save_ledger()
		return
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
		# Grant it through the ordinary path, which ends in finish() writing
		# this same id to the ledger.
		_pending_txn = tid
		_emit("ok", pid, "")
		return   # one at a time; the next launch picks up any others

# Called once the pack has been granted and the save written. The plugin has
# already closed the transaction with Apple, so nothing is sent anywhere -- what
# this records is that our side of the bargain is now on disk.
func finish(_product_id_str: String) -> void:
	if _pending_txn == "":
		return
	_granted[_pending_txn] = true
	_pending_txn = ""
	_save_ledger()

func _load_ledger() -> void:
	if not FileAccess.file_exists(LEDGER):
		return
	var f := FileAccess.open(LEDGER, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_granted = parsed
	_has_ledger = true

func _save_ledger() -> void:
	var f := FileAccess.open(LEDGER, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_granted))
	f.close()
