extends CanvasLayer
## UI — HUD, dialogue panel, choices, evidence board, title. Built in code.

signal choice_made(choice: Dictionary)
signal back_requested
signal restart_requested
signal shift_requested
signal timeline_solved
signal line_advanced
signal line_voice(stem: String)

const WHO := {"frank": "FRANK", "mira": "MIRA ROARKE", "theo": "THEO PIKE", "lenny": "LENNY BAPTISTE", "connie": "CONNIE VALE"}
const AMBER := Color(0.85, 0.64, 0.25)
const CYAN := Color(0.44, 0.83, 0.90)
const MUTED := Color(0.60, 0.54, 0.45)
const TEXT := Color(0.91, 0.86, 0.78)

var title_visible: bool = true
var scene_id: String = ""
var lines: Array = []
var line_idx: int = 0

var hud: HBoxContainer
var lbl_clock: Label
var lbl_flasks: Label
var lbl_state: Label
var btn_shift: Button
var btn_board: Button
var panel: PanelContainer
var dock: VBoxContainer
var lbl_more: Label
var lbl_loc: Label
var text: RichTextLabel
var choices: VBoxContainer
var board: PanelContainer
var board_list: VBoxContainer
var title: MarginContainer
var title_shade: TextureRect
var title_dim: ColorRect
var portrait: TextureRect
var portrait_cache: Dictionary = {}
var font_serif: Font
var tl: PanelContainer
var tl_pool: VBoxContainer
var tl_line: VBoxContainer
var tl_msg: Label
var tl_order: Array = []


var font_serif_italic: Font
var font_ui: Font


func _ready() -> void:
	layer = 100
	font_serif = load("res://assets/fonts/PlayfairDisplay-Regular.ttf")
	font_serif_italic = load("res://assets/fonts/PlayfairDisplay-Italic.ttf")
	font_ui = load("res://assets/fonts/Inter.ttf")
	_build_hud()
	_build_panel()
	_build_board()
	_build_timeline()
	_build_title()
	Story.clock_changed.connect(_update_clock)
	Story.flasks_changed.connect(_update_flasks)
	Story.state_changed.connect(_update_state)
	_update_flasks(Story.flasks)
	_update_state(Story.state)
	lbl_clock.text = Story.fmt_clock()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shift"):
		if not title_visible and Story.can_shift():
			shift_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("board"):
		if not title_visible:
			_toggle_board()
	elif event.is_action_pressed("advance"):
		if tl.visible:
			return
		if board.visible:
			board.visible = false
		elif title_visible:
			_start()
		elif line_idx < lines.size():
			_next_line()
		elif choices.get_child_count() == 1 and choices.get_child(0) is Button:
			var b: Button = choices.get_child(0)
			if not b.disabled:
				b.pressed.emit()
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var i: int = event.keycode - KEY_1
		if i < choices.get_child_count() and choices.get_child(i) is Button:
			var b: Button = choices.get_child(i)
			if not b.disabled and b.visible:
				b.pressed.emit()


# ---------------------------------------------------------------- build

func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(14)
	return s


func _build_hud() -> void:
	hud = HBoxContainer.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = 16
	hud.offset_right = -16
	hud.offset_top = 22
	hud.add_theme_constant_override("separation", 24)
	add_child(hud)
	lbl_clock = _hud_label("1:40 AM", AMBER)
	lbl_flasks = _hud_label("▮▮▮", AMBER)
	lbl_state = _hud_label("SOBER", AMBER)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)
	btn_board = _hud_button("BOARD  [E]")
	btn_board.pressed.connect(_toggle_board)
	btn_shift = _hud_button("⇧ DRINK")
	btn_shift.pressed.connect(_try_shift)


func _toggle_board() -> void:
	board.visible = not board.visible
	if board.visible:
		_refresh_board()


func _try_shift() -> void:
	if Story.can_shift():
		shift_requested.emit()


func _hud_label(t: String, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font_ui)
	l.add_theme_color_override("font_color", c)
	l.add_theme_font_size_override("font_size", 16)
	hud.add_child(l)
	return l


func _hud_button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.flat = true
	b.add_theme_font_override("font", font_ui)
	b.add_theme_color_override("font_color", AMBER)
	b.add_theme_font_size_override("font_size", 14)
	hud.add_child(b)
	return b


