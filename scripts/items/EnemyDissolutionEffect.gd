class_name EnemyDissolutionEffect
extends RefCounted

## Enemy Defeat & Dissolution Particle Visual Effect.
## Emits:
## 1. Dark Cursed Shadow Miasma: Explosive billowing puff of dark purple/black cursed smoke.
## 2. Dissolving Soul Embers: Luminous soul sparks rising into the air as the enemy is vanquished.
## 3. Cursed Energy Shockwave: Expanding horizontal ring of dark arcane energy.
## 4. Corpse Dissolution: Rising wisps during linger and smooth mesh transparency fadeout.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"

# Miasma puff settings
const MIASMA_AMOUNT := 36
const MIASMA_LIFETIME := 1.4
const MIASMA_SPREAD := 75.0

# Soul embers settings
const EMBER_AMOUNT := 45
const EMBER_LIFETIME := 1.6
const EMBER_SPREAD := 65.0

# Shockwave pulse settings
const PULSE_AMOUNT := 20
const PULSE_LIFETIME := 0.55

# Linger wisp settings
const LINGER_WISP_AMOUNT := 14
const LINGER_WISP_LIFETIME := 1.2

# Overall effect duration before root cleanup
const EFFECT_CLEANUP_DURATION := 2.5


## Spawns the enemy defeat burst at the given position.
## [param scene_tree] - SceneTree reference
## [param origin] - World position of the defeat burst (usually torso/center of enemy)
## [param scale_mult] - Size multiplier based on enemy dimensions
static func spawn(scene_tree: SceneTree, origin: Vector3, scale_mult: float = 1.0) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "EnemyDissolutionFX"
	root.add_child(container)
	container.global_position = origin

	_spawn_miasma_burst(container, origin, scale_mult)
	_spawn_soul_embers(container, origin, scale_mult)
	_spawn_cursed_pulse(container, origin, scale_mult)

	_schedule_cleanup(scene_tree, container, EFFECT_CLEANUP_DURATION)


## Attaches ongoing dissolution wisps and smooth mesh transparency fade to a lingering enemy corpse.
## [param body] - The enemy CharacterBody3D node
## [param center_offset] - Local offset to center of the enemy body
## [param linger_duration] - Total seconds the body will linger before queue_free
static func attach_dissolution_linger(body: CharacterBody3D, center_offset: Vector3, linger_duration: float) -> void:
	if body == null or not is_instance_valid(body) or body.get_tree() == null:
		return

	# 1. Spawn rising smoke & embers while lingering
	var wisp_emitter := CPUParticles3D.new()
	wisp_emitter.name = "CorpseDissolutionWisps"
	wisp_emitter.amount = LINGER_WISP_AMOUNT
	wisp_emitter.lifetime = LINGER_WISP_LIFETIME
	wisp_emitter.explosiveness = 0.0
	wisp_emitter.local_coords = false
	wisp_emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wisp_emitter.emission_sphere_radius = 0.25
	wisp_emitter.direction = Vector3.UP
	wisp_emitter.spread = 30.0
	wisp_emitter.initial_velocity_min = 0.4
	wisp_emitter.initial_velocity_max = 1.0
	wisp_emitter.gravity = Vector3(0.0, 0.6, 0.0)
	wisp_emitter.damping_min = 0.5
	wisp_emitter.damping_max = 1.2

	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex:
		mat.albedo_texture = tex
	quad.material = mat
	wisp_emitter.mesh = quad

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.4))
	wisp_emitter.scale_amount_curve = scale_curve

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(0.12, 0.04, 0.18, 0.0),
		Color(0.18, 0.06, 0.28, 0.45),
		Color(0.25, 0.10, 0.35, 0.25),
		Color(0.15, 0.05, 0.22, 0.0),
	])
	wisp_emitter.color_ramp = grad

	body.add_child(wisp_emitter)
	wisp_emitter.position = center_offset

	# 2. Smoothly fade out geometry instances during the final phase of linger
	var fade_duration := minf(linger_duration * 0.45, 1.0)
	var fade_delay := maxf(linger_duration - fade_duration, 0.0)

	var meshes: Array[GeometryInstance3D] = []
	_collect_geometry_recursive(body, meshes)

	if not meshes.is_empty():
		var tween := body.get_tree().create_tween()
		if fade_delay > 0.0:
			tween.tween_interval(fade_delay)

		tween.set_parallel(true)
		for g in meshes:
			if is_instance_valid(g):
				tween.tween_property(g, "transparency", 1.0, fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ── 1. Dark Cursed Shadow Miasma ──────────────────────────────────────────────

static func _spawn_miasma_burst(parent: Node3D, origin: Vector3, scale_mult: float) -> void:
	var miasma := CPUParticles3D.new()
	miasma.name = "ShadowMiasmaBurst"
	miasma.emitting = false
	miasma.one_shot = true
	miasma.amount = int(MIASMA_AMOUNT * clampf(scale_mult, 0.75, 2.0))
	miasma.lifetime = MIASMA_LIFETIME
	miasma.explosiveness = 0.88
	miasma.lifetime_randomness = 0.35

	miasma.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	miasma.emission_sphere_radius = 0.2 * scale_mult

	miasma.direction = Vector3(0.0, 0.6, 0.0)
	miasma.spread = MIASMA_SPREAD
	miasma.initial_velocity_min = 1.4 * scale_mult
	miasma.initial_velocity_max = 3.2 * scale_mult
	miasma.damping_min = 1.8
	miasma.damping_max = 3.2
	miasma.gravity = Vector3(0.0, 0.4, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.2, 1.15))
	scale_curve.add_point(Vector2(1.0, 1.85))
	miasma.scale_amount_curve = scale_curve
	miasma.scale_amount_min = 0.75 * scale_mult
	miasma.scale_amount_max = 1.45 * scale_mult

	# Deep obsidian black to rich cursed shadow violet fading out
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0.05, 0.02, 0.08, 0.0),
		Color(0.08, 0.03, 0.14, 0.88),
		Color(0.22, 0.07, 0.32, 0.45),
		Color(0.32, 0.12, 0.42, 0.0),
	])
	miasma.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.48 * scale_mult, 0.48 * scale_mult)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex:
		mat.albedo_texture = tex
	quad.material = mat
	miasma.mesh = quad

	parent.add_child(miasma)
	miasma.global_position = origin
	miasma.emitting = true


