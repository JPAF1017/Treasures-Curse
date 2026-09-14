class_name PickupSparklesEffect
extends RefCounted

## Pickup visual particle effect for coins, gem keys, and skull keys.
## Emits:
## 1. Twinkling 4-point radiant star sparkles bursting outward with upward lift.
## 2. Floating glimmer fairy dust sparks that drift and hang gracefully in 3D world space.

enum SparkleTheme {
	GOLD,
	BLUE_GEM,
	GREEN_GEM,
	YELLOW_GEM,
	RED_GEM,
	SKULL_KEY,
}

# Particle counts and settings
const STAR_AMOUNT := 26
const STAR_LIFETIME := 0.85
const GLIMMER_AMOUNT := 38
const GLIMMER_LIFETIME := 1.1

# Duration before container is freed
const EFFECT_DURATION := 1.5

static var _star_texture: Texture2D = null


## Spawns the pickup sparkles FX in world space at the given position.
## [param scene_tree] - SceneTree reference (get_tree())
## [param origin] - 3D world position where the item was picked up
## [param theme] - SparkleTheme enum value determining the color palette
static func spawn(scene_tree: SceneTree, origin: Vector3, theme: int = SparkleTheme.GOLD) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	# Container node to hold all temporary effect components
	var container := Node3D.new()
	container.name = "PickupSparklesFX"
	root.add_child(container)
	container.global_position = origin

	# 1. Twinkling radiant star particles
	_spawn_twinkling_stars(container, origin, theme)

	# 2. Lingering glimmer fairy dust sparks
	_spawn_glimmer_sparks(container, origin, theme)

	# Self-cleanup after animation completes
	_schedule_cleanup(scene_tree, container)


# ── 1. Twinkling Star Sparkles ────────────────────────────────────────────────

static func _spawn_twinkling_stars(parent: Node3D, origin: Vector3, theme: int) -> void:
	var stars := CPUParticles3D.new()
	stars.name = "TwinklingStars"
	stars.emitting = false
	stars.one_shot = true
	stars.amount = STAR_AMOUNT
	stars.lifetime = STAR_LIFETIME
	stars.explosiveness = 0.85
	stars.lifetime_randomness = 0.35

	stars.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	stars.emission_sphere_radius = 0.2

	# Upward burst with radial spread
	stars.direction = Vector3(0.0, 1.0, 0.0)
	stars.spread = 70.0
	stars.initial_velocity_min = 1.3
	stars.initial_velocity_max = 2.9
	stars.damping_min = 1.8
	stars.damping_max = 3.2
	stars.gravity = Vector3(0.0, 0.3, 0.0) # gentle upward float

	# Dynamic rotation
	stars.angle_min = -180.0
	stars.angle_max = 180.0

	# Scale curve: pops open snappy, holds twinkle, scales down gracefully
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(0.15, 1.15))
	scale_curve.add_point(Vector2(0.55, 0.85))
	scale_curve.add_point(Vector2(1.0, 0.0))
	stars.scale_amount_curve = scale_curve
	stars.scale_amount_min = 0.16
	stars.scale_amount_max = 0.34

	# Color gradient tailored by theme
	stars.color_ramp = _get_color_gradient(theme)

	# Billboard QuadMesh with additive unshaded glowing star material
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_star_texture()
	quad.material = mat
	stars.mesh = quad

	parent.add_child(stars)
	stars.global_position = origin
	stars.restart()
	stars.emitting = true


# ── 2. Glimmer Fairy Dust Sparks ──────────────────────────────────────────────

static func _spawn_glimmer_sparks(parent: Node3D, origin: Vector3, theme: int) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "GlimmerSparks"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = GLIMMER_AMOUNT
	sparks.lifetime = GLIMMER_LIFETIME
	sparks.explosiveness = 0.75
	sparks.lifetime_randomness = 0.4

	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.25

	# Radial burst with gentle lift
	sparks.direction = Vector3(0.0, 1.0, 0.0)
	sparks.spread = 80.0
	sparks.initial_velocity_min = 0.9
	sparks.initial_velocity_max = 2.4
	sparks.damping_min = 1.2
	sparks.damping_max = 2.4
	sparks.gravity = Vector3(0.0, -0.2, 0.0)

	# Scale curve: smooth fade
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.2, 1.2))
	scale_curve.add_point(Vector2(0.65, 0.75))
	scale_curve.add_point(Vector2(1.0, 0.0))
	sparks.scale_amount_curve = scale_curve
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.3

	sparks.color_ramp = _get_color_gradient(theme)

	# Tiny sphere mesh with additive unshaded glowing material
	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
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
	sparks.global_position = origin
	sparks.restart()
	sparks.emitting = true


