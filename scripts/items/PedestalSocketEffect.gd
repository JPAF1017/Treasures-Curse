class_name PedestalSocketEffect
extends RefCounted

## Puzzle Pedestal Socketing & Altar Completion Particle Effect.
## Emits:
## 1. Expanding ring of ethereal dungeon mist along the horizontal plane.
## 2. Radiant arcane rune flash bursting upward from the pedestal socket.
## 3. Rising soul embers / cursed miasma spores drifting gracefully into the air.

enum PulseTheme {
	CYAN,
	PURPLE,
	GOLD,
}

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"

# Normal socketing counts
const MIST_AMOUNT := 36
const MIST_LIFETIME := 1.5
const RUNE_AMOUNT := 22
const RUNE_LIFETIME := 0.95
const EMBER_AMOUNT := 32
const EMBER_LIFETIME := 1.25

# Altar completion counts (larger and more dramatic)
const COMPLETION_MIST_AMOUNT := 64
const COMPLETION_MIST_LIFETIME := 1.9
const COMPLETION_RUNE_AMOUNT := 45
const COMPLETION_RUNE_LIFETIME := 1.2
const COMPLETION_EMBER_AMOUNT := 60
const COMPLETION_EMBER_LIFETIME := 1.6

const EFFECT_DURATION := 2.2

static var _rune_texture: Texture2D = null


## Spawns the pedestal socketing cursed energy pulse in world space.
## [param scene_tree] - SceneTree reference (get_tree())
## [param origin] - 3D world position where the key/skull was socketed
## [param theme] - PulseTheme enum value (CYAN, PURPLE, GOLD)
static func spawn(scene_tree: SceneTree, origin: Vector3, theme: int = PulseTheme.CYAN) -> void:
	_spawn_effect(scene_tree, origin, theme, false)


## Spawns a larger, high-impact altar completion burst when the full puzzle unlocks.
## [param scene_tree] - SceneTree reference (get_tree())
## [param origin] - 3D world position of the altar or room center
## [param theme] - PulseTheme enum value (CYAN, PURPLE, GOLD)
static func spawn_altar_completion(scene_tree: SceneTree, origin: Vector3, theme: int = PulseTheme.PURPLE) -> void:
	_spawn_effect(scene_tree, origin, theme, true)


static func _spawn_effect(scene_tree: SceneTree, origin: Vector3, theme: int, is_completion: bool) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "PedestalSocketFX" if not is_completion else "AltarCompletionFX"
	root.add_child(container)
	container.global_position = origin

	# 1. Expanding horizontal ring of mist
	_spawn_mist_ring(container, origin, theme, is_completion)

	# 2. Ethereal arcane rune flash
	_spawn_rune_flash(container, origin, theme, is_completion)

	# 3. Rising soul embers / cursed spores
	_spawn_soul_embers(container, origin, theme, is_completion)

	# Self-cleanup after animation completes
	_schedule_cleanup(scene_tree, container)


# ── 1. Expanding Ring of Mist ─────────────────────────────────────────────────

static func _spawn_mist_ring(parent: Node3D, origin: Vector3, theme: int, is_completion: bool) -> void:
	var mist := CPUParticles3D.new()
	mist.name = "MistRing"
	mist.emitting = false
	mist.one_shot = true
	mist.amount = COMPLETION_MIST_AMOUNT if is_completion else MIST_AMOUNT
	mist.lifetime = COMPLETION_MIST_LIFETIME if is_completion else MIST_LIFETIME
	mist.explosiveness = 0.88
	mist.lifetime_randomness = 0.3

	# Ring emission shape along horizontal plane
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	mist.emission_ring_axis = Vector3(0.0, 1.0, 0.0)
	mist.emission_ring_radius = 1.2 if is_completion else 0.5
	mist.emission_ring_inner_radius = 0.2 if is_completion else 0.05
	mist.emission_ring_height = 0.08

	# Radial expansion outwards
	mist.direction = Vector3(0.0, 0.15, 0.0)
	mist.spread = 90.0
	mist.initial_velocity_min = 2.0 if is_completion else 1.2
	mist.initial_velocity_max = 4.2 if is_completion else 2.6
	mist.radial_accel_min = 3.0 if is_completion else 1.5
	mist.radial_accel_max = 6.0 if is_completion else 3.5
	mist.damping_min = 2.0
	mist.damping_max = 3.2
	mist.gravity = Vector3(0.0, 0.15, 0.0)

	# Scale curve: expands as it billows outward, dissolving into air
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.3, 1.3))
	scale_curve.add_point(Vector2(1.0, 2.2))
	mist.scale_amount_curve = scale_curve
	mist.scale_amount_min = 0.8 if is_completion else 0.5
	mist.scale_amount_max = 1.6 if is_completion else 1.0

	# Mist color gradient
	mist.color_ramp = _get_mist_gradient(theme)

	# Billboard QuadMesh with smoke texture
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true

	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex != null:
		mat.albedo_texture = tex
	quad.material = mat
	mist.mesh = quad

	parent.add_child(mist)
	mist.global_position = origin + Vector3(0.0, 0.05, 0.0)
	mist.restart()
	mist.emitting = true


