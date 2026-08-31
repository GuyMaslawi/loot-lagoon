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

# Platforms that are expected to have a real store behind them. A build for one
# of these with no store plugin loaded is a broken build, not a sandbox, and
# simulated() turns on that distinction.
const STORE_PLATFORMS := ["iOS", "Android"]

func _expects_store() -> bool:
	return OS.get_name() in STORE_PLATFORMS

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
# Android's. Never both: a build has one store or none.
var _billing: Node = null
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
	if Engine.has_singleton("IOSInAppPurchase"):
		_store = Engine.get_singleton("IOSInAppPurchase")
		# Connect before the first request, or a response that arrives
		# immediately is lost. The plugin does not buffer.
		_store.response.connect(_on_response)
		# Picks up transactions completed outside the app -- an Ask to Buy
		# approval coming through hours later, a purchase finished in the App
		# Store app.
		_store.request("startUpdateTask", {})
		_store.request("products", {"productIDs": all_product_ids()})
	elif Engine.has_singleton(PLAY_SINGLETON):
		_start_play()

# Whether there is a real store of any kind behind this build. Asked instead of
# `_store == null` everywhere that used to mean "is there a store", so that
# adding Android did not leave a trail of Apple-shaped null checks that quietly
# answer "no store" on a phone that has one.
func _has_store() -> bool:
	return _store != null or _billing != null

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
# A device with the plugin present is never simulated. Neither is one that
# merely *should* have had it. On iOS those were the same sentence, because iOS
# was the only platform that shipped; Android made them different. A build whose
# billing plugin is missing, switched off in the export preset, or broken at
# runtime reports no store in exactly the way the editor does -- and under the
# old line that made every Pay button in the shop grant its pack after a 0.7s
# pretend delay, for free, with "no real charge" printed underneath. That is the
# airplane-mode giveaway again, except permanent, and on a public store.
#
# So the question is not "did a plugin load" but "is this a build that is
# supposed to have a store behind it". A phone is never simulated. Whether it
# can be sold from is a separate question -- see sellable().
func simulated() -> bool:
	return not _has_store() and not _expects_store()

# Whether a purchase can actually be attempted. A real device that has not heard
# back from the store has one, but not one with prices, and the only honest
# answers are to wait or to say so. Granting is not on the list -- and neither
# is it for a phone whose plugin never loaded, which will never answer at all.
func sellable() -> bool:
	return simulated() or live

# What to call the shop when talking to the player. An error that names the
# wrong company reads as a bug even when the rest of the sentence is true.
func _store_label() -> String:
	match OS.get_name():
		"Android": return "Google Play"
		"iOS", "macOS": return "the App Store"
		_: return "the store"

func purchase(pack: Dictionary) -> void:
	if busy:
		return
	var pid := product_id(pack)
	if not sellable():
		if not _has_store():
			# A platform that is supposed to have a store, with nothing behind
			# it. Nothing will ever answer, so there is no "try again" to offer
			# -- and refusing is the entire point, because what this replaced
			# was handing the pack over for nothing.
			_emit("fail", pid, "The shop is unavailable in this build.")
			return
		# Real store, no product data. Ask again -- the usual cause is a launch
		# with no network, and by now there may be one -- and tell the player to
		# try in a moment rather than handing them the pack.
		_request_products()
		_emit("fail", pid, "Can't reach %s yet. Try again in a moment." % _store_label())
		return
	busy = true
	_pending = pid
	_pending_txn = ""
	if simulated():
		_simulate(pid)
		return
	_arm_watchdog(pid)
	if _billing != null:
		_launch_play_purchase(pid)
		return
	if int(_store.request("purchase", {"productID": pid})) != 0:
		_fail(pid, "Could not reach %s." % _store_label())

