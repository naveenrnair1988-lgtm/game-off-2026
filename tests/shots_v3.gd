extends SceneTree
## Renders the animated cast, Chapter Three and the jukebox for visual review.
var main
var st
var n := 0
func _init(): call_deferred("_run")
func settle(talk: bool = false) -> void:
	if main.cam_tween: main.cam_tween.kill()
	if main.fov_tween: main.fov_tween.kill()
	main._snap_camera(main.cam_station)
	for pp in main.puppets.values():
		for i in 30: pp._process(0.1)
		if talk and pp.speaking():
			# hold on a loud syllable
			var best := 0
			for i in pp.env.size():
				if pp.env[i] > pp.env[best]: best = i
			pp.speak_t = best * 0.05
			pp.set_process(false)
			for i in 6:
				pp.speak_t = best * 0.05
				pp.set_process(true); pp._process(0.03); pp.set_process(false)
func shot(name: String, talk: bool = false) -> void:
	settle(talk)
	for i in 3: await process_frame
	n += 1
	root.get_texture().get_image().save_png("%s/v3_%02d_%s.png" % [OS.get_environment("SHOT_DIR"), n, name])
	for pp in main.puppets.values(): pp.set_process(true)
	print("shot ", n, " ", name)
func drain() -> void:
	while main.ui.line_idx < main.ui.lines.size():
		main.ui._next_line()
func pal(v: bool) -> void:
	main._apply_palette(main.VOICE if v else main.SOBER, 0.0)
	main.post_mat.set_shader_parameter("voice", 1.0 if v else 0.0)
func _run():
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	st = root.get_node("Story")
	for i in 8: await process_frame
	main.ui._start()
	await process_frame
	main.title_key.light_energy = 0.0
	main.neon_light.light_energy = 0.9
	st.shift_forced("V"); pal(true)
	main.go("hub"); await process_frame; await shot("hub_voice")
	main.go("loc_jukebox"); await process_frame; await shot("jukebox")
	main.go("int_lenny"); await process_frame; await shot("lenny_talk", true)
	st.minutes = st.CH3_MINUTES
	main.go("hub"); await process_frame; main.ui._next_line(); await shot("ch3_phone")
	drain(); await shot("ch3_choice", true)
	main._on_choice(st.scenes["ch3_phone"]["choices"][0]); await process_frame; await shot("ch3_answer")
	st.found["E05v"] = true
	main.go("int_lenny"); await process_frame; drain()
	main._on_present("E05v"); await process_frame; main.ui._next_line(); await shot("crack_lenny_react", true)
	drain(); await shot("crack_lenny_choices")
	st.shift_forced("S"); pal(false); st.set_flag("ch4"); st.found["E04v"] = true; st.found["E07v"] = true
	main.go("int_theo"); await process_frame; await shot("theo_talk", true)
	drain(); main._on_present("E04v"); await process_frame; main.ui._next_line(); await shot("crack_theo_talk", true)
	main.go("int_mira"); await process_frame; await shot("mira_talk", true)
	main.go("int_connie"); await process_frame; await shot("connie_talk", true)
	main.go("hub"); await process_frame; await shot("hub_sober")
	quit()
