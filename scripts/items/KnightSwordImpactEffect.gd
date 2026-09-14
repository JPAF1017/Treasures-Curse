class_name KnightSwordImpactEffect
extends RefCounted

## Visual and auditory particle effects for the Knight's greatsword collisions.
## Handles:
## 1. Wall & Stone Collision: Deflected friction sparks shower, tumbled stone chips,
##    billowing mortar dust cloud, and heavy metallic clash sound.
## 2. Player Collision: Arterial blood splatter burst, cutting sparks flare,
##    and optional heavy knockback distortion shockwave.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"
const WALL_HIT_SOUND_PATH := "res://sounds/Interactions/hit_solid.mp3"
const FLESH_HIT_SOUND_PATH := "res://sounds/Interactions/hit_sharp.mp3"

const WALL_SPARKS_AMOUNT := 36
const WALL_HEAVY_SPARKS_AMOUNT := 52
const WALL_CHIPS_AMOUNT := 20
const WALL_HEAVY_CHIPS_AMOUNT := 32
const WALL_DUST_AMOUNT := 16
const WALL_HEAVY_DUST_AMOUNT := 26

const EFFECT_LIFETIME := 2.0


## Spawns particles and audio when the Knight's greatsword hits a dungeon wall, pillar, or floor.
## [param scene_tree] - SceneTree reference
## [param world_position] - 3D impact position
## [param surface_normal] - Surface normal of the struck geometry
## [param is_heavy] - Whether this was a HeavySmash attack
static func spawn_wall_impact(scene_tree: SceneTree, world_position: Vector3, surface_normal: Vector3 = Vector3.UP, is_heavy: bool = false) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "KnightSwordWallImpactFX"
	root.add_child(container)
	container.global_position = world_position

	var normal := surface_normal.normalized()
	if normal.length_squared() < 0.01:
		normal = Vector3.UP

	# 1. Deflected friction sparks
	_spawn_wall_sparks(container, normal, is_heavy)

	# 2. Masonry chips and stone debris
	_spawn_wall_chips(container, normal, is_heavy)

	# 3. Pulverized stone dust plume
	_spawn_wall_dust(container, normal, is_heavy)

	# 4. Heavy smash radial shockwave
	if is_heavy:
		_spawn_heavy_shockwave_ring(container, normal)

	# 5. Metallic clash audio
	_spawn_impact_audio(container, WALL_HIT_SOUND_PATH, 3.0 if is_heavy else 1.5, randf_range(0.85, 1.15))

	# 6. Cleanup
	_schedule_cleanup(scene_tree, container)


## Spawns particles and audio when the Knight's greatsword strikes the player.
## [param scene_tree] - SceneTree reference
## [param world_position] - 3D target position (player)
## [param hit_direction] - Vector from knight to player
## [param is_heavy] - Whether this was a HeavySmash attack
static func spawn_player_impact(scene_tree: SceneTree, world_position: Vector3, hit_direction: Vector3 = Vector3.ZERO, is_heavy: bool = false) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var hit_dir := hit_direction.normalized()
	if hit_dir.length_squared() < 0.01:
		hit_dir = Vector3.UP

	# 1. Arterial blood splatter burst
	BloodSplatterEffect.spawn(scene_tree, world_position, hit_dir)

	# 2. Cutting sparks flare & flesh impact audio in container
	var container := Node3D.new()
	container.name = "KnightSwordFleshImpactFX"
	root.add_child(container)
	container.global_position = world_position + Vector3(0.0, 1.0, 0.0)

	_spawn_cutting_sparks(container, hit_dir, is_heavy)
	_spawn_impact_audio(container, FLESH_HIT_SOUND_PATH, 2.0 if is_heavy else 0.5, randf_range(0.9, 1.1))

	# 3. Heavy smash shockwave distortion
	if is_heavy:
		KnockbackShockwaveEffect.spawn(scene_tree, world_position + Vector3(0.0, 1.0, 0.0), hit_dir, 1.4)

	_schedule_cleanup(scene_tree, container)


