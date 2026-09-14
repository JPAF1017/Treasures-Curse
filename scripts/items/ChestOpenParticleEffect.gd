class_name ChestOpenParticleEffect
extends RefCounted

## Chest opening visual particle effect.
## Emits:
## 1. Ancient dungeon dust puffs escaping horizontally & upward from the chest seams.
## 2. Sparkling golden dust floating upward in a rich fountain-like burst.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"

# Ancient dust settings (generous cloud escaping the ancient seal)
const DUST_AMOUNT := 72
const DUST_LIFETIME := 1.7
const DUST_BOX_EXTENTS := Vector3(1.0, 0.15, 0.7)

# Golden sparkles settings (abundant sparkling treasure shower)
const SPARKLE_AMOUNT := 110
const SPARKLE_LIFETIME := 2.0
const SPARKLE_BOX_EXTENTS := Vector3(0.75, 0.1, 0.55)

# Overall effect lifetime before node cleanup
const EFFECT_DURATION := 2.6


## Spawns the chest opening burst FX in world space.
## [param scene_tree] - SceneTree reference (get_tree())
## [param seam_origin] - Chest center / lid seam world position
## [param interior_origin] - Chest inside / spawn area world position
static func spawn(scene_tree: SceneTree, seam_origin: Vector3, interior_origin: Vector3 = Vector3.ZERO) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var interior_pos := interior_origin if interior_origin != Vector3.ZERO else seam_origin + Vector3(0.0, 0.4, 0.0)

	# Container node to hold all temporary effect components
	var container := Node3D.new()
	container.name = "ChestOpenFX"
	root.add_child(container)
	container.global_position = seam_origin

	# 1. Ancient dungeon dust puffing outward from seam
	_spawn_seam_dust(container, seam_origin)

	# 2. Golden sparkling dust fountain bursting upward
	_spawn_golden_sparkles(container, interior_pos)

	# Self-cleanup after animation completes
	_schedule_cleanup(scene_tree, container)


# ── 1. Ancient Dungeon Dust ───────────────────────────────────────────────────

static func _spawn_seam_dust(parent: Node3D, origin: Vector3) -> void:
	var dust := CPUParticles3D.new()
	dust.name = "SeamDustParticles"
	dust.emitting = false
	dust.one_shot = true
	dust.amount = DUST_AMOUNT
	dust.lifetime = DUST_LIFETIME
	dust.explosiveness = 0.88
	dust.lifetime_randomness = 0.35

	# Shape: box along chest seam line
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = DUST_BOX_EXTENTS

	# Velocity: outward burst with slight upward lift
	dust.direction = Vector3(0.0, 0.35, 0.0)
	dust.spread = 80.0
	dust.initial_velocity_min = 0.8
	dust.initial_velocity_max = 2.6
	dust.damping_min = 1.6
	dust.damping_max = 2.8
	dust.gravity = Vector3(0.0, 0.15, 0.0)

	# Scale curve: expands as it billows into dungeon air
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.25, 1.25))
	scale_curve.add_point(Vector2(1.0, 2.0))
	dust.scale_amount_curve = scale_curve
	dust.scale_amount_min = 0.7
	dust.scale_amount_max = 1.4

	# Color ramp: dusty sepia / sandstone grey fading out
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.72, 0.67, 0.56, 0.0),
		Color(0.70, 0.65, 0.54, 0.42),
		Color(0.58, 0.53, 0.44, 0.28),
		Color(0.48, 0.44, 0.37, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	dust.color_ramp = grad

	# Billboard QuadMesh
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)

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
	dust.global_position = origin
	dust.restart()
	dust.emitting = true


# ── 2. Golden Sparkling Dust ──────────────────────────────────────────────────

static func _spawn_golden_sparkles(parent: Node3D, origin: Vector3) -> void:
	var sparkles := CPUParticles3D.new()
	sparkles.name = "GoldenSparkles"
	sparkles.emitting = false
	sparkles.one_shot = true
	sparkles.amount = SPARKLE_AMOUNT
	sparkles.lifetime = SPARKLE_LIFETIME
	sparkles.explosiveness = 0.75
	sparkles.lifetime_randomness = 0.4

	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparkles.emission_box_extents = SPARKLE_BOX_EXTENTS

	# Upward burst with graceful spread
	sparkles.direction = Vector3(0.0, 1.0, 0.0)
	sparkles.spread = 42.0
	sparkles.initial_velocity_min = 2.6
	sparkles.initial_velocity_max = 5.6
	sparkles.damping_min = 1.0
	sparkles.damping_max = 2.0
	sparkles.gravity = Vector3(0.0, -2.0, 0.0)

	# Scale curve: starts snappy, sparkles/shrinks gracefully
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.18, 1.2))
	scale_curve.add_point(Vector2(0.65, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	sparkles.scale_amount_curve = scale_curve
	sparkles.scale_amount_min = 0.7
	sparkles.scale_amount_max = 1.5

	# Color ramp: bright white-gold flash -> brilliant yellow -> amber gold -> fade out
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 0.82, 1.0),
		Color(1.0, 0.85, 0.22, 0.95),
		Color(1.0, 0.65, 0.08, 0.80),
		Color(0.92, 0.42, 0.02, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.65, 1.0])
	sparkles.color_ramp = grad

	# Sphere mesh with additive unshaded glowing material
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	sphere.radial_segments = 4
	sphere.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat
	sparkles.mesh = sphere

	parent.add_child(sparkles)
	sparkles.global_position = origin
	sparkles.restart()
	sparkles.emitting = true


# ── Cleanup ───────────────────────────────────────────────────────────────────

static func _schedule_cleanup(scene_tree: SceneTree, container: Node3D) -> void:
	if scene_tree == null or container == null:
		return

	var timer := scene_tree.create_timer(EFFECT_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)
