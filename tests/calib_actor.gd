extends SceneTree
## Calibration renders for a skinned character: face shapes, head turns and the body clips.
## SHOT_DIR, ONLY=name (default theo).
func _init(): call_deferred("_run")

func _run():
	var M = load("res://scripts/Main.gd")
	var RIG: Dictionary = M.get_script_constant_map()["RIG"]
	var dir := OS.get_environment("SHOT_DIR")
	var slot := OS.get_environment("ONLY") if OS.get_environment("ONLY") != "" else "theo"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var rig: Dictionary = RIG[slot]
	var pivot := Node3D.new()
	root.add_child(pivot)
	var inst: Node3D = load("res://assets/models/%s.glb" % slot).instantiate()
	pivot.add_child(inst)
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/character.gdshader")
	var src := mi.get_active_material(0) as BaseMaterial3D
	sm.set_shader_parameter("albedo_tex", src.albedo_texture)
	sm.set_shader_parameter("mouth", rig["mouth"])
	for si in mi.mesh.get_surface_count():
		mi.set_surface_override_material(si, sm)
	var h := float(rig["h"])
	var a := Actor.new()
	a.clip_idle = str(rig.get("idle", "idle"))
	a.clip_talk = str(rig.get("talk", "talk"))
	root.add_child(a)
	a.setup_actor(pivot, inst, sm, h * float(rig.get("head_h", 0.93)), 7)
	a.set_process(false)
	var head := Vector3(0, h * float(rig["eye"]) - 0.02, 0.06)
	var poses := {
		"open": {}, "half": {"jaw": 0.5}, "jaw": {"jaw": 1.0}, "shut": {"blink": 1.0}, "browup": {"brow_up": 1.0}, "browdn": {"brow_dn": 1.0},
		"left": {"_head": Vector3(0.0, 0.5, 0.0)}, "down": {"_head": Vector3(0.25, 0.0, 0.0)},
		"body0": {"_body": 0.0}, "body1": {"_body": 1.5}, "body2": {"_body": 3.0}, "talk1": {"_body": 1.0, "_clip": "talk"}, "talk2": {"_body": 2.2, "_clip": "talk"},
	}
	for pn in poses.keys():
		var p: Dictionary = poses[pn]
		for k in ["jaw", "blink", "brow_up", "brow_dn"]:
			a._shape(k, float(p.get(k, 0.0)))
		sm.set_shader_parameter("jaw", float(p.get("jaw", 0.0)))
		a.head = p.get("_head", Vector3.ZERO)
		if p.has("_body"):
			var clip: String = p.get("_clip", a.clip_idle)
			if a.anim.has_animation(clip):
				a.anim.play(clip)
				a.anim.seek(float(p["_body"]), true)
				a.anim.pause()
			cam.fov = 30
			cam.look_at_from_position(Vector3(1.2, h * 0.6, 4.2), Vector3(0, h * 0.52, 0))
		else:
			a.anim.play(a.clip_idle); a.anim.seek(0.0, true); a.anim.pause()
			cam.fov = 9
			# aim at the head bone wherever the clip put it
			var hb := a.skel.global_transform * a.skel.get_bone_global_pose(a.skel.find_bone("Head")).origin
			var tgt := hb + Vector3(0, h * 0.045, 0.0)
			cam.look_at_from_position(tgt + Vector3(0.2, 0.0, 2.9), tgt)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [dir, slot, pn])
	quit()