func _build_panel() -> void:
	# A dock pinned to the bottom that only takes the height it needs and grows upward:
	# choices on top, then one line of dialogue. The room stays visible above it.
	dock = VBoxContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left = 110
	dock.offset_right = -110
	dock.offset_bottom = -78
	dock.offset_top = -78
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.alignment = BoxContainer.ALIGNMENT_END
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_theme_constant_override("separation", 8)
	add_child(dock)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 4)
	choices.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(choices)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style("S"))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_panel_input)
	dock.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(96, 128)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.visible = false
	row.add_child(portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	lbl_loc = Label.new()
	lbl_loc.add_theme_font_override("font", font_ui)
	lbl_loc.add_theme_color_override("font_color", AMBER)
	lbl_loc.add_theme_font_size_override("font_size", 12)
	lbl_loc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lbl_loc)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(0, 64)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("normal_font", font_serif)
	text.add_theme_font_override("italics_font", font_serif_italic)
	text.add_theme_font_override("bold_font", font_serif)
	text.add_theme_font_size_override("normal_font_size", 21)
	text.add_theme_font_size_override("italics_font_size", 21)
	text.add_theme_color_override("default_color", TEXT)
	text.add_theme_constant_override("line_separation", 4)
	v.add_child(text)
	lbl_more = Label.new()
	lbl_more.text = "▸"
	lbl_more.add_theme_color_override("font_color", AMBER)
	lbl_more.add_theme_font_size_override("font_size", 16)
	lbl_more.size_flags_vertical = Control.SIZE_SHRINK_END
	lbl_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl_more)
	dock.visible = false


func _panel_style(state: String) -> StyleBoxFlat:
	var sb := _style(Color(0.035, 0.045, 0.06, 0.90) if state == "V" else Color(0.05, 0.04, 0.035, 0.90), Color(0.22, 0.42, 0.50, 0.9) if state == "V" else Color(0.42, 0.33, 0.20, 0.9))
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _on_panel_input(event: InputEvent) -> void:
	var click: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if click and line_idx < lines.size():
		_next_line()


func _build_board() -> void:
	board = PanelContainer.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 60
	board.offset_right = -60
	board.offset_top = 50
	board.offset_bottom = -50
	board.add_theme_stylebox_override("panel", _style(Color(0.05, 0.04, 0.035, 0.97), Color(0.3, 0.24, 0.16)))
	add_child(board)
	var v := VBoxContainer.new()
	board.add_child(v)
	var h := Label.new()
	h.text = "EVIDENCE BOARD"
	h.add_theme_color_override("font_color", MUTED)
	v.add_child(h)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	board_list = VBoxContainer.new()
	board_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_list.add_theme_constant_override("separation", 6)
	sc.add_child(board_list)
	var close := Button.new()
	close.text = "CLOSE  [Esc / Space]"
	close.pressed.connect(func(): board.visible = false)
	v.add_child(close)
	board.visible = false


func _build_timeline() -> void:
	tl = PanelContainer.new()
	tl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tl.offset_left = 60
	tl.offset_right = -60
	tl.offset_top = 50
	tl.offset_bottom = -50
	tl.add_theme_stylebox_override("panel", _style(Color(0.05, 0.04, 0.035, 0.97), Color(0.3, 0.24, 0.16)))
	add_child(tl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	tl.add_child(v)
	var h := Label.new()
	h.text = "THE TIMELINE  —  click the events in the order they happened"
	h.add_theme_color_override("font_color", MUTED)
	v.add_child(h)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 20)
	v.add_child(cols)
	var sc1 := ScrollContainer.new()
	sc1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(sc1)
	tl_pool = VBoxContainer.new()
	tl_pool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl_pool.add_theme_constant_override("separation", 6)
	sc1.add_child(tl_pool)
	var sc2 := ScrollContainer.new()
	sc2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(sc2)
	tl_line = VBoxContainer.new()
	tl_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl_line.add_theme_constant_override("separation", 6)
	sc2.add_child(tl_line)
	tl_msg = Label.new()
	tl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl_msg.add_theme_color_override("font_color", CYAN)
	v.add_child(tl_msg)
	tl.visible = false


func show_timeline() -> void:
	dock.visible = false
	board.visible = false
	tl.visible = true
	tl_order = []
	tl_msg.text = ""
	_tl_refresh()


