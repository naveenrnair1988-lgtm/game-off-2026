extends Node3D
## Main — builds THE LAST CALL in 3D from primitives, owns the camera,
## hotspots and lighting, and drives story flow through the UI layer.
## Everything is procedural so the project opens clean with zero assets;
## replace the primitive props with GLB models in assets/models/ as they land.

@onready var cam: Camera3D = $Camera
@onready var ui: CanvasLayer = $UI

var current_scene: String = ""
var in_hub: bool = false
var hotspots: Array[Area3D] = []
var env: Environment
var lights: Array[Light3D] = []
var cam_tween: Tween
var clue_meshes: Array[MeshInstance3D] = []   # props that glow in Voice state
var post_mat: ShaderMaterial
var headlight: OmniLight3D
var headlights_on: bool = false
var in_title: bool = false
var title_key: SpotLight3D
var neon_light: OmniLight3D
var music: AudioStreamPlayer
const MUSIC_TITLE_DB := -6.0
const MUSIC_GAME_DB := -20.0
var post_layer: CanvasLayer
var cam_base: Transform3D
var sway_t: float = 0.0
var tex_wood: Texture2D
var tex_wood_n: Texture2D
var tex_floor: Texture2D
var tex_floor_n: Texture2D
var tex_wall: Texture2D
var tex_leather_n: Texture2D

## Drop GLB files here (assets/models/<name>.glb) and they replace the primitive at that slot.
## [position on the floor, y-rotation in degrees, target size in metres, axis the size applies to].
## Models are auto-fitted: whatever units or origin the file has, it is scaled to the target
## size, centred on the slot and stood on the floor. Size 0 = use the file as-is.
## If a model faces the wrong way, change only the rotation here.
const MODEL_SLOTS := {
	"bar_counter": [Vector3(0.0, 0.0, -2.55), 0.0, 0.0, "y"],
	"back_bar":    [Vector3(0.0, 0.0, -4.0), 0.0, 0.0, "y"],
	"jukebox":     [Vector3(-4.75, 0.0, -1.2), 90.0, 1.5, "y"],
	"booth":       [Vector3(-4.0, 0.0, 2.5), 0.0, 0.0, "y"],
	"body":        [Vector3(1.0, 0.0, -3.1), 0.0, 1.8, "long"],
	"stool":       [Vector3(0.0, 0.0, -1.9), 0.0, 0.8, "y"],
	"frank":       [Vector3(0.0, 0.0, 1.9), 180.0, 1.8, "y"],
	"mira":        [Vector3(0.0, 0.0, -3.25), 90.0, 1.2, "y"],
	"theo":        [Vector3(0.0, 0.0, 3.6), 180.0, 1.78, "y"],
	"lenny":       [Vector3(-2.0, 0.0, 0.4), 40.0, 1.75, "y"],
	"connie":      [Vector3(3.0, 0.0, -1.9), -30.0, 1.45, "y"],
}

# Camera stations: [position, look_at]
const STATIONS := {
	"title":  [Vector3(-3.25, 1.34, -2.12), Vector3(4.5, 1.62, -2.62)],
	"hub":    [Vector3(0.0, 1.7, 2.6),  Vector3(0.0, 1.1, -2.5)],
	"booth":  [Vector3(-2.2, 1.5, 2.4), Vector3(-4.2, 0.9, 2.5)],
	"bar":    [Vector3(2.9, 2.0, -3.3), Vector3(1.0, 0.15, -3.1)],
	"floor":  [Vector3(2.0, 1.5, -0.2), Vector3(3.2, 0.5, -2.2)],
	"office": [Vector3(3.2, 1.6, -1.0), Vector3(4.6, 1.2, -1.0)],
	"mira":   [Vector3(3.3, 1.55, -3.35), Vector3(0.5, 0.55, -3.15)],
	"theo":   [Vector3(0.0, 1.6, 1.2),  Vector3(0.0, 1.3, 3.9)],
	"lenny":  [Vector3(-0.3, 1.6, 2.0), Vector3(-2.0, 1.3, 0.4)],
	"connie": [Vector3(1.6, 1.6, -0.4), Vector3(3.0, 1.1, -1.9)],
}

# Scene id prefix → station
const SCENE_STATION := {
	"ch1_wake": "booth", "ch1_body": "bar", "ch1_mira1": "mira", "ch1_others": "hub",
	"ch1_drink": "hub", "ch1_voice": "hub", "hub": "hub",
	"loc_booth": "booth", "loc_bar": "bar", "loc_floor": "floor", "loc_office": "office",
	"int_mira": "mira", "int_theo": "theo", "int_lenny": "lenny", "int_connie": "connie",
	"accuse": "hub",
	"ch4_blackout": "connie", "ch4_drink": "floor", "ch4_connie": "connie", "ch4_sober": "office",
	"ch5_intro": "office", "ch5_silence": "office",
	"end_true": "hub", "end_true_tell": "hub", "end_true_stand": "hub",
}

