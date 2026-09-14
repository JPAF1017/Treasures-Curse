class_name KnockbackShockwaveEffect
extends RefCounted

## Heavy Knockback Radial Shockwave & Kinetic Impact Visual Effect.
## Emits:
## 1. Radial Shockwave Distortion Ring: Fast-expanding, glowing 3D torus ring along the impact plane.
## 2. Kinetic Sparks / Impact Debris: Flat planar burst of high-speed sparks along the shockwave wavefront.
## 3. Central Impact Flash: Brief incandescent micro-flash at the contact point.

const EFFECT_DURATION := 0.35

# Color configuration
const SHOCKWAVE_START_COLOR := Color(1.0, 0.96, 0.82, 0.92)
const SHOCKWAVE_END_COLOR := Color(1.0, 0.75, 0.35, 0.0)

const SPARK_AMOUNT := 18
const SPARK_LIFETIME := 0.22


## Spawns the heavy knockback shockwave at the contact point.
## [param scene_tree] - SceneTree reference
## [param contact_point] - 3D world position of the impact
## [param impact_direction] - Direction of the strike/knockback vector
## [param scale_mult] - Size multiplier based on attack strength/target size
static func spawn(scene_tree: SceneTree, contact_point: Vector3, impact_direction: Vector3 = Vector3.UP, scale_mult: float = 1.0) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "KnockbackShockwaveFX"
	root.add_child(container)
	container.global_position = contact_point

	# Align container rotation with the impact direction
	var dir := impact_direction.normalized()
	if dir != Vector3.ZERO:
		var up := Vector3.UP
		if absf(dir.dot(up)) > 0.95:
			up = Vector3.RIGHT
		container.look_at(contact_point + dir, up)

	# 1. 3D Torus Shockwave Distortion Ring
	_spawn_shockwave_ring(container, scene_tree, scale_mult)

	# 2. Kinetic Impact Sparks along the ring plane
	_spawn_kinetic_sparks(container, scale_mult)

	# 3. Central Micro-Flash
	_spawn_impact_flash(container, scene_tree, scale_mult)

	# Auto-cleanup after effect completes
	_schedule_cleanup(scene_tree, container)


# ── 1. Shockwave Distortion Ring ──────────────────────────────────────────────

static func _spawn_shockwave_ring(parent: Node3D, scene_tree: SceneTree, scale_mult: float) -> void:
	var ring_mesh_inst := MeshInstance3D.new()
	ring_mesh_inst.name = "ShockwaveRing"

	var torus := TorusMesh.new()
	torus.inner_radius = 0.44
	torus.outer_radius = 0.56
	torus.ring_segments = 6
	torus.rings = 28
	ring_mesh_inst.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = SHOCKWAVE_START_COLOR
	ring_mesh_inst.material_override = mat

	# Orient ring flat against the impact normal (XY plane perpendicular to Z)
	ring_mesh_inst.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	parent.add_child(ring_mesh_inst)

	var start_scale := Vector3(0.08, 0.08, 0.08) * scale_mult
	var end_scale := Vector3(1.65, 1.65, 0.35) * scale_mult
	ring_mesh_inst.scale = start_scale

	var tween := scene_tree.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring_mesh_inst, "scale", end_scale, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", SHOCKWAVE_END_COLOR, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


# ── 2. Kinetic Impact Sparks ──────────────────────────────────────────────────

static func _spawn_kinetic_sparks(parent: Node3D, scale_mult: float) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "KineticSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = SPARK_AMOUNT
	sparks.lifetime = SPARK_LIFETIME
	sparks.explosiveness = 0.94

	# Emit in flat planar ring along impact normal
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3.FORWARD
	sparks.emission_ring_radius = 0.12 * scale_mult
	sparks.emission_ring_inner_radius = 0.02 * scale_mult

	sparks.direction = Vector3.UP
	sparks.flatness = 0.92
	sparks.initial_velocity_min = 4.2 * scale_mult
	sparks.initial_velocity_max = 7.5 * scale_mult
	sparks.damping_min = 3.5
	sparks.damping_max = 5.5
	sparks.gravity = Vector3.ZERO

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.6, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	sparks.scale_amount_curve = scale_curve
	sparks.scale_amount_min = 0.5 * scale_mult
	sparks.scale_amount_max = 1.1 * scale_mult

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 0.92, 0.45, 1.0),
		Color(1.0, 0.55, 0.15, 0.75),
		Color(0.8, 0.25, 0.05, 0.0),
	])
	sparks.color_ramp = grad

	var sphere := SphereMesh.new()
	sphere.radius = 0.022 * scale_mult
	sphere.height = 0.044 * scale_mult
	sphere.radial_segments = 4
	sphere.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat
	sparks.mesh = sphere

	parent.add_child(sparks)
	sparks.emitting = true


# ── 3. Central Impact Flash ───────────────────────────────────────────────────

static func _spawn_impact_flash(parent: Node3D, scene_tree: SceneTree, scale_mult: float) -> void:
	var flash_inst := MeshInstance3D.new()
	flash_inst.name = "ImpactFlash"

	var sphere := SphereMesh.new()
	sphere.radius = 0.08 * scale_mult
	sphere.height = 0.16 * scale_mult
	sphere.radial_segments = 6
	sphere.rings = 3
	flash_inst.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 1.0, 0.95, 1.0)
	flash_inst.material_override = mat

	parent.add_child(flash_inst)

	var tween := scene_tree.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash_inst, "scale", Vector3.ZERO, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.07)


# ── Helpers ───────────────────────────────────────────────────────────────────

static func _schedule_cleanup(scene_tree: SceneTree, node: Node) -> void:
	if scene_tree == null or node == null:
		return
	scene_tree.create_timer(EFFECT_DURATION).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free()
	)
