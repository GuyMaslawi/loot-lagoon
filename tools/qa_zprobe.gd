extends Node
var m: Control

func _dump(name: String, c: Control) -> void:
	if c == null or not is_instance_valid(c):
		print("%s : MISSING" % name)
		return
	print("%s : visible_in_tree=%s rect=%s z=%d z_rel=%s" % [
		name, str(c.is_visible_in_tree()), str(c.get_global_rect()), c.z_index, str(c.is_z_relative())])

func _ready() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(720, 1560)
	w.size = Vector2i(360, 780)
	await get_tree().process_frame
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(5.0).timeout
	print("view_size=%s content_bottom=%f safe_bottom=%f" % [str(m.view_size()), m.content_bottom(), m.safe_bottom()])
	# open the collections page the way a tap does
	var page: Control = m.pages.get("collections")
	m._goto(page)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	print("current_page_is_collections=%s page_visible=%s page_z=%d" % [str(m._current_page == page), str(page.is_visible_in_tree()), page.z_index])
	var strip: Control = m._status_strip
	_dump("strip", strip)
	print("strip_text='%s'" % m._status_strip_text())
	# find the dock: the Control child of page with z_index 20
	var dock: Control = null
	for ch in page.get_children():
		if ch is Control and (ch as Control).z_index == 20:
			dock = ch
	_dump("dock", dock)
	if dock != null and strip != null and strip.visible:
		var inter := strip.get_global_rect().intersection(dock.get_global_rect())
		print("intersection=%s area=%f" % [str(inter), inter.size.x * inter.size.y])
	# draw-order sanity: who is later in the canvas
	print("strip_parent=%s dock_parent=%s" % [str(strip.get_parent().name), str(dock.get_parent().name) if dock else "-"])
	get_tree().quit()
