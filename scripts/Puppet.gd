class_name Puppet
extends Node
## Drives one character's shader rig (shaders/puppet.gdshader): idle breathing and weight shift,
## looking at whoever is talking, nodding and jaw movement on their own lines, and reactions.

var mat: ShaderMaterial
var pivot: Node3D            # the character's placement in the room (faces +Z)
var head_height: float = 1.5 # metres above the floor
var seed_t: float = 0.0
var t: float = 0.0

var look_target: Vector3 = Vector3.ZERO
var has_target: bool = false
var look_strength: float = 0.0     # eased towards look_goal
var look_goal: float = 0.0
var glance: Vector2 = Vector2.ZERO # idle wander (yaw, pitch)
var glance_goal: Vector2 = Vector2.ZERO
var glance_left: float = 2.0

var head: Vector3 = Vector3.ZERO   # current pitch, yaw, roll
var torso: Vector3 = Vector3.ZERO
var jaw: float = 0.0

var env: PackedByteArray = PackedByteArray()   # voice loudness, 0..9 per ENV_STEP seconds
var speak_t: float = -1.0
var flinch: float = 0.0
var flinch_dir: Vector3 = Vector3(0.22, 0.18, 0.0)
var lean: float = 0.0
var lean_goal: float = 0.0
var rng := RandomNumberGenerator.new()

const ENV_STEP := 0.05
const MAX_YAW := 0.62
const MAX_PITCH := 0.30


func setup(p_pivot: Node3D, p_mat: ShaderMaterial, p_head_height: float, p_seed: int) -> void:
	pivot = p_pivot
	mat = p_mat
	head_height = p_head_height
	rng.seed = p_seed
	seed_t = rng.randf() * 20.0
	glance_left = rng.randf_range(1.0, 4.0)


func look_at_point(world: Vector3, strength: float = 1.0) -> void:
	look_target = world
	has_target = true
	look_goal = strength


func look_idle() -> void:
	look_goal = 0.0


## Start moving the mouth along a loudness envelope ("0379..." one digit per 50 ms).
func speak(envelope: String) -> void:
	env = envelope.to_ascii_buffer()
	speak_t = 0.0
	lean_goal = 1.0


func hush() -> void:
	speak_t = -1.0
	lean_goal = 0.0


func speaking() -> bool:
	return speak_t >= 0.0


## A reaction: the head drops and turns away, then comes back slowly.
func react(amount: float = 1.0, turn: float = 1.0) -> void:
	flinch = amount
	flinch_dir = Vector3(0.24, 0.20 * turn, 0.05 * turn)


func _loud() -> float:
	if speak_t < 0.0 or env.is_empty():
		return 0.0
	var f := speak_t / ENV_STEP
	var i := int(f)
	if i >= env.size() - 1:
		return 0.0
	var a := float(env[i] - 48) / 9.0
	var b := float(env[i + 1] - 48) / 9.0
	return clampf(lerpf(a, b, f - float(i)), 0.0, 1.0)


func _process(delta: float) -> void:
	if mat == null or pivot == null or not pivot.is_visible_in_tree():
		return
	t += delta
	var tt := t + seed_t

	# idle wander: every few seconds the eyes go somewhere else for a moment
	glance_left -= delta
	if glance_left <= 0.0:
		if glance_goal.length() > 0.01:
			glance_goal = Vector2.ZERO
			glance_left = rng.randf_range(3.0, 8.0)
		else:
			glance_goal = Vector2(rng.randf_range(-0.28, 0.28), rng.randf_range(-0.05, 0.10))
			glance_left = rng.randf_range(0.8, 2.2)
	glance = glance.lerp(glance_goal, 1.0 - exp(-delta * 3.5))

	# look target, in the character's own space
	look_strength = lerpf(look_strength, look_goal, 1.0 - exp(-delta * 2.5))
	var yaw := 0.0
	var pitch := 0.0
	if has_target:
		var d: Vector3 = pivot.global_transform.affine_inverse() * look_target
		d.y -= head_height
		yaw = clampf(atan2(d.x, d.z), -MAX_YAW * 1.4, MAX_YAW * 1.4) * look_strength
		pitch = clampf(-atan2(d.y, maxf(0.3, Vector2(d.x, d.z).length())), -MAX_PITCH, MAX_PITCH) * look_strength
	var idle_w := 1.0 - 0.6 * look_strength
	yaw += glance.x * idle_w + sin(tt * 0.31) * 0.025
	pitch += glance.y * idle_w + sin(tt * 0.47) * 0.012

	# speech: the jaw follows the voice, the head nods on the loud syllables
	var loud := 0.0
	if speak_t >= 0.0:
		speak_t += delta
		loud = _loud()
		if speak_t > float(env.size()) * ENV_STEP + 0.3:
			hush()
	jaw = lerpf(jaw, loud, 1.0 - exp(-delta * (26.0 if loud > jaw else 14.0)))
	pitch += jaw * 0.045 + (sin(tt * 2.3) * 0.012 if speak_t >= 0.0 else 0.0)
	yaw += sin(tt * 1.7) * 0.02 if speak_t >= 0.0 else 0.0
	lean = lerpf(lean, lean_goal, 1.0 - exp(-delta * 2.0))

	# reaction
	flinch = maxf(0.0, flinch - delta * (0.9 if flinch > 0.5 else 0.35))
	var fl := smoothstep(0.0, 1.0, flinch)
	pitch += flinch_dir.x * fl
	yaw += flinch_dir.y * fl

	yaw = clampf(yaw, -MAX_YAW, MAX_YAW)
	var goal_head := Vector3(pitch, yaw * 0.78, sin(tt * 0.23) * 0.012 + flinch_dir.z * fl - yaw * 0.06)
	var goal_torso := Vector3(
		sin(tt * 0.9) * 0.004 + lean * 0.022 + fl * 0.05,
		yaw * 0.22,
		sin(tt * 0.19) * 0.010)
	var k := 1.0 - exp(-delta * 7.0)
	head = head.lerp(goal_head, k)
	torso = torso.lerp(goal_torso, k)
	mat.set_shader_parameter("head_rot", head)
	mat.set_shader_parameter("torso_rot", torso)
	mat.set_shader_parameter("jaw", jaw)
	mat.set_shader_parameter("breathe", sin(tt * 1.55))