# Hotspots in the hub: name, scene id, position, size
const HOTSPOTS := [
	["The booth", "loc_booth", Vector3(-4.0, 0.6, 2.5), Vector3(1.4, 1.2, 1.6)],
	["Behind the bar", "loc_bar", Vector3(1.0, 0.3, -3.1), Vector3(1.6, 0.6, 0.8)],
	["The rail", "loc_floor", Vector3(2.6, 0.3, -2.1), Vector3(1.6, 0.6, 0.4)],
	["The office", "loc_office", Vector3(4.7, 1.0, -1.0), Vector3(0.3, 2.0, 1.0)],
	["Mira", "int_mira", Vector3(0.2, 0.6, -3.1), Vector3(0.6, 1.2, 0.6)],
	["Theo", "int_theo", Vector3(0.0, 0.9, 3.6), Vector3(0.6, 1.8, 0.6)],
	["Lenny", "int_lenny", Vector3(-2.0, 0.9, 0.4), Vector3(0.6, 1.8, 0.6)],
	["Connie", "int_connie", Vector3(3.0, 0.9, -1.9), Vector3(0.6, 1.8, 0.6)],
]

# Palettes
const SOBER := {
	"bg": Color(0.04, 0.035, 0.03), "ambient": Color(0.30, 0.23, 0.16), "ambient_energy": 0.7,
	"fog": Color(0.07, 0.05, 0.04), "fog_density": 0.008,
	"light": Color(1.0, 0.78, 0.52), "light_energy": 4.5,
}
## Title screen: the bar after close. Almost everything is off except one lamp and the neon.
const TITLE := {
	"bg": Color(0.012, 0.01, 0.014), "ambient": Color(0.10, 0.07, 0.09), "ambient_energy": 0.22,
	"fog": Color(0.05, 0.03, 0.045), "fog_density": 0.03,
	"light": Color(1.0, 0.70, 0.42), "light_energy": 0.55,
}
const VOICE := {
	"bg": Color(0.02, 0.04, 0.06), "ambient": Color(0.20, 0.38, 0.45), "ambient_energy": 1.1,
	"fog": Color(0.04, 0.10, 0.14), "fog_density": 0.045,
	"light": Color(0.50, 0.88, 1.0), "light_energy": 2.4,
}


func _ready() -> void:
	_build_textures()
	_build_room()
	_load_models()
	_build_lighting()
	_build_hotspots()
	_build_post()
	ui.choice_made.connect(_on_choice)
	ui.back_requested.connect(func(): go("hub"))
	ui.restart_requested.connect(func(): go("__restart"))
	ui.shift_requested.connect(func(): Story.shift())
	ui.timeline_solved.connect(func(): go("ch5_silence"))
	Story.state_changed.connect(_on_state_changed)
	Story.timed_out.connect(func(): call_deferred("go", "end_timeout"))
	_build_title_set()
	_build_music()
	_enter_title()


func _process(delta: float) -> void:
	# slow handheld breathing on the camera, on top of whatever station it is at
	sway_t += delta
	if in_title:
		# very slow push down the bar
		var st: Array = STATIONS["title"]
		var drift := Vector3(sin(sway_t * 0.07) * 0.35, sin(sway_t * 0.05) * 0.03, 0.0)
		cam.position = st[0] + drift
		cam.look_at(st[1], Vector3.UP)
		cam_base = cam.transform
	if cam_tween == null or not cam_tween.is_running():
		var t := cam_base
		t.origin += Vector3(sin(sway_t * 0.37) * 0.012, sin(sway_t * 0.61) * 0.009, 0.0)
		t.basis = cam_base.basis.rotated(cam_base.basis.x, sin(sway_t * 0.43) * 0.0025).rotated(Vector3.UP, sin(sway_t * 0.29) * 0.003)
		cam.transform = t
	if post_mat:
		post_mat.set_shader_parameter("time_seed", fmod(sway_t, 100.0))


# ---------------------------------------------------------------- flow

