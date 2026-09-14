class_name LandingDustEffect
extends RefCounted

## Radial stone dust puff and ground debris particle effect for player jumping and landing.
## Emits:
## 1. Expanding radial ring of stone dust billowing outward along the floor.
## 2. Snappy central ground dust poof right beneath the boots.
## 3. Physical stone debris chips / pebbles scattered across the floor on impact.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"

# Normal jump takeoff counts
const JUMP_RING_AMOUNT := 18
const JUMP_RING_LIFETIME := 0.45
const JUMP_RING_RADIUS := 0.35
const JUMP_DEBRIS_AMOUNT := 8

# Normal landing counts
const NORMAL_RING_AMOUNT := 28
const NORMAL_RING_LIFETIME := 0.65
const NORMAL_RING_RADIUS := 0.6
const NORMAL_DEBRIS_AMOUNT := 14

# Hard landing counts (larger impact, heavier billowing cloud and pebbles)
const HARD_RING_AMOUNT := 54
const HARD_RING_LIFETIME := 0.95
const HARD_RING_RADIUS := 1.25
const HARD_DEBRIS_AMOUNT := 32

const EFFECT_DURATION := 1.5


## Spawns dust burst when player jumps off the ground.
## [param scene_tree] - SceneTree reference (get_tree())
## [param origin] - 3D position at the player's feet
static func spawn_jump(scene_tree: SceneTree, origin: Vector3) -> void:
	_spawn_effect(scene_tree, origin, false, false, 0.0)


## Spawns dust burst when player touches down on the floor.
## [param scene_tree] - SceneTree reference (get_tree())
## [param origin] - 3D position at the player's feet
## [param is_hard] - Whether this was a high-velocity hard impact
## [param intensity] - Normalized intensity factor (0.0 to 1.0)
static func spawn_landing(scene_tree: SceneTree, origin: Vector3, is_hard: bool = false, intensity: float = 0.0) -> void:
	_spawn_effect(scene_tree, origin, true, is_hard, intensity)


## Spawns a dust puff kicked backwards when sprinting.
## [param scene_tree] - SceneTree reference (get_tree())
## [param origin] - 3D position at the player's feet
## [param move_direction] - Movement direction vector
static func spawn_sprint(scene_tree: SceneTree, origin: Vector3, move_direction: Vector3 = Vector3.ZERO) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "SprintDustFX"
	root.add_child(container)
	container.global_position = origin + Vector3(0.0, 0.04, 0.0)

	# Calculate kickback direction (opposite to movement with slight upward tilt)
	var kick_dir := -move_direction.normalized()
	kick_dir.y = 0.35
	if kick_dir.length_squared() < 0.01:
		kick_dir = Vector3(0.0, 0.35, 0.0)
	else:
		kick_dir = kick_dir.normalized()

	# 1. Trailing dust puff kicked backwards
	_spawn_sprint_puff(container, kick_dir)

	# 2. Backward stone debris chips
	_spawn_sprint_debris(container, kick_dir)

	# Cleanup
	_schedule_cleanup(scene_tree, container)



static func _spawn_effect(scene_tree: SceneTree, origin: Vector3, is_landing: bool, is_hard: bool, intensity: float) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "JumpDustFX" if not is_landing else ("HardLandingDustFX" if is_hard else "LandingDustFX")
	root.add_child(container)
	# Position slightly above floor surface to prevent clipping
	container.global_position = origin + Vector3(0.0, 0.04, 0.0)

	# 1. Radial dust ring along floor
	_spawn_radial_dust_ring(container, is_landing, is_hard, intensity)

	# 2. Central ground dust puff
	_spawn_center_puff(container, is_landing, is_hard)

	# 3. Stone debris chips / pebbles
	_spawn_stone_debris(container, is_landing, is_hard)

	# Cleanup
	_schedule_cleanup(scene_tree, container)


# ── 1. Expanding Radial Dust Ring ─────────────────────────────────────────────