# ── 2. Dissolving Soul Embers ─────────────────────────────────────────────────

static func _spawn_soul_embers(parent: Node3D, origin: Vector3, scale_mult: float) -> void:
	var embers := CPUParticles3D.new()
	embers.name = "SoulEmbers"
	embers.emitting = false
	embers.one_shot = true
	embers.amount = int(EMBER_AMOUNT * clampf(scale_mult, 0.75, 2.0))
	embers.lifetime = EMBER_LIFETIME
	embers.explosiveness = 0.75
	embers.lifetime_randomness = 0.4

	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.28 * scale_mult

	embers.direction = Vector3(0.0, 1.0, 0.0)
	embers.spread = EMBER_SPREAD
	embers.initial_velocity_min = 1.2 * scale_mult
	embers.initial_velocity_max = 3.6 * scale_mult
	embers.gravity = Vector3(0.0, 1.3, 0.0)
	embers.damping_min = 1.4
	embers.damping_max = 2.4

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.2, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.1))
	embers.scale_amount_curve = scale_curve
	embers.scale_amount_min = 0.4
	embers.scale_amount_max = 0.85

	# Radiant magenta-purple and ethereal soul cyan
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(0.95, 0.45, 1.0, 1.0),
		Color(0.65, 0.85, 1.0, 0.85),
		Color(0.5, 0.3, 0.9, 0.0),
	])
	embers.color_ramp = grad

	var sphere := SphereMesh.new()
	sphere.radius = 0.024 * scale_mult
	sphere.height = 0.048 * scale_mult
	sphere.radial_segments = 4
	sphere.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat
	embers.mesh = sphere

	parent.add_child(embers)
	embers.global_position = origin
	embers.emitting = true


# ── 3. Cursed Energy Shockwave Pulse ──────────────────────────────────────────

static func _spawn_cursed_pulse(parent: Node3D, origin: Vector3, scale_mult: float) -> void:
	var pulse := CPUParticles3D.new()
	pulse.name = "CursedShockwavePulse"
	pulse.emitting = false
	pulse.one_shot = true
	pulse.amount = PULSE_AMOUNT
	pulse.lifetime = PULSE_LIFETIME
	pulse.explosiveness = 0.92

	pulse.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	pulse.emission_ring_axis = Vector3.UP
	pulse.emission_ring_radius = 0.15 * scale_mult
	pulse.emission_ring_inner_radius = 0.05 * scale_mult

	pulse.direction = Vector3.UP
	pulse.flatness = 0.9
	pulse.initial_velocity_min = 2.0 * scale_mult
	pulse.initial_velocity_max = 3.5 * scale_mult
	pulse.damping_min = 2.0
	pulse.damping_max = 3.5
	pulse.gravity = Vector3.ZERO

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.3, 1.2))
	scale_curve.add_point(Vector2(1.0, 0.1))
	pulse.scale_amount_curve = scale_curve
	pulse.scale_amount_min = 0.5 * scale_mult
	pulse.scale_amount_max = 1.1 * scale_mult

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(0.8, 0.3, 1.0, 0.0),
		Color(0.65, 0.15, 0.9, 0.75),
		Color(0.4, 0.08, 0.6, 0.35),
		Color(0.2, 0.04, 0.3, 0.0),
	])
	pulse.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.32 * scale_mult, 0.32 * scale_mult)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex:
		mat.albedo_texture = tex
	quad.material = mat
	pulse.mesh = quad

	parent.add_child(pulse)
	pulse.global_position = origin
	pulse.emitting = true


# ── Helpers ───────────────────────────────────────────────────────────────────

static func _collect_geometry_recursive(node: Node, out_meshes: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D and not (node is CPUParticles3D):
		out_meshes.append(node as GeometryInstance3D)
	for child in node.get_children():
		_collect_geometry_recursive(child, out_meshes)


static func _schedule_cleanup(scene_tree: SceneTree, node: Node, delay: float) -> void:
	if scene_tree == null or node == null:
		return
	scene_tree.create_timer(delay).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free()
	)
