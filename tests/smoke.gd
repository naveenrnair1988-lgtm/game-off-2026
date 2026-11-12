extends SceneTree
## Headless smoke test: plays the whole game by script — look, shift, confront, accuse —
## and checks the rules along the way.
## Run:  godot --headless --path . -s tests/smoke.gd

var fails := 0
var st: Node
var main: Node
var ui: Node


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		push_error("FAIL: " + msg)


func _init() -> void:
	call_deferred("_run")


func visit(id: String) -> void:
	main.go(id)
	await process_frame
	while ui.line_idx < ui.lines.size():
		ui._next_line()


func _run() -> void:
	st = root.get_node_or_null("Story")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	ui = main.get_node("UI")

	# 1. data integrity: links, evidence, confrontations, voice files
	for id in st.scenes.keys():
		for c in st.scenes[id]["choices"]:
			check(c["next"].begins_with("__") or st.scenes.has(c["next"]), "%s -> %s missing" % [id, c["next"]])
		for e in st.scenes[id].get("grant", []):
			check(st.evidence.has(e), "%s grants unknown %s" % [id, e])
		for l in st.scenes[id]["lines"]:
			if str(l.get("vo", "")) != "":
				check(ResourceLoader.exists("res://assets/voice/%s.ogg" % l["vo"]), "missing voice file " + str(l["vo"]))
		check(main.SCENE_STATION.has(id), "no camera station for scene " + id)
		check(main.STATIONS.has(main.SCENE_STATION.get(id, "")), "unknown camera station for scene " + id)
	for stem in st.scenes.keys():
		for l in st.scenes[stem]["lines"]:
			if str(l.get("vo", "")) != "":
				check(main.lipsync.has(l["vo"]), "no lip-sync data for " + str(l["vo"]))
	check(main.puppets.size() == 4, "four characters are rigged")
	for sid in st.present_cfg.keys():
		var cfg: Dictionary = st.present_cfg[sid]
		check(st.scenes.has(sid) and st.scenes.has(cfg["crack"]), "confrontation scenes exist for " + sid)
		for e in cfg["breaks"]:
			check(st.evidence.has(e), "unknown breaking evidence " + str(e))
		for k in ["wrong", "wrong_state"]:
			check(ResourceLoader.exists("res://assets/voice/%s.ogg" % cfg[k]["vo"]), "missing voice file " + str(cfg[k]["vo"]))

	# 2. Chapter One: the first drink forces the Voice
	ui._start()
	await process_frame
	check(main.current_scene == "ch1_wake", "start at ch1_wake, got " + main.current_scene)
	for id in ["ch1_body", "ch1_mira1", "ch1_others", "ch1_drink"]:
		await visit(id)
	main._on_choice({"next": "ch1_voice", "shiftTo": "V"})
	await process_frame
	check(st.state == "V" and st.flasks == 2, "first drink: Voice, two flasks left")
	await visit("ch2_brief")
	await visit("hub")
	check(main.in_hub, "hub enables hotspots")

	# 3. the Voice finds things (three stops, thirty minutes)
	var m0: int = st.minutes
	for id in ["loc_bar", "loc_floor", "loc_office"]:
		await visit(id)
		if id != "loc_office":
			await visit("hub")
	check(st.minutes == m0 + 30, "three stops cost thirty minutes")

	# 3b. Chapter Three: at 2:10 the phone rings; answering it is evidence
	main.go("hub")
	await process_frame
	check(main.current_scene == "ch3_phone", "the phone rings at 2:10, got %s at %s" % [main.current_scene, st.fmt_clock()])
	while ui.line_idx < ui.lines.size():
		ui._next_line()
	check(ui.timer_left > 0.0, "the phone is on a timer")
	main._on_choice(st.scenes["ch3_phone"]["choices"][0])
	await process_frame
	check(main.current_scene == "ch3_answer" and st.found.has("E12"), "answering gets the 12:20 call")
	await visit("hub")
	check(main.current_scene == "hub", "Chapter Three fires only once")
	await visit("loc_jukebox")
	check(st.found.has("E14v"), "the Voice reads the jukebox")
	await visit("hub")
	for e in ["E01v", "E04v", "E05v", "E07v", "E06v"]:
		check(st.found.has(e), "Voice sweep found " + e)

	# 4. Lenny: wrong evidence costs five minutes; the right evidence, in the Voice, breaks him
	await visit("int_lenny")
	var m1: int = st.minutes
	main._on_present("E01v")
	await process_frame
	check(st.minutes == m1 + 5 and not st.has_flag("cracked_lenny"), "wrong evidence costs five minutes")
	check(ui.lines.size() == 1 and ui.lines[0]["who"] == "lenny", "Lenny answers the wrong evidence")
	main._on_present("E05v")
	await process_frame
	check(main.current_scene == "crack_lenny" and st.has_flag("cracked_lenny"), "Lenny breaks to the Voice")
	check(st.found.has("C2"), "Lenny's confession is on the board")
	main._on_choice(st.scenes["crack_lenny"]["choices"][0])
	await process_frame
	check(main.current_scene == "crack_lenny_ledger" and st.has_flag("lenny_ledger"), "Lenny gives up where the ledger is")

	# 5. Theo will not confess to the Voice
	await visit("int_theo")
	var m2: int = st.minutes
	main._on_present("E04v")
	await process_frame
	check(not st.has_flag("cracked_theo") and st.minutes == m2, "Theo shuts down in front of the Voice, no time lost")
	check(ui.lines[0]["who"] == "theo", "Theo answers")

	# 6. sober up (twenty minutes); the next hub visit is Chapter Four
	check(st.shift("S"), "can sober up")
	check(st.minutes == m2 + 20, "sobering up costs twenty minutes")
	main.go("hub")
	await process_frame
	check(main.current_scene == "ch4_blackout", "Chapter Four fires at the hub after 2:40, got %s at %s" % [main.current_scene, st.fmt_clock()])
	check(not st.can_shift(), "no shifting during the Chapter Four decision")
	main._on_choice(st.scenes["ch4_blackout"]["choices"][1])   # put it away
	await process_frame
	check(main.current_scene == "ch4_sober" and st.state == "S", "putting it away keeps you sober")
	check(st.found.has("E10") and st.found.has("E11"), "sober branch finds the cloth and the carbon")
	await visit("hub")
	check(main.current_scene == "hub", "Chapter Four fires only once")

	# 7. sober Frank gets the confessions
	await visit("int_theo")
	main._on_present("E04v")
	await process_frame
	check(main.current_scene == "crack_theo" and st.found.has("C1"), "Theo confesses to sober Frank")
	while ui.line_idx < ui.lines.size():
		ui._next_line()
	check(ui.timer_left > 0.0, "how you answer Theo is on a timer")
	main._on_choice(st.scenes["crack_theo"]["choices"][0])
	await process_frame
	check(main.current_scene == "crack_theo_kind" and st.has_flag("theo_kind"), "being kind to Theo is remembered")
	await visit("int_mira")
	main._on_present("E10")
	await process_frame
	check(main.current_scene == "crack_mira" and st.found.has("C3"), "Mira confesses to sober Frank")
	check(st.cracked_count() == 3, "three confessions")
	await visit("int_connie")
	var opts: Array = st.visible_choices("int_connie")
	check(opts[0]["next"] == "__present", "Connie will not tell before you show her the glass")
	main._on_present("E07v")
	await process_frame
	check(main.current_scene == "crack_connie" and st.has_flag("connie_admits"), "Connie admits she never left")
	await visit("int_connie")
	opts = st.visible_choices("int_connie")
	check(opts[0]["next"] == "ch4_connie", "Connie offers her account once all three have confessed")
	await visit("ch4_connie")
	check(st.found.has("E08") and st.ready_for_timeline(), "Connie's account unlocks the timeline")
	var said: Array = []
	for cl in st.visible_lines("ch4_connie"):
		said.append(cl["vo"])
	check(said.has("c10"), "Connie owns up to the 12:20 call when you answered the phone")
	check(not st.true_unlocked(), "Frank's card is locked until the timeline is built")
	check(not st.over, "still time on the clock (%s)" % st.fmt_clock())

	# 8. timeline and the true ending
	await visit("accuse")
	check(st.fmt_clock() == "3:58 AM", "the accusation lands at 3:58")
	await visit("ch5_intro")
	main.go("__timeline")
	await process_frame
	check(ui.tl.visible, "timeline shown")
	ui._tl_pick("t3")
	check(ui.tl_order.is_empty() and ui.tl_msg.text != "", "a wrong pick resets with a contradiction")
	for t in ["t1", "t2", "t3", "t4", "t5", "t6"]:
		ui._tl_pick(t)
	await process_frame
	check(main.current_scene == "ch5_silence" and st.true_unlocked(), "solving the timeline unlocks Frank")
	await visit("end_true")
	check(st.found.has("E09"), "the Voice's confession is on the board")
	check(ui.timer_left > 0.0, "the last choice is on a timer")
	# silence is an answer: let the timer run out
	ui._process(60.0)
	await process_frame
	check(main.current_scene == "end_true_stand", "saying nothing lets it stand, got " + main.current_scene)
	check(st.over and st.endings_seen.has("end_true_stand"), "ending recorded")
	var told: Array = []
	for el in st.visible_lines("end_true_tell"):
		told.append(el["vo"])
	check(told.has("n56") and told.has("n58") and told.has("n59") and not told.has("n57"), "the ending remembers what you did: " + str(told))
	check(st.recap().contains("3 of 3 confessions"), "recap: " + st.recap())
	main.go("hub")
	await process_frame
	check(main.current_scene == "end_true_stand", "nothing but endings after the night is over")

	# 9. restart, then: doing nothing at Chapter Four means the schedule wins
	main.go("__restart")
	await process_frame
	check(st.minutes == st.START_MINUTES and st.flasks == 3 and st.found.is_empty() and st.flags.is_empty(), "restart resets")
	check(ui.title_visible, "restart shows the title")
	ui._start()
	await process_frame
	await visit("ch3_phone")
	ui._process(60.0)
	await process_frame
	check(main.current_scene == "ch3_ring" and not st.found.has("E12"), "if you do nothing, the phone rings out; got " + main.current_scene)
	await visit("ch4_blackout")
	check(ui.timer_left > 0.0, "Chapter Four is on a timer")
	ui._process(60.0)
	await process_frame
	check(main.current_scene == "ch4_drink" and st.state == "V", "if you do not choose, Frank drinks; got %s / %s" % [main.current_scene, st.state])

	# 10. running out the clock
	st.add_minutes(500)
	await process_frame
	await process_frame
	check(main.current_scene == "end_timeout", "the clock running out ends the night, got " + main.current_scene)

	print("SMOKE: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