static func _spawn_radial_dust_ring(parent: Node3D, is_landing: bool, is_hard: bool, intensity: float) -> void:
	var ring := CPUParticles3D.new()
	ring.name = "DustRing"
	ring.emitting = false
	ring.one_shot = true

	var amount: int
	var lifetime: float
	var radius: float
	var vel_min: float
	var vel_max: float
	var rad_accel: float

	if not is_landing:
		amount = JUMP_RING_AMOUNT
		lifetime = JUMP_RING_LIFETIME
		radius = JUMP_RING_RADIUS
		vel_min = 0.8
		vel_max = 1.9
		rad_accel = 1.8
	elif is_hard:
		var factor := 1.0 + intensity * 0.4
		amount = int(float(HARD_RING_AMOUNT) * factor)
		lifetime = HARD_RING_LIFETIME
		radius = HARD_RING_RADIUS * factor
		vel_min = 2.2 * factor
		vel_max = 4.8 * factor
		rad_accel = 4.5 * factor
	else:
		var factor := 1.0 + intensity * 0.3
		amount = int(float(NORMAL_RING_AMOUNT) * factor)
		lifetime = NORMAL_RING_LIFETIME
		radius = NORMAL_RING_RADIUS * factor
		vel_min = 1.2 * factor
		vel_max = 2.8 * factor
		rad_accel = 2.4 * factor

	ring.amount = amount
	ring.lifetime = lifetime
	ring.explosiveness = 0.92
	ring.lifetime_randomness = 0.35

	# Ring emission shape along horizontal plane
	ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	ring.emission_ring_axis = Vector3(0.0, 1.0, 0.0)
	ring.emission_ring_radius = radius
	ring.emission_ring_inner_radius = radius * 0.25
	ring.emission_ring_height = 0.06

	# Radial expansion outwards along ground
	ring.direction = Vector3(0.0, 0.18, 0.0)
	ring.spread = 85.0
	ring.initial_velocity_min = vel_min
	ring.initial_velocity_max = vel_max
	ring.radial_accel_min = rad_accel * 0.7
	ring.radial_accel_max = rad_accel * 1.3
	ring.damping_min = 1.8
	ring.damping_max = 3.2
	ring.gravity = Vector3(0.0, 0.1, 0.0)

	# Dynamic rotation
	ring.angle_min = -180.0
	ring.angle_max = 180.0

	# Scale curve: pops open rapidly, billows out, fades into air
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.2, 1.15))
	scale_curve.add_point(Vector2(0.65, 1.5))
	scale_curve.add_point(Vector2(1.0, 1.8))
	ring.scale_amount_curve = scale_curve
	ring.scale_amount_min = 0.6 if not is_hard else 0.9
	ring.scale_amount_max = 1.1 if not is_hard else 1.8

	# Sandstone sepia dust gradient
	ring.color_ramp = _get_dust_gradient(is_hard)

	# Billboard QuadMesh with smoke texture
	var quad := QuadMesh.new()
	quad.size = Vector2(0.65, 0.65) if not is_hard else Vector2(0.9, 0.9)

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
	ring.mesh = quad

	parent.add_child(ring)
	ring.position = Vector3.ZERO
	ring.restart()
	ring.emitting = true


# ── 2. Central Ground Dust Puff ───────────────────────────────────────────────

static func _spawn_center_puff(parent: Node3D, is_landing: bool, is_hard: bool) -> void:
	var puff := CPUParticles3D.new()
	puff.name = "CenterPuff"
	puff.emitting = false
	puff.one_shot = true
	puff.amount = 16 if is_hard else (10 if is_landing else 7)
	puff.lifetime = 0.6 if is_hard else 0.45
	puff.explosiveness = 0.9
	puff.lifetime_randomness = 0.3

	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.12 if not is_hard else 0.22

	puff.direction = Vector3(0.0, 1.0, 0.0)
	puff.spread = 50.0
	puff.initial_velocity_min = 0.5
	puff.initial_velocity_max = 1.6 if not is_hard else 2.5
	puff.damping_min = 1.5
	puff.damping_max = 2.5
	puff.gravity = Vector3(0.0, 0.15, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.25, 1.2))
	scale_curve.add_point(Vector2(1.0, 1.6))
	puff.scale_amount_curve = scale_curve
	puff.scale_amount_min = 0.5
	puff.scale_amount_max = 1.0 if not is_hard else 1.4

	puff.color_ramp = _get_dust_gradient(is_hard)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)

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
	puff.mesh = quad

	parent.add_child(puff)
	puff.position = Vector3.ZERO
	puff.restart()
	puff.emitting = true


# ── 3. Stone Debris & Pebble Chips ────────────────────────────────────────────

