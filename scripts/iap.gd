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
# With no plugin present -- the editor, the simulator, any build made before
# the Paid Apps Agreement goes active -- it runs in simulation and grants after
# a short delay, exactly as the prototype store always did.
extends Node

# product_id is Apple's, not the pack's own short id.
signal purchase_succeeded(product_id: String)
signal purchase_failed(product_id: String, message: String)
# Fires once Apple has answered with real product data, so open screens can
# repaint their prices in the player's own currency.
signal products_loaded()

const PREFIX := "com.guymaslawi.lootlagoon."

# How long a simulated purchase pretends to talk to Apple. Long enough that the
# spinner is visible and the flow gets exercised, short enough not to annoy.
const SIM_DELAY := 0.7

# True once the store has answered with real products. Until then every price
# on screen is the hardcoded USD string from cv.gd.
var live := false
# One purchase at a time. Apple will happily queue a second, but a store where
# two Pay buttons are in flight has no honest way to report which one failed.
var busy := false

var _store: Object = null
var _prices := {}      # product_id -> Apple's localized price string
var _pending := ""
# Events stay in the plugin's own queue until the game says it is ready for
# them. A transaction interrupted on a previous launch is replayed the moment
# polling starts, and popping that while the title screen is still up would
# hand a granted pack to a game whose pages do not exist yet.
var _started := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton("InAppStore"):
		return
	_store = Engine.get_singleton("InAppStore")
	# Consumables must be finished by us, not by the plugin, and only after the
	# coins are actually in the save file. Letting the plugin auto-finish means
	# a crash between "Apple charged them" and "we wrote the save" loses the
	# purchase with no way to recover it.
	_store.set_auto_finish_transaction(false)
	_store.request_product_info({"product_ids": all_product_ids()})

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
	if _store == null or not live:
		_simulate(pid)
		return
	var err = _store.purchase({"product_id": pid})
	if typeof(err) == TYPE_INT and int(err) != OK:
		_fail(pid, "Could not reach the App Store.")

# Consumables are never "restored" -- spins already spent are gone -- but a
# transaction interrupted mid-flight comes back through the same queue, so the
# hook exists for the day a non-consumable (an ad-free unlock, say) is added.
func restore() -> void:
	if _store != null and live:
		_store.restore_purchases()

func _simulate(pid: String) -> void:
	var t := get_tree().create_timer(SIM_DELAY)
	t.timeout.connect(func() -> void:
		busy = false
		_pending = ""
		purchase_succeeded.emit(pid)
	)

func _fail(pid: String, message: String) -> void:
	busy = false
	_pending = ""
	purchase_failed.emit(pid, message)

# Called once the game is built and listening. Nothing is popped before this.
func begin() -> void:
	_started = true

func _process(_delta: float) -> void:
	if _store == null or not _started:
		return
	while int(_store.get_pending_event_count()) > 0:
		_handle(_store.pop_pending_event())

# The plugin's event shapes have drifted between versions, so every field is
# read defensively. An event we do not recognise must not strand `busy` at true
# -- that would wedge the store shut for the rest of the session.
func _handle(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"product_info":
			if String(event.get("result", "")) != "ok":
				return
			var ids: Array = event.get("ids", [])
			var shown: Array = event.get("localized_prices", event.get("prices", []))
			for i in ids.size():
				if i < shown.size():
					_prices[String(ids[i])] = String(shown[i])
			live = not ids.is_empty()
			if live:
				products_loaded.emit()
		"purchase":
			var pid := String(event.get("product_id", _pending))
			match String(event.get("result", "")):
				"ok":
					busy = false
					_pending = ""
					purchase_succeeded.emit(pid)
				"error":
					_fail(pid, String(event.get("error", "The purchase did not go through.")))
				_:
					pass  # "progress" -- Apple is still working, keep waiting
		"restore":
			pass

# Called once the pack has been granted and the save written. Only now is it
# safe to tell Apple the transaction is done.
func finish(product_id_str: String) -> void:
	if _store != null and live:
		_store.finish_transaction(product_id_str)
