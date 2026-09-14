class_name StatueCrumbleEffect
extends RefCounted

## Visual particle effect for the Statue's awakening and movement in the dark.
## Emits:
## 1. Awakening Crumble: Stone flakes, pebbles, and pulverized ancient mortar dust
##    crumbling and showering down off the statue's body when transitioning from
##    frozen stone to active pursuit.
## 2. Movement Step Crumble: Subtle stone grit and dust puffs shed at the feet
##    during strides in the dark.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"
const CRUMBLE_SOUND_PATH := "res://sounds/Interactions/hit_solid.mp3"

const AWAKENING_PEBBLE_AMOUNT := 32
const AWAKENING_DUST_AMOUNT := 22
const AWAKENING_GRIT_AMOUNT := 20
const STEP_PEBBLE_AMOUNT := 8
const STEP_DUST_AMOUNT := 6

const EFFECT_LIFETIME := 2.0


## Spawns the full awakening crumble effect over the statue's body.
## [param scene_tree] - SceneTree reference
## [param statue_position] - Global origin of the statue CharacterBody3D
## [param forward_dir] - Facing direction of the statue
static func spawn_awakening(scene_tree: SceneTree, statue_position: Vector3, forward_dir: Vector3 = Vector3.FORWARD) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "StatueAwakeningCrumbleFX"
	root.add_child(container)
	# Center container roughly at torso/chest height of the statue
	container.global_position = statue_position + Vector3(0.0, 1.6, 0.0)

	var dir := forward_dir.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD

	# 1. Shower of crumbling stone pebbles cascading down from body/joints
	_spawn_body_pebbles(container, dir)

	# 2. Billowing ancient mortar and stone dust puffs
	_spawn_body_dust(container, dir)

	# 3. Fine crumbling stone grit
	_spawn_joint_grit(container)

	# 4. Subtle stone cracking / crumble audio
	_spawn_crumble_audio(container)

	# 5. Cleanup
	_schedule_cleanup(scene_tree, container)


## Spawns a subtle footstep crumble when the statue takes heavy strides.
## [param scene_tree] - SceneTree reference
## [param foot_position] - Ground contact point near feet
static func spawn_step_crumble(scene_tree: SceneTree, foot_position: Vector3) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "StatueStepCrumbleFX"
	root.add_child(container)
	container.global_position = foot_position + Vector3(0.0, 0.08, 0.0)

	# 1. Footstep stone chips
	var chips := CPUParticles3D.new()
	chips.name = "StepChips"
	chips.emitting = false
	chips.one_shot = true
	chips.amount = STEP_PEBBLE_AMOUNT
	chips.lifetime = 0.55
	chips.explosiveness = 0.92

	chips.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	chips.emission_sphere_radius = 0.15

	chips.direction = Vector3.UP
	chips.spread = 60.0
	chips.initial_velocity_min = 1.0
	chips.initial_velocity_max = 2.4
	chips.gravity = Vector3(0.0, -16.0, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.65, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	chips.scale_amount_curve = scale_curve

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(0.60, 0.58, 0.54, 1.0),
		Color(0.42, 0.40, 0.36, 1.0),
		Color(0.28, 0.26, 0.22, 0.0),
	])
	chips.color_ramp = grad

	var box := BoxMesh.new()
	box.size = Vector3(0.038, 0.038, 0.038)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.58, 0.55, 0.50)
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	chips.mesh = box

	container.add_child(chips)
	chips.position = Vector3.ZERO
	chips.restart()
	chips.emitting = true

	# 2. Footstep ground dust
	var dust := CPUParticles3D.new()
	dust.name = "StepDust"
	dust.emitting = false
	dust.one_shot = true
	dust.amount = STEP_DUST_AMOUNT
	dust.lifetime = 0.5
	dust.explosiveness = 0.88

	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.12

	dust.direction = Vector3.UP
	dust.spread = 70.0
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 1.6
	dust.damping_min = 1.5
	dust.damping_max = 2.8
	dust.gravity = Vector3(0.0, 0.2, 0.0)

	var dust_curve := Curve.new()
	dust_curve.add_point(Vector2(0.0, 0.35))
	dust_curve.add_point(Vector2(0.3, 1.1))
	dust_curve.add_point(Vector2(1.0, 1.6))
	dust.scale_amount_curve = dust_curve

	var dust_grad := Gradient.new()
	dust_grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	dust_grad.colors = PackedColorArray([
		Color(0.72, 0.68, 0.60, 0.0),
		Color(0.68, 0.64, 0.56, 0.45),
		Color(0.50, 0.46, 0.40, 0.25),
		Color(0.35, 0.32, 0.28, 0.0),
	])
	dust.color_ramp = dust_grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust_mat.vertex_color_use_as_albedo = true

	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex != null:
		dust_mat.albedo_texture = tex
	quad.material = dust_mat
	dust.mesh = quad

	container.add_child(dust)
	dust.position = Vector3.ZERO
	dust.restart()
	dust.emitting = true

	_schedule_cleanup(scene_tree, container)


# ── Awakening Components ─────────────────────────────────────────────────────