func _arm_watchdog(pid: String) -> void:
	var t := get_tree().create_timer(PURCHASE_TIMEOUT, true, false, true)
	_watchdog = t
	t.timeout.connect(func() -> void:
		if _watchdog != t or not busy or _pending != pid:
			return
		_watchdog = null
		_fail(pid, "No answer from %s. If you were charged, the purchase will arrive shortly." % _store_label())
	)

func _disarm_watchdog() -> void:
	_watchdog = null

# Consumables are never "restored" -- spins already spent are gone -- but this
# asks Apple to re-send anything it thinks is outstanding, which is the honest
# answer to a player who believes a purchase went missing.
func restore() -> void:
	if _store != null:
		_store.request("appStoreSync", {})
	elif _billing != null:
		# On Play this is not a courtesy -- it is the actual recovery path. Any
		# purchase the player paid for and was not handed is still unconsumed,
		# and this is the call that hands it back.
		_billing.query_purchases(0)

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
	elif _billing != null:
		_billing.query_purchases(0)

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
	# A grant we cannot write down is a grant we will make again next launch.
	if _ledger_unwritable:
		push_warning("IAP: ledger unwritable; skipping reconcile this launch.")
		return
	if not _has_ledger:
		var n := 0
		for t in rows:
			if typeof(t) == TYPE_DICTIONARY:
				_granted[String(t.get("id", ""))] = true
				n += 1
		_granted[BASELINE_COUNT] = n
		_has_ledger = true
		_ledger_unverified = false
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
	# A ledger that says it was baselined but names nothing cannot prove which
	# of these have been handed over already. One is the honest case -- a first
	# purchase lost to a kill mid-grant, on a build before the baseline count
	# existed. The rest of Apple's history is not.
	if _ledger_unverified and _outstanding.size() > RECONCILE_UNVERIFIED_MAX:
		push_warning("IAP: ledger records no baseline; granting %d of %d outstanding."
				% [RECONCILE_UNVERIFIED_MAX, _outstanding.size()])
		_outstanding = _outstanding.slice(0, RECONCILE_UNVERIFIED_MAX)
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
	var txn := _pending_txn
	_granted[txn] = true
	_pending_txn = ""
	_save_ledger()
	# Play only, and the order matters. Consuming is what tells Google we have
	# handed the pack over; until it lands the purchase stays owned, which is
	# precisely the crash-safety net Apple does not give us. So it happens
	# *after* the ledger is on disk and never before -- consume first and die,
	# and the purchase is gone from both sides at once.
	if _billing != null:
		_billing.consume_purchase(txn)
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
# How many transactions Apple listed at the moment the baseline was taken. Its
# presence is what tells a real baseline from a hand-written one -- see
# _load_ledger. Its value is only ever read by a human reading the file.
const BASELINE_COUNT := "__baseline_n"

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
		# Truncating to `{}` was closed. Writing the sentinel and nothing else
		# was not: `{"__baselined": true}` satisfies the line above while
		# recording no transactions at all, so _reconcile takes the *else*
		# branch, finds Apple's entire history outstanding, and hands it over --
		# every pack the Apple ID ever bought, on every launch.
		#
		# The shape is recognisable because a real baseline now writes down how
		# many transactions it saw. What it is NOT is proof of tampering: a
		# genuine ledger from a build before this key, on a device whose very
		# first purchase died between Apple charging the card and finish()
		# returning, has exactly this shape too, and that player is owed a pack.
		#
		# So it is not refused, it is rationed -- see RECONCILE_UNVERIFIED_MAX.
		# One outstanding transaction is the honest recovery case; a hundred is
		# somebody reading this comment.
		_ledger_unverified = (not _granted.has(BASELINE_COUNT)) and _txn_count() == 0
		return
	# Every copy on disk failed to parse. Say so rather than looking fresh.
	_ledger_unreadable = found

