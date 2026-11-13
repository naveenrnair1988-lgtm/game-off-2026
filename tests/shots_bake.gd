extends SceneTree
## Renders a fixed set of views for judging the room: SHOT_DIR, TAG (file prefix).
var main
var st
func _init(): call_deferred("_run")
func shot(name: String) -> void:
	if main.cam_tween: main.cam_tween.kill()
	if main.fov_tween: main.fov_tween.kill()
	main._snap_camera(main.cam_station)
	for pp in main.puppets.values():
		for i in 20: pp._process(0.1)
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [OS.get_environment("SHOT_DIR"), OS.get_environment("TAG"), name])
	print("shot ", name)
func pal(v: bool) -> void:
	main._apply_palette(main.VOICE if v else main.SOBER, 0.0)
	main.post_mat.set_shader_parameter("voice", 1.0 if v else 0.0)
func _run():
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	st = root.get_node("Story")
	for i in 8: await process_frame
	main.ui.title.modulate.a = 1.0
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s_title.png" % [OS.get_environment("SHOT_DIR"), OS.get_environment("TAG")])
	main.ui._start()
	await process_frame
	main.title_key.light_energy = 0.0
	main.title_key.visible = false
	main.neon_light.light_energy = 0.9
	pal(false); st.set_flag("ch3"); st.set_flag("ch4")
	var only := OS.get_environment("ONLY")
	for id in ["hub", "loc_bar", "loc_booth", "loc_floor", "loc_office", "int_theo", "int_lenny", "int_connie", "int_mira", "loc_jukebox"]:
		if only != "" and not only.split(",").has(id): continue
		st.over = false; st.minutes = st.START_MINUTES
		main.go(id); await process_frame
		await shot(id)
	if only == "" or only.split(",").has("voice"):
		st.shift_forced("V"); pal(true)
		main.go("hub"); await process_frame; await shot("hub_voice")
		main.go("int_lenny"); await process_frame; await shot("lenny_voice")
		st.shift_forced("S"); pal(false)
	if only == "" or only.split(",").has("end"):
		st.found["E08"] = true; st.set_flag("timeline")
		main.go("end_true"); await process_frame
		main.headlight.visible = true; main.headlight.light_energy = 6.0
		await shot("headlights")
	quit()
