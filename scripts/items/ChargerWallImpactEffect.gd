class_name ChargerWallImpactEffect
extends RefCounted

## Charger wall & pillar impact particle effect.
## Spawns when the Charger enemy charges or lunges forward, misses the player,
## and slams into dungeon walls or solid pillars.
##
## Emits:
## 1. Shower of crumbled 3D rock chips & masonry pebbles blasting outward from the point of impact.
## 2. Heavy expanding plume of crushed dungeon stone dust billowing out along the wall normal.
## 3. Radial dust shockwave ring expanding across the wall surface.
## 4. Bright friction sparks flying off the stone masonry.
## 5. Positional heavy impact sound (hit_solid.mp3) with varied pitch.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"
const IMPACT_SOUND_PATH := "res://sounds/Interactions/hit_solid.mp3"

const DEBRIS_CHIPS_AMOUNT := 32
const DUST_PLUME_AMOUNT := 24
const SHOCKWAVE_RING_AMOUNT := 20
const SPARKS_AMOUNT := 16

const EFFECT_LIFETIME := 2.0


## Spawns the full wall impact effect at the given contact position.
## [param scene_tree] - SceneTree reference (get_tree())
## [param world_position] - 3D impact contact point on the wall/pillar
## [param wall_normal] - Normal vector pointing outward from the impacted surface
static func spawn(scene_tree: SceneTree, world_position: Vector3, wall_normal: Vector3 = Vector3.UP) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "ChargerWallImpactFX"
	root.add_child(container)
	container.global_position = world_position

	# Ensure valid outward normal
	var normal := wall_normal.normalized()
	if normal.length_squared() < 0.01:
		normal = Vector3.UP

	# 1. Shower of crumbled rock chips and masonry pebbles
	_spawn_rock_chips(container, normal)

	# 2. Heavy plume of pulverized stone dust
	_spawn_dust_plume(container, normal)

	# 3. Radial wall shockwave ring
	_spawn_shockwave_ring(container, normal)

	# 4. Friction sparks
	_spawn_friction_sparks(container, normal)

	# 5. Heavy stone impact sound
	_spawn_impact_audio(container)

	# 6. Auto-cleanup
	_schedule_cleanup(scene_tree, container)


# ── 1. Shower of Crumbled Rock Chips ──────────────────────────────────────────

static func _spawn_rock_chips(parent: Node3D, normal: Vector3) -> void:
	var chips := CPUParticles3D.new()
	chips.name = "RockChips"
	chips.emitting = false
	chips.one_shot = true
	chips.amount = DEBRIS_CHIPS_AMOUNT
	chips.lifetime = 0.85
	chips.explosiveness = 0.96
	chips.lifetime_randomness = 0.45

	chips.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	chips.emission_sphere_radius = 0.2

	# Burst outwards away from wall with slight upward bias
	var burst_dir := (normal + Vector3(0.0, 0.45, 0.0)).normalized()
	chips.direction = burst_dir
	chips.spread = 55.0
	chips.initial_velocity_min = 3.5
	chips.initial_velocity_max = 7.5
	chips.damping_min = 1.0
	chips.damping_max = 2.8
	chips.gravity = Vector3(0.0, -19.0, 0.0)

	# Angular tumbling velocity
	chips.angular_velocity_min = -360.0
	chips.angular_velocity_max = 360.0

	# Scale curve: maintain solid chunk volume, then vanish on floor contact
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.72, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	chips.scale_amount_curve = scale_curve
	chips.scale_amount_min = 0.5
	chips.scale_amount_max = 1.5

	# Stone colors: masonry grey, dungeon slate, sand-tinted mortar
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.55, 0.52, 0.46, 1.0),
		Color(0.38, 0.35, 0.31, 1.0),
		Color(0.25, 0.22, 0.20, 0.0),
	])
	chips.color_ramp = grad

	# 3D Box chunk mesh
	var box := BoxMesh.new()
	box.size = Vector3(0.065, 0.065, 0.065)

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


# ── 2. Heavy Dungeon Impact Dust Plume ────────────────────────────────────────