# True when the ledger on disk could not be written. Nothing that has already
# been paid for is blocked by this -- a purchase in flight still completes and
# still grants, because the player's money has already moved. What it blocks is
# the *reconcile* path, which hands over history on the strength of the ledger
# not mentioning it.
#
# That distinction is the whole point. A grant we cannot record is a grant we
# will make again on the next launch, and again after that: the same file that
# refuses to be written is the file _reconcile reads to decide what is still
# owed. Making user://iap_granted.json.tmp a *directory* turned a one-off edit
# into an unlimited standing order, because every _save_ledger after it returned
# silently and nothing was ever written down.
var _ledger_unwritable := false

# Set when a ledger claims to be baselined but records nothing -- see
# _load_ledger. Not a refusal, a ration.
var _ledger_unverified := false
const RECONCILE_UNVERIFIED_MAX := 1

# How many real transaction ids the ledger holds, ignoring the bookkeeping keys.
func _txn_count() -> int:
	var n := 0
	for k in _granted.keys():
		if str(k) != BASELINE_KEY and str(k) != BASELINE_COUNT:
			n += 1
	return n

func _save_ledger() -> void:
	_granted[BASELINE_KEY] = true
	# Same discipline as the save file, for the same reason: a half-written
	# ledger is indistinguishable from no ledger, and _reconcile answers "no
	# ledger" by writing off every outstanding purchase. Scratch file first,
	# rename over the real one only once it is closed and whole.
	# A leftover of the wrong kind -- a directory where the scratch file goes --
	# makes every open() below fail forever. Clearing it first turns a permanent
	# condition into a transient one.
	var d := DirAccess.open("user://")
	if d != null and not FileAccess.file_exists(LEDGER_TMP):
		d.remove(LEDGER_TMP)
	var f := FileAccess.open(LEDGER_TMP, FileAccess.WRITE)
	if f == null:
		_ledger_write_failed("could not open the scratch file")
		return
	f.store_string(JSON.stringify(_granted))
	f.close()
	if FileAccess.get_open_error() != OK:
		_ledger_write_failed("the write did not complete")
		return
	if d == null:
		_ledger_write_failed("user:// could not be opened")
		return
	if FileAccess.file_exists(LEDGER):
		d.remove(LEDGER_BAK)
		d.rename(LEDGER, LEDGER_BAK)
	if d.rename(LEDGER_TMP, LEDGER) != OK:
		if FileAccess.file_exists(LEDGER_BAK):
			d.rename(LEDGER_BAK, LEDGER)
		_ledger_write_failed("the rename did not land")
		return
	_ledger_unwritable = false

func _ledger_write_failed(why: String) -> void:
	_ledger_unwritable = true
	push_warning("IAP: ledger not written (%s); reconcile is off this launch." % why)


# --- Google Play -----------------------------------------------------------
#
# The same three jobs the StoreKit section does -- prices, one purchase, and
# whatever the store still owes this player -- against an API that disagrees
# with Apple's about nearly every detail.
#
# THE INVERSION, and it is the one thing to get right here. On Apple a
# consumable stays in Transaction.all for ever, so the launch reconcile *must*
# take a baseline on a fresh install or it re-gifts every purchase the Apple ID
# ever made. On Play the opposite holds: queryPurchases returns only what has
# not been **consumed**, and consuming is something this app does by hand, in
# finish(), after the pack is granted and the save is written. So every row Play
# hands back is a live debt, and the baseline branch that protects the iOS path
# would here quietly write off real money. Nothing below reaches it. If a future
# change makes these two paths share a reconcile, this is the comment that was
# ignored.
#
# The inversion is also a gift. It hands Android the crash-safety net iOS lacks:
# die between Google taking the money and _save_game() returning, and the
# purchase is still unconsumed, so the next launch is simply handed it again.
#
# THE PLUGIN: godot-sdk-integrations/godot-google-play-billing 3.3.0, the
# first-party one, on Billing Library 9.1.0. The version is not incidental --
# Play rejects new apps built against Billing Library 7 or older from
# 2026-08-31. The addon is vendored at addons/GodotGooglePlayBilling/ and needs
# gradle_build/use_gradle_build=true, which ship_android.sh refuses to build
# without.