func _tl_refresh() -> void:
	for c in tl_pool.get_children():
		c.queue_free()
	for c in tl_line.get_children():
		c.queue_free()
	var events: Array = Story.timeline["events"]
	# pool: shuffled deterministically by id so the order on screen is not the answer
	var pool: Array = events.duplicate()
	pool.sort_custom(func(a, b): return a["text"].length() < b["text"].length())
	for ev in pool:
		if tl_order.has(ev["id"]):
			continue
		var b := Button.new()
		b.text = ev["text"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_stylebox_override("normal", _style(Color(0.10, 0.08, 0.065), Color(0.22, 0.18, 0.13)))
		b.add_theme_stylebox_override("hover", _style(Color(0.13, 0.10, 0.08), AMBER))
		b.pressed.connect(_tl_pick.bind(ev["id"]))
		tl_pool.add_child(b)
	var i := 1
	for id in tl_order:
		for ev in events:
			if ev["id"] == id:
				var l := Label.new()
				l.text = "%d.  %s   %s" % [i, ev["time"], ev["text"]]
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.add_theme_color_override("font_color", TEXT)
				tl_line.add_child(l)
				i += 1


func _tl_pick(id: String) -> void:
	var events: Array = Story.timeline["events"]
	var expected: String = events[tl_order.size()]["id"]
	if id == expected:
		tl_order.append(id)
		tl_msg.text = ""
		if tl_order.size() == events.size():
			tl.visible = false
			Story.current_no_shift = false
			timeline_solved.emit()
			return
	else:
		var contra: Dictionary = Story.timeline["contradictions"]
		tl_msg.text = str(contra.get(id, "That's not it."))
		tl_order = []
	_tl_refresh()


func _build_title() -> void:
	# soft black falloff from the left so the type sits on darkness, not on the bar
	title_dim = ColorRect.new()
	title_dim.visible = false
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.88))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.set_offset(1, 0.62)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	title_shade = TextureRect.new()
	title_shade.texture = gt
	title_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_shade.stretch_mode = TextureRect.STRETCH_SCALE
	title_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_shade)
	title = MarginContainer.new()
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.add_theme_constant_override("margin_left", 84)
	title.add_theme_constant_override("margin_right", 40)
	title.add_theme_constant_override("margin_top", 96)
	title.add_theme_constant_override("margin_bottom", 96)
	add_child(title)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.add_child(v)
	var k := Label.new()
	k.text = "A   F R A N K   S A B L E   M Y S T E R Y"
	k.add_theme_font_override("font", font_ui)
	k.add_theme_font_size_override("font_size", 12)
	k.add_theme_color_override("font_color", Color(0.62, 0.55, 0.46))
	v.add_child(k)
	var t := Label.new()
	t.text = "On the Rocks"
	t.add_theme_font_override("font", font_serif)
	t.add_theme_font_size_override("font_size", 84)
	t.add_theme_color_override("font_color", Color(0.95, 0.90, 0.82))
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("shadow_offset_y", 3)
	v.add_child(t)
	var t2 := Label.new()
	t2.text = "The Last Shift"
	t2.add_theme_font_override("font", font_serif_italic)
	t2.add_theme_font_size_override("font_size", 44)
	t2.add_theme_color_override("font_color", Color(1.0, 0.36, 0.46))
	t2.add_theme_color_override("font_shadow_color", Color(0.9, 0.05, 0.2, 0.45))
	t2.add_theme_constant_override("shadow_offset_y", 0)
	t2.add_theme_constant_override("shadow_outline_size", 14)
	v.add_child(t2)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	v.add_child(gap)
	var p := Label.new()
	p.text = "One bar. One body. One detective who is useless sober\nand brilliant drunk. Solve it twice."
	p.add_theme_font_override("font", font_serif)
	p.add_theme_font_size_override("font_size", 19)
	p.add_theme_color_override("font_color", Color(0.78, 0.72, 0.63))
	v.add_child(p)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 26)
	v.add_child(gap2)
	var b := Button.new()
	b.text = "BEGIN THE NIGHT"
	b.add_theme_font_override("font", font_ui)
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_color_override("font_color", Color(0.95, 0.90, 0.82))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.55))
	var sb := _style(Color(0, 0, 0, 0.35), Color(0.95, 0.90, 0.82, 0.55))
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.set_corner_radius_all(2)
	var sbh := _style(Color(0.25, 0.03, 0.07, 0.55), Color(1.0, 0.36, 0.46))
	sbh.content_margin_left = 28
	sbh.content_margin_right = 28
	sbh.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_start)
	v.add_child(b)
	var seen := Label.new()
	seen.name = "Seen"
	seen.add_theme_font_override("font", font_serif_italic)
	seen.add_theme_font_size_override("font_size", 14)
	seen.add_theme_color_override("font_color", Color(0.62, 0.55, 0.46))
	v.add_child(seen)
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0, 30)
	v.add_child(gap3)
	var c := Label.new()
	c.text = "SPACE advance   ·   1–9 choose   ·   SHIFT shift   ·   E evidence   ·   click the room to look\nGAME OFF 2026  ·  SHIFT"
	c.add_theme_font_override("font", font_ui)
	c.add_theme_font_size_override("font_size", 11)
	c.add_theme_color_override("font_color", Color(0.48, 0.43, 0.37))
	v.add_child(c)


