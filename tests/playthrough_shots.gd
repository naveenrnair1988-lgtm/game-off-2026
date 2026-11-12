extends SceneTree
## Renders every scene in both states to PNGs for visual review.
## Run: SHOT_DIR=/some/dir xvfb-run godot --path . --rendering-driver opengl3 -s tests/playthrough_shots.gd
var main
var st
var n := 0
func _init(): call_deferred("_run")
func shot(name: String) -> void:
	if main.cam_tween: main.cam_tween.kill()
	main.cam.transform = main.cam_base
	for i in 5: await process_frame
	n += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [OS.get_environment("SHOT_DIR"), n, name])
	print("shot ", n, " ", name)
func visit(id: String, state: String, drain: bool = true) -> void:
	st.over = false
	st.minutes = st.START_MINUTES + 30
	st.flasks = 2
	if st.state != state:
		st.shift_forced(state)
		st.flasks = 2
	st.flags["ch4"] = true
	main.go(id)
	await process_frame
	if drain:
		while main.ui.line_idx < main.ui.lines.size():
			main.ui._next_line()
	await shot(id + "_" + state)
func _run():
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	st = root.get_node("Story")
	for i in 8: await process_frame
	main.ui.title.modulate.a = 1.0
	n += 1
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%02d_title.png" % [OS.get_environment("SHOT_DIR"), n])
	main.ui._start()
	await process_frame
	main._apply_palette(main.SOBER, 0.0)
	main.title_key.light_energy = 0.0
	main.neon_light.light_energy = 0.9
	var only := OS.get_environment("ONLY")
	var plan := [["ch1_wake","S"],["ch1_body","S"],["ch1_mira1","S"],["ch1_others","S"],["ch1_drink","S"],["ch1_voice","V"],["hub","V"],["loc_booth","V"],["loc_bar","V"],["loc_floor","V"],["loc_office","V"],["int_mira","V"],["int_theo","V"],["int_lenny","V"],["int_connie","V"],["hub","S"],["loc_booth","S"],["loc_bar","S"],["loc_floor","S"],["loc_office","S"],["int_mira","S"],["int_theo","S"],["int_connie","S"],["ch4_blackout","S"],["ch4_sober","S"],["ch4_drink","V"],["ch4_connie","V"],["accuse","V"],["ch5_intro","V"],["ch5_silence","S"],["end_true","V"],["end_true_tell","S"],["end_theo","S"],["end_timeout","S"]]
	for p in plan:
		if only != "" and not only.split(",").has(p[0] + "_" + p[1]): continue
		if p[1] == "V": main._apply_palette(main.VOICE, 0.0)
		else: main._apply_palette(main.SOBER, 0.0)
		main.post_mat.set_shader_parameter("voice", 1.0 if p[1] == "V" else 0.0)
		await visit(p[0], p[1])
	if only == "":
		st.over = false
		main.go("__timeline")
		await shot("timeline")
		main.ui.tl.visible = false
		main.ui._toggle_board()
		await shot("board")
	quit()