# ── 2. Ethereal Arcane Rune Flash ─────────────────────────────────────────────

static func _spawn_rune_flash(parent: Node3D, origin: Vector3, theme: int, is_completion: bool) -> void:
	var runes := CPUParticles3D.new()
	runes.name = "RuneFlash"
	runes.emitting = false
	runes.one_shot = true
	runes.amount = COMPLETION_RUNE_AMOUNT if is_completion else RUNE_AMOUNT
	runes.lifetime = COMPLETION_RUNE_LIFETIME if is_completion else RUNE_LIFETIME
	runes.explosiveness = 0.92
	runes.lifetime_randomness = 0.3

	runes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	runes.emission_sphere_radius = 0.35 if is_completion else 0.2

	# Upward burst with focused cone
	runes.direction = Vector3(0.0, 1.0, 0.0)
	runes.spread = 55.0
	runes.initial_velocity_min = 2.4 if is_completion else 1.6
	runes.initial_velocity_max = 5.0 if is_completion else 3.4
	runes.damping_min = 2.2
	runes.damping_max = 3.6
	runes.gravity = Vector3(0.0, 0.4, 0.0) # floats upward

	# Random rotation
	runes.angle_min = -180.0
	runes.angle_max = 180.0

	# Scale curve: snappy burst, hangs, shrinks
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(0.12, 1.25))
	scale_curve.add_point(Vector2(0.6, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	runes.scale_amount_curve = scale_curve
	runes.scale_amount_min = 0.3 if is_completion else 0.2
	runes.scale_amount_max = 0.6 if is_completion else 0.42

	runes.color_ramp = _get_rune_gradient(theme)

	# Billboard QuadMesh with procedural arcane rune texture
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_rune_texture()
	quad.material = mat
	runes.mesh = quad

	parent.add_child(runes)
	runes.global_position = origin
	runes.restart()
	runes.emitting = true


# ── 3. Rising Soul Embers / Spores ────────────────────────────────────────────

static func _spawn_soul_embers(parent: Node3D, origin: Vector3, theme: int, is_completion: bool) -> void:
	var embers := CPUParticles3D.new()
	embers.name = "SoulEmbers"
	embers.emitting = false
	embers.one_shot = true
	embers.amount = COMPLETION_EMBER_AMOUNT if is_completion else EMBER_AMOUNT
	embers.lifetime = COMPLETION_EMBER_LIFETIME if is_completion else EMBER_LIFETIME
	embers.explosiveness = 0.78
	embers.lifetime_randomness = 0.4

	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.4 if is_completion else 0.25

	embers.direction = Vector3(0.0, 1.0, 0.0)
	embers.spread = 70.0
	embers.initial_velocity_min = 1.0
	embers.initial_velocity_max = 2.8 if is_completion else 2.2
	embers.damping_min = 1.0
	embers.damping_max = 2.0
	embers.gravity = Vector3(0.0, 0.6, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.2, 1.2))
	scale_curve.add_point(Vector2(0.7, 0.7))
	scale_curve.add_point(Vector2(1.0, 0.0))
	embers.scale_amount_curve = scale_curve
	embers.scale_amount_min = 0.7
	embers.scale_amount_max = 1.4

	embers.color_ramp = _get_rune_gradient(theme)

	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
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
	embers.restart()
	embers.emitting = true


# ── Color Gradients ───────────────────────────────────────────────────────────

static func _get_rune_gradient(theme: int) -> Gradient:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.16, 0.62, 1.0])

	match theme:
		PulseTheme.PURPLE:
			grad.colors = PackedColorArray([
				Color(1.0, 1.0, 1.0, 1.0),      # pure white flash
				Color(0.86, 0.42, 1.0, 0.95),   # radiant cursed violet
				Color(0.56, 0.12, 0.90, 0.80),   # deep amethyst
				Color(0.24, 0.03, 0.45, 0.0),   # fade out
			])
		PulseTheme.GOLD:
			grad.colors = PackedColorArray([
				Color(1.0, 1.0, 0.9, 1.0),      # pure white flash
				Color(1.0, 0.88, 0.22, 0.95),   # radiant gold
				Color(1.0, 0.60, 0.08, 0.80),   # amber topaz
				Color(0.85, 0.35, 0.02, 0.0),   # fade out
			])
		PulseTheme.CYAN, _:
			grad.colors = PackedColorArray([
				Color(1.0, 1.0, 1.0, 1.0),      # pure white flash
				Color(0.28, 0.96, 1.0, 0.95),   # radiant ethereal cyan
				Color(0.08, 0.65, 0.95, 0.80),   # spectral teal
				Color(0.02, 0.22, 0.60, 0.0),   # fade out
			])

	return grad