# ---------------------------------------------------------------- flow

func show_title() -> void:
	title_visible = true
	title.visible = true
	title_shade.visible = true
	hud.visible = false
	title.modulate.a = 0.0
	create_tween().tween_property(title, "modulate:a", 1.0, 1.8)
	dock.visible = false
	board.visible = false
	tl.visible = false
	var seen: Label = title.find_child("Seen", true, false)
	if seen:
		var n: Array = Story.endings_seen
		if n.has("ending_tell") and n.has("ending_stand"):
			seen.text = "You have told them, and you have let it stand. There is nothing left to choose."
		elif n.has("ending_tell"):
			seen.text = "Last time, you told them."
		elif n.has("ending_stand"):
			seen.text = "Last time, you let it stand."
		else:
			seen.text = ""


func _start() -> void:
	title_visible = false
	title.visible = false
	title_shade.visible = false
	hud.visible = true
	choice_made.emit({"next": "ch1_wake", "shiftTo": ""})


func show_scene(id: String) -> void:
	scene_id = id
	lines = Story.visible_lines(id)
	line_idx = 0
	dock.visible = true
	board.visible = false
	_next_line()


func _next_line() -> void:
	_clear_choices()
	var sc: Dictionary = Story.scenes[scene_id]
	if bool(sc.get("hub", false)):
		_show_hub()
		return
	if line_idx < lines.size():
		var l: Dictionary = lines[line_idx]
		line_idx += 1
		panel.visible = true
		_show_line(l)
		var vo := str(l.get("vo", ""))
		line_voice.emit(vo)
		if line_idx > 1 and vo == "":
			line_advanced.emit()
		lbl_more.visible = line_idx < lines.size()
		if line_idx >= lines.size():
			_finish_scene()
	else:
		panel.visible = lines.size() > 0
		lbl_more.visible = false
		_finish_scene()


## Portraits are optional: assets/portraits/<who>.png (mira, theo, lenny, connie, frank).
func _set_portrait(who: String) -> void:
	if not portrait_cache.has(who):
		var path := "res://assets/portraits/%s.png" % who
		portrait_cache[who] = load(path) if ResourceLoader.exists(path) else null
	var tex: Texture2D = portrait_cache[who]
	portrait.texture = tex
	portrait.visible = tex != null
	portrait.modulate = Color(0.75, 0.95, 1.0) if Story.state == "V" else Color(1.0, 0.92, 0.82)


## One line at a time. The box holds the speaker and what they said, nothing else.
func _show_line(l: Dictionary) -> void:
	var who: String = l["who"]
	var t: String = str(l["text"]).replace("[", "[lb]")
	text.clear()
	if bool(l.get("card", false)):
		portrait.visible = false
		lbl_loc.text = ""
		lbl_loc.visible = false
		text.append_text("[center][font_size=30]%s[/font_size][/center]" % t)
		return
	lbl_loc.visible = true
	match who:
		"narr":
			portrait.visible = false
			lbl_loc.text = str(Story.scenes[scene_id].get("loc", "")).to_upper()
			lbl_loc.add_theme_color_override("font_color", MUTED)
			text.append_text("[color=#d8cdb8]%s[/color]" % t)
		"voice":
			_set_portrait("frank")   # the Voice wears Frank's face, lit cold
			lbl_loc.text = "THE VOICE"
			lbl_loc.add_theme_color_override("font_color", CYAN)
			text.append_text("[i][color=#8fe0ee]%s[/color][/i]" % t)
		_:
			_set_portrait(who)
			lbl_loc.text = WHO.get(who, who.to_upper())
			lbl_loc.add_theme_color_override("font_color", AMBER)
			text.append_text(t)


