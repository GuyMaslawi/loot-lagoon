extends Node
# Does a purchase callback arriving off the main thread empty the shop page?
#
# StoreKit 2 is async Swift: its callbacks run on whatever task the framework
# feels like, and the plugin here is a prebuilt xcframework with no source in
# this repo, so the only way to ask the question is to reproduce the shape --
# call the same handler from a worker thread and look at the page.
#
#   godot --headless --path . res://tools/qa_thread.tscn

var m: Control
var _t: Thread

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	var t0 := Time.get_ticks_msec()
	while not bool(m.get("_booted")):
		if Time.get_ticks_msec() - t0 > 20000:
			print("BOOT TIMEOUT"); get_tree().quit(1); return
		await get_tree().process_frame

	m._goto(m.pages["shop"])
	for _i in 6:
		await get_tree().process_frame
	var body: VBoxContainer = m._page_bodies["shop"]
	print("main-thread id: %d" % OS.get_main_thread_id())
	print("shop rows before:      %d" % body.get_child_count())

	_t = Thread.new()
	_t.start(_off_main)
	while _t.is_alive():
		await get_tree().process_frame
	_t.wait_to_finish()

	for _i in 120:
		await get_tree().process_frame

	var rows := body.get_child_count()
	var popup = m.get("_popup")
	print("shop rows after:       %d" % rows)
	print("popup up:              %s" % ("yes" if popup != null else "NO"))
	var bad := 0
	if rows < 5:
		bad += 1
		print("  [FAIL] an off-thread receipt left the shop page EMPTY -- the")
		print("         rebuild's add_child calls were refused off the main thread")
	if popup == null:
		bad += 1
		print("  [FAIL] nothing was shown to say what was bought")
	print("QA-THREAD: %s" % ("ALL PASS" if bad == 0 else "%d FAILURES" % bad))
	get_tree().quit(1 if bad > 0 else 0)

# THROUGH iap.gd, the way a real receipt arrives -- not straight into main.gd.
# `_dispatch` is the funnel every purchase signal already passes through on both
# platforms, so calling it from a worker thread is exactly what StoreKit 2 does
# when it answers off its own task.
func _off_main() -> void:
	print("worker thread id: %d" % OS.get_thread_caller_id())
	IAP._dispatch("ok", IAP.PREFIX + "coins_m", "")