# ── Theme Color Gradients ─────────────────────────────────────────────────────

static func _get_color_gradient(theme: int) -> Gradient:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.65, 1.0])

	match theme:
		SparkleTheme.BLUE_GEM:
			grad.colors = PackedColorArray([
				Color(0.9, 0.96, 1.0, 1.0),    # brilliant white-blue flash
				Color(0.28, 0.88, 1.0, 0.95),  # radiant cyan
				Color(0.12, 0.48, 1.0, 0.80),  # royal sapphire
				Color(0.05, 0.18, 0.75, 0.0),  # fade out
			])
		SparkleTheme.GREEN_GEM:
			grad.colors = PackedColorArray([
				Color(0.9, 1.0, 0.93, 1.0),    # brilliant white-green flash
				Color(0.32, 1.0, 0.58, 0.95),  # radiant mint
				Color(0.08, 0.82, 0.28, 0.80),  # vibrant emerald
				Color(0.02, 0.42, 0.12, 0.0),  # fade out
			])
		SparkleTheme.YELLOW_GEM:
			grad.colors = PackedColorArray([
				Color(1.0, 1.0, 0.9, 1.0),     # brilliant white-yellow flash
				Color(1.0, 0.94, 0.25, 0.95),  # bright lemon yellow
				Color(1.0, 0.70, 0.10, 0.80),  # warm amber topaz
				Color(0.85, 0.42, 0.02, 0.0),  # fade out
			])
		SparkleTheme.RED_GEM:
			grad.colors = PackedColorArray([
				Color(1.0, 0.9, 0.93, 1.0),    # brilliant white-rose flash
				Color(1.0, 0.28, 0.48, 0.95),  # vibrant rose ruby
				Color(0.92, 0.10, 0.22, 0.80),  # deep crimson ruby
				Color(0.58, 0.02, 0.08, 0.0),  # fade out
			])
		SparkleTheme.SKULL_KEY:
			grad.colors = PackedColorArray([
				Color(0.95, 0.9, 1.0, 1.0),    # brilliant white-violet flash
				Color(0.78, 0.45, 1.0, 0.95),  # ethereal lavender
				Color(0.52, 0.16, 0.88, 0.80),  # cursed amethyst
				Color(0.26, 0.04, 0.52, 0.0),  # fade out
			])
		SparkleTheme.GOLD, _:
			grad.colors = PackedColorArray([
				Color(1.0, 1.0, 0.85, 1.0),    # brilliant white-gold flash
				Color(1.0, 0.86, 0.22, 0.95),  # shining gold
				Color(1.0, 0.62, 0.08, 0.80),  # warm amber gold
				Color(0.90, 0.40, 0.02, 0.0),  # fade out
			])

	return grad


# ── Procedural Star Texture ───────────────────────────────────────────────────

static func _get_star_texture() -> Texture2D:
	if _star_texture != null:
		return _star_texture

	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (float(size) - 1.0) * 0.5

	for y in range(size):
		for x in range(size):
			var nx := (float(x) - center) / center
			var ny := (float(y) - center) / center
			var dist := sqrt(nx * nx + ny * ny)

			# Central glowing flare
			var core := clampf(1.0 - dist * 2.4, 0.0, 1.0)
			core = core * core

			# Horizontal & vertical star spikes
			var spike_h := clampf(1.0 - absf(nx), 0.0, 1.0) * clampf(1.0 - absf(ny) * 7.5, 0.0, 1.0)
			var spike_v := clampf(1.0 - absf(ny), 0.0, 1.0) * clampf(1.0 - absf(nx) * 7.5, 0.0, 1.0)

			# Diagonal micro-flares
			var d1 := absf(nx - ny) * 0.7071
			var d2 := absf(nx + ny) * 0.7071
			var d_diag := maxf(absf(nx), absf(ny))
			var diag_spike := clampf(1.0 - d_diag * 1.5, 0.0, 1.0) * (clampf(1.0 - d1 * 12.0, 0.0, 1.0) + clampf(1.0 - d2 * 12.0, 0.0, 1.0)) * 0.35

			var alpha := clampf(core + (spike_h + spike_v) * 0.88 + diag_spike, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_star_texture = ImageTexture.create_from_image(img)
	return _star_texture


# ── Cleanup ───────────────────────────────────────────────────────────────────

static func _schedule_cleanup(scene_tree: SceneTree, container: Node3D) -> void:
	if scene_tree == null or container == null:
		return

	var timer := scene_tree.create_timer(EFFECT_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)