func _show_hub() -> void:
	line_idx = lines.size()
	panel.visible = false
	line_voice.emit("")
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	choices.add_child(bar)
	var hint := Label.new()
	hint.text = "Click a person or a place.  Each stop costs ten minutes."
	hint.add_theme_font_override("font", font_ui)
	hint.add_theme_color_override("font_color", TEXT)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("shadow_outline_size", 6)
	bar.add_child(hint)
	var acc := _choice_button("Stop looking — make an accusation")
	choices.remove_child(acc)
	bar.add_child(acc)
	acc.pressed.connect(func(): choice_made.emit({"next": "accuse", "shiftTo": ""}))


func _finish_scene() -> void:
	var sc: Dictionary = Story.scenes[scene_id]
	for e in Story.scene_evidence(scene_id):
		text.append_text("\n[color=#e0aa45][font_size=14]◆ EVIDENCE   %s[/font_size][/color]" % str(Story.evidence[e]["t"]).replace("[", "[lb]"))
	_clear_choices()
	var i := 1
	for c in Story.visible_choices(scene_id):
		var label: String = "%d   %s" % [i, c["label"]]
		if c.get("small", "") != "":
			label += "   ·   " + c["small"]
		var b := _choice_button(label)
		if bool(c.get("requiresTrue", false)) and not Story.true_unlocked():
			b.disabled = true
			b.text += "   [locked: %s]" % Story.true_progress()
		if c["next"] == "__restart":
			b.pressed.connect(func(): restart_requested.emit())
		else:
			b.pressed.connect(func(): choice_made.emit(c))
		i += 1


func _choice_button(t: String, subtle: bool = false) -> Button:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font_ui)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", MUTED if subtle else TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var accent := CYAN if Story.state == "V" else AMBER
	var n := _style(Color(0.04, 0.035, 0.03, 0.86), Color(0.30, 0.25, 0.18, 0.8))
	var h := _style(Color(0.10, 0.08, 0.06, 0.95), accent)
	var dd := _style(Color(0.04, 0.035, 0.03, 0.6), Color(0.16, 0.14, 0.11, 0.6))
	for sb in [n, h, dd]:
		sb.set_corner_radius_all(3)
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		sb.content_margin_left = 16
		sb.content_margin_right = 20
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", dd)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	choices.add_child(b)
	return b


func _clear_choices() -> void:
	for c in choices.get_children():
		choices.remove_child(c)
		c.queue_free()


func _update_clock(_m: int) -> void:
	lbl_clock.text = Story.fmt_clock()


func _update_flasks(n: int) -> void:
	lbl_flasks.text = "▮".repeat(n) + "▯".repeat(Story.FLASKS - n)


func _update_state(s: String) -> void:
	var c := CYAN if s == "V" else AMBER
	lbl_state.text = "THE VOICE" if s == "V" else "SOBER"
	lbl_state.add_theme_color_override("font_color", c)
	lbl_clock.add_theme_color_override("font_color", c)
	lbl_flasks.add_theme_color_override("font_color", c)
	btn_shift.text = "⇧ SOBER UP  (+30 min)" if s == "V" else "⇧ DRINK"
	btn_shift.add_theme_color_override("font_color", c)
	btn_board.add_theme_color_override("font_color", c)
	panel.add_theme_stylebox_override("panel", _panel_style(s))


func _refresh_board() -> void:
	for c in board_list.get_children():
		c.queue_free()
	for k in Story.evidence.keys():
		var e: Dictionary = Story.evidence[k]
		var have: bool = Story.found.has(k)
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tag := "[color=#70d3e6]VOICE[/color]" if e["s"] == "V" else "[color=#f2c97a]SOBER[/color]"
		var body := str(e["t"]).replace("[", "[lb]") if have else "— — —"
		l.append_text("[font_size=11]%s[/font_size]   %s" % [tag, body])
		l.modulate = Color(1, 1, 1, 1.0 if have else 0.35)
		board_list.add_child(l)
