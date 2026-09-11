extends Node
# Temporary QA harness -- the receipt-report queue, and the promises it makes.
# Not shipped.
#
# The queue's one job is "never lose a real report, never bother a real
# player". Every test here is one of the ways it could quietly break that:
# a transport failure burning the retry budget, a half-written file reading
# as an empty queue, a server verdict that removes the wrong thing, a
# misconfigured server draining the attempts of a receipt that deserved them.
#
# Nothing here touches the real server. The URL is pointed at a dead local
# port for the one test that exercises real transport, and every other test
# hands _handle_answer a crafted body directly.

var fails := 0

const DEAD := "http://127.0.0.1:1"

func _ready() -> void:
	_isolate()
	_t_enqueue_refusals()
	_t_enqueue_dedupes_and_caps()
	_t_queue_survives_a_restart()
	_t_transport_failure_costs_no_attempt()
	await _t_dead_port_keeps_the_item()
	_t_final_verdicts_settle_items()
	_t_unsettled_answers_burn_attempts()
	_t_save_is_atomic()
	_t_finish_hands_the_receipt_over()
	print("QA-RECEIPTS: %s" % ("ALL PASS" if fails == 0 else "%d FAILURES" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _chk(name: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1

# The autoload loaded the dev machine's real config and possibly a real queue
# file. Point it at nothing and start empty, so no test can leak a request at
# the live project or inherit state from a previous run.
func _isolate() -> void:
	Receipts._url = DEAD
	Receipts._key = "test-key"
	Receipts._queue = []
	Receipts._flagged = []
	Receipts._busy = false
	for f in [Receipts.QUEUE_PATH, Receipts.QUEUE_TMP]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)

func _item(receipt: String, attempts := 0) -> Dictionary:
	return {"platform": "ios", "receipt": receipt, "product": "com.x.pack", "attempts": attempts}

func _answer(verdict: String, is_final: bool, code := 200) -> void:
	var body := JSON.stringify({"verdict": verdict, "detail": "test", "final": is_final})
	Receipts._handle_answer(HTTPRequest.RESULT_SUCCESS, code, body.to_utf8_buffer())

# --- what enqueue refuses ----------------------------------------------------

func _t_enqueue_refusals() -> void:
	print("enqueue refuses what it cannot use")
	_isolate()
	Receipts.enqueue("", "t1", "p")
	Receipts.enqueue("ios", "", "p")
	_chk("no platform / no receipt never queues", Receipts._queue.is_empty())
	var url := String(Receipts._url)
	Receipts._url = ""
	Receipts.enqueue("ios", "t1", "p")
	_chk("an unconfigured build never queues", Receipts._queue.is_empty())
	Receipts._url = url

func _t_enqueue_dedupes_and_caps() -> void:
	print("enqueue dedupes, and the cap drops the oldest")
	_isolate()
	Receipts.enqueue("ios", "t1", "p")
	Receipts.enqueue("ios", "t1", "p")
	_chk("the same receipt queues once", Receipts._queue.size() == 1)
	_isolate()
	for i in Receipts.MAX_QUEUE + 5:
		Receipts.enqueue("ios", "t%d" % i, "p")
	_chk("the queue never exceeds MAX_QUEUE", Receipts._queue.size() == Receipts.MAX_QUEUE)
	_chk("and the oldest was the one dropped",
			String(Receipts._queue[0].get("receipt", "")) == "t5")

# --- the file ----------------------------------------------------------------

func _t_queue_survives_a_restart() -> void:
	print("a queued report survives a relaunch")
	_isolate()
	Receipts.enqueue("android", "tok-1", "com.x.pack")
	Receipts._flagged = [{"platform": "ios", "receipt": "bad-1", "product": "p", "detail": "d"}]
	Receipts._save_queue()
	Receipts._queue = []
	Receipts._flagged = []
	Receipts._load_queue()
	_chk("the queue comes back", Receipts._queue.size() == 1
			and String(Receipts._queue[0].get("receipt", "")) == "tok-1")
	_chk("the flagged list comes back", Receipts._flagged.size() == 1)

func _t_save_is_atomic() -> void:
	print("the save leaves no scratch file and a readable queue")
	_isolate()
	Receipts.enqueue("ios", "t1", "p")
	_chk("no tmp left behind", not FileAccess.file_exists(Receipts.QUEUE_TMP))
	var f := FileAccess.open(Receipts.QUEUE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text() if f != null else "")
	if f != null:
		f.close()
	_chk("the file on disk parses", typeof(parsed) == TYPE_DICTIONARY)

# --- transport vs verdicts ---------------------------------------------------

func _t_transport_failure_costs_no_attempt() -> void:
	print("no network is not the receipt's fault")
	_isolate()
	Receipts._queue = [_item("t1")]
	Receipts._busy = true
	Receipts._handle_answer(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	_chk("the item stays queued", Receipts._queue.size() == 1)
	_chk("and its attempts are untouched", int(Receipts._queue[0].get("attempts", -1)) == 0)
	_chk("and the sender is free again", not Receipts._busy)

func _t_dead_port_keeps_the_item() -> void:
	print("a real request to a dead port keeps the item queued")
	_isolate()
	Receipts._queue = [_item("t1")]
	Receipts._try_send()
	var deadline := Time.get_ticks_msec() + 10000
	while Receipts._busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_chk("the request completed", not Receipts._busy)
	_chk("the item is still there", Receipts._queue.size() == 1)
	_chk("with no attempt burned", int(Receipts._queue[0].get("attempts", -1)) == 0)

func _t_final_verdicts_settle_items() -> void:
	print("final verdicts settle items; invalid also flags")
	_isolate()
	Receipts._queue = [_item("t1")]
	Receipts._busy = true
	_answer("valid", true)
	_chk("valid removes the item", Receipts._queue.is_empty())
	_chk("and flags nothing", Receipts._flagged.is_empty())
	Receipts._queue = [_item("t2")]
	Receipts._busy = true
	_answer("invalid", true)
	_chk("invalid removes the item", Receipts._queue.is_empty())
	_chk("and records it locally", Receipts._flagged.size() == 1
			and String(Receipts._flagged[0].get("receipt", "")) == "t2")
	# A "final" claim on a failed HTTP status must not settle anything -- a
	# proxy or captive portal can hand back any body with any code.
	Receipts._queue = [_item("t3")]
	Receipts._busy = true
	_answer("valid", true, 500)
	_chk("final on a 500 does not settle", Receipts._queue.size() == 1)

func _t_unsettled_answers_burn_attempts() -> void:
	print("unsettled answers count, and the cap ends them")
	_isolate()
	Receipts._queue = [_item("t1")]
	Receipts._busy = true
	_answer("unknown", false)
	_chk("the item stays", Receipts._queue.size() == 1)
	_chk("with one attempt on it", int(Receipts._queue[0].get("attempts", 0)) == 1)
	Receipts._queue = [_item("t2", Receipts.MAX_ATTEMPTS - 1)]
	Receipts._busy = true
	_answer("unknown", false)
	_chk("the attempt cap drops the item", Receipts._queue.is_empty())

# --- the hand-off from the money path ---------------------------------------

func _t_finish_hands_the_receipt_over() -> void:
	print("IAP.finish hands the transaction to the queue")
	_isolate()
	var granted_before: Dictionary = IAP._granted.duplicate()
	# A pretend store, so finish() reads as an iOS build. finish() itself only
	# ever asks whether _store is null, never talks to it.
	IAP._store = RefCounted.new()
	IAP._pending_txn = "txn-qa-1"
	IAP.finish("com.guymaslawi.lootlagoon.pack_s")
	_chk("the receipt is queued", Receipts._queue.size() == 1
			and String(Receipts._queue[0].get("receipt", "")) == "txn-qa-1"
			and String(Receipts._queue[0].get("platform", "")) == "ios")
	_chk("and the ledger recorded the grant first", IAP._granted.has("txn-qa-1"))
	IAP._store = null
	IAP._granted = granted_before
	IAP._save_ledger()
	# In the editor and on desktop there is no store and finish() has no
	# transaction -- the queue must stay silent there.
	_isolate()
	IAP._pending_txn = ""
	IAP.finish("com.guymaslawi.lootlagoon.pack_s")
	_chk("a simulated purchase reports nothing", Receipts._queue.is_empty())