static func _spawn_stone_debris(parent: Node3D, is_landing: bool, is_hard: bool) -> void:
	var debris := CPUParticles3D.new()
	debris.name = "StoneDebris"
	debris.emitting = false
	debris.one_shot = true
	debris.amount = HARD_DEBRIS_AMOUNT if is_hard else (NORMAL_DEBRIS_AMOUNT if is_landing else JUMP_DEBRIS_AMOUNT)
	debris.lifetime = 0.7 if is_hard else 0.5
	debris.explosiveness = 0.95
	debris.lifetime_randomness = 0.4

	debris.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	debris.emission_sphere_radius = 0.1

	debris.direction = Vector3(0.0, 0.6, 0.0)
	debris.spread = 75.0
	debris.initial_velocity_min = 1.5 if not is_hard else 2.6
	debris.initial_velocity_max = 3.2 if not is_hard else 5.5
	debris.damping_min = 1.2
	debris.damping_max = 2.2
	debris.gravity = Vector3(0.0, -16.0, 0.0) # snappy fall to ground

	# Scale curve: holds shape then vanishes
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.7, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	debris.scale_amount_curve = scale_curve
	debris.scale_amount_min = 0.5
	debris.scale_amount_max = 1.2 if not is_hard else 1.6

	# Tint variation: dark grey stone to sandy dungeon masonry
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.52, 0.48, 0.42, 1.0),
		Color(0.40, 0.36, 0.32, 1.0),
		Color(0.28, 0.25, 0.22, 0.0),
	])
	debris.color_ramp = grad

	# Tiny 3D box chip mesh
	var box := BoxMesh.new()
	box.size = Vector3(0.032, 0.032, 0.032)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.55, 0.50, 0.44)
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	debris.mesh = box

	parent.add_child(debris)
	debris.position = Vector3.ZERO
	debris.restart()
	debris.emitting = true


# ── 4. Sprint Dust Puff & Debris ──────────────────────────────────────────────

static func _spawn_sprint_puff(parent: Node3D, kick_dir: Vector3) -> void:
	var puff := CPUParticles3D.new()
	puff.name = "SprintPuff"
	puff.emitting = false
	puff.one_shot = true
	puff.amount = 9
	puff.lifetime = 0.4
	puff.explosiveness = 0.88
	puff.lifetime_randomness = 0.3

	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.12

	puff.direction = kick_dir
	puff.spread = 45.0
	puff.initial_velocity_min = 1.0
	puff.initial_velocity_max = 2.4
	puff.damping_min = 2.0
	puff.damping_max = 3.5
	puff.gravity = Vector3(0.0, 0.15, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.25, 1.1))
	scale_curve.add_point(Vector2(1.0, 1.5))
	puff.scale_amount_curve = scale_curve
	puff.scale_amount_min = 0.4
	puff.scale_amount_max = 0.85

	puff.color_ramp = _get_dust_gradient(false)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)

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
	puff.mesh = quad

	parent.add_child(puff)
	puff.position = Vector3.ZERO
	puff.restart()
	puff.emitting = true


static func _spawn_sprint_debris(parent: Node3D, kick_dir: Vector3) -> void:
	var debris := CPUParticles3D.new()
	debris.name = "SprintDebris"
	debris.emitting = false
	debris.one_shot = true
	debris.amount = 4
	debris.lifetime = 0.36
	debris.explosiveness = 0.95
	debris.lifetime_randomness = 0.35

	debris.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	debris.emission_sphere_radius = 0.08

	debris.direction = kick_dir
	debris.spread = 35.0
	debris.initial_velocity_min = 1.4
	debris.initial_velocity_max = 2.8
	debris.damping_min = 1.5
	debris.damping_max = 2.5
	debris.gravity = Vector3(0.0, -14.0, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.7, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	debris.scale_amount_curve = scale_curve
	debris.scale_amount_min = 0.4
	debris.scale_amount_max = 0.9

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.52, 0.48, 0.42, 1.0),
		Color(0.40, 0.36, 0.32, 1.0),
		Color(0.28, 0.25, 0.22, 0.0),
	])
	debris.color_ramp = grad

	var box := BoxMesh.new()
	box.size = Vector3(0.024, 0.024, 0.024)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.55, 0.50, 0.44)
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	debris.mesh = box

	parent.add_child(debris)
	debris.position = Vector3.ZERO
	debris.restart()
	debris.emitting = true


# ── Color Gradients ───────────────────────────────────────────────────────────

static func _get_dust_gradient(is_hard: bool) -> Gradient:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])

	var alpha_peak := 0.62 if is_hard else 0.45
	var alpha_mid := 0.38 if is_hard else 0.25

	grad.colors = PackedColorArray([
		Color(0.74, 0.70, 0.60, 0.0),
		Color(0.72, 0.67, 0.57, alpha_peak),
		Color(0.58, 0.54, 0.46, alpha_mid),
		Color(0.44, 0.40, 0.34, 0.0),
	])
	return grad


# ── Cleanup ───────────────────────────────────────────────────────────────────

static func _schedule_cleanup(scene_tree: SceneTree, container: Node3D) -> void:
	if scene_tree == null or container == null:
		return

	var timer := scene_tree.create_timer(EFFECT_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)
