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
var cam_station: String = ""

## Drop GLB files here (assets/models/<name>.glb) and they replace the primitive at that slot.
## Each slot is a list of placements: [position, y-rotation in degrees, target size in metres,
## axis the size applies to ("y" = height, "long" = longest horizontal side)].
## Models are auto-fitted: whatever units or origin the file has, it is scaled to the target
## size, centred on the placement and stood on it. If one faces the wrong way, change the rotation.
const MODEL_SLOTS := {
	"jukebox":  [[Vector3(-4.72, 0.0, -1.0), 90.0, 1.5, "y"]],
	"body":     [[Vector3(-4.1, 0.0, -3.1), 0.0, 1.8, "long"]],
	"mira":     [[Vector3(-3.5, 0.0, -2.2), 25.0, 1.2, "y"]],
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
	"mira":   [Vector3(-2.1, 1.25, -0.7), Vector3(-3.5, 0.75, -2.2), 50.0],
	"theo":   [Vector3(2.5, 1.5, 1.7),  Vector3(4.4, 1.0, 2.45), 54.0],
	"lenny":  [Vector3(-2.2, 1.5, 1.7), Vector3(-0.65, 0.95, 0.2), 54.0],
	"connie": [Vector3(1.5, 1.45, -0.6), Vector3(3.0, 0.85, -1.95), 54.0],
	"phone":  [Vector3(-0.45, 1.5, -1.9), Vector3(0.25, 1.05, -3.72), 42.0],
	"jukebox": [Vector3(-2.9, 1.35, -0.2), Vector3(-4.7, 0.85, -1.0), 50.0],
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
	"end_true": "hub", "end_true_tell": "hub", "end_true_stand": "booth",
	"end_theo": "theo", "end_lenny": "lenny", "end_mira": "mira", "end_connie": "connie", "end_timeout": "booth",
	"ch3_phone": "phone", "ch3_answer": "phone", "ch3_ring": "hub", "loc_jukebox": "jukebox",
	"crack_theo_kind": "theo", "crack_theo_hard": "theo", "crack_lenny_ledger": "lenny", "crack_lenny_call": "lenny",
	"ch2_brief": "hub", "crack_theo": "theo", "crack_lenny": "lenny", "crack_mira": "mira", "crack_connie": "connie",
}
# When one of these people speaks, the camera cuts to them, wherever the scene is set.
## Shader-rig settings per character, as fractions of the model's height:
## waist, neck, mouth line, neck pivot (x, z), face surface z. See shaders/puppet.gdshader.
const RIG := {
	"mira":   {"waist": 0.45, "neck": 0.768, "mouth": 0.826, "chin": 0.786, "c": Vector2(0.0, 0.0), "face": 0.105,
		"eye": 0.888, "eye_dx": 0.026, "eye_cx": 0.0},
	"theo":   {"waist": 0.55, "neck": 0.872, "mouth": 0.888, "chin": 0.872, "c": Vector2(0.0, 0.005), "face": 0.058,
		"eye": 0.922, "eye_dx": 0.017, "eye_cx": 0.0,
		"arms": {"b": Vector2(0.122, 0.085), "h": Vector2(0.56, 0.80), "shoulder": Vector2(0.10, 0.80), "elbow": 0.62, "low": 0.40, "gesture": 1.0, "lead_right": true}},
	"lenny":  {"waist": 0.55, "neck": 0.890, "mouth": 0.886, "chin": 0.863, "c": Vector2(0.005, 0.02), "face": 0.100,
		"eye": 0.932, "eye_dx": 0.021, "eye_cx": 0.004},   # no arm bones: his coat cannot be told apart from his sleeves
	"connie": {"waist": 0.50, "neck": 0.838, "mouth": 0.880, "chin": 0.858, "c": Vector2(-0.007, -0.087), "face": -0.008,
		"eye": 0.9266, "eye_dx": 0.017, "eye_cx": 0.005},
}
var puppets: Dictionary = {}       # name -> Puppet
var speaker: String = ""           # who is talking right now
var lipsync: Dictionary = {}       # voice file stem -> loudness envelope
const SPEAKER_STATION := {"mira": "mira", "theo": "theo", "lenny": "lenny", "connie": "connie"}