# ── Wall Impact Components ───────────────────────────────────────────────────

static func _spawn_wall_sparks(parent: Node3D, normal: Vector3, is_heavy: bool) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "SwordSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = WALL_HEAVY_SPARKS_AMOUNT if is_heavy else WALL_SPARKS_AMOUNT
	sparks.lifetime = 0.42 if is_heavy else 0.35
	sparks.explosiveness = 0.98
	sparks.lifetime_randomness = 0.35

	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.15

	var spark_dir := (normal + Vector3(0.0, 0.3, 0.0)).normalized()
	sparks.direction = spark_dir
	sparks.spread = 55.0 if not is_heavy else 70.0
	sparks.initial_velocity_min = 4.5 if not is_heavy else 6.0
	sparks.initial_velocity_max = 9.0 if not is_heavy else 13.0
	sparks.damping_min = 1.5
	sparks.damping_max = 3.5
	sparks.gravity = Vector3(0.0, -14.0, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.55, 0.9))
	scale_curve.add_point(Vector2(1.0, 0.0))
	sparks.scale_amount_curve = scale_curve
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.5 if not is_heavy else 2.0

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.88, 0.25, 1.0),
		Color(1.0, 0.45, 0.05, 0.9),
		Color(0.8, 0.18, 0.0, 0.0),
	])
	sparks.color_ramp = grad

	var sphere := SphereMesh.new()
	var radius := 0.022 if not is_heavy else 0.03
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 4
	sphere.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	sparks.mesh = sphere
	sparks.material_override = mat

	parent.add_child(sparks)
	sparks.position = Vector3.ZERO
	sparks.restart()
	sparks.emitting = true


static func _spawn_wall_chips(parent: Node3D, normal: Vector3, is_heavy: bool) -> void:
	var chips := CPUParticles3D.new()
	chips.name = "MasonryChips"
	chips.emitting = false
	chips.one_shot = true
	chips.amount = WALL_HEAVY_CHIPS_AMOUNT if is_heavy else WALL_CHIPS_AMOUNT
	chips.lifetime = 0.75 if not is_heavy else 0.9
	chips.explosiveness = 0.95
	chips.lifetime_randomness = 0.4

	chips.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	chips.emission_sphere_radius = 0.15

	var burst_dir := (normal + Vector3(0.0, 0.4, 0.0)).normalized()
	chips.direction = burst_dir
	chips.spread = 50.0
	chips.initial_velocity_min = 3.0 if not is_heavy else 4.5
	chips.initial_velocity_max = 6.5 if not is_heavy else 9.5
	chips.damping_min = 1.0
	chips.damping_max = 2.5
	chips.gravity = Vector3(0.0, -18.0, 0.0)

	chips.angular_velocity_min = -360.0
	chips.angular_velocity_max = 360.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.7, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	chips.scale_amount_curve = scale_curve
	chips.scale_amount_min = 0.5
	chips.scale_amount_max = 1.3 if not is_heavy else 1.8

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.55, 0.52, 0.46, 1.0),
		Color(0.38, 0.35, 0.31, 1.0),
		Color(0.25, 0.22, 0.20, 0.0),
	])
	chips.color_ramp = grad

	var box := BoxMesh.new()
	var chip_size := 0.05 if not is_heavy else 0.075
	box.size = Vector3(chip_size, chip_size, chip_size)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.56, 0.52, 0.47)
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	chips.mesh = box

	parent.add_child(chips)
	chips.position = Vector3.ZERO
	chips.restart()
	chips.emitting = true