static func _spawn_dust_plume(parent: Node3D, normal: Vector3) -> void:
	var plume := CPUParticles3D.new()
	plume.name = "DustPlume"
	plume.emitting = false
	plume.one_shot = true
	plume.amount = DUST_PLUME_AMOUNT
	plume.lifetime = 0.95
	plume.explosiveness = 0.92
	plume.lifetime_randomness = 0.35

	plume.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	plume.emission_sphere_radius = 0.25

	plume.direction = normal
	plume.spread = 65.0
	plume.initial_velocity_min = 2.2
	plume.initial_velocity_max = 5.2
	plume.damping_min = 2.2
	plume.damping_max = 3.8
	plume.gravity = Vector3(0.0, -0.4, 0.0)

	plume.angle_min = -180.0
	plume.angle_max = 180.0

	# Swelling billowing dust curve
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.2, 1.3))
	scale_curve.add_point(Vector2(0.6, 1.85))
	scale_curve.add_point(Vector2(1.0, 2.3))
	plume.scale_amount_curve = scale_curve
	plume.scale_amount_min = 0.85
	plume.scale_amount_max = 1.75

	# Dusty sandstone sepia ramp
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0.72, 0.67, 0.57, 0.0),
		Color(0.70, 0.64, 0.54, 0.65),
		Color(0.55, 0.50, 0.43, 0.40),
		Color(0.40, 0.36, 0.30, 0.0),
	])
	plume.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)

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
	plume.mesh = quad

	parent.add_child(plume)
	plume.position = Vector3.ZERO
	plume.restart()
	plume.emitting = true


# ── 3. Radial Wall Shockwave Ring ─────────────────────────────────────────────

static func _spawn_shockwave_ring(parent: Node3D, normal: Vector3) -> void:
	var ring := CPUParticles3D.new()
	ring.name = "ShockwaveRing"
	ring.emitting = false
	ring.one_shot = true
	ring.amount = SHOCKWAVE_RING_AMOUNT
	ring.lifetime = 0.65
	ring.explosiveness = 0.94

	ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	ring.emission_ring_radius = 0.35
	ring.emission_ring_inner_radius = 0.1
	ring.emission_ring_axis = normal

	ring.direction = normal
	ring.spread = 85.0
	ring.initial_velocity_min = 2.8
	ring.initial_velocity_max = 5.6
	ring.damping_min = 2.5
	ring.damping_max = 4.5
	ring.gravity = Vector3.ZERO

	ring.angle_min = -180.0
	ring.angle_max = 180.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.25, 1.2))
	scale_curve.add_point(Vector2(1.0, 1.8))
	ring.scale_amount_curve = scale_curve
	ring.scale_amount_min = 0.7
	ring.scale_amount_max = 1.3

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(0.78, 0.73, 0.63, 0.0),
		Color(0.75, 0.70, 0.60, 0.55),
		Color(0.60, 0.55, 0.47, 0.28),
		Color(0.42, 0.38, 0.32, 0.0),
	])
	ring.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)

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


# ── 4. Friction Sparks ────────────────────────────────────────────────────────

static func _spawn_friction_sparks(parent: Node3D, normal: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "FrictionSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = SPARKS_AMOUNT
	sparks.lifetime = 0.35
	sparks.explosiveness = 0.98
	sparks.lifetime_randomness = 0.3

	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.1

	var spark_dir := (normal + Vector3(0.0, 0.25, 0.0)).normalized()
	sparks.direction = spark_dir
	sparks.spread = 50.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 8.5
	sparks.damping_min = 1.5
	sparks.damping_max = 3.0
	sparks.gravity = Vector3(0.0, -14.0, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.6, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	sparks.scale_amount_curve = scale_curve
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.4

	# White-hot to fiery orange
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.85, 0.25, 1.0),
		Color(1.0, 0.45, 0.05, 0.85),
		Color(0.8, 0.2, 0.0, 0.0),
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


# ── 5. Heavy Stone Impact Audio ───────────────────────────────────────────────

static func _spawn_impact_audio(parent: Node3D) -> void:
	var audio := AudioStreamPlayer3D.new()
	audio.name = "ImpactAudio"
	var stream: AudioStream = load(IMPACT_SOUND_PATH)
	if stream == null:
		return

	audio.stream = stream
	audio.volume_db = 2.5
	audio.pitch_scale = randf_range(0.88, 1.12)
	audio.unit_size = 5.0
	audio.max_distance = 28.0

	parent.add_child(audio)
	audio.position = Vector3.ZERO
	audio.play()


# ── 6. Cleanup ────────────────────────────────────────────────────────────────

static func _schedule_cleanup(scene_tree: SceneTree, container: Node3D) -> void:
	if scene_tree == null or container == null:
		return

	var timer := scene_tree.create_timer(EFFECT_LIFETIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)
