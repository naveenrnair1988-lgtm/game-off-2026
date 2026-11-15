extends SceneTree
## Screenshots for the store page and README: SHOT_DIR.
var main: Node
var st: Node
var ui: Node
func _init(): call_deferred("_run")
func shot(name: String, frames: int = 80) -> void:
	for i in frames: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("SHOT_DIR"), name])
func drain(keep: int = 0) -> void:
	while ui.line_idx < ui.lines.size() - keep:
		ui._finish_reveal(); ui._next_line()
	ui._finish_reveal()
func _run():
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	st = root.get_node("Story"); ui = main.get_node("UI")
	for i in 40: await process_frame
	ui.title.modulate.a = 1.0
	await shot("01_title", 30)
	ui._start(); await process_frame
	main.title_key.visible = false
	main.go("ch1_body"); await drain(3); await shot("02_body")
	st.shift_forced("V")
	main.go("hub"); await shot("03_room_voice", 110)
	main.go("loc_bar"); await process_frame
	main._on_spot_picked("charger"); await drain(); await shot("04_look_closer", 60)
	main.go("int_lenny"); await drain(4); await shot("05_lenny", 100)
	st.found["E05v"] = true
	main._on_present("E05v"); await drain(2); await shot("06_lenny_cracks", 120)
	st.shift_forced("S")
	main.go("int_theo"); await drain(8); await shot("07_theo", 90)
	for e in st.evidence.keys(): st.found[e] = true
	for f in ["cracked_theo", "cracked_lenny", "cracked_mira", "connie_admits"]: st.set_flag(f)
	main.go("ch4_connie"); await drain(11); await shot("08_connie", 90)
	main.go("__timeline"); ui._tl_pick("t1"); ui._tl_pick("t2"); ui._tl_pick("t3")
	await shot("09_timeline", 12)
	ui.tl.visible = false; st.current_no_shift = false
	ui._toggle_board(); await shot("10_board", 12)
	quit()
