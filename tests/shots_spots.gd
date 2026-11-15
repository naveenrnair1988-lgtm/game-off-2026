extends SceneTree
## Renders the look-closer mode in each room, for both Franks: SHOT_DIR, TAG, optional ONLY=scene ids.
var main: Node
var st: Node
func _init(): call_deferred("_run")
func shot(name: String) -> void:
	for i in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [OS.get_environment("SHOT_DIR"), OS.get_environment("TAG"), name])

func _run():
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	st = root.get_node("Story")
	for i in 8: await process_frame
	main.ui._start()
	await process_frame
	main.title_key.visible = false
	var only := OS.get_environment("ONLY")
	for id in ["loc_booth", "loc_bar", "loc_floor", "loc_office", "loc_jukebox"]:
		if only != "" and not only.split(",").has(id): continue
		for state in ["S", "V"]:
			st.over = false; st.minutes = st.START_MINUTES
			st.shift_forced(state)
			main.go(id); await process_frame
			await shot("%s_%s" % [id, state])
			var k := 0
			for sp in st.spots(id):
				main._on_spot_picked(str(sp["id"]))
				while main.ui.line_idx < main.ui.lines.size(): main.ui._next_line()
				await shot("%s_%s_%d" % [id, state, k])
				main.ui._show_spots()
				k += 1
	quit()