func go(id: String) -> void:
	if id == "__timeline":
		Story.current_no_shift = true
		ui.show_timeline()
		return
	if id == "hub" and Story.ch4_due():
		id = "ch4_blackout"
	if id == "__restart":
		_set_headlights(false)
		Story.reset()
		_set_hub(false)
		_enter_title()
		return
	if not Story.scenes.has(id):
		push_error("No scene: " + id)
		return
	if Story.over and not bool(Story.scenes[id].get("ending", false)):
		return  # the night is over; only endings may play
	if not Story.enter_scene(id):
		return  # timed_out signal routes to end_timeout
	current_scene = id
	var sc: Dictionary = Story.scenes[id]
	Story.current_no_shift = bool(sc.get("noShift", false))
	_set_headlights(id == "accuse" or id == "end_true" or id == "end_timeout")
	_set_hub(bool(sc.get("hub", false)))
	_move_camera(SCENE_STATION.get(id, "hub"))
	Story.grant_evidence(id)
	ui.show_scene(id)


func _on_choice(choice: Dictionary) -> void:
	if in_title:
		_leave_title()
	if choice.get("shiftTo", "") != "":
		Story.shift_forced(choice["shiftTo"])
	go(choice["next"])


func _on_state_changed(s: String) -> void:
	_apply_palette(VOICE if s == "V" else SOBER, 0.8)
	_refresh_hotspot_labels()
	_refresh_clue_glow()
	if post_mat:
		var t := create_tween()
		t.tween_method(func(v): post_mat.set_shader_parameter("voice", v), float(post_mat.get_shader_parameter("voice")), 1.0 if s == "V" else 0.0, 0.8)
	if current_scene != "" and not ui.title_visible:
		Story.grant_evidence(current_scene)
		ui.show_scene(current_scene)  # re-read the room in the new state


# ---------------------------------------------------------------- camera

func _move_camera(station: String) -> void:
	var st: Array = STATIONS[station]
	if cam_tween:
		cam_tween.kill()
	var target := Transform3D().looking_at(st[1] - st[0], Vector3.UP)
	target.origin = st[0]
	cam_base = target
	cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam_tween.tween_property(cam, "transform", target, 1.1)


func _snap_camera(station: String) -> void:
	var st: Array = STATIONS[station]
	cam.position = st[0]
	cam.look_at(st[1], Vector3.UP)
	cam_base = cam.transform


# ---------------------------------------------------------------- title screen

func _enter_title() -> void:
	in_title = true
	current_scene = ""
	_apply_palette(TITLE, 0.0)
	if post_mat:
		post_mat.set_shader_parameter("voice", 0.0)
	title_key.light_energy = 9.0
	neon_light.light_energy = 2.3
	_snap_camera("title")
	if music and music.stream and not music.playing:
		music.play()
	if music:
		music.volume_db = MUSIC_TITLE_DB
	ui.show_title()


func _leave_title() -> void:
	in_title = false
	_apply_palette(SOBER, 2.0)
	var t := create_tween().set_parallel(true)
	t.tween_property(title_key, "light_energy", 0.0, 2.0)
	t.tween_property(neon_light, "light_energy", 0.9, 2.0)
	if music:
		t.tween_property(music, "volume_db", MUSIC_GAME_DB, 3.0)


func _build_music() -> void:
	music = AudioStreamPlayer.new()
	music.name = "Music"
	add_child(music)
	for path in ["res://assets/audio/theme.ogg", "res://assets/audio/theme.mp3"]:
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream is AudioStreamMP3:
				(stream as AudioStreamMP3).loop = true
			elif stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			music.stream = stream
			break


