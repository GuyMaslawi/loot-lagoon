extends Node

var m: Control

func _ready() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(720, 1280)
	w.size = Vector2i(720, 1560)
	await get_tree().process_frame
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(5.0).timeout
	print("view_size=", m.view_size(), " content_bottom=", m.content_bottom(),
		" safe_bottom=", m.safe_bottom(), " nav_slab_top=", m.nav_slab_top())
	var strip: Control = m._status_strip
	m._refresh_status_strip()
	await get_tree().process_frame
	await get_tree().process_frame
	print("strip visible=", strip.visible, " text='", m._status_strip_label.text, "'")
	print("strip rect=", strip.get_global_rect(), " z=", strip.z_index)
	for key in ["shop", "quests", "clan", "options", "alerts", "boxes", "collections"]:
		var page: Control = m.pages.get(key, null)
		if page == null:
			continue
		var was := page.visible
		page.visible = true
		m._fill_page(key)
		await get_tree().process_frame
		await get_tree().process_frame
		var sc: ScrollContainer = null
		for c in page.get_children():
			if c is ScrollContainer:
				sc = c
		if sc == null:
			continue
		sc.scroll_vertical = 100000
		await get_tree().process_frame
		await get_tree().process_frame
		var vb: Control = sc.get_child(0)
		var last: Control = null
		for c in vb.get_children():
			if c is Control:
				last = c
		print("--- page ", key, " page.z=", page.z_index)
		print("    sc rect=", sc.get_global_rect(), " scroll_v=", sc.scroll_vertical,
			" vmax=", sc.get_v_scroll_bar().max_value, " vpage=", sc.get_v_scroll_bar().page)
		if last != null:
			print("    last child ", last.get_class(), " '",
				(last.text if last is Label else ""), "' rect=", last.get_global_rect())
		var sr := strip.get_global_rect()
		var cr := sc.get_global_rect()
		var ov := sr.intersection(cr)
		print("    overlap strip x scroll viewport = ", ov)
		page.visible = was
	get_tree().quit(0)
