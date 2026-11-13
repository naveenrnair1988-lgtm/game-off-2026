extends SceneTree
## Step 1 of the lighting bake: write the static room out for Blender.
## Run:  godot --headless --path . -s tools/export_scene.gd -- <out_dir>
## Writes scene.json plus one .bin per mesh (float32 positions, normals, uvs; uint32 indices),
## all in world space. tools/bake_room.py picks it up from there.

var out_dir := ""
var manifest := {"meshes": [], "lights": [], "materials": {}}
var n_bin := 0


func _init() -> void:
	call_deferred("_run")


func _key_for(main: Node, m: Material) -> String:
	if m is ShaderMaterial:
		return ""
	var sm := m as StandardMaterial3D
	if sm == null:
		return "col:808080"
	for n in main.mats.keys():
		if main.mats[n] == sm:
			_note_material(str(n), sm)
			return str(n)
	var k := "col:%s:%d:%d" % [sm.albedo_color.to_html(false), int(sm.roughness * 100.0), int(sm.metallic * 100.0)]
	_note_material(k, sm)
	return k


func _note_material(k: String, sm: StandardMaterial3D) -> void:
	if manifest["materials"].has(k):
		return
	manifest["materials"][k] = {
		"color": [sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b],
		"rough": sm.roughness, "metal": sm.metallic,
		"tex": sm.albedo_texture.resource_path if sm.albedo_texture else "",
		"normal": sm.normal_texture.resource_path if sm.normal_texture else "",
		"normal_scale": sm.normal_scale,
		"triplanar": sm.uv1_triplanar, "scale": sm.uv1_scale.x,
	}


func _write_mesh(mi: MeshInstance3D, role: String, key: String, extra: Dictionary = {}) -> void:
	var xf := mi.global_transform
	var nb := xf.basis.inverse().transposed()
	var flip := xf.basis.determinant() < 0.0
	for si in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var pos := PackedFloat32Array()
		var nn := PackedFloat32Array()
		var uu := PackedFloat32Array()
		pos.resize(v.size() * 3)
		nn.resize(v.size() * 3)
		uu.resize(v.size() * 2)
		for i in v.size():
			var p := xf * v[i]
			pos[i * 3] = p.x
			pos[i * 3 + 1] = p.y
			pos[i * 3 + 2] = p.z
			var q := (nb * nrm[i]).normalized() if i < nrm.size() else Vector3.UP
			nn[i * 3] = q.x
			nn[i * 3 + 1] = q.y
			nn[i * 3 + 2] = q.z
			if i < uv.size():
				uu[i * 2] = uv[i].x
				uu[i * 2 + 1] = uv[i].y
		if idx.is_empty():
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		var name := "m%04d.bin" % n_bin
		n_bin += 1
		var f := FileAccess.open(out_dir + "/" + name, FileAccess.WRITE)
		f.store_buffer(pos.to_byte_array())
		f.store_buffer(nn.to_byte_array())
		f.store_buffer(uu.to_byte_array())
		f.store_buffer(idx.to_byte_array())
		f.close()
		var e := {"file": name, "verts": v.size(), "indices": idx.size(), "role": role, "key": key, "name": str(mi.name), "flip": flip, "has_uv": not uv.is_empty()}
		e.merge(extra)
		manifest["meshes"].append(e)


func _all_meshes(n: Node, acc: Array) -> void:
	if n is MeshInstance3D:
		acc.append(n)
	for c in n.get_children():
		_all_meshes(c, acc)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "bake_tmp"
	DirAccess.make_dir_recursive_absolute(out_dir)
	OS.set_environment("LS_NOBAKE", "1")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame
	main.ui._start()
	for i in 3:
		await process_frame
	for c in main.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var nm := str(mi.name)
			if not mi.visible or main.clue_meshes.has(mi) or nm.begins_with("PH_lamp_"):
				continue
			var sm := mi.material_override as StandardMaterial3D
			if sm == null:
				continue
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if sm.emission_enabled or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				var col := sm.emission if sm.emission_enabled else sm.albedo_color
				var en := sm.emission_energy_multiplier if sm.emission_enabled else 1.0
				_write_mesh(mi, "emit", "emit", {"color": [col.r, col.g, col.b], "energy": en, "group": "street" if nm == "Window" else "lamps"})
				continue
			mi.set_meta("baked", true)
			_write_mesh(mi, "bake", _key_for(main, sm))
		elif c is Node3D and str(c.name).begins_with("Model_"):
			var slot := str(c.name).trim_prefix("Model_").get_slice("_", 0)
			var acc: Array = []
			_all_meshes(c, acc)
			for mi in acc:
				if main.RIG.has(slot):
					_write_mesh(mi, "caster", "caster")
				else:
					_write_mesh(mi, "bake", "prop:" + slot, {"instance": str(c.name)})
		elif c is OmniLight3D:
			var l := c as OmniLight3D
			var kind := "lamp"
			if l == main.neon_light:
				kind = "neon"
			elif l == main.headlight:
				kind = "headlight"
			elif not main.lights.has(l):
				kind = "street"
			manifest["lights"].append({"kind": kind, "pos": [l.position.x, l.position.y, l.position.z], "color": [l.light_color.r, l.light_color.g, l.light_color.b], "energy": l.light_energy, "range": l.omni_range})
	var f := FileAccess.open(out_dir + "/scene.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	print("exported ", manifest["meshes"].size(), " meshes, ", manifest["lights"].size(), " lights to ", out_dir)
	quit()
