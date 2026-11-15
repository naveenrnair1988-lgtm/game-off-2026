class_name Actor
extends Puppet
## A skinned character: body animation clips from the rig, a head that turns to whoever is
## talking (laid over the clip by a skeleton modifier), and face shape keys for the jaw, lids and
## brows. Same interface as Puppet, so the rest of the game does not care which kind it has.

var skel: Skeleton3D
var mesh: MeshInstance3D
var anim: AnimationPlayer
var clip_idle: String = "idle"
var clip_talk: String = "talk"
var clip_now: String = ""
var bs: Dictionary = {}            # shape key name -> index
var turner: HeadTurn
var hold_clip: String = ""         # a pose held instead of the idle (e.g. kneeling), and where in it
var hold_at: float = 0.0
var idle_len: float = 0.0          # use only this much of the idle clip, back and forth (0 = all of it)
var seat: bool = false             # a sitting clip drifts off the origin: put the hips back over the pivot


## Lays the look-at rotation over whatever the animation did this frame.
class HeadTurn extends SkeletonModifier3D:
	var actor: Actor
	var b_head: int = -1
	var b_neck: int = -1
	var b_spine: int = -1

	func _process_modification() -> void:
		var s := get_skeleton()
		if s == null or actor == null or actor.pivot == null:
			return
		# rotations are worked out in the character's own space (faces +Z) and moved into the skeleton's
		var to_skel := s.global_transform.basis.orthonormalized().inverse() * actor.pivot.global_transform.basis.orthonormalized()
		var h := actor.head
		var t := actor.torso
		_turn(s, b_spine, to_skel, Vector3(t.x, t.y, t.z))
		_turn(s, b_neck, to_skel, Vector3(h.x * 0.4, h.y * 0.4, h.z * 0.4))
		_turn(s, b_head, to_skel, Vector3(h.x * 0.6, h.y * 0.6, h.z * 0.6))

	func _turn(s: Skeleton3D, b: int, to_skel: Basis, e: Vector3) -> void:
		if b < 0:
			return
		var r := Basis.from_euler(Vector3(e.x, e.y, e.z), EULER_ORDER_YXZ)
		var rs := to_skel * r * to_skel.inverse()
		var g := s.get_bone_global_pose(b)
		g.basis = rs * g.basis
		s.set_bone_global_pose(b, g)


func setup_actor(p_pivot: Node3D, inst: Node3D, p_mat: ShaderMaterial, p_head_height: float, p_seed: int) -> void:
	setup(p_pivot, p_mat, p_head_height, p_seed)
	skel = _find(inst, "Skeleton3D") as Skeleton3D
	mesh = _find(inst, "MeshInstance3D") as MeshInstance3D
	anim = _find(inst, "AnimationPlayer") as AnimationPlayer
	if mesh and mesh.mesh:
		for i in mesh.mesh.get_blend_shape_count():
			bs[str(mesh.mesh.get_blend_shape_name(i))] = i
	if skel:
		turner = HeadTurn.new()
		turner.name = "HeadTurn"
		turner.actor = self
		turner.b_head = skel.find_bone("Head")
		turner.b_neck = skel.find_bone("neck")
		turner.b_spine = skel.find_bone("Spine01")
		skel.add_child(turner)
	if anim:
		for n in anim.get_animation_list():
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		if idle_len > 0.0 and anim.has_animation(clip_idle):
			var ia := anim.get_animation(clip_idle)
			ia.length = minf(idle_len, ia.length)
			ia.loop_mode = Animation.LOOP_PINGPONG
		_play(clip_idle, 0.0)
		if seat and skel:
			anim.seek(0.0, true)
			var hb := skel.find_bone("Hips")
			if hb >= 0:
				var hips: Vector3 = pivot.global_transform.affine_inverse() * (skel.global_transform * skel.get_bone_global_pose(hb).origin)
				inst.position.x -= hips.x
				inst.position.z -= hips.z
		elif anim.current_animation != "":
			anim.seek(rng.randf() * anim.current_animation_length, true)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _play(clip: String, blend: float) -> void:
	if anim == null or not anim.has_animation(clip) or clip == clip_now:
		return
	clip_now = clip
	anim.play(clip, blend)


