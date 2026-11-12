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
var voice_player: AudioStreamPlayer      # the people in the room
var head_player: AudioStreamPlayer       # the Voice: same line path, through the "Head" bus
var sfx: Dictionary = {}          # name -> AudioStreamPlayer (missing files are simply absent)
var last_evidence_sfx: float = -10.0
const MUSIC_TITLE_DB := -6.0
const MUSIC_GAME_DB := -20.0
var post_layer: CanvasLayer
var cam_base: Transform3D
var sway_t: float = 0.0
var mats: Dictionary = {}           # named shared materials
var fov_tween: Tween

## Drop GLB files here (assets/models/<name>.glb) and they replace the primitive at that slot.
## Each slot is a list of placements: [position, y-rotation in degrees, target size in metres,
## axis the size applies to ("y" = height, "long" = longest horizontal side)].
## Models are auto-fitted: whatever units or origin the file has, it is scaled to the target
## size, centred on the placement and stood on it. If one faces the wrong way, change the rotation.
const MODEL_SLOTS := {
	"jukebox":  [[Vector3(-4.72, 0.0, -1.0), 90.0, 1.5, "y"]],
	"body":     [[Vector3(-4.1, 0.0, -3.1), 0.0, 1.8, "long"]],
	"mira":     [[Vector3(-3.5, 0.0, -2.2), -150.0, 1.2, "y"]],
	"theo":     [[Vector3(4.3, 0.0, 2.4), -90.0, 1.78, "y"]],
	"lenny":    [[Vector3(-0.7, 0.0, 0.2), -55.0, 1.75, "y"]],
	"connie":   [[Vector3(3.0, 0.0, -1.9), -45.0, 1.45, "y"]],
	"stool":    [[Vector3(-2.0, 0.0, -1.9), 0.0, 0.8, "y"], [Vector3(-0.75, 0.0, -1.9), 40.0, 0.8, "y"], [Vector3(0.5, 0.0, -1.9), 110.0, 0.8, "y"], [Vector3(1.75, 0.0, -1.9), 200.0, 0.8, "y"]],
	"booth":    [[Vector3(-4.25, 0.0, 0.9), 90.0, 2.3, "long"]],
	"register": [[Vector3(0.7, 0.95, -3.72), 0.0, 0.5, "y"]],
	"desk":     [[Vector3(7.25, 0.0, -1.75), 0.0, 2.0, "long"]],
	"safe":     [[Vector3(8.0, 0.0, 0.05), -90.0, 0.95, "y"]],
	"lamp":     [[Vector3(-2.0, 2.3, -2.4), 0.0, 0.9, "y"], [Vector3(0.4, 2.3, -2.4), 0.0, 0.9, "y"], [Vector3(2.8, 2.3, -2.4), 0.0, 0.9, "y"], [Vector3(-4.2, 2.3, 0.9), 0.0, 0.9, "y"], [Vector3(1.5, 2.3, 1.3), 0.0, 0.9, "y"]],
}

# Camera stations: [position, look_at, vertical fov]
const STATIONS := {
	"title":  [Vector3(-3.25, 1.34, -2.12), Vector3(4.5, 1.62, -2.62), 62.0],
	"hub":    [Vector3(-4.55, 2.25, 3.8),  Vector3(0.5, 0.75, -2.0), 68.0],
	"booth":  [Vector3(-2.2, 1.5, 2.5), Vector3(-4.3, 0.55, 0.8), 58.0],
	"bar":    [Vector3(-2.5, 2.2, -0.9), Vector3(-4.0, 0.0, -3.0), 58.0],
	"floor":  [Vector3(1.5, 1.3, -0.5), Vector3(3.0, 0.35, -2.2), 58.0],
	"office": [Vector3(5.75, 1.65, 0.3), Vector3(7.3, 0.55, -1.6), 62.0],
	"mira":   [Vector3(-2.75, 1.25, -3.55), Vector3(-3.85, 0.35, -2.55), 60.0],
	"theo":   [Vector3(2.5, 1.5, 1.7),  Vector3(4.4, 1.0, 2.45), 54.0],
	"lenny":  [Vector3(-2.2, 1.5, 1.7), Vector3(-0.65, 0.95, 0.2), 54.0],
	"connie": [Vector3(1.5, 1.45, -0.6), Vector3(3.0, 0.85, -1.95), 54.0],
	"rail":   [Vector3(0.9, 0.5, -1.45), Vector3(3.3, 0.3, -2.1), 46.0],
}
const SCENE_STATION := {
	"ch1_wake": "booth", "ch1_body": "bar", "ch1_mira1": "mira", "ch1_others": "hub",
	"ch1_drink": "hub", "ch1_voice": "hub", "hub": "hub",
	"loc_booth": "booth", "loc_bar": "bar", "loc_floor": "floor", "loc_office": "office",
	"int_mira": "mira", "int_theo": "theo", "int_lenny": "lenny", "int_connie": "connie",
	"accuse": "hub",
	"ch4_blackout": "connie", "ch4_drink": "rail", "ch4_connie": "connie", "ch4_sober": "office",
	"ch5_intro": "office", "ch5_silence": "office",
	"end_true": "rail", "end_true_tell": "hub", "end_true_stand": "booth",
	"end_theo": "theo", "end_lenny": "lenny", "end_mira": "mira", "end_connie": "connie", "end_timeout": "booth",
}

