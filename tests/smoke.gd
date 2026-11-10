extends SceneTree
## Headless smoke test: walks every scene in both states, checks links,
## evidence grants, the clock and the shift mechanic.
## Run:  godot --headless --path . -s tests/smoke.gd

var fails := 0
var st: Node


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		push_error("FAIL: " + msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	st = root.get_node_or_null("Story")
	if st == null:
		st = load("res://scripts/Story.gd").new()
		st.name = "Story"
		root.add_child(st)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ui = main.get_node("UI")

	# 1. story data links
	for id in st.scenes.keys():
		for c in st.scenes[id]["choices"]:
			check(c["next"].begins_with("__") or st.scenes.has(c["next"]), "%s -> %s missing" % [id, c["next"]])
		for e in st.scenes[id].get("grant", []):
			check(st.evidence.has(e), "%s grants unknown %s" % [id, e])
	check(st.scenes.size() >= 20, "scene count")

	# 2. title → ch1 → first drink forces Voice
	ui._start()
	await process_frame
	check(main.current_scene == "ch1_wake", "start at ch1_wake, got " + main.current_scene)
	for id in ["ch1_body", "ch1_mira1", "ch1_others", "ch1_drink"]:
		main.go(id)
		await process_frame
	main._on_choice({"next": "ch1_voice", "shiftTo": "V"})
	await process_frame
	check(st.state == "V", "first drink shifts to Voice")
	check(st.flasks == 2, "first drink costs a flask, flasks=%d" % st.flasks)

	# 3. Voice sweep of the four key V locations (40 min) → 2:20
	main.go("hub")
	await process_frame
	check(main.in_hub, "hub enables hotspots")
	var m0: int = st.minutes
	for id in ["loc_bar", "loc_floor", "loc_office", "int_theo"]:
		main.go(id)
		await process_frame
		check(not main.in_hub, "hotspots off inside " + id)
		check(ui.lines.size() > 0, "lines visible in " + id)
		while ui.line_idx < ui.lines.size():
			ui._next_line()
		main.go("hub")
		await process_frame
	check(st.minutes == m0 + 40, "each stop costs 10 min (got +%d)" % (st.minutes - m0))
	var v: int = st.true_counts()["V"]
	check(v >= 4, "voice sweep finds >=4 V items, got %d" % v)
	check(not st.ch4_due(), "ch4 not due before 2:40 (now %s)" % st.fmt_clock())

	# 4. sober up (+30 → 2:50) → next hub visit is Chapter Four
	check(st.shift("S"), "can sober up")
	check(st.state == "S", "sober")
	main.go("hub")
	await process_frame
	check(main.current_scene == "ch4_blackout", "hub at 2:50 routes to ch4_blackout, got " + main.current_scene)
	check(st.has_flag("ch4"), "ch4 flag set")
	check(not st.can_shift(), "no shifting inside ch4 choice")
	# take the sober branch: office carbon + wet cloth
	main.go("ch4_sober")
	await process_frame
	check(st.found.has("E10") and st.found.has("E11"), "sober branch grants E10+E11")
	main.go("hub")
	await process_frame
	check(main.current_scene == "hub", "ch4 fires only once")
	check(st.can_shift(), "shifting allowed again in hub")

	# 5. sober sweep: booth + bar (20 min → 3:10) for S items
	for id in ["loc_booth", "loc_bar"]:
		main.go(id)
		await process_frame
		main.go("hub")
		await process_frame
	var sc_: int = st.true_counts()["S"]
	check(sc_ >= 4, "sober items >=4, got %d" % sc_)
	check(not st.ready_for_timeline(), "not ready without Connie")

	# 6. second drink, Connie's testimony via int_connie (10 min → 3:20)
	check(st.shift("V"), "second drink")
	check(st.flasks == 1, "flasks after second drink")
	main.go("int_connie")
	await process_frame
	var opts: Array = st.visible_choices("int_connie")
	check(opts.size() == 2 and opts[0]["next"] == "ch4_connie", "Connie offers testimony in V after ch4")
	main.go("ch4_connie")
	await process_frame
	check(st.found.has("E08"), "Connie grants E08")
	check(st.ready_for_timeline(), "ready for timeline: " + st.true_progress())
	check(not st.true_unlocked(), "Frank card still locked before timeline")

	# 7. accuse → timeline → wrong pick resets → correct order → ch5_silence → accuse with Frank unlocked
	main.go("accuse")
	await process_frame
	var acc: Array = st.visible_choices("accuse")
	check(acc[0]["next"] == "ch5_intro", "timeline route visible on accuse")
	main.go("ch5_intro")
	await process_frame
	main.go("__timeline")
	await process_frame
	check(ui.tl.visible, "timeline panel shown")
	check(not st.can_shift(), "no shifting during the puzzle")
	ui._tl_pick("t3")
	check(ui.tl_order.is_empty() and ui.tl_msg.text != "", "wrong pick resets with a contradiction")
	for t in ["t1", "t2", "t3", "t4", "t5", "t6"]:
		ui._tl_pick(t)
	await process_frame
	check(not ui.tl.visible, "timeline closes when solved")
	check(main.current_scene == "ch5_silence", "solved timeline → ch5_silence, got " + main.current_scene)
	check(st.has_flag("timeline"), "timeline flag set")
	check(st.true_unlocked(), "Frank card unlocked: " + st.true_progress())
	check(not st.over, "night not over yet (%s)" % st.fmt_clock())

	# 8. true ending, both branches
	main.go("end_true")
	await process_frame
	check(st.found.has("E09"), "Voice confession on the board")
	main.go("end_true_tell")
	await process_frame
	check(st.over and st.endings_seen.has("ending_tell"), "tell ending recorded")
	main.go("hub")
	await process_frame
	check(main.current_scene == "end_true_tell", "non-ending scenes blocked after the night ends")

	# 9. restart resets, title shows the ending
	main.go("__restart")
	await process_frame
	check(st.minutes == st.START_MINUTES and st.flasks == 3 and st.found.is_empty() and st.flags.is_empty(), "restart resets state")
	check(ui.title_visible, "restart shows title")
	check(st.endings_seen.has("ending_tell"), "ending persists across restart")

	# 10. timeout path still works
	ui._start()
	await process_frame
	st.add_minutes(500)
	await process_frame
	await process_frame
	check(main.current_scene == "end_timeout", "timeout routes to end_timeout, got " + main.current_scene)

	print("SMOKE: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