static func _spawn_wall_dust(parent: Node3D, normal: Vector3, is_heavy: bool) -> void:
	var dust := CPUParticles3D.new()
	dust.name = "StoneDust"
	dust.emitting = false
	dust.one_shot = true
	dust.amount = WALL_HEAVY_DUST_AMOUNT if is_heavy else WALL_DUST_AMOUNT
	dust.lifetime = 0.75 if not is_heavy else 0.95
	dust.explosiveness = 0.9
	dust.lifetime_randomness = 0.3

	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.2

	dust.direction = normal
	dust.spread = 60.0
	dust.initial_velocity_min = 1.8 if not is_heavy else 2.6
	dust.initial_velocity_max = 4.2 if not is_heavy else 6.0
	dust.damping_min = 2.0
	dust.damping_max = 3.5
	dust.gravity = Vector3(0.0, -0.3, 0.0)

	dust.angle_min = -180.0
	dust.angle_max = 180.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.25, 1.25))
	scale_curve.add_point(Vector2(1.0, 2.0))
	dust.scale_amount_curve = scale_curve
	dust.scale_amount_min = 0.7
	dust.scale_amount_max = 1.5 if not is_heavy else 2.2

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.72, 0.67, 0.57, 0.0),
		Color(0.70, 0.64, 0.54, 0.55 if not is_heavy else 0.75),
		Color(0.55, 0.50, 0.43, 0.32),
		Color(0.40, 0.36, 0.30, 0.0),
	])
	dust.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7) if not is_heavy else Vector2(1.0, 1.0)

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


static func _spawn_heavy_shockwave_ring(parent: Node3D, normal: Vector3) -> void:
	var ring := CPUParticles3D.new()
	ring.name = "HeavyShockwaveRing"
	ring.emitting = false
	ring.one_shot = true
	ring.amount = 22
	ring.lifetime = 0.6
	ring.explosiveness = 0.94

	ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	ring.emission_ring_radius = 0.4
	ring.emission_ring_inner_radius = 0.1
	ring.emission_ring_axis = normal

	ring.direction = normal
	ring.spread = 85.0
	ring.initial_velocity_min = 3.5
	ring.initial_velocity_max = 6.5
	ring.damping_min = 2.5
	ring.damping_max = 4.5
	ring.gravity = Vector3.ZERO

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.2, 1.2))
	scale_curve.add_point(Vector2(1.0, 1.9))
	ring.scale_amount_curve = scale_curve

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(0.78, 0.73, 0.63, 0.0),
		Color(0.75, 0.70, 0.60, 0.6),
		Color(0.58, 0.53, 0.45, 0.25),
		Color(0.40, 0.36, 0.30, 0.0),
	])
	ring.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)

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


# ── Player / Flesh Impact Components ─────────────────────────────────────────

static func _spawn_cutting_sparks(parent: Node3D, hit_dir: Vector3, is_heavy: bool) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "CuttingSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 16 if not is_heavy else 24
	sparks.lifetime = 0.28
	sparks.explosiveness = 0.96

	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.12

	sparks.direction = (hit_dir + Vector3(0.0, 0.4, 0.0)).normalized()
	sparks.spread = 45.0
	sparks.initial_velocity_min = 3.5
	sparks.initial_velocity_max = 7.0 if not is_heavy else 9.5
	sparks.damping_min = 1.5
	sparks.damping_max = 3.0
	sparks.gravity = Vector3(0.0, -10.0, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.5, 0.7))
	scale_curve.add_point(Vector2(1.0, 0.0))
	sparks.scale_amount_curve = scale_curve

	# Crimson-white cutting sparks
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.4, 0.3, 1.0),
		Color(0.85, 0.08, 0.08, 0.8),
		Color(0.4, 0.0, 0.0, 0.0),
	])
	sparks.color_ramp = grad

	var sphere := SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	sphere.radial_segments = 4
	sphere.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	sparks.mesh = sphere
	sparks.material_override = mat

	parent.add_child(sparks)
	sparks.position = Vector3.ZERO
	sparks.restart()
	sparks.emitting = true


# ── Audio & Cleanup Helpers ───────────────────────────────────────────────────

static func _spawn_impact_audio(parent: Node3D, sound_path: String, volume_db: float, pitch: float) -> void:
	var audio := AudioStreamPlayer3D.new()
	audio.name = "ImpactAudio"
	var stream: AudioStream = load(sound_path)
	if stream == null:
		return

	audio.stream = stream
	audio.volume_db = volume_db
	audio.pitch_scale = pitch
	audio.unit_size = 5.0
	audio.max_distance = 26.0

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