# Hotspots in the hub: name, scene id, position, size
const HOTSPOTS := [
	["The booth", "loc_booth", Vector3(-4.25, 0.7, 0.9), Vector3(1.6, 1.4, 2.2)],
	["Danny", "loc_bar", Vector3(-4.1, 0.3, -3.1), Vector3(1.9, 0.7, 0.9)],
	["The rail", "loc_floor", Vector3(1.3, 0.35, -2.1), Vector3(2.2, 0.7, 0.5)],
	["The office", "loc_office", Vector3(5.1, 1.05, -0.8), Vector3(0.5, 2.1, 1.0)],
	["The jukebox", "loc_jukebox", Vector3(-4.6, 0.8, -1.0), Vector3(0.9, 1.6, 1.0)],
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
	_build_title_set()
	_apply_bake()
	ui.choice_made.connect(_on_choice)
	ui.back_requested.connect(func(): go("hub"))
	ui.restart_requested.connect(func(): go("__restart"))
	ui.shift_requested.connect(func(): Story.shift())
	ui.timeline_solved.connect(func(): go("ch5_silence"))
	Story.state_changed.connect(_on_state_changed)
	Story.timed_out.connect(func(): call_deferred("go", "end_timeout"))
	_build_music()
	_build_sfx()
	_build_voice()
	var lf := FileAccess.open("res://data/lipsync.json", FileAccess.READ)
	if lf:
		var parsed: Variant = JSON.parse_string(lf.get_as_text())
		if parsed is Dictionary:
			lipsync = parsed
	ui.line_voice.connect(_on_line_voice)
	ui.line_who.connect(_on_line_who)
	ui.present_requested.connect(func(): ui.open_present())
	ui.present_picked.connect(_on_present)
	ui.line_advanced.connect(func(): _play("page"))
	Story.evidence_found.connect(_on_evidence_sfx)
	_enter_title()


# ---------------------------------------------------------------- baked lighting
## If assets/baked/room.glb exists, the static room is swapped for the Blender-baked version:
## the same geometry merged into a few meshes, lit by path-traced lightmaps (shaders/baked.gdshader).
## Characters, bottles, clue props and anything that glows stay live. Rebuild the bake with
## tools/export_scene.gd then tools/bake_room.py. Set LS_NOBAKE=1 to see the unbaked room.
const BAKE_DIR := "res://assets/baked/"
const LAMP_GAIN := 3.4          # palette lamp energy -> lightmap gain
const AMBIENT_GAIN := 0.42
var baked_root: Node3D
var baked_mats: Array[ShaderMaterial] = []
var baked := false


## The static meshes that the bake replaces. tools/export_scene.gd uses the same rule.
func _is_static_mesh(c: Node) -> bool:
	var mi := c as MeshInstance3D
	if mi == null or not mi.visible or clue_meshes.has(mi) or str(mi.name).begins_with("PH_lamp_"):
		return false
	var sm := mi.material_override as StandardMaterial3D
	if sm == null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	return not (sm.emission_enabled or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)


func _collect_meshes(n: Node, acc: Array) -> void:
	if n is MeshInstance3D:
		acc.append(n)
	for c in n.get_children():
		_collect_meshes(c, acc)


func _apply_bake() -> void:
	if OS.get_environment("LS_NOBAKE") != "" or not ResourceLoader.exists(BAKE_DIR + "room.glb"):
		return
	var f := FileAccess.open(BAKE_DIR + "lightmaps.json", FileAccess.READ)
	if f == null:
		return
	var meta: Variant = JSON.parse_string(f.get_as_text())
	if not (meta is Dictionary):
		return
	var packed: PackedScene = load(BAKE_DIR + "room.glb")
	if packed == null:
		return
	# hide what the bake replaces
	for c in get_children():
		if _is_static_mesh(c):
			(c as Node3D).visible = false
		elif c is Node3D and str(c.name).begins_with("Model_") and not RIG.has(str(c.name).trim_prefix("Model_").get_slice("_", 0)):
			(c as Node3D).visible = false
		elif str(c.name).begins_with("PH_lamp_"):
			(c as Node3D).visible = false
	baked_root = packed.instantiate()
	baked_root.name = "Baked"
	add_child(baked_root)
	var lamp_pos: Array = []
	for l in lights:
		lamp_pos.append(l.position)
	var tex_cache := {}
	var lm := func(atlas: String, group: String) -> Texture2D:
		var k := "%s_%s" % [atlas, group]
		if not tex_cache.has(k):
			tex_cache[k] = load(BAKE_DIR + str(meta[k]["file"])) if meta.has(k) else null
		return tex_cache[k]
	var acc: Array = []
	_collect_meshes(baked_root, acc)
	var by_key := {}
	for mi in acc:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(si)
			var key := str(src.resource_name) if src else ""
			if not by_key.has(key):
				var atlas := "props" if key.begins_with("prop:") else "room"
				var sm := ShaderMaterial.new()
				sm.shader = load("res://shaders/baked.gdshader")
				sm.set_shader_parameter("lm_lamps", lm.call(atlas, "lamps"))
				sm.set_shader_parameter("lm_accent", lm.call(atlas, "accent"))
				sm.set_shader_parameter("lm_head", lm.call(atlas, "head"))
				sm.set_shader_parameter("lm_scale", Vector3(float(meta.get(atlas + "_lamps", {}).get("scale", 1.0)), float(meta.get(atlas + "_accent", {}).get("scale", 1.0)), float(meta.get(atlas + "_head", {}).get("scale", 1.0))))
				sm.set_shader_parameter("lamp_pos", lamp_pos)
				sm.set_shader_parameter("lamp_count", lamp_pos.size())
				if key.begins_with("prop:"):
					var slot := key.trim_prefix("prop:")
					sm.set_shader_parameter("triplanar", false)
					sm.set_shader_parameter("use_tex", true)
					sm.set_shader_parameter("albedo_tex", load("res://assets/models/%s_Image_0.webp" % slot))
					sm.set_shader_parameter("rough", 0.6)
				else:
					var info: Dictionary = meta["materials"].get(key, {})
					var col: Array = info.get("color", [0.6, 0.6, 0.6])
					sm.set_shader_parameter("tint", Vector3(col[0], col[1], col[2]))
					sm.set_shader_parameter("rough", float(info.get("rough", 0.8)))
					sm.set_shader_parameter("metal", float(info.get("metal", 0.0)))
					sm.set_shader_parameter("tile", float(info.get("scale", 1.0)))
					if str(info.get("tex", "")) != "":
						sm.set_shader_parameter("use_tex", true)
						sm.set_shader_parameter("albedo_tex", load(str(info["tex"])))
					if str(info.get("normal", "")) != "":
						sm.set_shader_parameter("use_normal", true)
						sm.set_shader_parameter("normal_tex", load(str(info["normal"])))
						sm.set_shader_parameter("normal_scale", float(info.get("normal_scale", 1.0)))
				by_key[key] = sm
				baked_mats.append(sm)
			mi.set_surface_override_material(si, by_key[key])
	# nothing left for the live lights to cast shadows onto
	for l in lights:
		l.shadow_enabled = false
	baked = true
	_build_atmosphere()
	print("baked room: ", acc.size(), " meshes, ", baked_mats.size(), " materials")


## Light you can see in the air: a soft cone under each pendant and a halo round each bulb and the neon.
var glow_lamps: Array[ShaderMaterial] = []
var glow_neon: ShaderMaterial


func _glow(mode: int, mesh: Mesh, pos: Vector3, col: Color, strength: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/glow.gdshader")
	sm.set_shader_parameter("mode", mode)
	sm.set_shader_parameter("color", Vector3(col.r, col.g, col.b))
	sm.set_shader_parameter("strength", strength)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	add_child(mi)
	return sm


func _build_atmosphere() -> void:
	var halo := QuadMesh.new()
	halo.size = Vector2(1.1, 1.1)
	for cfg in MODEL_SLOTS["lamp"]:
		var p: Vector3 = cfg[0]
		var cone := CylinderMesh.new()
		cone.top_radius = 0.10
		cone.bottom_radius = 1.25
		cone.height = p.y - 0.05
		cone.radial_segments = 28
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		glow_lamps.append(_glow(0, cone, Vector3(p.x, (p.y - 0.05) * 0.5 + 0.02, p.z), Color(1, 1, 1), 0.20))
		glow_lamps.append(_glow(1, halo, p + Vector3(0, 0.02, 0), Color(1, 1, 1), 0.55))
	var nh := QuadMesh.new()
	nh.size = Vector2(3.2, 1.6)
	glow_neon = _glow(1, nh, Vector3(5.05, 2.3, -2.85), Color(1.0, 0.16, 0.34), 0.35)


## The palette tweens drive the live lights; the baked room follows them every frame.
func _update_bake() -> void:
	if not baked or lights.is_empty():
		return
	var l0: Light3D = lights[0]
	var lc := l0.light_color * (l0.light_energy * LAMP_GAIN)
	# sky-coloured ambient from the palette, plus a little warm spill that rises and falls with the lamps
	var amb := env.ambient_light_color * (env.ambient_light_energy * AMBIENT_GAIN) + Color(0.075, 0.060, 0.048) * (l0.light_energy / 3.4)
	var accent := neon_light.light_energy / 0.9 if neon_light else 1.0
	var head := headlight.light_energy / 6.0 * 0.4 if headlight and headlight.visible else 0.0
	var gl := l0.light_color * (l0.light_energy / 3.4)
	for g in glow_lamps:
		g.set_shader_parameter("color", Vector3(gl.r, gl.g, gl.b))
	if glow_neon:
		glow_neon.set_shader_parameter("strength", 0.35 * accent)
	for sm in baked_mats:
		sm.set_shader_parameter("lamp_col", Vector3(lc.r, lc.g, lc.b))
		sm.set_shader_parameter("ambient", Vector3(amb.r, amb.g, amb.b))
		sm.set_shader_parameter("accent_gain", accent)
		sm.set_shader_parameter("head_gain", head)


# ---------------------------------------------------------------- adaptive quality
## The game picks a quality tier, then steps down whenever the frame rate stays low.
##
## Measured in Chrome on Intel integrated graphics: the cost is per pixel (the room is lit by
## many lamps), and on the web neither 3D scaling nor MSAA changes it. What does work there is
## drawing fewer pixels and letting the browser stretch the canvas, so on the web a tier is a
## cap on how many lines the game draws. On desktop a tier scales the 3D view instead.
const TIERS := [
	{"lines": 1440, "scale": 1.0, "msaa": Viewport.MSAA_4X, "shadows": true, "glow": true},
	{"lines": 1080, "scale": 0.77, "msaa": Viewport.MSAA_2X, "shadows": true, "glow": true},
	{"lines": 810, "scale": 0.62, "msaa": Viewport.MSAA_DISABLED, "shadows": true, "glow": true},
	{"lines": 630, "scale": 0.5, "msaa": Viewport.MSAA_DISABLED, "shadows": false, "glow": false},
]
const FPS_FLOOR := 42.0
var tier: int = -1
var fps_t: float = 0.0
var fps_n: int = 0
var fps_grace: float = 4.0
var fps_now: float = 0.0
var shadow_lights: Array[Light3D] = []
var good_windows: int = 0
var slow_streak: int = 0
var stepped_up: bool = false
var is_web: bool = OS.has_feature("web")
var forced_tier: int = -2          # -2 = not read yet, -1 = automatic
var fps_label: Label


func _set_tier(t: int) -> void:
	t = clampi(t, 0, TIERS.size() - 1)
	if t == tier:
		return
	tier = t
	var q: Dictionary = TIERS[t]
	var vp := get_viewport()
	if is_web:
		# cap the canvas at this many lines; the browser stretches it to the window
		JavaScriptBridge.eval("""(function(lines){
			if (window.__lsRealDpr === undefined) { window.__lsRealDpr = window.devicePixelRatio || 1; }
			var r = Math.min(window.__lsRealDpr, lines / Math.max(1, window.innerHeight));
			window.__lsLines = lines;
			Object.defineProperty(window, 'devicePixelRatio', { get: function () { return Math.min(window.__lsRealDpr, window.__lsLines / Math.max(1, window.innerHeight)); }, configurable: true });
			window.dispatchEvent(new Event('resize'));
		})(%d)""" % int(q["lines"]), true)
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		# never render the room below about 600 lines, however small the window
		vp.scaling_3d_scale = clampf(maxf(float(q["scale"]), 600.0 / maxf(1.0, float(vp.size.y))), 0.25, 1.0)
	vp.msaa_3d = q["msaa"]
	for l in shadow_lights:
		l.shadow_enabled = q["shadows"]
	if env:
		env.glow_enabled = q["glow"]
	fps_grace = 2.5
	print("quality tier ", t)


## A fixed tier can be asked for: LS_TIER=0..3 on desktop, or ?tier=0..3 on the web page.
func _forced_tier() -> int:
	if forced_tier == -2:
		var v := OS.get_environment("LS_TIER")
		if v == "" and is_web:
			var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('tier') || ''", true)
			v = str(q) if q != null else ""
		forced_tier = int(v) if v.is_valid_int() else -1
	return forced_tier


func _initial_tier() -> int:
	var forced := _forced_tier()
	if forced >= 0:
		return forced
	if is_web:
		return 1   # 1080 lines: sharp enough, and a quarter of the pixels of a 4K window
	var px := float(get_viewport().size.x) * float(get_viewport().size.y)
	if px > 5.0e6:
		return 2
	if px > 2.4e6:
		return 1
	return 0


## F3 (or ?fps=1 on the web) shows the frame rate and the quality tier.
func _toggle_fps() -> void:
	if fps_label == null:
		fps_label = Label.new()
		fps_label.add_theme_font_override("font", load("res://assets/fonts/Inter.ttf"))
		fps_label.add_theme_font_size_override("font_size", 13)
		fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		fps_label.add_theme_constant_override("shadow_outline_size", 6)
		fps_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		fps_label.offset_left = -220
		fps_label.offset_top = -30
		fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fps_label.visible = false
		ui.add_child(fps_label)
	fps_label.visible = not fps_label.visible


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle_fps()


func _watch_fps(delta: float) -> void:
	if tier < 0:
		for l in lights:
			if l.shadow_enabled:
				shadow_lights.append(l)
		_set_tier(_initial_tier())
		if is_web and str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('fps') || ''", true)) == "1":
			_toggle_fps()
		return
	if fps_grace > 0.0:
		fps_grace -= delta
		fps_t = 0.0
		fps_n = 0
		return
	if delta > 3.0:
		# one long frame is a pause (tab switch, load); several in a row is a slow machine
		slow_streak += 1
		if slow_streak < 3:
			return
	else:
		slow_streak = 0
	fps_t += delta
	fps_n += 1
	if fps_t >= 1.5:
		var fps := float(fps_n) / fps_t
		fps_now = fps
		fps_t = 0.0
		fps_n = 0
		if fps_label and fps_label.visible:
			fps_label.text = "%d fps  ·  tier %d  ·  %d×%d" % [roundi(fps), tier, get_viewport().size.x, get_viewport().size.y]
		if fps < FPS_FLOOR and tier < TIERS.size() - 1 and _forced_tier() < 0:
			_set_tier(tier + 1)
			good_windows = 0
		elif fps > 57.0 and tier > 0 and not stepped_up and _forced_tier() < 0:
			# plenty of headroom for a while: try one tier better, once
			good_windows += 1
			if good_windows >= 6:
				stepped_up = true
				_set_tier(tier - 1)
		else:
			good_windows = 0


func _process(delta: float) -> void:
	_watch_fps(delta)
	_update_bake()
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
	if id == "hub" and Story.ch3_due():
		id = "ch3_phone"
	elif id == "hub" and Story.ch4_due():
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
	if id == "ch3_phone":
		_play("phone")
	else:
		_stop("phone")
	Story.grant_evidence(id)
	ui.show_scene(id)


## Cut to whoever is speaking; fall back to the scene's own shot for Frank, the Voice and narration.
func _on_line_who(who: String) -> void:
	if in_title or current_scene == "":
		return
	var target: String = SPEAKER_STATION.get(who, SCENE_STATION.get(current_scene, "hub"))
	if target != cam_station:
		_move_camera(target, 0.7)
	_direct_cast(who)
	# a confession gets a slow push-in while they talk
	if current_scene.begins_with("crack_") and puppets.has(who):
		if fov_tween:
			fov_tween.kill()
		fov_tween = create_tween()
		fov_tween.tween_interval(0.75)
		fov_tween.tween_property(cam, "fov", float(STATIONS[target][2]) - 9.0, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## The player showed this suspect a piece of evidence.
func _on_present(evidence_id: String) -> void:
	var r: Dictionary = Story.present(current_scene, evidence_id)
	match str(r["result"]):
		"crack":
			var who := current_scene.trim_prefix("int_")
			go(str(r["scene"]))
			if puppets.has(who):
				# Lenny bristles (brows down, chin away); the others are caught out (brows up)
				puppets[who].react(1.0, -1.0 if who == "lenny" else 1.0, -1.0 if who == "lenny" else 1.0)
		"wrong_state":
			Story.toast.emit("Not to this Frank. Shift, then show it again.")
			ui.show_interject(r["line"])
		"wrong":
			if not Story.over:
				Story.toast.emit("Five minutes gone.")
				ui.show_interject(r["line"])


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

func _move_camera(station: String, dur: float = 1.2) -> void:
	var st: Array = STATIONS[station]
	cam_station = station
	if cam_tween:
		cam_tween.kill()
	var target := Transform3D().looking_at(st[1] - st[0], Vector3.UP)
	target.origin = st[0]
	cam_base = target
	cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
	cam_tween.tween_property(cam, "transform", target, dur)
	cam_tween.tween_property(cam, "fov", float(st[2]), dur)


func _snap_camera(station: String) -> void:
	var st: Array = STATIONS[station]
	cam_station = station
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
	title_key.visible = true
	title_key.light_energy = 9.0
	neon_light.light_energy = 2.3
	_snap_camera("title")
	if music and music.stream and not music.playing:
		music.play()
	if music:
		music.volume_db = MUSIC_TITLE_DB
	ui.show_title()


func _set_cast_visible(on: bool) -> void:
	if baked_root:
		var bb := baked_root.find_child("Model_body", true, false) as Node3D
		if bb:
			bb.visible = on
	for n in ["Model_lenny", "Model_theo", "Model_mira", "Model_body", "PH_lenny", "PH_theo", "PH_mira", "PH_body"]:
		var node := get_node_or_null(n) as Node3D
		if node:
			# a placeholder stays hidden if its model replaced it
			if n.begins_with("PH_") and (get_node_or_null("Model_" + n.substr(3)) != null or baked_root != null):
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
	t.chain().tween_callback(func(): title_key.visible = false)
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
	if puppets.has(speaker):
		puppets[speaker].speak(str(lipsync.get(stem, "")))


func _is_voice_line(stem: String) -> bool:
	if current_scene == "" or not Story.scenes.has(current_scene):
		return false
	for l in Story.scenes[current_scene]["lines"]:
		if str(l.get("vo", "")) == stem:
			return str(l["who"]) == "voice"
	return false


## Sound effects live in assets/audio/<name>.(ogg|mp3|wav). Any that are missing are skipped.
func _build_sfx() -> void:
	var defs := {"drink": -4.0, "sober": -6.0, "room": -24.0, "police": -8.0, "page": -16.0, "evidence": -8.0, "phone": -7.0}
	for n in defs.keys():
		for ext in ["ogg", "mp3", "wav"]:
			var path := "res://assets/audio/%s.%s" % [n, ext]
			if not ResourceLoader.exists(path):
				continue
			var stream: AudioStream = load(path)
			if n == "room" or n == "phone":
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
	if on:
		headlight.visible = true
	t.tween_property(headlight, "light_energy", 6.0 if on else 0.0, 1.6 if on else 0.4)
	if not on:
		t.chain().tween_callback(func(): headlight.visible = headlights_on)
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
	# with a bake present the furniture comes from assets/baked/room.glb, already lit
	var use_bake := OS.get_environment("LS_NOBAKE") == "" and ResourceLoader.exists(BAKE_DIR + "room.glb")
	for slot in MODEL_SLOTS.keys():
		var path := "res://assets/models/%s.glb" % slot
		if use_bake and not RIG.has(slot):
			for c in get_children():
				if c.name == "PH_" + slot or str(c.name).begins_with("PH_" + slot + "_"):
					c.visible = false
			continue
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
			if RIG.has(slot) and i == 0:
				_make_puppet(str(slot), pivot, inst, float(cfg[2]))
			i += 1
		# hide the primitive placeholder(s) for this slot
		for c in get_children():
			if c.name == "PH_" + slot or str(c.name).begins_with("PH_" + slot + "_"):
				c.visible = false


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null


## Swap a character's material for the shader rig and give it a Puppet to drive it.
func _make_puppet(slot: String, pivot: Node3D, inst: Node3D, height: float) -> void:
	var mi := _find_mesh(inst)
	if mi == null or mi.mesh == null:
		return
	var box: AABB = mi.mesh.get_aabb()
	var rig: Dictionary = RIG[slot]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/puppet.gdshader")
	var src := mi.get_active_material(0) as BaseMaterial3D
	if src:
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		sm.set_shader_parameter("tint", Vector3(src.albedo_color.r, src.albedo_color.g, src.albedo_color.b))
		if src.normal_enabled and src.normal_texture:
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("use_normal", true)
		if src.roughness_texture:
			sm.set_shader_parameter("orm_tex", src.roughness_texture)
			sm.set_shader_parameter("use_orm", true)
			sm.set_shader_parameter("rough", src.roughness)
			sm.set_shader_parameter("metal", src.metallic)
		else:
			sm.set_shader_parameter("rough", src.roughness)
			sm.set_shader_parameter("metal", src.metallic)
	var h := box.size.y
	var cx := box.get_center().x
	var cz := box.get_center().z
	sm.set_shader_parameter("y0", box.position.y)
	sm.set_shader_parameter("h", h)
	sm.set_shader_parameter("waist", rig["waist"])
	sm.set_shader_parameter("neck", rig["neck"])
	sm.set_shader_parameter("mouth", rig["mouth"])
	sm.set_shader_parameter("chin", rig["chin"])
	sm.set_shader_parameter("eye", rig["eye"])
	sm.set_shader_parameter("eye_dx", rig["eye_dx"])
	sm.set_shader_parameter("eye_cx", rig["eye_cx"])
	if rig.has("arms"):
		var ar: Dictionary = rig["arms"]
		sm.set_shader_parameter("arms", true)
		sm.set_shader_parameter("arm_b", ar["b"])
		sm.set_shader_parameter("arm_h", ar["h"])
		sm.set_shader_parameter("shoulder", ar["shoulder"])
		sm.set_shader_parameter("elbow", ar["elbow"])
		sm.set_shader_parameter("arm_low", ar["low"])
	sm.set_shader_parameter("head_c", Vector2(cx + rig["c"].x * h, cz + rig["c"].y * h))
	sm.set_shader_parameter("face_z", cz + float(rig["face"]) * h)
	for si in mi.mesh.get_surface_count():
		mi.set_surface_override_material(si, sm)
	mi.extra_cull_margin = 0.5
	var pp := Puppet.new()
	pp.name = "Puppet_" + slot
	add_child(pp)
	pp.setup(pivot, sm, height * (float(rig["neck"]) + 1.0) * 0.5, slot.hash())
	if rig.has("arms"):
		pp.has_arms = true
		pp.gesture = float(rig["arms"]["gesture"])
		pp.lead_right = bool(rig["arms"]["lead_right"])
	puppets[slot] = pp


func _head_pos(slot: String) -> Vector3:
	var pp: Puppet = puppets[slot]
	return pp.pivot.global_position + Vector3(0, pp.head_height, 0)


## Point everyone's attention: at the speaker if one of them is talking, otherwise at Frank (the camera).
func _direct_cast(who: String) -> void:
	speaker = who if puppets.has(who) else ""
	for n in puppets.keys():
		var pp: Puppet = puppets[n]
		if n == speaker:
			pp.look_at_point(cam_base.origin, 1.0)
		elif speaker != "":
			pp.look_at_point(_head_pos(speaker), 0.85)
			pp.hush()
		else:
			pp.look_at_point(cam_base.origin, 0.75 if not in_hub else 0.35)
			pp.hush()


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
	if on:
		_direct_cast("")
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
	# a pair of wall sconces either side of the entrance, so the door end of the room has its own light
	for sz in [1.5, 3.3]:
		_tbox(Vector3(5.15, 2.0, sz), Vector3(0.03, 0.30, 0.14), brass)
		var sc := _tbox(Vector3(5.10, 2.03, sz), Vector3(0.07, 0.18, 0.10), _emissive(Color(1.0, 0.72, 0.40), 3.0))
		sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	headlight.visible = false          # a light that is off still costs per-pixel work unless hidden
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
	# the bar's landline: an old black desk phone on the back counter
	_box(Vector3(0.05, 0.99, -3.72), Vector3(0.24, 0.07, 0.2), Color(0.03, 0.03, 0.035), 0.35)
	_box(Vector3(0.05, 1.035, -3.76), Vector3(0.2, 0.05, 0.1), Color(0.03, 0.03, 0.035), 0.35)
	_cyl(Vector3(0.05, 1.085, -3.76), 0.028, 0.26, Color(0.03, 0.03, 0.035), 0.3, 0.0, PI * 0.5)
	_cyl(Vector3(0.05, 1.03, -3.66), 0.055, 0.012, Color(0.75, 0.72, 0.62), 0.5)
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
