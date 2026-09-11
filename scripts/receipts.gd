# Server-side receipt verification -- the reporting half.
#
# The client GRANTS FIRST and reports AFTER, always. By the time anything in
# this file runs, the player has their pack and the save is on disk; nothing
# here can block, delay or claw back a purchase, and a verdict of "invalid"
# changes nothing on the device beyond a log line and a local mark. What the
# report buys is a server-side ledger (iap_receipts) written by asking Apple
# and Google directly whether each receipt is real -- the record a patched
# client cannot edit, and the one that catches off-the-shelf receipt spoofing.
#
# Every design choice below follows from "never lose a real report, never
# bother a real player":
#
#   - The queue is a file, so a receipt reported into a tunnel is still there
#     next launch. Same tmp+rename discipline as the IAP ledger, because a
#     half-written queue reads as no queue.
#   - Transport failure (no network at all) costs no attempt -- a phone in
#     airplane mode must not burn through the retry budget. Only an answer
#     that arrived and was not final counts against MAX_ATTEMPTS.
#   - The server says whether a verdict is final. valid / invalid / refunded
#     end the item; pending / unknown / any HTTP error keep it for the timer,
#     so a not-yet-deployed function or missing store credentials degrade to
#     "try again later", silently, forever bounded by the attempt cap.
#   - One request in flight, ever. This path has no deadline, so it never
#     needs to compete with the game for the radio.
extends Node

const QUEUE_PATH := "user://receipt_queue.json"
const QUEUE_TMP := "user://receipt_queue.json.tmp"
const FN_PATH := "/functions/v1/verify_purchase"

# A queue longer than this is not a backlog, it is a bug or an attack on the
# file; the oldest entry has had the most attempts, so it is the one dropped.
const MAX_QUEUE := 100
# Server-answered non-final attempts before an item is given up on. At one
# try per launch plus one per RETRY_GAP, this is weeks of a misconfigured
# server before a receipt is quietly dropped.
const MAX_ATTEMPTS := 30
# How long between retries while the app stays open.
const RETRY_GAP := 600.0
# How many server-flagged receipts are remembered locally, newest kept. Only
# ever read by a human debugging a device; the authoritative list is the
# server table.
const MAX_FLAGGED := 20
const HTTP_TIMEOUT := 20.0
# First try waits for the boot to finish -- this path has no deadline and the
# title screen does.
const BOOT_DELAY := 8.0

var _url := ""
var _key := ""
var _queue: Array = []     # of {platform, receipt, product, attempts}
var _flagged: Array = []   # of {platform, receipt, product, detail}
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg: Dictionary = Cloud._load_config()
	_url = str(cfg.get("url", "")).rstrip("/")
	_key = str(cfg.get("publishable_key", ""))
	_load_queue()
	var t := Timer.new()
	t.wait_time = RETRY_GAP
	t.autostart = true
	t.timeout.connect(_try_send)
	add_child(t)
	get_tree().create_timer(BOOT_DELAY).timeout.connect(_try_send)
	# The network coming back is the moment a queued report stops failing.
	Cloud.reachable_changed.connect(func(ok: bool) -> void:
		if ok:
			_try_send()
	)

# Called by IAP.finish() with the transaction the grant was just recorded
# under. Refusals here are silent on purpose: an unconfigured build has
# nowhere to report to, and a duplicate is a retry of a report already queued.
func enqueue(platform: String, receipt: String, product: String) -> void:
	if platform == "" or receipt == "" or _url == "" or _key == "":
		return
	for e in _queue:
		if String(e.get("receipt", "")) == receipt:
			return
	while _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append({"platform": platform, "receipt": receipt, "product": product, "attempts": 0})
	_save_queue()
	_try_send()

func _try_send() -> void:
	if _busy or _queue.is_empty() or _url == "":
		return
	_busy = true
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)
	var item: Dictionary = _queue[0]
	var body := {
		"platform": String(item.get("platform", "")),
		"receipt_id": String(item.get("receipt", "")),
		"product_id": String(item.get("product", "")),
		"install_id": Diag.install_id(),
	}
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp: PackedByteArray) -> void:
		http.queue_free()
		_handle_answer(result, code, resp)
	)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + _key,
	])
	if http.request(_url + FN_PATH, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		_busy = false

# Split from the HTTPRequest callback so the QA harness can hand it crafted
# answers without a server on the other end.
func _handle_answer(result: int, code: int, resp: PackedByteArray) -> void:
	_busy = false
	if _queue.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		# No transport at all. Not the item's fault, so not its attempt --
		# the timer or the next reachable_changed tries again.
		return
	var item: Dictionary = _queue[0]
	var parsed = JSON.parse_string(resp.get_string_from_utf8())
	var d: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var verdict := String(d.get("verdict", ""))
	var is_final: bool = bool(d.get("final", false)) and code >= 200 and code < 300
	if is_final:
		_queue.pop_front()
		if verdict != "valid":
			# The server says this receipt is not what the device was told it
			# was. Nothing is clawed back -- see the header -- but it is worth
			# a mark on the device and a breadcrumb in the funnel.
			push_warning("Receipts: server flagged a %s receipt as %s (%s)"
					% [String(item.get("platform", "")), verdict, String(d.get("detail", ""))])
			_flagged.append({
				"platform": String(item.get("platform", "")),
				"receipt": String(item.get("receipt", "")),
				"product": String(item.get("product", "")),
				"detail": String(d.get("detail", "")),
			})
			while _flagged.size() > MAX_FLAGGED:
				_flagged.pop_front()
			Diag.note("receipt_flagged")
		_save_queue()
		# Settle the rest of the backlog while the server is clearly there.
		_try_send()
		return
	# Answered but unsettled: pending payment, missing config on the server,
	# a 404 from a function not deployed yet, a 429 from the limiter. Count it
	# and keep it, unless this item has been counted out.
	item["attempts"] = int(item.get("attempts", 0)) + 1
	if int(item["attempts"]) >= MAX_ATTEMPTS:
		push_warning("Receipts: giving up on a %s receipt after %d attempts (last: %s %s)"
				% [String(item.get("platform", "")), MAX_ATTEMPTS, str(code), verdict])
		_queue.pop_front()
	_save_queue()

# --- the file ---------------------------------------------------------------

func _load_queue() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return
	var f := FileAccess.open(QUEUE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d := parsed as Dictionary
	if typeof(d.get("queue")) == TYPE_ARRAY:
		_queue = []
		for e in (d.get("queue") as Array):
			if typeof(e) == TYPE_DICTIONARY and String((e as Dictionary).get("receipt", "")) != "":
				_queue.append(e)
	if typeof(d.get("flagged")) == TYPE_ARRAY:
		_flagged = d.get("flagged")

func _save_queue() -> void:
	# Same dance as the IAP ledger, for the same reasons -- including clearing
	# a wrong-kind leftover so a directory at the scratch path is a transient
	# fault rather than a permanent one.
	var d := DirAccess.open("user://")
	if d != null and not FileAccess.file_exists(QUEUE_TMP):
		d.remove(QUEUE_TMP)
	var f := FileAccess.open(QUEUE_TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"queue": _queue, "flagged": _flagged}))
	f.close()
	if d == null:
		return
	if FileAccess.file_exists(QUEUE_PATH):
		d.remove(QUEUE_PATH)
	d.rename(QUEUE_TMP, QUEUE_PATH)
