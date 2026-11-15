extends SceneTree
## Each suspect at their station, idle and mid-line, after the animation has really run. SHOT_DIR, TAG.
var main: Node
var st: Node
func _init(): call_deferred("_run")
func shot(name: String, frames: int = 80) -> void:
	for i in frames: await process_frame
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
	for who in ["theo", "lenny", "connie", "mira"]:
		if only != "" and not only.split(",").has(who): continue
		st.over = false; st.minutes = st.START_MINUTES
		main.go("int_" + who); await process_frame
		await shot(who + "_talk", 70)
		while main.ui.line_idx < main.ui.lines.size(): main.ui._next_line()
		main.puppets[who].hush()
		await shot(who + "_idle", 110)
	main.go("hub"); await shot("hub", 60)
	quit()