## Props that sell the title shot and stay in the room afterwards:
## the neon sign, a last drink on the bar, one lamp left on.
func _build_title_set() -> void:
	# neon sign on the far wall, dead ahead down the bar
	var sign := Label3D.new()
	sign.name = "Neon"
	sign.text = "The Last Call"
	sign.font = load("res://assets/fonts/PlayfairDisplay-Italic.ttf")
	sign.font_size = 150
	sign.pixel_size = 0.0027
	sign.modulate = Color(1.0, 0.62, 0.68)
	sign.outline_modulate = Color(1.0, 0.10, 0.28, 0.7)
	sign.outline_size = 26
	sign.position = Vector3(5.06, 2.25, -2.75)
	sign.rotation_degrees.y = -90.0
	add_child(sign)
	neon_light = OmniLight3D.new()
	neon_light.position = Vector3(4.55, 2.2, -2.75)
	neon_light.light_color = Color(1.0, 0.22, 0.38)
	neon_light.omni_range = 6.5
	neon_light.omni_attenuation = 1.3
	neon_light.light_energy = 0.9
	add_child(neon_light)
	# the last drink: rocks glass, whisky, one ice cube, the bottle behind it
	var gp := Vector3(-2.45, 1.15, -2.38)
	var glass := _cyl(gp + Vector3(0, 0.05, 0), 0.042, 0.10, Color(0.85, 0.92, 1.0, 0.22), 0.03)
	(glass.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var whisky := _cyl(gp + Vector3(0, 0.03, 0), 0.037, 0.045, Color(0.80, 0.42, 0.08, 0.85), 0.05)
	var wm := whisky.material_override as StandardMaterial3D
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.emission_enabled = true
	wm.emission = Color(0.9, 0.45, 0.08)
	wm.emission_energy_multiplier = 0.35
	var ice := _box(gp + Vector3(0.005, 0.055, 0.004), Vector3(0.036, 0.036, 0.036), Color(0.9, 0.95, 1.0, 0.5), 0.05)
	ice.rotation_degrees = Vector3(18, 30, 12)
	(ice.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cyl(gp + Vector3(0.42, 0.13, -0.16), 0.043, 0.26, Color(0.16, 0.08, 0.03), 0.12)
	_cyl(gp + Vector3(0.42, 0.31, -0.16), 0.016, 0.10, Color(0.16, 0.08, 0.03), 0.12)
	_box(gp + Vector3(0.42, 0.13, -0.116), Vector3(0.06, 0.09, 0.004), Color(0.82, 0.76, 0.62), 0.9)
	# a coaster and Danny's tab book
	_cyl(gp + Vector3(0, 0.003, 0), 0.06, 0.006, Color(0.55, 0.12, 0.10), 0.9)
	_box(gp + Vector3(0.9, 0.015, 0.05), Vector3(0.22, 0.03, 0.15), Color(0.10, 0.22, 0.14), 0.7)
	# one lamp left on over the drink
	title_key = SpotLight3D.new()
	title_key.position = gp + Vector3(0.15, 1.5, 0.25)
	title_key.rotation_degrees = Vector3(-84, 0, 0)
	title_key.light_color = Color(1.0, 0.74, 0.42)
	title_key.spot_range = 4.0
	title_key.spot_angle = 26.0
	title_key.spot_angle_attenuation = 1.6
	title_key.shadow_enabled = true
	title_key.light_energy = 0.0
	add_child(title_key)


# ---------------------------------------------------------------- headlights

## The police arriving: the front window flares and a cold light sweeps the room.
func _set_headlights(on: bool) -> void:
	if on == headlights_on or headlight == null:
		return
	headlights_on = on
	var win := get_node_or_null("Window") as MeshInstance3D
	var t := create_tween().set_parallel(true)
	t.tween_property(headlight, "light_energy", 6.0 if on else 0.0, 1.6 if on else 0.4)
	if on:
		headlight.position.x = -4.6
		t.tween_property(headlight, "position:x", -1.6, 2.4).set_trans(Tween.TRANS_SINE)
	if win:
		var m: StandardMaterial3D = win.material_override
		m.emission_enabled = true
		m.emission = Color(0.8, 0.9, 1.0)
		t.tween_property(m, "emission_energy_multiplier", 4.0 if on else 0.0, 1.6 if on else 0.4)


# ---------------------------------------------------------------- post-process

func _build_post() -> void:
	post_layer = CanvasLayer.new()
	post_layer.layer = 50   # above the 3D view, below the UI (UI CanvasLayer is 100)
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	post_mat.set_shader_parameter("voice", 0.0)
	rect.material = post_mat
	post_layer.add_child(rect)


# ---------------------------------------------------------------- models

func _load_models() -> void:
	for slot in MODEL_SLOTS.keys():
		var path := "res://assets/models/%s.glb" % slot
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var inst: Node3D = scene.instantiate()
		var cfg: Array = MODEL_SLOTS[slot]
		var pivot := Node3D.new()
		pivot.name = "Model_" + slot
		pivot.position = cfg[0]
		pivot.rotation_degrees.y = cfg[1]
		pivot.add_child(inst)
		_fit_model(inst, float(cfg[2]), str(cfg[3]))
		add_child(pivot)
		# hide the primitive placeholder(s) for this slot
		for c in get_children():
			if c.name == "PH_" + slot or str(c.name).begins_with("PH_" + slot + "_"):
				c.visible = false


## Bounding box of every mesh under `n`, in the space of `n`'s parent.
func _model_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var box: AABB = here * (n as MeshInstance3D).get_aabb()
		if acc.is_empty():
			acc.append(box)
		else:
			acc[0] = (acc[0] as AABB).merge(box)
	for c in n.get_children():
		_model_aabb(c, here, acc)


## Scale to the target size, centre on the pivot, stand on the floor.
func _fit_model(inst: Node3D, target: float, axis: String) -> void:
	if target <= 0.0:
		return
	inst.transform = Transform3D.IDENTITY
	var acc: Array = []
	_model_aabb(inst, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		return
	var box: AABB = acc[0]
	var extent: float = box.size.y if axis == "y" else maxf(box.size.x, box.size.z)
	if extent <= 0.0001:
		return
	var k := target / extent
	var centre := box.get_center()
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-centre.x * k, -box.position.y * k, -centre.z * k)


# ---------------------------------------------------------------- hotspots

func _build_hotspots() -> void:
	for h in HOTSPOTS:
		var a := Area3D.new()
		a.name = "Hotspot_" + str(h[1])
		a.position = h[2]
		a.set_meta("scene_id", h[1])
		a.set_meta("label", h[0])
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = h[3]
		cs.shape = box
		a.add_child(cs)
		var lbl := Label3D.new()
		lbl.name = "Label"
		lbl.text = h[0]
		lbl.position = Vector3(0, h[3].y * 0.5 + 0.25, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 40
		lbl.pixel_size = 0.004
		lbl.outline_size = 8
		lbl.no_depth_test = true
		a.add_child(lbl)
		a.input_event.connect(_on_hotspot_input.bind(a))
		a.mouse_entered.connect(func(): _set_label_hot(a, true))
		a.mouse_exited.connect(func(): _set_label_hot(a, false))
		add_child(a)
		hotspots.append(a)
	_set_hub(false)


func _on_hotspot_input(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, area: Area3D) -> void:
	if not in_hub:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go(area.get_meta("scene_id"))
	elif event is InputEventScreenTouch and event.pressed:
		go(area.get_meta("scene_id"))


func _set_hub(on: bool) -> void:
	in_hub = on
	for a in hotspots:
		a.input_ray_pickable = on
		a.get_node("Label").visible = on


func _set_label_hot(a: Area3D, hot: bool) -> void:
	var lbl: Label3D = a.get_node("Label")
	lbl.modulate = (Color(1, 1, 1) if hot else _label_color())


func _label_color() -> Color:
	return Color(0.45, 0.85, 1.0) if Story.state == "V" else Color(0.85, 0.64, 0.25)


func _refresh_hotspot_labels() -> void:
	for a in hotspots:
		a.get_node("Label").modulate = _label_color()


# ---------------------------------------------------------------- lighting

func _build_lighting() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# three pendant lights over the bar, one over the booth, one in the office
	for p in [Vector3(-2.2, 2.6, -2.4), Vector3(0.0, 2.6, -2.4), Vector3(2.2, 2.6, -2.4), Vector3(-4.0, 2.4, 2.5), Vector3(4.4, 2.4, -1.0)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 8.0
		l.omni_attenuation = 1.1
		l.shadow_enabled = true
		add_child(l)
		lights.append(l)
		# visible bulb
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		bulb.mesh = sm
		bulb.position = p
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		m.emission = Color(1.0, 0.85, 0.6)
		m.emission_energy_multiplier = 3.0
		bulb.material_override = m
		add_child(bulb)


func _apply_palette(p: Dictionary, dur: float) -> void:
	if dur <= 0.0:
		env.background_color = p["bg"]
		env.ambient_light_color = p["ambient"]
		env.ambient_light_energy = p["ambient_energy"]
		env.fog_light_color = p["fog"]
		env.fog_density = p["fog_density"]
		for l in lights:
			l.light_color = p["light"]
			l.light_energy = p["light_energy"]
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(env, "background_color", p["bg"], dur)
	t.tween_property(env, "ambient_light_color", p["ambient"], dur)
	t.tween_property(env, "ambient_light_energy", p["ambient_energy"], dur)
	t.tween_property(env, "fog_light_color", p["fog"], dur)
	t.tween_property(env, "fog_density", p["fog_density"], dur)
	for l in lights:
		t.tween_property(l, "light_color", p["light"], dur)
		t.tween_property(l, "light_energy", p["light_energy"], dur)


# ---------------------------------------------------------------- clue glow

func _clue(mi: MeshInstance3D) -> MeshInstance3D:
	clue_meshes.append(mi)
	return mi


func _refresh_clue_glow() -> void:
	var on := Story.state == "V"
	for mi in clue_meshes:
		var m: StandardMaterial3D = mi.material_override
		m.emission_enabled = on
		m.emission = Color(0.45, 0.85, 1.0)
		m.emission_energy_multiplier = 1.6 if on else 0.0


# ---------------------------------------------------------------- textures

func _noise_tex(seed_: int, freq: float, octaves: int, w: int, h: int, as_normal: bool = false, strength: float = 4.0) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = w
	t.height = h
	t.seamless = true
	t.as_normal_map = as_normal
	t.bump_strength = strength
	if not as_normal:
		# keep albedo variation subtle: 0.62 .. 1.0 so colour stays colour
		var g := Gradient.new()
		g.set_color(0, Color(0.62, 0.62, 0.62))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		t.color_ramp = g
	return t


func _build_textures() -> void:
	# wood grain: stretched noise reads as planks
	tex_wood = _noise_tex(7, 0.012, 4, 512, 128)
	tex_wood_n = _noise_tex(7, 0.012, 4, 512, 128, true, 3.0)
	tex_floor = _noise_tex(21, 0.05, 3, 256, 256)
	tex_floor_n = _noise_tex(21, 0.05, 3, 256, 256, true, 6.0)
	tex_wall = _noise_tex(33, 0.03, 5, 256, 256)
	tex_leather_n = _noise_tex(44, 0.2, 2, 128, 128, true, 2.0)


func _mat_tex(c: Color, albedo: Texture2D, normal: Texture2D, rough: float, metal: float, uv: Vector3, tex_mix: float = 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = albedo
	m.roughness = rough
	m.metallic = metal
	m.uv1_scale = uv
	m.uv1_triplanar = true
	m.normal_enabled = normal != null
	m.normal_texture = normal
	m.normal_scale = 0.8
	# darken albedo by the noise so the colour is still the colour
	m.detail_enabled = false
	return m


# ---------------------------------------------------------------- room

func _mat(c: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _tbox(pos: Vector3, size: Vector3, m: Material, name_: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = m
	if name_ != "":
		mi.name = name_
	add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, c: Color, rough: float = 0.9, metal: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c, rough, metal)
	add_child(mi)
	return mi


func _cyl(pos: Vector3, radius: float, height: float, c: Color, rough: float = 0.6, metal: float = 0.0, rot_z: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.position = pos
	mi.rotation.z = rot_z
	mi.material_override = _mat(c, rough, metal)
	add_child(mi)
	return mi


func _person(pos: Vector3, c: Color, height: float = 1.75, slot: String = "") -> void:
	var mi := MeshInstance3D.new()
	if slot != "":
		mi.name = "PH_" + slot
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = height
	mi.mesh = cap
	mi.position = pos + Vector3(0, height * 0.5, 0)
	mi.material_override = _mat(c, 0.95)
	add_child(mi)


func _build_room() -> void:
	var wood := Color(0.24, 0.15, 0.09)
	var dark := Color(0.11, 0.08, 0.06)
	var wall := Color(0.30, 0.22, 0.16)
	var brass := Color(0.78, 0.60, 0.25)
	var cloth := Color(0.55, 0.52, 0.48)
	var m_floor := _mat_tex(Color(0.20, 0.15, 0.11), tex_floor, tex_floor_n, 0.55, 0.0, Vector3(2.0, 2.0, 2.0))
	var m_wall := _mat_tex(Color(0.30, 0.21, 0.14), tex_wall, null, 0.95, 0.0, Vector3(1.5, 1.5, 1.5))
	var m_wood := _mat_tex(Color(0.30, 0.18, 0.10), tex_wood, tex_wood_n, 0.45, 0.0, Vector3(0.6, 2.4, 0.6))
	var m_wood_dark := _mat_tex(Color(0.17, 0.10, 0.06), tex_wood, tex_wood_n, 0.5, 0.0, Vector3(0.6, 2.4, 0.6))
	var m_leather := _mat_tex(Color(0.38, 0.09, 0.07), null, tex_leather_n, 0.7, 0.0, Vector3(3.0, 3.0, 3.0))
	# floor and ceiling
	_tbox(Vector3(0, -0.05, 0), Vector3(10.4, 0.1, 8.4), m_floor)
	_box(Vector3(0, 3.25, 0), Vector3(10.4, 0.1, 8.4), Color(0.08, 0.06, 0.05))
	# ceiling beams
	for z in [-2.8, -1.4, 0.0, 1.4, 2.8]:
		_tbox(Vector3(0, 3.1, z), Vector3(10.4, 0.2, 0.18), m_wood_dark)
	# walls, with wainscot
	_tbox(Vector3(0, 1.6, -4.2), Vector3(10.4, 3.2, 0.2), m_wall)      # back wall
	_tbox(Vector3(0, 1.6, 4.2), Vector3(10.4, 3.2, 0.2), m_wall)       # front wall
	_tbox(Vector3(-5.2, 1.6, 0), Vector3(0.2, 3.2, 8.4), m_wall)       # left
	_tbox(Vector3(5.2, 1.6, 0), Vector3(0.2, 3.2, 8.4), m_wall)        # right
	_tbox(Vector3(0, 0.5, 4.08), Vector3(10.4, 1.0, 0.04), m_wood_dark)
	_tbox(Vector3(-5.08, 0.5, 0), Vector3(0.04, 1.0, 8.4), m_wood_dark)
	_tbox(Vector3(5.08, 0.5, 0), Vector3(0.04, 1.0, 8.4), m_wood_dark)
	# front door (in front wall) and office door (in right wall)
	_box(Vector3(0, 1.1, 4.08), Vector3(1.0, 2.2, 0.06), Color(0.16, 0.10, 0.07))
	_box(Vector3(5.08, 1.1, -1.0), Vector3(0.06, 2.2, 1.0), Color(0.16, 0.10, 0.07))
	# window (front wall, left): emissive pane for headlights later
	var win := _box(Vector3(-3.0, 1.9, 4.08), Vector3(2.2, 1.2, 0.04), Color(0.05, 0.06, 0.09), 0.2)
	win.name = "Window"
	headlight = OmniLight3D.new()
	headlight.position = Vector3(-3.0, 1.9, 3.6)
	headlight.light_color = Color(0.85, 0.92, 1.0)
	headlight.light_energy = 0.0
	headlight.omni_range = 9.0
	headlight.shadow_enabled = true
	add_child(headlight)
	# bar counter + top + back bar
	_tbox(Vector3(0, 0.55, -2.55), Vector3(7.2, 1.1, 0.7), m_wood, "PH_bar_counter")
	_tbox(Vector3(0, 1.12, -2.55), Vector3(7.4, 0.06, 0.9), m_wood_dark)
	# back bar with a mirror strip
	_tbox(Vector3(0, 1.3, -4.0), Vector3(7.2, 2.6, 0.3), m_wood_dark, "PH_back_bar")
	_box(Vector3(0, 2.0, -3.84), Vector3(6.8, 1.5, 0.01), Color(0.55, 0.58, 0.62), 0.05, 1.0)
	for y in [1.6, 2.2, 2.8]:
		_tbox(Vector3(0, y, -3.85), Vector3(7.0, 0.04, 0.3), m_wood)
	# bottles on the shelves
	var rng := RandomNumberGenerator.new()
	rng.seed = 1137
	for y in [1.62, 2.22, 2.82]:
		var x := -3.3
		while x < 3.3:
			var h := rng.randf_range(0.22, 0.34)
			var c := Color(rng.randf_range(0.2, 0.6), rng.randf_range(0.1, 0.35), rng.randf_range(0.05, 0.2))
			_cyl(Vector3(x, y + h * 0.5, -3.85), 0.045, h, c, 0.15)
			x += rng.randf_range(0.14, 0.26)
	# the top-shelf bottle's empty spot: a brass tag on the highest shelf
	_clue(_box(Vector3(2.9, 2.86, -3.72), Vector3(0.12, 0.05, 0.02), brass, 0.3, 0.9))
	# brass foot rail along the bar
	_cyl(Vector3(0, 0.22, -2.1), 0.035, 7.0, brass, 0.25, 0.95, PI * 0.5)
	# the handprint at the end of the rail — a Voice-only clue
	_clue(_box(Vector3(3.3, 0.245, -2.1), Vector3(0.18, 0.012, 0.09), Color(0.55, 0.45, 0.25), 0.8))
	for x in [-3.2, -1.6, 0.0, 1.6, 3.2]:
		_cyl(Vector3(x, 0.11, -2.1), 0.015, 0.22, brass, 0.25, 0.95)
	# stools — Connie's is the last one at x = 3.0
	for x in [-3.0, -1.5, 0.0, 1.5, 3.0]:
		var leg := _cyl(Vector3(x, 0.38, -1.9), 0.03, 0.76, Color(0.2, 0.2, 0.2), 0.4, 0.8)
		var seat := _cyl(Vector3(x, 0.78, -1.9), 0.18, 0.06, Color(0.30, 0.10, 0.08), 0.8)
		if x == 3.0:
			leg.name = "PH_connie_stool_leg"
			seat.name = "PH_connie_stool_seat"
	# Connie's glass — still sweating
	_clue(_cyl(Vector3(3.0, 1.21, -2.4), 0.035, 0.12, Color(0.8, 0.9, 0.95, 0.5), 0.05))
	# till (register) behind the bar, drawer out
	_box(Vector3(-0.6, 1.3, -3.3), Vector3(0.5, 0.3, 0.4), Color(0.25, 0.25, 0.27), 0.4, 0.6)
	_box(Vector3(-0.6, 1.17, -3.05), Vector3(0.46, 0.05, 0.3), Color(0.2, 0.2, 0.22), 0.4, 0.6)
	# Theo's phone on the charger behind the register
	_clue(_box(Vector3(-0.2, 1.17, -3.4), Vector3(0.07, 0.01, 0.14), Color(0.05, 0.05, 0.06), 0.2))
	# cigar ash on the office carpet (office is through the right wall; keep it near the door)
	_clue(_box(Vector3(4.6, 0.005, -1.3), Vector3(0.06, 0.01, 0.04), Color(0.6, 0.6, 0.58), 1.0))
	# the body — a shape under a cloth, behind the bar
	_tbox(Vector3(1.0, 0.15, -3.1), Vector3(1.7, 0.3, 0.6), _mat(cloth, 1.0), "PH_body")
	_box(Vector3(1.6, 0.03, -2.85), Vector3(0.5, 0.01, 0.4), Color(0.25, 0.02, 0.02), 0.3)  # the halo
	# broken bottle — neck and shards
	_cyl(Vector3(0.3, 0.05, -2.9), 0.03, 0.1, Color(0.35, 0.2, 0.08), 0.1, 0.0, PI * 0.5)
	for i in range(6):
		_box(Vector3(0.2 + rng.randf_range(-0.2, 0.2), 0.01, -2.95 + rng.randf_range(-0.15, 0.15)), Vector3(0.05, 0.01, 0.04), Color(0.4, 0.25, 0.1), 0.1)
	# booth — benches and table, left-front
	_tbox(Vector3(-4.6, 0.25, 2.5), Vector3(0.5, 0.5, 1.6), m_leather, "PH_booth")
	_tbox(Vector3(-4.8, 0.8, 2.5), Vector3(0.1, 0.6, 1.6), m_leather)
	_tbox(Vector3(-3.4, 0.25, 2.5), Vector3(0.5, 0.5, 1.6), m_leather)
	_tbox(Vector3(-3.2, 0.8, 2.5), Vector3(0.1, 0.6, 1.6), m_leather)
	_tbox(Vector3(-4.0, 0.7, 2.5), Vector3(0.7, 0.05, 1.3), m_wood)
	_cyl(Vector3(-4.0, 0.35, 2.5), 0.05, 0.65, Color(0.2, 0.2, 0.2), 0.4, 0.8)
	# Frank's coat on the booth seat
	_box(Vector3(-4.6, 0.55, 2.1), Vector3(0.45, 0.1, 0.5), Color(0.18, 0.16, 0.14), 1.0)
	# jukebox, left wall
	_tbox(Vector3(-4.8, 0.75, -1.2), Vector3(0.6, 1.5, 0.9), _mat(Color(0.30, 0.12, 0.08), 0.3), "PH_jukebox")
	var juke := _box(Vector3(-4.48, 1.1, -1.2), Vector3(0.02, 0.5, 0.7), Color(0.9, 0.5, 0.2), 0.2)
	juke.name = "PH_jukebox_glow"
	var jm: StandardMaterial3D = juke.material_override
	jm.emission_enabled = true
	jm.emission = Color(0.9, 0.45, 0.15)
	jm.emission_energy_multiplier = 1.5
	# a few tables on the floor
	for p in [Vector3(-1.5, 0, 1.5), Vector3(1.8, 0, 1.8)]:
		var top := _cyl(p + Vector3(0, 0.72, 0), 0.4, 0.04, wood, 0.3)
		top.material_override = m_wood
		_cyl(p + Vector3(0, 0.36, 0), 0.04, 0.72, Color(0.2, 0.2, 0.2), 0.4, 0.8)
	# people (placeholder capsules — replaced by models later)
	_person(Vector3(0.2, 0.0, -3.1), Color(0.55, 0.55, 0.60), 1.2, "mira")   # Mira, kneeling
	_person(Vector3(0.0, 0.0, 3.6), Color(0.35, 0.40, 0.45), 1.75, "theo")   # Theo at the door
	_person(Vector3(-2.0, 0.0, 0.4), Color(0.62, 0.50, 0.30), 1.75, "lenny") # Lenny, camel coat
	_person(Vector3(3.0, 0.5, -1.9), Color(0.45, 0.35, 0.45), 1.1, "connie") # Connie, seated
