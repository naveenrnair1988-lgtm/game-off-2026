extends SceneTree
## Renders the confrontation / timer / recap screens for visual review.
var main
var st
var n := 0
func _init(): call_deferred("_run")
func shot(name: String) -> void:
	for i in 6: await process_frame
	n += 1
	root.get_texture().get_image().save_png("%s/v2_%02d_%s.png" % [OS.get_environment("SHOT_DIR"), n, name])
	print("shot ", n, " ", name)
func drain() -> void:
	while main.ui.line_idx < main.ui.lines.size():
		main.ui._next_line()
func settle() -> void:
	if main.cam_tween: main.cam_tween.kill()
	var s: Array = main.STATIONS[main.cam_station]
	main._snap_camera(main.cam_station)
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
	for id in ["loc_bar", "loc_floor", "loc_office"]:
		main.go(id); await process_frame; drain()
	main.go("ch2_brief"); await process_frame; settle(); await shot("brief_line1")
	drain(); await shot("brief_choices")
	main.go("int_lenny"); await process_frame; settle(); await shot("lenny_line1")
	drain(); settle(); await shot("lenny_choices")
	main.ui.open_present(); await shot("present_board")
	main.ui._toggle_board() if main.ui.board.visible else null
	main._on_present("E01v"); await process_frame; settle(); await shot("lenny_wrong")
	main._on_present("E05v"); await process_frame; settle(); await shot("crack_lenny_1")
	main.ui._next_line(); main.ui._next_line(); settle(); await shot("crack_lenny_3")
	drain(); settle(); await shot("crack_lenny_end")
	main.go("int_theo"); await process_frame; drain()
	main._on_present("E04v"); await process_frame; settle(); await shot("theo_wrong_state")
	st.shift("S"); pal(false)
	main.go("hub"); await process_frame; settle(); await shot("ch4_line1")
	drain(); settle(); await shot("ch4_timer")
	main._on_choice(st.scenes["ch4_blackout"]["choices"][1]); await process_frame; drain()
	main.go("hub"); await process_frame; drain(); settle(); await shot("hub_sober")
	main.go("int_theo"); await process_frame; drain()
	main._on_present("E04v"); await process_frame; settle(); await shot("crack_theo_1")
	drain(); settle(); await shot("crack_theo_end")
	main.go("int_mira"); await process_frame; drain()
	main._on_present("E10"); await process_frame; main.ui._next_line(); settle(); await shot("crack_mira_2")
	main.go("int_connie"); await process_frame; drain()
	main._on_present("E07v"); await process_frame; settle(); await shot("crack_connie_1")
	main.go("int_connie"); await process_frame; drain(); settle(); await shot("connie_choices")
	main.go("ch4_connie"); await process_frame; drain()
	main.ui._toggle_board(); await shot("board_full"); main.ui._toggle_board()
	st.set_flag("timeline")
	main.go("end_true"); await process_frame; drain(); settle(); await shot("end_true_timer")
	main.go("end_true_tell"); await process_frame; drain(); settle(); await shot("ending_recap")
	quit()
