extends Node

const DESIGN_W := 720.0
const DESIGN_H := 1560.0

var m: Control

func _ready() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(int(DESIGN_W), int(DESIGN_H))
	w.size = Vector2i(540, 1170)
	await get_tree().process_frame
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout

	print("view_size=", m.view_size(), " safe_top=", m.safe_top(), " safe_bottom=", m.safe_bottom())
	print("content_bottom=", m.content_bottom(), " nav_slab_top=", m.nav_slab_top())

	# Make the strip visible the way an offline signed-in player would.
	Cloud._access = "harness"
	Cloud._reachable = false
	m._refresh_status_strip()
	await get_tree().process_frame
	await get_tree().process_frame

	var strip: Control = m._status_strip
	print("strip visible=", strip.visible, " text=", m._status_strip_label.text)
	print("strip rect=", strip.get_global_rect())
	print("strip min=", strip.get_combined_minimum_size())

	for key in ["shop", "quests", "collections", "boxes", "clan", "options", "alerts"]:
		var page: Control = m.pages.get(key, null)
		if page == null:
			print("[skip] ", key)
			continue
		var was := page.visible
		var prev := m._current_page
		page.visible = true
		if prev != page and is_instance_valid(prev):
			prev.visible = false
		m._current_page = page
		m._fill_page(key)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var sc: ScrollContainer = null
		for c in page.get_children():
			if c is ScrollContainer:
				sc = c
		if sc == null:
			print("[no sc] ", key)
			continue
		var vb: Control = sc.get_child(0)
		var vmax := int(sc.get_v_scroll_bar().max_value)
		sc.scroll_vertical = 1000000
		await get_tree().process_frame
		await get_tree().process_frame
		var scr := sc.get_global_rect()
		print("== ", key, " sc=", scr, " content_h=", vb.size.y, " vmax=", vmax, " scroll=", sc.scroll_vertical)
		# last visible child bottoms
		var n := vb.get_child_count()
		for i in range(maxi(0, n - 3), n):
			var ch: Control = vb.get_child(i)
			print("   child[", i, "] ", ch.get_class(), " rect=", ch.get_global_rect(),
				" text=", (ch.text if ch is Label else ""))
		var overlap := scr.intersects(strip.get_global_rect())
		print("   strip overlaps viewport: ", overlap)
		page.visible = was
	get_tree().quit()