const PLAY_SINGLETON := "GodotGooglePlayBilling"
const PLAY_INAPP := 0          # BillingClient.ProductType.INAPP

const PLAY_OK := 0
const PLAY_USER_CANCELED := 1
const PLAY_ITEM_ALREADY_OWNED := 7

const PLAY_STATE_PURCHASED := 1
const PLAY_STATE_PENDING := 2

# Loaded by path rather than by its class_name, deliberately. A `BillingClient`
# written into this file is a hard compile-time dependency: iap.gd would then
# refuse to parse anywhere the addon is absent or fails to parse itself, and
# "anywhere" includes the iOS build, where this file is the money path. By path
# and behind the singleton check, the worst case on any non-Android build is a
# null that the guard below already handles.
const PLAY_CLIENT := "res://addons/GodotGooglePlayBilling/BillingClient.gd"

func _start_play() -> void:
	var client_script := load(PLAY_CLIENT) as GDScript
	if client_script == null:
		push_warning("IAP: Play billing singleton is present but %s is missing." % PLAY_CLIENT)
		return
	_billing = client_script.new()
	add_child(_billing)
	_billing.connected.connect(_on_play_connected)
	_billing.connect_error.connect(_on_play_connect_error)
	_billing.query_product_details_response.connect(_on_play_products)
	_billing.on_purchase_updated.connect(_on_play_purchase_updated)
	_billing.query_purchases_response.connect(_on_play_purchases)
	_billing.consume_purchase_response.connect(_on_play_consumed)
	# Nothing can be asked before this lands; Play is a bound service, not a
	# library call.
	_billing.start_connection()

# Asked of whichever backend exists. The iOS path re-requests products from
# inside purchase() when it has none, and that line had to stop naming Apple.
func _request_products() -> void:
	if _store != null:
		_store.request("products", {"productIDs": all_product_ids()})
	elif _billing != null:
		_billing.query_product_details(PackedStringArray(all_product_ids()), PLAY_INAPP)

func _on_play_connected() -> void:
	_request_products()
	# Everything Play still considers owned: purchases from a previous launch
	# that were never consumed, and anything that completed while the app was
	# closed. This is the reconcile, and it needs no baseline -- see the note
	# at the top of this section.
	_billing.query_purchases(PLAY_INAPP)

func _on_play_connect_error(response_code: int, debug_message: String) -> void:
	# `live` stays false, so sellable() refuses and the shop says so. Not fatal
	# and not silent: the usual causes are a device with no Play Store and a
	# build Play has never seen, and both are worth finding in a device log.
	push_warning("IAP: Play billing would not connect (%d): %s" % [response_code, debug_message])

func _launch_play_purchase(pid: String) -> void:
	var result: Dictionary = _billing.purchase(pid)
	var code := int(result.get("response_code", PLAY_OK))
	if code == PLAY_OK:
		return
	if code == PLAY_ITEM_ALREADY_OWNED:
		# A previous purchase of this product was never consumed -- almost
		# always one we granted and failed to close out. Play will not sell it
		# twice, and it is right not to. Ask for what is owned instead: the
		# query hands it back, the ledger decides whether it still needs
		# granting, and either way it gets consumed and the product is buyable
		# again.
		_billing.query_purchases(PLAY_INAPP)
		_fail(pid, "You already own that. Restoring it now -- try again in a moment.")
		return
	_fail(pid, "Could not reach %s." % _store_label())