# Hotspots in the hub: name, scene id, position, size
const HOTSPOTS := [
	["The booth", "loc_booth", Vector3(-4.25, 0.7, 0.9), Vector3(1.6, 1.4, 2.2)],
	["Danny", "loc_bar", Vector3(-4.1, 0.3, -3.1), Vector3(1.9, 0.7, 0.9)],
	["The rail", "loc_floor", Vector3(1.3, 0.35, -2.1), Vector3(2.2, 0.7, 0.5)],
	["The office", "loc_office", Vector3(5.1, 1.05, -0.8), Vector3(0.5, 2.1, 1.0)],
	["Mira", "int_mira", Vector3(-3.5, 0.6, -2.2), Vector3(0.7, 1.2, 0.7)],
	["Theo", "int_theo", Vector3(4.3, 0.9, 2.4), Vector3(0.7, 1.8, 0.7)],
	["Lenny", "int_lenny", Vector3(-0.7, 0.9, 0.2), Vector3(0.9, 1.8, 0.9)],
	["Connie", "int_connie", Vector3(3.0, 0.9, -1.9), Vector3(0.7, 1.8, 0.7)],
]

# Palettes
const SOBER := {
	"bg": Color(0.02, 0.02, 0.025), "ambient": Color(0.20, 0.21, 0.26), "ambient_energy": 0.55,
	"fog": Color(0.05, 0.04, 0.04), "fog_density": 0.01,
	"light": Color(1.0, 0.76, 0.50), "light_energy": 3.4,
}
## Title screen: the bar after close. Almost everything is off except one lamp and the neon.
const TITLE := {
	"bg": Color(0.012, 0.01, 0.014), "ambient": Color(0.10, 0.08, 0.11), "ambient_energy": 0.30,
	"fog": Color(0.05, 0.03, 0.045), "fog_density": 0.03,
	"light": Color(1.0, 0.70, 0.42), "light_energy": 0.5,
}
const VOICE := {
	"bg": Color(0.01, 0.025, 0.04), "ambient": Color(0.16, 0.34, 0.42), "ambient_energy": 1.0,
	"fog": Color(0.03, 0.09, 0.13), "fog_density": 0.04,
	"light": Color(0.50, 0.86, 1.0), "light_energy": 2.2,
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
	_build_sfx()
	_build_voice()
	ui.line_voice.connect(_on_line_voice)
	ui.line_advanced.connect(func(): _play("page"))
	Story.evidence_found.connect(_on_evidence_sfx)
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
	if not in_title:
		_play("drink" if s == "V" else "sober")
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
	cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	cam_tween.tween_property(cam, "transform", target, 1.2)
	cam_tween.tween_property(cam, "fov", float(st[2]), 1.2)


func _snap_camera(station: String) -> void:
	var st: Array = STATIONS[station]
	cam.position = st[0]
	cam.look_at(st[1], Vector3.UP)
	cam.fov = float(st[2])
	cam_base = cam.transform


# ---------------------------------------------------------------- title screen

func _enter_title() -> void:
	in_title = true
	_set_cast_visible(false)
	if voice_player:
		voice_player.stop()
		head_player.stop()
	_stop("room")
	_stop("police")
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


func _set_cast_visible(on: bool) -> void:
	for n in ["Model_lenny", "Model_theo", "Model_mira", "Model_body", "PH_lenny", "PH_theo", "PH_mira", "PH_body"]:
		var node := get_node_or_null(n) as Node3D
		if node:
			# a placeholder stays hidden if its model replaced it
			if n.begins_with("PH_") and get_node_or_null("Model_" + n.substr(3)) != null:
				node.visible = false
			else:
				node.visible = on


func _leave_title() -> void:
	in_title = false
	_set_cast_visible(true)
	_play("room")
	_apply_palette(SOBER, 2.0)
	var t := create_tween().set_parallel(true)
	t.tween_property(title_key, "light_energy", 0.0, 2.0)
	t.tween_property(neon_light, "light_energy", 0.9, 2.0)
	if music:
		t.tween_property(music, "volume_db", MUSIC_GAME_DB, 3.0)


## Spoken lines live in assets/voice/<stem>.ogg; story.json names the stem per line ("vo").
## The Voice plays through its own bus with a tight reverb and a short slap delay,
## so it sounds like it is inside Frank's head rather than in the room.
func _build_voice() -> void:
	if AudioServer.get_bus_index("Head") == -1:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Head")
		AudioServer.set_bus_send(bi, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.18
		rv.damping = 0.7
		rv.wet = 0.22
		rv.dry = 0.9
		rv.spread = 0.2
		AudioServer.add_bus_effect(bi, rv)
		var dl := AudioEffectDelay.new()
		dl.tap1_delay_ms = 85.0
		dl.tap1_level_db = -14.0
		dl.tap2_active = false
		dl.dry = 1.0
		AudioServer.add_bus_effect(bi, dl)
	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoiceRoom"
	voice_player.volume_db = 0.0
	add_child(voice_player)
	head_player = AudioStreamPlayer.new()
	head_player.name = "VoiceHead"
	head_player.bus = "Head"
	head_player.volume_db = 1.5
	add_child(head_player)


func _on_line_voice(stem: String) -> void:
	voice_player.stop()
	head_player.stop()
	if stem == "":
		return
	var path := "res://assets/voice/%s.ogg" % stem
	if not ResourceLoader.exists(path):
		return
	var pl := head_player if _is_voice_line(stem) else voice_player
	pl.stream = load(path)
	pl.play()


func _is_voice_line(stem: String) -> bool:
	if current_scene == "" or not Story.scenes.has(current_scene):
		return false
	for l in Story.scenes[current_scene]["lines"]:
		if str(l.get("vo", "")) == stem:
			return str(l["who"]) == "voice"
	return false


## Sound effects live in assets/audio/<name>.(ogg|mp3|wav). Any that are missing are skipped.
func _build_sfx() -> void:
	var defs := {"drink": -4.0, "sober": -6.0, "room": -24.0, "police": -8.0, "page": -16.0, "evidence": -8.0}
	for n in defs.keys():
		for ext in ["ogg", "mp3", "wav"]:
			var path := "res://assets/audio/%s.%s" % [n, ext]
			if not ResourceLoader.exists(path):
				continue
			var stream: AudioStream = load(path)
			if n == "room":
				if stream is AudioStreamMP3:
					(stream as AudioStreamMP3).loop = true
				elif stream is AudioStreamOggVorbis:
					(stream as AudioStreamOggVorbis).loop = true
				elif stream is AudioStreamWAV:
					(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
					(stream as AudioStreamWAV).loop_end = int((stream as AudioStreamWAV).get_length() * (stream as AudioStreamWAV).mix_rate)
			var pl := AudioStreamPlayer.new()
			pl.name = "Sfx_" + n
			pl.stream = stream
			pl.volume_db = defs[n]
			add_child(pl)
			sfx[n] = pl
			break


func _play(n: String) -> void:
	if sfx.has(n):
		(sfx[n] as AudioStreamPlayer).play()


func _stop(n: String) -> void:
	if sfx.has(n):
		(sfx[n] as AudioStreamPlayer).stop()


func _on_evidence_sfx(_id: String) -> void:
	# several items can land in one scene; one sting is enough
	if sway_t - last_evidence_sfx > 1.0:
		last_evidence_sfx = sway_t
		_play("evidence")


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
	sign.position = Vector3(5.17, 2.3, -2.85)
	sign.rotation_degrees.y = -90.0
	add_child(sign)
	neon_light = OmniLight3D.new()
	neon_light.position = Vector3(4.6, 2.25, -2.85)
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
	if on:
		_play("police")
	var win := get_node_or_null("Window") as MeshInstance3D
	var t := create_tween().set_parallel(true)
	t.tween_property(headlight, "light_energy", 6.0 if on else 0.0, 1.6 if on else 0.4)
	if on:
		headlight.position.x = -4.6
		t.tween_property(headlight, "position:x", -1.6, 2.4).set_trans(Tween.TRANS_SINE)
	if win:
		var m: StandardMaterial3D = win.material_override
		t.tween_property(m, "emission_energy_multiplier", 5.0 if on else 0.9, 1.6 if on else 0.4)


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
		var i := 0
		for cfg in MODEL_SLOTS[slot]:
			var inst: Node3D = scene.instantiate()
			var pivot := Node3D.new()
			pivot.name = ("Model_" + slot) if i == 0 else ("Model_%s_%d" % [slot, i])
			pivot.position = cfg[0]
			pivot.rotation_degrees.y = cfg[1]
			pivot.add_child(inst)
			_fit_model(inst, float(cfg[2]), str(cfg[3]))
			add_child(pivot)
			i += 1
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
		lbl.text = "◆  " + str(h[0]).to_upper()
		var lift: float = {"loc_bar": 0.25, "loc_booth": 0.1, "loc_floor": -0.1, "loc_office": 0.5, "int_mira": 0.55, "int_connie": -0.2, "int_lenny": 0.3, "int_theo": 0.3}.get(str(h[1]), 0.25)
		lbl.position = Vector3(0, h[3].y * 0.5 + lift, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font = load("res://assets/fonts/Inter.ttf")
		lbl.font_size = 36
		lbl.fixed_size = true
		lbl.pixel_size = 0.00085
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
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
	# pendants: three over the bar, one over the booth, one mid-room; plus the office desk lamp.
	# Only two cast shadows: omni shadows are the most expensive thing in the scene on the web.
	var k := 0
	for cfg in MODEL_SLOTS["lamp"]:
		var p: Vector3 = cfg[0] + Vector3(0, 0.02, 0)
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 7.0
		l.omni_attenuation = 1.25
		l.shadow_enabled = (k == 1 or k == 4)
		add_child(l)
		lights.append(l)
		# placeholder bulb, hidden when the lamp model is present
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		bulb.mesh = sm
		bulb.position = p
		bulb.name = "PH_lamp_%d" % k
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		m.emission = Color(1.0, 0.85, 0.6)
		m.emission_energy_multiplier = 3.0
		bulb.material_override = m
		add_child(bulb)
		var cord := _cyl(p + Vector3(0, 0.5, 0), 0.006, 0.8, Color(0.05, 0.05, 0.05), 0.6)
		cord.name = "PH_lamp_cord%d" % k
		cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shade := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.24
		cone.height = 0.16
		cone.radial_segments = 24
		shade.mesh = cone
		shade.position = p + Vector3(0, 0.1, 0)
		shade.name = "PH_lamp_shade%d" % k
		shade.material_override = _mat(Color(0.05, 0.16, 0.10), 0.3, 0.3)
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shade)
		# the lit underside of the shade
		var glowm := StandardMaterial3D.new()
		glowm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glowm.albedo_color = Color(1.0, 0.86, 0.62)
		var disc := _cyl(p + Vector3(0, 0.03, 0), 0.07, 0.02, Color(1, 1, 1))
		disc.material_override = glowm
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		k += 1
	var desk := OmniLight3D.new()
	desk.position = Vector3(6.75, 1.25, -1.65)
	desk.omni_range = 4.5
	desk.omni_attenuation = 1.4
	desk.shadow_enabled = false
	add_child(desk)
	lights.append(desk)


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


# ---------------------------------------------------------------- materials

## World-space triplanar material from assets/textures/<name>.jpg (+ <name>_n.jpg).
## `tile` is how many metres one repeat of the texture covers.
func _tex_mat(name_: String, tile: float, rough: float, tint: Color = Color(1, 1, 1), normal_scale: float = 1.0, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	var ap := "res://assets/textures/%s.jpg" % name_
	if ResourceLoader.exists(ap):
		m.albedo_texture = load(ap)
	var np := "res://assets/textures/%s_n.jpg" % name_
	if ResourceLoader.exists(np):
		m.normal_enabled = true
		m.normal_texture = load(np)
		m.normal_scale = normal_scale
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _build_textures() -> void:
	mats["wall"] = _tex_mat("wall", 1.3, 0.92, Color(0.80, 0.85, 0.80), 0.8)
	mats["panel"] = _tex_mat("panel", 2.0, 0.42, Color(0.58, 0.50, 0.48), 1.2)
	mats["floor"] = _tex_mat("floor", 0.72, 0.34, Color(0.50, 0.47, 0.43), 0.7)
	mats["ceiling"] = _tex_mat("ceiling", 2.4, 0.7, Color(0.75, 0.75, 0.78), 1.4)
	mats["bartop"] = _tex_mat("bartop", 1.6, 0.22, Color(0.95, 0.88, 0.82), 0.6)
	mats["wood"] = _tex_mat("bartop", 1.1, 0.5, Color(0.50, 0.42, 0.38), 0.8)
	mats["wood_dark"] = _tex_mat("bartop", 1.1, 0.55, Color(0.26, 0.21, 0.19), 0.8)
	mats["carpet"] = _tex_mat("carpet", 1.2, 1.0, Color(0.80, 0.78, 0.78), 0.8)
	mats["leather"] = _tex_mat("leather", 0.9, 0.5, Color(0.90, 0.85, 0.85), 1.3)
	mats["brass"] = _mat(Color(0.80, 0.60, 0.26), 0.28, 0.95)
	mats["iron"] = _mat(Color(0.10, 0.10, 0.11), 0.5, 0.8)
	mats["plaster"] = _mat(Color(0.20, 0.19, 0.18), 0.95)


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
	return _tbox(pos, size, _mat(c, rough, metal))


func _cyl(pos: Vector3, radius: float, height: float, c: Color, rough: float = 0.6, metal: float = 0.0, rot_z: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 20
	cm.rings = 1
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


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## Three MultiMeshes (body, neck, label) give ~120 bottles in three draw calls.
func _build_bottles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1137
	var glass := [Color(0.20, 0.09, 0.03), Color(0.05, 0.14, 0.07), Color(0.30, 0.16, 0.05), Color(0.10, 0.10, 0.11), Color(0.42, 0.30, 0.12), Color(0.16, 0.05, 0.04), Color(0.55, 0.50, 0.40)]
	var items: Array = []   # [pos, height, radius, colour]
	for y in [1.62, 2.22, 2.82]:
		var x := -3.35
		while x < 3.35:
			var h := rng.randf_range(0.24, 0.36)
			var r := rng.randf_range(0.034, 0.048)
			if not (y > 2.8 and absf(x - 2.9) < 0.12):   # the gap where the top-shelf bottle used to be
				items.append([Vector3(x, y, -3.86 + rng.randf_range(-0.03, 0.03)), h, r, glass[rng.randi() % glass.size()]])
			x += r * 2.0 + rng.randf_range(0.03, 0.10)
	var body := CylinderMesh.new()
	body.top_radius = 1.0
	body.bottom_radius = 1.0
	body.height = 1.0
	body.radial_segments = 12
	body.rings = 1
	var neck := CylinderMesh.new()
	neck.top_radius = 0.30
	neck.bottom_radius = 0.95
	neck.height = 1.0
	neck.radial_segments = 12
	neck.rings = 1
	var label := BoxMesh.new()
	label.size = Vector3(1.5, 1.0, 0.1)
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 0.08
	gm.metallic = 0.25
	gm.metallic_specular = 0.9
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.roughness = 0.9
	var mms: Array = []
	for cfg in [[body, gm], [neck, gm], [label, lm]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = cfg[0]
		mm.instance_count = items.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = cfg[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		mms.append(mm)
	var labels := [Color(0.82, 0.76, 0.60), Color(0.70, 0.62, 0.45), Color(0.55, 0.12, 0.10), Color(0.15, 0.15, 0.16), Color(0.85, 0.82, 0.75)]
	for i in items.size():
		var p: Vector3 = items[i][0]
		var h: float = items[i][1]
		var r: float = items[i][2]
		var c: Color = items[i][3]
		var bh := h * 0.62
		var nh := h * 0.38
		mms[0].set_instance_transform(i, Transform3D(Basis().scaled(Vector3(r, bh, r)), p + Vector3(0, bh * 0.5, 0)))
		mms[0].set_instance_color(i, c)
		mms[1].set_instance_transform(i, Transform3D(Basis().scaled(Vector3(r, nh, r)), p + Vector3(0, bh + nh * 0.5, 0)))
		mms[1].set_instance_color(i, c)
		mms[2].set_instance_transform(i, Transform3D(Basis().scaled(Vector3(r, bh * 0.5, r)), p + Vector3(0, bh * 0.45, r * 0.98)))
		mms[2].set_instance_color(i, labels[rng.randi() % labels.size()])


func _build_room() -> void:
	var wall: Material = mats["wall"]
	var panel: Material = mats["panel"]
	var wood: Material = mats["wood"]
	var wood_dark: Material = mats["wood_dark"]
	var brass: Material = mats["brass"]
	var H := 3.2

	# ---- shell -------------------------------------------------------------
	_tbox(Vector3(0, -0.05, 0), Vector3(10.6, 0.1, 8.6), mats["floor"])
	_tbox(Vector3(0, H + 0.05, 0), Vector3(10.6, 0.1, 8.6), mats["ceiling"])
	for z in [-2.8, -1.4, 0.0, 1.4, 2.8]:
		_tbox(Vector3(0, H - 0.1, z), Vector3(10.4, 0.2, 0.2), wood_dark)
	_tbox(Vector3(0, H * 0.5, -4.3), Vector3(10.6, H, 0.2), wall)            # back
	_tbox(Vector3(0, H * 0.5, 4.3), Vector3(10.6, H, 0.2), wall)             # front
	_tbox(Vector3(-5.3, H * 0.5, 0), Vector3(0.2, H, 8.6), wall)             # left
	# right wall, with a doorway to the office at z = -1.3 .. -0.3
	_tbox(Vector3(5.3, H * 0.5, -2.8), Vector3(0.2, H, 3.0), wall)
	_tbox(Vector3(5.3, H * 0.5, 2.0), Vector3(0.2, H, 4.6), wall)
	_tbox(Vector3(5.3, 2.1 + (H - 2.1) * 0.5, -0.8), Vector3(0.2, H - 2.1, 1.0), wall)
	# wainscot and chair rail on every wall of the bar room
	_tbox(Vector3(0, 0.5, 4.18), Vector3(10.4, 1.0, 0.05), panel)
	_tbox(Vector3(-5.18, 0.5, 0), Vector3(0.05, 1.0, 8.4), panel)
	_tbox(Vector3(5.18, 0.5, -2.8), Vector3(0.05, 1.0, 3.0), panel)
	_tbox(Vector3(5.18, 0.5, 2.0), Vector3(0.05, 1.0, 4.6), panel)
	_tbox(Vector3(0, 1.02, 4.16), Vector3(10.4, 0.05, 0.08), wood_dark)
	_tbox(Vector3(-5.16, 1.02, 0), Vector3(0.08, 0.05, 8.4), wood_dark)
	_tbox(Vector3(5.16, 1.02, -2.8), Vector3(0.08, 0.05, 3.0), wood_dark)
	_tbox(Vector3(5.16, 1.02, 2.0), Vector3(0.08, 0.05, 4.6), wood_dark)
	# office door frame, and the door standing open into the office
	_tbox(Vector3(5.3, 1.05, -1.33), Vector3(0.26, 2.1, 0.07), wood_dark)
	_tbox(Vector3(5.3, 1.05, -0.27), Vector3(0.26, 2.1, 0.07), wood_dark)
	_tbox(Vector3(5.3, 2.13, -0.8), Vector3(0.26, 0.07, 1.13), wood_dark)
	_tbox(Vector3(5.45, 1.03, -1.85), Vector3(0.05, 2.06, 0.95), wood)

	# ---- entrance door (right wall) and front window ----------------------
	_tbox(Vector3(5.17, 1.07, 2.4), Vector3(0.07, 2.14, 1.08), wood_dark)
	_tbox(Vector3(5.14, 1.05, 2.4), Vector3(0.05, 2.02, 0.94), wood)
	var pane := _tbox(Vector3(5.11, 1.5, 2.4), Vector3(0.02, 0.8, 0.6), _emissive(Color(0.20, 0.30, 0.45), 0.7))
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tbox(Vector3(5.09, 1.02, 2.72), Vector3(0.05, 0.04, 0.12), brass)
	# window: street glow behind venetian blinds
	var win := _tbox(Vector3(-1.6, 1.85, 4.17), Vector3(4.0, 1.4, 0.03), _emissive(Color(0.16, 0.24, 0.40), 0.9), "Window")
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tbox(Vector3(-1.6, 2.59, 4.13), Vector3(4.2, 0.09, 0.1), wood_dark)
	_tbox(Vector3(-1.6, 1.11, 4.13), Vector3(4.2, 0.09, 0.14), wood_dark)
	_tbox(Vector3(-3.66, 1.85, 4.13), Vector3(0.09, 1.57, 0.1), wood_dark)
	_tbox(Vector3(0.46, 1.85, 4.13), Vector3(0.09, 1.57, 0.1), wood_dark)
	_tbox(Vector3(-1.6, 1.85, 4.13), Vector3(0.07, 1.4, 0.08), wood_dark)
	var slat := _mat(Color(0.09, 0.085, 0.08), 0.6)
	var sy := 1.2
	while sy < 2.55:
		var sl := _tbox(Vector3(-1.6, sy, 4.11), Vector3(4.0, 0.012, 0.05), slat)
		sl.rotation_degrees.x = 28.0
		sl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sy += 0.075
	headlight = OmniLight3D.new()
	headlight.position = Vector3(-3.0, 1.9, 3.6)
	headlight.light_color = Color(0.85, 0.92, 1.0)
	headlight.light_energy = 0.0
	headlight.omni_range = 9.0
	headlight.shadow_enabled = false
	add_child(headlight)
	# the street: a cold spill through the blinds, always on
	var street := OmniLight3D.new()
	street.position = Vector3(-1.6, 1.9, 3.7)
	street.light_color = Color(0.40, 0.55, 0.85)
	street.light_energy = 0.55
	street.omni_range = 5.5
	street.omni_attenuation = 1.6
	add_child(street)

	# ---- the bar -----------------------------------------------------------
	# counter runs x = -3.0 .. 3.6; the left end is open (that is where Danny is)
	_tbox(Vector3(0.3, 0.54, -2.55), Vector3(6.6, 1.08, 0.62), panel)
	_tbox(Vector3(0.3, 1.11, -2.55), Vector3(6.84, 0.07, 0.92), mats["bartop"])
	_tbox(Vector3(0.3, 1.06, -2.08), Vector3(6.84, 0.05, 0.05), wood_dark)
	_tbox(Vector3(0.3, 0.06, -2.2), Vector3(6.7, 0.12, 0.12), wood_dark)
	# brass foot rail
	var rail := _cyl(Vector3(0.3, 0.24, -2.08), 0.032, 6.6, Color(1, 1, 1), 0.25, 0.95, PI * 0.5)
	rail.material_override = brass
	for x in [-2.8, -1.25, 0.3, 1.85, 3.4]:
		var post := _cyl(Vector3(x, 0.12, -2.08), 0.014, 0.24, Color(1, 1, 1))
		post.material_override = brass
	# the handprint at the end of the rail: a Voice-only clue
	_clue(_box(Vector3(3.3, 0.265, -2.08), Vector3(0.18, 0.012, 0.085), Color(0.55, 0.45, 0.25), 0.8))
	# back bar: low cabinet, mirror, three lit shelves
	_tbox(Vector3(0, 0.475, -3.92), Vector3(7.2, 0.95, 0.56), panel)
	_tbox(Vector3(0, 0.97, -3.92), Vector3(7.3, 0.05, 0.62), mats["bartop"])
	_tbox(Vector3(0, 2.1, -4.16), Vector3(7.3, 2.25, 0.08), wood_dark)
	var mirror := _box(Vector3(0, 2.1, -4.11), Vector3(6.9, 1.9, 0.01), Color(0.10, 0.13, 0.15), 0.04, 0.9)
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tbox(Vector3(-3.62, 2.1, -4.0), Vector3(0.1, 2.3, 0.36), wood_dark)
	_tbox(Vector3(3.62, 2.1, -4.0), Vector3(0.1, 2.3, 0.36), wood_dark)
	_tbox(Vector3(0, 3.22, -4.0), Vector3(7.5, 0.12, 0.42), wood_dark)
	for y in [1.6, 2.2, 2.8]:
		_tbox(Vector3(0, y, -3.9), Vector3(7.1, 0.035, 0.3), wood)
		# warm strip under the shelf above lights the labels
		var strip := _tbox(Vector3(0, y + 0.55, -3.78), Vector3(6.9, 0.012, 0.02), _emissive(Color(1.0, 0.72, 0.40), 2.2))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_bottles()
	# the top-shelf bottle's empty spot: a brass tag and a ring in the dust
	_clue(_box(Vector3(2.9, 2.825, -3.76), Vector3(0.10, 0.045, 0.012), Color(0.80, 0.60, 0.26), 0.3, 0.9))
	# register placeholder, drawer out
	_tbox(Vector3(0.7, 1.17, -3.72), Vector3(0.45, 0.38, 0.4), brass, "PH_register")
	_tbox(Vector3(0.7, 1.03, -3.5), Vector3(0.4, 0.08, 0.3), wood_dark, "PH_register_drawer")
	# Theo's phone on the charger beside the register
	_clue(_box(Vector3(1.2, 1.0, -3.8), Vector3(0.075, 0.012, 0.15), Color(0.04, 0.04, 0.05), 0.15))
	_box(Vector3(1.2, 0.997, -3.93), Vector3(0.03, 0.01, 0.12), Color(0.85, 0.85, 0.85), 0.6)
	# Connie's glass, still sweating
	var cg := _cyl(Vector3(3.0, 1.2, -2.4), 0.034, 0.12, Color(0.85, 0.93, 1.0, 0.35), 0.03)
	(cg.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_clue(cg)
	# stool placeholders (hidden when stool.glb is present); Connie's model brings its own
	var k := 0
	for cfg in MODEL_SLOTS["stool"]:
		var p: Vector3 = cfg[0]
		var leg := _cyl(p + Vector3(0, 0.38, 0), 0.03, 0.76, Color(0.2, 0.2, 0.2), 0.4, 0.8)
		leg.name = "PH_stool_leg%d" % k
		var seat := _cyl(p + Vector3(0, 0.78, 0), 0.18, 0.06, Color(0.30, 0.10, 0.08), 0.8)
		seat.name = "PH_stool_seat%d" % k
		seat.material_override = mats["leather"]
		var base := _cyl(p + Vector3(0, 0.015, 0), 0.2, 0.03, Color(1, 1, 1))
		base.material_override = brass
		base.name = "PH_stool_base%d" % k
		var ring := _cyl(p + Vector3(0, 0.3, 0), 0.15, 0.02, Color(1, 1, 1))
		ring.material_override = brass
		ring.name = "PH_stool_ring%d" % k
		k += 1
	var cleg := _cyl(Vector3(3.0, 0.38, -1.9), 0.03, 0.76, Color(0.2, 0.2, 0.2), 0.4, 0.8)
	cleg.name = "PH_connie_stool_leg"
	var cseat := _cyl(Vector3(3.0, 0.78, -1.9), 0.18, 0.06, Color(0.30, 0.10, 0.08), 0.8)
	cseat.name = "PH_connie_stool_seat"

	# ---- Danny, at the open end of the bar ---------------------------------
	_tbox(Vector3(-4.1, 0.15, -3.1), Vector3(1.7, 0.3, 0.6), _mat(Color(0.55, 0.52, 0.48), 1.0), "PH_body")
	var halo := _cyl(Vector3(-3.3, 0.004, -2.85), 0.28, 0.006, Color(0.16, 0.012, 0.012), 0.12)
	halo.scale = Vector3(1.4, 1.0, 0.9)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the broken top-shelf bottle: neck, base and shards
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_cyl(Vector3(-3.05, 0.03, -2.55), 0.016, 0.11, Color(0.30, 0.16, 0.05), 0.08, 0.0, PI * 0.5)
	_cyl(Vector3(-3.25, 0.03, -2.45), 0.042, 0.06, Color(0.30, 0.16, 0.05), 0.08)
	for i in range(9):
		var sh := _box(Vector3(-3.2 + rng.randf_range(-0.3, 0.3), 0.006, -2.5 + rng.randf_range(-0.2, 0.2)), Vector3(rng.randf_range(0.02, 0.06), 0.008, rng.randf_range(0.02, 0.05)), Color(0.36, 0.20, 0.07), 0.06)
		sh.rotation_degrees.y = rng.randf_range(0, 180)
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ---- booth, jukebox, tables -------------------------------------------
	var lth: Material = mats["leather"]
	_tbox(Vector3(-4.25, 0.25, 0.05), Vector3(1.5, 0.5, 0.5), lth, "PH_booth_a")
	_tbox(Vector3(-4.25, 0.85, -0.17), Vector3(1.5, 0.75, 0.1), lth, "PH_booth_b")
	_tbox(Vector3(-4.25, 0.25, 1.75), Vector3(1.5, 0.5, 0.5), lth, "PH_booth_c")
	_tbox(Vector3(-4.25, 0.85, 1.97), Vector3(1.5, 0.75, 0.1), lth, "PH_booth_d")
	_tbox(Vector3(-4.25, 0.72, 0.9), Vector3(1.3, 0.05, 0.7), wood, "PH_booth_e")
	# Frank's coat on the seat, his coaster and the receipt on the table (the model sits under them)
	var coat := _box(Vector3(-4.0, 0.56, 1.72), Vector3(0.55, 0.09, 0.4), Color(0.13, 0.12, 0.11), 1.0)
	coat.rotation_degrees.y = 12.0
	_cyl(Vector3(-3.95, 0.775, 0.8), 0.05, 0.006, Color(0.55, 0.12, 0.10), 0.9)
	var rc := _box(Vector3(-4.15, 0.775, 1.05), Vector3(0.07, 0.003, 0.13), Color(0.86, 0.83, 0.74), 0.9)
	rc.rotation_degrees.y = 25.0
	_tbox(Vector3(-4.72, 0.75, -1.0), Vector3(0.6, 1.5, 0.9), _mat(Color(0.30, 0.12, 0.08), 0.3), "PH_jukebox")
	for p in [Vector3(1.5, 0, 1.3), Vector3(-1.5, 0, 2.7)]:
		var top := _cyl(p + Vector3(0, 0.73, 0), 0.42, 0.04, Color(1, 1, 1))
		top.material_override = wood
		var stem := _cyl(p + Vector3(0, 0.36, 0), 0.035, 0.72, Color(1, 1, 1))
		stem.material_override = mats["iron"]
		var foot := _cyl(p + Vector3(0, 0.02, 0), 0.24, 0.04, Color(1, 1, 1))
		foot.material_override = mats["iron"]
	# framed pictures break up the long walls
	for cfg in [[Vector3(-5.17, 1.95, 2.9), 0.0], [Vector3(-5.17, 1.95, -2.4), 0.0]]:
		_tbox(cfg[0], Vector3(0.04, 0.62, 0.86), wood_dark)
		_tbox(cfg[0] + Vector3(0.022, 0, 0), Vector3(0.01, 0.5, 0.74), _mat(Color(0.20, 0.17, 0.13), 0.5))
	for x in [2.3, 3.6]:
		_tbox(Vector3(x, 1.95, 4.17), Vector3(0.66, 0.5, 0.04), wood_dark)
		_tbox(Vector3(x, 1.95, 4.148), Vector3(0.54, 0.38, 0.01), _mat(Color(0.20, 0.17, 0.13), 0.5))

	# ---- the office --------------------------------------------------------
	var ox := 6.95   # centre x of the office (x 5.4 .. 8.5, z -2.9 .. 0.7)
	_tbox(Vector3(ox, -0.05, -1.1), Vector3(3.3, 0.1, 3.8), mats["carpet"])
	_tbox(Vector3(ox, H + 0.05, -1.1), Vector3(3.3, 0.1, 3.8), mats["plaster"])
	_tbox(Vector3(ox, H * 0.5, -3.0), Vector3(3.3, H, 0.2), mats["panel"])
	_tbox(Vector3(ox, H * 0.5, 0.8), Vector3(3.3, H, 0.2), mats["panel"])
	_tbox(Vector3(8.6, H * 0.5, -1.1), Vector3(0.2, H, 4.0), mats["panel"])
	_tbox(Vector3(7.25, 0.76, -1.75), Vector3(1.7, 0.06, 0.8), wood, "PH_desk")
	_tbox(Vector3(6.62, 0.37, -1.75), Vector3(0.42, 0.73, 0.74), wood_dark, "PH_desk_p1")
	_tbox(Vector3(7.88, 0.37, -1.75), Vector3(0.42, 0.73, 0.74), wood_dark, "PH_desk_p2")
	_tbox(Vector3(7.25, 0.795, -1.75), Vector3(1.2, 0.012, 0.55), _mat(Color(0.06, 0.20, 0.12), 0.7), "PH_desk_top")
	var lampbase := _cyl(Vector3(6.75, 0.83, -1.95), 0.07, 0.03, Color(1, 1, 1))
	lampbase.material_override = brass
	lampbase.name = "PH_desk_l1"
	var lampstem := _cyl(Vector3(6.75, 0.98, -1.95), 0.012, 0.3, Color(1, 1, 1))
	lampstem.material_override = brass
	lampstem.name = "PH_desk_l2"
	var lampshade := _tbox(Vector3(6.75, 1.14, -1.9), Vector3(0.36, 0.07, 0.14), _emissive(Color(0.10, 0.55, 0.28), 1.2), "PH_desk_l3")
	lampshade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in range(4):
		var paper := _box(Vector3(7.2 + i * 0.16, 0.805 + i * 0.001, -1.7 + (i % 2) * 0.12), Vector3(0.21, 0.002, 0.3), Color(0.86, 0.83, 0.74), 0.9)
		paper.rotation_degrees.y = -20.0 + i * 17.0
		paper.name = "PH_desk_paper%d" % i
	var carbon := _box(Vector3(7.55, 0.807, -1.62), Vector3(0.21, 0.002, 0.3), Color(0.10, 0.14, 0.38), 0.5)
	carbon.rotation_degrees.y = 12.0
	carbon.name = "PH_desk_carbon"
	_tbox(Vector3(7.3, 0.45, -2.45), Vector3(0.5, 0.9, 0.5), wood_dark, "PH_desk_chair")
	_tbox(Vector3(8.0, 0.45, 0.05), Vector3(0.6, 0.9, 0.6), _mat(Color(0.10, 0.20, 0.13), 0.6, 0.4), "PH_safe")
	# the little sink in the corner, and the cloth
	_box(Vector3(5.75, 0.82, -2.72), Vector3(0.5, 0.14, 0.36), Color(0.52, 0.52, 0.50), 0.3)
	_box(Vector3(5.75, 0.88, -2.72), Vector3(0.40, 0.03, 0.26), Color(0.30, 0.30, 0.30), 0.2)
	var tap := _cyl(Vector3(5.75, 0.99, -2.86), 0.012, 0.18, Color(1, 1, 1))
	tap.material_override = brass
	_box(Vector3(5.82, 0.9, -2.68), Vector3(0.2, 0.03, 0.14), Color(0.78, 0.62, 0.62), 1.0)
	_tbox(Vector3(5.75, 0.375, -2.74), Vector3(0.5, 0.75, 0.3), wood_dark)
	# cigar ash on the carpet by the desk
	_clue(_box(Vector3(6.55, 0.006, -1.05), Vector3(0.07, 0.01, 0.045), Color(0.62, 0.62, 0.60), 1.0))
	# filing cabinet and a wall calendar so the back wall is not bare
	_tbox(Vector3(8.2, 0.65, -2.55), Vector3(0.5, 1.3, 0.6), _mat(Color(0.22, 0.24, 0.22), 0.5, 0.5))
	_box(Vector3(6.9, 1.75, -2.89), Vector3(0.42, 0.56, 0.01), Color(0.80, 0.77, 0.68), 0.9)

	# people (placeholder capsules, hidden when the character models load)
	_person(MODEL_SLOTS["mira"][0][0], Color(0.55, 0.55, 0.60), 1.2, "mira")
	_person(MODEL_SLOTS["theo"][0][0], Color(0.35, 0.40, 0.45), 1.75, "theo")
	_person(MODEL_SLOTS["lenny"][0][0], Color(0.62, 0.50, 0.30), 1.75, "lenny")
	_person(MODEL_SLOTS["connie"][0][0] + Vector3(0, 0.5, 0), Color(0.45, 0.35, 0.45), 1.1, "connie")
