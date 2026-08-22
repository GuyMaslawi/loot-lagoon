extends Node
var m: Control
func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	add_child(m)
	await get_tree().create_timer(4.0).timeout
	# How many distinct Shader objects the game is holding, and how many more
	# each page rebuild mints.
	print("shaders after boot: %d" % _count())
	for key in ["shop", "quests", "collections", "boxes", "options", "alerts"]:
		var a := _count()
		var t0 := Time.get_ticks_usec()
		m._fill_page(key)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		await get_tree().process_frame
		await get_tree().process_frame
		print("  %-12s +%3d shaders  (%.1f ms to build)" % [key, _count() - a, ms])
	# and a rebuild loop, the way a player flicking between tabs does it
	var before := _count()
	var t0 := Time.get_ticks_usec()
	for i in 20:
		m._fill_page("shop")
		await get_tree().process_frame
	var total := float(Time.get_ticks_usec() - t0) / 1000.0
	print("20 shop rebuilds: %+d shaders, %.0f ms" % [_count() - before, total])
	get_tree().quit()

# Distinct compiled programs, not materials. Many nodes share one shader now,
# which is the whole point -- counting materials would report no change at all.
func _count() -> int:
	var seen := {}
	for o in _walk(m):
		seen[(o as Shader).get_instance_id()] = true
	return seen.size()

func _walk(n: Node) -> Array:
	var out := []
	var ci := n as CanvasItem
	if ci != null and ci.material is ShaderMaterial and (ci.material as ShaderMaterial).shader != null:
		out.append((ci.material as ShaderMaterial).shader)
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