## Hold one moment of a clip as a pose (Mira kneeling by the body). Empty name releases it.
func hold(clip: String, at: float = 0.0) -> void:
	hold_clip = clip
	hold_at = at
	if anim == null:
		return
	if clip == "":
		anim.speed_scale = 1.0
		_play(clip_idle, 1.2)
	elif anim.has_animation(clip):
		clip_now = clip
		anim.play(clip, 0.0)      # a blend would never finish with the clip stopped
		anim.seek(at, true)
		anim.speed_scale = 0.0


func speak(envelope: String) -> void:
	super.speak(envelope)
	if hold_clip == "":
		_play(clip_talk, 0.45)


func hush() -> void:
	super.hush()
	if hold_clip == "":
		_play(clip_idle, 0.7)


func _shape(n: String, v: float) -> void:
	if bs.has(n):
		mesh.set_blend_shape_value(bs[n], clampf(v, 0.0, 1.0))


func _process(delta: float) -> void:
	if mat == null or pivot == null or not pivot.is_visible_in_tree():
		return
	t += delta
	var tt := t + seed_t

	glance_left -= delta
	if glance_left <= 0.0:
		if glance_goal.length() > 0.01:
			glance_goal = Vector2.ZERO
			glance_left = rng.randf_range(3.0, 8.0)
		else:
			glance_goal = Vector2(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.05, 0.10))
			glance_left = rng.randf_range(0.8, 2.2)
	glance = glance.lerp(glance_goal, 1.0 - exp(-delta * 3.5))

	look_strength = lerpf(look_strength, look_goal, 1.0 - exp(-delta * 2.5))
	var yaw := 0.0
	var pitch := 0.0
	if has_target:
		var d: Vector3 = pivot.global_transform.affine_inverse() * look_target
		d.y -= head_height
		yaw = clampf(atan2(d.x, d.z), -MAX_YAW * 1.4, MAX_YAW * 1.4) * look_strength
		pitch = clampf(-atan2(d.y, maxf(0.3, Vector2(d.x, d.z).length())), -MAX_PITCH, MAX_PITCH) * look_strength
	var idle_w := 1.0 - 0.6 * look_strength
	yaw += glance.x * idle_w
	pitch += glance.y * idle_w

	var loud := 0.0
	if speak_t >= 0.0:
		speak_t += delta
		loud = _loud()
		if speak_t > float(env.size()) * ENV_STEP + 0.3:
			hush()
	jaw = lerpf(jaw, loud, 1.0 - exp(-delta * (26.0 if loud > jaw else 14.0)))
	pitch += jaw * 0.04
	if hold_clip != "":
		pitch -= 0.5 * look_strength   # held low (kneeling): the face comes up to whoever she is looking at

	flinch = maxf(0.0, flinch - delta * (0.9 if flinch > 0.5 else 0.35))
	var fl := smoothstep(0.0, 1.0, flinch)
	pitch += flinch_dir.x * fl
	yaw += flinch_dir.y * fl

	blink_left -= delta
	if blink_left <= 0.0 and blink_t < 0.0:
		blink_t = 0.0
		blink_left = rng.randf_range(2.2, 6.0)
	var lid := 0.0
	if blink_t >= 0.0:
		blink_t += delta
		lid = sin(clampf(blink_t / 0.17, 0.0, 1.0) * PI)
		if blink_t >= 0.17:
			blink_t = -1.0
	brow_goal = lerpf(brow_goal, 0.0, 1.0 - exp(-delta * 0.25))
	brow = lerpf(brow, brow_goal + jaw * 0.35, 1.0 - exp(-delta * 6.0))

	yaw = clampf(yaw, -MAX_YAW, MAX_YAW)
	var k := 1.0 - exp(-delta * 7.0)
	head = head.lerp(Vector3(pitch, yaw * 0.78, flinch_dir.z * fl), k)
	torso = torso.lerp(Vector3(fl * 0.05, yaw * 0.22, 0.0), k)

	_shape("jaw", jaw)
	_shape("blink", lid)
	_shape("brow_up", brow)
	_shape("brow_dn", -brow)
	mat.set_shader_parameter("jaw", jaw)