static func _get_mist_gradient(theme: int) -> Gradient:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.6, 1.0])

	match theme:
		PulseTheme.PURPLE:
			grad.colors = PackedColorArray([
				Color(0.75, 0.40, 0.95, 0.0),
				Color(0.70, 0.35, 0.95, 0.45),
				Color(0.48, 0.16, 0.72, 0.25),
				Color(0.20, 0.05, 0.35, 0.0),
			])
		PulseTheme.GOLD:
			grad.colors = PackedColorArray([
				Color(1.0, 0.85, 0.35, 0.0),
				Color(1.0, 0.80, 0.25, 0.42),
				Color(0.85, 0.55, 0.12, 0.22),
				Color(0.45, 0.25, 0.02, 0.0),
			])
		PulseTheme.CYAN, _:
			grad.colors = PackedColorArray([
				Color(0.25, 0.90, 1.0, 0.0),
				Color(0.28, 0.92, 1.0, 0.48),
				Color(0.12, 0.58, 0.80, 0.26),
				Color(0.04, 0.22, 0.45, 0.0),
			])

	return grad


# ── Procedural Arcane Rune Texture ────────────────────────────────────────────

static func _get_rune_texture() -> Texture2D:
	if _rune_texture != null:
		return _rune_texture

	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (float(size) - 1.0) * 0.5

	for y in range(size):
		for x in range(size):
			var nx := (float(x) - center) / center
			var ny := (float(y) - center) / center
			var dist := sqrt(nx * nx + ny * ny)

			# Central core glow
			var core := clampf(1.0 - dist * 2.8, 0.0, 1.0)
			core = core * core

			# Outer rune circle (radius ~0.76)
			var outer_circle := clampf(1.0 - absf(dist - 0.76) * 14.0, 0.0, 1.0)

			# Inner rune circle (radius ~0.42)
			var inner_circle := clampf(1.0 - absf(dist - 0.42) * 16.0, 0.0, 1.0)

			# 8-spoke arcane radial runes
			var angle := atan2(ny, nx)
			# Normalize angle to [0, 2*PI]
			if angle < 0.0:
				angle += TAU
			var spoke_dist := absf(fposmod(angle + PI / 8.0, PI / 4.0) - PI / 8.0)
			var spoke_mask := clampf(1.0 - spoke_dist * 18.0, 0.0, 1.0)
			var spoke := spoke_mask * clampf(1.0 - absf(dist - 0.59) * 4.5, 0.0, 1.0)

			# Cardinal 4-point flares extending outside the outer circle
			var flare_h := clampf(1.0 - absf(nx), 0.0, 1.0) * clampf(1.0 - absf(ny) * 9.0, 0.0, 1.0)
			var flare_v := clampf(1.0 - absf(ny), 0.0, 1.0) * clampf(1.0 - absf(nx) * 9.0, 0.0, 1.0)
			var flares := (flare_h + flare_v) * 0.75

			var alpha := clampf(core + outer_circle * 0.9 + inner_circle * 0.85 + spoke * 0.9 + flares, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_rune_texture = ImageTexture.create_from_image(img)
	return _rune_texture


# ── Cleanup ───────────────────────────────────────────────────────────────────

static func _schedule_cleanup(scene_tree: SceneTree, container: Node3D) -> void:
	if scene_tree == null or container == null:
		return

	var timer := scene_tree.create_timer(EFFECT_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)