static func _spawn_body_pebbles(parent: Node3D, forward_dir: Vector3) -> void:
	var pebbles := CPUParticles3D.new()
	pebbles.name = "BodyPebbles"
	pebbles.emitting = false
	pebbles.one_shot = true
	pebbles.amount = AWAKENING_PEBBLE_AMOUNT
	pebbles.lifetime = 0.9
	pebbles.explosiveness = 0.92
	pebbles.lifetime_randomness = 0.45

	# Emitted along the torso and limbs
	pebbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pebbles.emission_box_extents = Vector3(0.42, 0.9, 0.35)

	# Slight outward burst with bias forward in direction of awakening step
	var burst_dir := (forward_dir * 0.4 + Vector3(0.0, 0.2, 0.0)).normalized()
	pebbles.direction = burst_dir
	pebbles.spread = 75.0
	pebbles.initial_velocity_min = 1.2
	pebbles.initial_velocity_max = 3.0
	pebbles.damping_min = 1.0
	pebbles.damping_max = 2.4
	pebbles.gravity = Vector3(0.0, -17.5, 0.0)

	pebbles.angular_velocity_min = -320.0
	pebbles.angular_velocity_max = 320.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.9))
	scale_curve.add_point(Vector2(0.65, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	pebbles.scale_amount_curve = scale_curve
	pebbles.scale_amount_min = 0.5
	pebbles.scale_amount_max = 1.4

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.65, 0.62, 0.57, 1.0),
		Color(0.44, 0.41, 0.37, 1.0),
		Color(0.28, 0.25, 0.22, 0.0),
	])
	pebbles.color_ramp = grad

	var box := BoxMesh.new()
	box.size = Vector3(0.048, 0.048, 0.048)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.62, 0.59, 0.53)
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	pebbles.mesh = box

	parent.add_child(pebbles)
	pebbles.position = Vector3.ZERO
	pebbles.restart()
	pebbles.emitting = true


static func _spawn_body_dust(parent: Node3D, forward_dir: Vector3) -> void:
	var dust := CPUParticles3D.new()
	dust.name = "BodyDust"
	dust.emitting = false
	dust.one_shot = true
	dust.amount = AWAKENING_DUST_AMOUNT
	dust.lifetime = 1.05
	dust.explosiveness = 0.88
	dust.lifetime_randomness = 0.35

	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.4, 0.85, 0.3)

	dust.direction = (forward_dir * 0.3 + Vector3(0.0, -0.2, 0.0)).normalized()
	dust.spread = 65.0
	dust.initial_velocity_min = 0.8
	dust.initial_velocity_max = 2.4
	dust.damping_min = 1.8
	dust.damping_max = 3.2
	dust.gravity = Vector3(0.0, -0.6, 0.0)

	dust.angle_min = -180.0
	dust.angle_max = 180.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.25, 1.25))
	scale_curve.add_point(Vector2(1.0, 1.85))
	dust.scale_amount_curve = scale_curve
	dust.scale_amount_min = 0.75
	dust.scale_amount_max = 1.6

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.74, 0.70, 0.62, 0.0),
		Color(0.70, 0.65, 0.56, 0.52),
		Color(0.55, 0.50, 0.42, 0.28),
		Color(0.38, 0.34, 0.28, 0.0),
	])
	dust.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.65, 0.65)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true

	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex != null:
		mat.albedo_texture = tex
	quad.material = mat
	dust.mesh = quad

	parent.add_child(dust)
	dust.position = Vector3.ZERO
	dust.restart()
	dust.emitting = true


static func _spawn_joint_grit(parent: Node3D) -> void:
	var grit := CPUParticles3D.new()
	grit.name = "JointGrit"
	grit.emitting = false
	grit.one_shot = true
	grit.amount = AWAKENING_GRIT_AMOUNT
	grit.lifetime = 0.8
	grit.explosiveness = 0.95
	grit.lifetime_randomness = 0.4

	grit.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	grit.emission_box_extents = Vector3(0.35, 0.7, 0.25)

	grit.direction = Vector3.DOWN
	grit.spread = 45.0
	grit.initial_velocity_min = 0.5
	grit.initial_velocity_max = 1.8
	grit.damping_min = 1.2
	grit.damping_max = 2.5
	grit.gravity = Vector3(0.0, -19.0, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.6, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	grit.scale_amount_curve = scale_curve
	grit.scale_amount_min = 0.4
	grit.scale_amount_max = 1.0

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(0.58, 0.54, 0.48, 1.0),
		Color(0.40, 0.37, 0.33, 1.0),
		Color(0.25, 0.22, 0.20, 0.0),
	])
	grit.color_ramp = grad

	var sphere := SphereMesh.new()
	sphere.radius = 0.018
	sphere.height = 0.036
	sphere.radial_segments = 4
	sphere.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	grit.mesh = sphere
	grit.material_override = mat

	parent.add_child(grit)
	grit.position = Vector3.ZERO
	grit.restart()
	grit.emitting = true


static func _spawn_crumble_audio(parent: Node3D) -> void:
	var audio := AudioStreamPlayer3D.new()
	audio.name = "CrumbleAudio"
	var stream: AudioStream = load(CRUMBLE_SOUND_PATH)
	if stream == null:
		return

	audio.stream = stream
	audio.volume_db = -4.0
	audio.pitch_scale = randf_range(0.62, 0.78)  # Deeper stone cracking / crumbling pitch
	audio.unit_size = 4.0
	audio.max_distance = 22.0

	parent.add_child(audio)
	audio.position = Vector3.ZERO
	audio.play()


static func _schedule_cleanup(scene_tree: SceneTree, container: Node3D) -> void:
	if scene_tree == null or container == null:
		return

	var timer := scene_tree.create_timer(EFFECT_LIFETIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)
