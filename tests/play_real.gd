extends SceneTree
## Plays a whole route the way a player does (through the UI, in real time) and saves a frame for
## every line, choice and room view, so the run can be watched back as a film strip.
## SHOT_DIR, ROUTE=true|theo|timeout (default true), LINE_FRAMES (default 40).
var main: Node
var st: Node
var ui: Node
var n := 0
var lf := 40
func _init(): call_deferred("_run")

func snap(tag: String) -> void:
	for i in lf: await process_frame
	await RenderingServer.frame_post_draw
	n += 1
	var img := root.get_texture().get_image()
	img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	img.save_jpg("%s/%03d_%s.jpg" % [OS.get_environment("SHOT_DIR"), n, tag.left(28)], 0.82)

func buttons() -> Array:
	var out: Array = []
	for c in ui.choices.find_children("*", "Button", true, false):
		if not c.disabled: out.append(c)
	return out

## read every line of whatever is on screen, one frame each
func read() -> void:
	await snap(main.current_scene)
	while ui.line_idx < ui.lines.size():
		ui._finish_reveal()
		ui._next_line()
		await snap(main.current_scene)

func choose(match_text: String) -> void:
	for b in buttons():
		if match_text == "" or (b as Button).text.findn(match_text) >= 0:
			(b as Button).pressed.emit()
			await process_frame
			await read()
			return
	push_error("PLAY: no choice matching '%s' in %s; have %s" % [match_text, main.current_scene, buttons().map(func(x): return x.text)])

func room(id: String) -> void:
	main.go(id)
	await process_frame
	await read()

func look_all() -> void:
	for sp in st.spots(main.current_scene):
		main._on_spot_picked(str(sp["id"]))
		await read()
		ui._show_spots()
		await process_frame
	await snap(main.current_scene + "_looked")

func back() -> void:
	main.go("hub")
	await process_frame
	await read()   # may be the phone, or the ninety-minute mark

func be(state: String) -> void:
	if st.state != state:
		st.shift()
	await snap("shift_" + st.state)

func show(e: String) -> void:
	main._on_present(e)
	await process_frame
	await read()

func _run():
	lf = int(OS.get_environment("LINE_FRAMES")) if OS.get_environment("LINE_FRAMES") != "" else 40
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	st = root.get_node("Story")
	ui = main.get_node("UI")
	for i in 30: await process_frame
	await snap("title")
	ui._start()
	await process_frame
	await read()
	# Chapter One runs on single choices
	while main.current_scene.begins_with("ch1") or main.current_scene == "ch2_brief":
		await choose("")
	var route := OS.get_environment("ROUTE") if OS.get_environment("ROUTE") != "" else "true"
	await snap("hub")
	if route == "timeout":
		for id in ["loc_bar", "loc_floor", "loc_office", "loc_booth", "loc_jukebox", "int_theo", "int_mira", "int_connie", "int_lenny"]:
			if st.over: break
			await room(id); await look_all(); await back()
			if main.current_scene == "ch3_phone": await choose("ring"); await choose("")
			if main.current_scene == "ch4_blackout": await choose("Drink"); await choose("")
		while not st.over:
			st.shift(); await room("int_theo"); await back()
		await read()
		print("PLAY END scene=", main.current_scene, " clock=", st.fmt_clock()); quit(); return
	# the Voice looks at the room
	for id in ["loc_bar", "loc_floor", "loc_office", "loc_booth", "loc_jukebox"]:
		await room(id); await look_all(); await back()
		if main.current_scene == "ch3_phone":
			await choose("Answer"); await choose("")
	await room("int_lenny"); await show("E01v"); await show("E05v"); await choose("ledger"); await choose("")
	if main.current_scene == "ch3_phone": await choose("Answer"); await choose("")
	if main.current_scene == "ch4_blackout": await choose("Put it away"); await choose("")
	if route == "theo":
		await choose("accusation"); await choose("Theo"); print("PLAY END scene=", main.current_scene); await snap("end"); quit(); return
	await be("S")
	await back()
	if main.current_scene == "ch4_blackout": await choose("Put it away"); await choose("")
	await room("int_theo"); await show("E04v"); await choose("not your fault"); await choose("")
	if main.current_scene == "ch4_blackout": await choose("Put it away"); await choose("")
	await room("int_mira"); await show("E01v"); await choose("")
	if main.current_scene == "ch4_blackout": await choose("Put it away"); await choose("")
	await room("int_connie"); await show("E07v"); await choose("")
	await room("int_connie"); await choose("what you saw"); await choose("")
	await room("loc_booth"); await look_all(); await back()
	print("PLAY before accuse: clock=", st.fmt_clock(), " found=", st.found.keys())
	await choose("accusation")
	await choose("Lay it all out")
	await choose("timeline")
	await snap("timeline_open")
	for id in ["t1", "t3", "t2"]:      # one wrong placement on purpose, to see the pushback
		ui._tl_pick(id); await snap("timeline_" + id)
	for id in ["t1", "t2", "t3", "t4", "t5", "t6"]:
		if not ui.tl.visible: break
		ui._tl_pick(id); await snap("timeline_" + id)
	await read()
	await choose("")
	await choose("Frank Sable")
	await choose("I did it")
	await snap("ending")
	print("PLAY END scene=", main.current_scene, " clock=", st.fmt_clock(), " endings=", st.endings_seen)
	quit()