func _on_play_products(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != PLAY_OK:
		return
	for item in response.get("product_details", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var pid := String(item.get("product_id", ""))
		# Billing Library 9 made this a list -- a product can carry several
		# one-time offers. We sell exactly one price per product, so the first
		# is the price, and an empty list means Play knows the id but has no
		# purchasable offer attached to it yet.
		var offers: Array = item.get("one_time_purchase_offer_details_list", [])
		if pid == "" or offers.is_empty() or typeof(offers[0]) != TYPE_DICTIONARY:
			continue
		_prices[pid] = String(offers[0].get("formatted_price", ""))
	# Deliberately the same liveness test the iOS path uses, and for the same
	# reason: at least one price we could actually print, not merely at least
	# one key. A dictionary of empty strings means we are reading the response
	# wrongly, and calling that "live" puts PAY with a blank price on every
	# button in the shop.
	live = false
	for v in _prices.values():
		if String(v) != "":
			live = true
			break
	if live:
		_emit("prices", "", "")

func _on_play_purchase_updated(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code == PLAY_USER_CANCELED:
		# Backing out of Play's sheet. A decision, not a fault -- same handling
		# as StoreKit's userCancelled, and for the same reason.
		var pid := _pending
		busy = false
		_pending = ""
		_pending_txn = ""
		_disarm_watchdog()
		_emit("cancel", pid, "")
		return
	if code != PLAY_OK:
		_fail(_pending, String(response.get("debug_message", "The purchase did not go through.")))
		return
	for row in response.get("purchases", []):
		if typeof(row) == TYPE_DICTIONARY:
			_take_play_purchase(row)

# The launch reconcile. Every row is a debt; there is no history here to guard
# against, so there is no baseline.
func _on_play_purchases(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != PLAY_OK:
		return
	# A response that did not carry the list is one we misread, not an empty
	# one. Same distinction the iOS reconcile draws.
	if typeof(response.get("purchases")) != TYPE_ARRAY:
		return
	for row in response.get("purchases", []):
		if typeof(row) == TYPE_DICTIONARY:
			_take_play_purchase(row)

# One purchase off Play, from whichever direction it arrived. Both the answer to
# a Pay button and the launch reconcile land here, because on Play they are
# genuinely the same object and telling them apart is this function's job.
func _take_play_purchase(row: Dictionary) -> void:
	var token := String(row.get("purchase_token", ""))
	var ids: PackedStringArray = row.get("product_ids", PackedStringArray())
	if token == "" or ids.is_empty():
		return
	var pid := String(ids[0])

	var state := int(row.get("purchase_state", 0))
	if state == PLAY_STATE_PENDING:
		# Play's deferred payment -- cash at a kiosk, a parent to approve. The
		# sale is neither made nor lost, so the store reopens and the next
		# query delivers the verdict. It has to be said out loud or the confirm
		# modal sits there with a disabled Pay button and no way to close it.
		if busy and _pending == pid:
			busy = false
			_pending = ""
			_disarm_watchdog()
			_emit("defer", pid, "")
		return
	if state != PLAY_STATE_PURCHASED:
		return

	if _granted.has(token):
		# Handed over already, on this launch or an earlier one, and simply
		# never consumed -- the ledger is what remembers. Close it out rather
		# than granting it twice; until it is consumed Play will keep offering
		# it back and the product cannot be bought again.
		_billing.consume_purchase(token)
		return

	# The answer to the Pay button the player is looking at right now.
	if busy and _pending == pid:
		busy = false
		_pending = ""
		_disarm_watchdog()
		_pending_txn = token
		_emit("ok", pid, "")
		return

	# Arrived on its own. Joins the same queue the iOS reconcile uses, and is
	# handed over one at a time because each grant ends in a popup the player
	# has to see.
	for entry in _outstanding:
		if String(entry[0]) == token:
			return
	_outstanding.append([token, pid])
	if _pending_txn == "":
		_grant_next()

func _on_play_consumed(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code == PLAY_OK:
		return
	# Not a lost purchase and not something to tell the player about: the pack
	# is granted and the ledger says so. Play will hand the purchase back on the
	# next query, the ledger will recognise it, and it will be consumed again.
	# Worth a device log, because the state it leaves behind -- an owned,
	# unconsumed product -- is what makes the next buy return ITEM_ALREADY_OWNED.
	push_warning("IAP: Play refused to consume (%d): %s" % [code, String(response.get("debug_message", ""))])
