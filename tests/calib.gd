extends SceneTree
## Rig calibration renders: each character's head with the jaw open, eyes shut, brows moved, head turned,
## and arms raised. SHOT_DIR, optional ONLY=name.
func _init(): call_deferred("_run")

func _run():
	var M = load("res://scripts/Main.gd")
	var RIG: Dictionary = M.get_script_constant_map()["RIG"]
	var dir := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("ONLY")
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
	for slot in RIG.keys():
		if only != "" and only != slot:
			continue
		var rig: Dictionary = RIG[slot]
		var inst: Node3D = load("res://assets/models/%s.glb" % slot).instantiate()
		root.add_child(inst)
		var mi := _find(inst)
		var box: AABB = mi.mesh.get_aabb()
		var h := box.size.y
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/puppet.gdshader")
		var src := mi.get_active_material(0) as BaseMaterial3D
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		var cx := box.get_center().x
		var cz := box.get_center().z
		sm.set_shader_parameter("y0", box.position.y)
		sm.set_shader_parameter("h", h)
		for k in ["waist", "neck", "mouth", "chin", "eye", "eye_dx", "eye_cx", "mouth_w"]:
			sm.set_shader_parameter(k, rig[k])
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
		var g: Transform3D = mi.global_transform
		var head := g * Vector3(cx + rig["c"].x * h, box.position.y + (float(rig["eye"]) - 0.015) * h, cz + float(rig["face"]) * h)
		var s := g.basis.get_scale().y * h
		var poses := {
			"open": {}, "jaw": {"jaw": 1.0}, "half": {"jaw": 0.5}, "shut": {"blink": 1.0}, "browup": {"brow": 1.0}, "browdn": {"brow": -1.0},
			"turn": {"head_rot": Vector3(0.15, 0.55, 0.0)}, "side": {"jaw": 1.0, "_side": true},
			"body": {"_body": true}, "arms": {"_body": true, "arm_l": Vector2(0.35, 0.7), "arm_r": Vector2(0.6, 1.1), "torso_rot": Vector3(0.08, 0.2, 0.0)},
		}
		for pn in poses.keys():
			var p: Dictionary = poses[pn]
			for k in ["jaw", "blink", "brow"]:
				sm.set_shader_parameter(k, p.get(k, 0.0))
			sm.set_shader_parameter("head_rot", p.get("head_rot", Vector3.ZERO))
			sm.set_shader_parameter("torso_rot", p.get("torso_rot", Vector3.ZERO))
			sm.set_shader_parameter("arm_l", p.get("arm_l", Vector2.ZERO))
			sm.set_shader_parameter("arm_r", p.get("arm_r", Vector2.ZERO))
			if p.has("_body"):
				var mid := g * Vector3(cx, box.position.y + 0.55 * h, cz)
				cam.fov = 30
				cam.look_at_from_position(mid + Vector3(0.9 * s, 0.1 * s, 2.3 * s), mid)
			elif p.has("_side"):
				cam.fov = 12
				cam.look_at_from_position(head + Vector3(1.6 * s, 0.0, -0.05 * s), head + Vector3(0, 0, -0.05 * s))
			else:
				cam.fov = 9
				cam.look_at_from_position(head + Vector3(0.12 * s, 0.0, 1.7 * s), head)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [dir, slot, pn])
		inst.queue_free()
		await process_frame
	quit()

func _find(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find(c)
		if m:
			return m
	return null
