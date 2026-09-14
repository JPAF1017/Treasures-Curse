class_name MeleeSwingTrailEffect
extends Node3D

## Dynamic Melee Weapon Swing Trail & Wind Slash Visual Effect.
## Generates a smooth, translucent swoosh ribbon following the weapon blade/head
## using an ImmediateMesh triangle strip, accompanied by trailing wind wisp particles.
## Supports both local camera-space (first-person viewmodel) and world-space (third-person held weapon).

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"

# Default configuration constants
const DEFAULT_MAX_LIFETIME := 0.18
const DEFAULT_MAX_SAMPLES := 28
const MIN_SAMPLE_DISTANCE := 0.02
const INTERPOLATE_DISTANCE := 0.06

# Visual & Color defaults
var trail_color: Color = Color(0.88, 0.95, 1.0, 0.72)
var edge_color: Color = Color(1.0, 1.0, 1.0, 0.95)
var base_color_tint: Color = Color(0.75, 0.88, 1.0, 0.25)
var max_lifetime: float = DEFAULT_MAX_LIFETIME
var max_samples: int = DEFAULT_MAX_SAMPLES

# Transform offsets relative to weapon node
var tip_offset: Vector3 = Vector3(0.0, 1.15, 0.0)
var base_offset: Vector3 = Vector3(0.0, 0.25, 0.0)

# Mode flags
var is_local_space: bool = true
var target_visual_layer: int = 1

# Internal state
var _samples: Array[Dictionary] = []
var _is_swing_active: bool = false
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var _particles: CPUParticles3D = null
var _has_prev_point: bool = false
var _prev_tip: Vector3 = Vector3.ZERO
var _prev_base: Vector3 = Vector3.ZERO


func _ready() -> void:
	_init_components()


## Configures the trail effect for either local camera-space or world-space rendering.
func setup(local_mode: bool, layer: int, config: Dictionary = {}) -> void:
	is_local_space = local_mode
	target_visual_layer = layer
	_init_components()
	set_trail_config(config)
	_apply_visual_layers()


## Applies weapon-specific configuration dictionary.
func set_trail_config(config: Dictionary) -> void:
	if config.has("color"):
		trail_color = config["color"]
	if config.has("edge_color"):
		edge_color = config["edge_color"]
	if config.has("base_color"):
		base_color_tint = config["base_color"]
	else:
		base_color_tint = Color(trail_color.r, trail_color.g, trail_color.b, trail_color.a * 0.35)
	if config.has("lifetime"):
		max_lifetime = config["lifetime"]
	if config.has("tip_offset"):
		tip_offset = config["tip_offset"]
	if config.has("base_offset"):
		base_offset = config["base_offset"]
	if config.has("max_samples"):
		max_samples = config["max_samples"]

	if _particles and is_instance_valid(_particles):
		_particles.color = trail_color


func _init_components() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return

	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "TrailMesh"
	_mesh_instance.mesh = _immediate_mesh
	add_child(_mesh_instance)

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_mesh_instance.material_override = _material

	_init_particles()
	_apply_visual_layers()


func _init_particles() -> void:
	if _particles != null and is_instance_valid(_particles):
		return

	_particles = CPUParticles3D.new()
	_particles.name = "TipWisps"
	_particles.emitting = false
	_particles.amount = 14
	_particles.lifetime = 0.15
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.local_coords = false
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 0.025
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 0.05
	_particles.initial_velocity_max = 0.25
	_particles.spread = 35.0
	_particles.damping_min = 0.8
	_particles.damping_max = 1.6
	_particles.color = trail_color

	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)

	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mat.vertex_color_use_as_albedo = true

	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex:
		p_mat.albedo_texture = tex
	quad.material = p_mat
	_particles.mesh = quad

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.15))
	_particles.scale_amount_curve = scale_curve
	_particles.scale_amount_min = 0.6
	_particles.scale_amount_max = 1.2

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.65),
		Color(1.0, 1.0, 1.0, 0.35),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_particles.color_ramp = grad

	add_child(_particles)


func _apply_visual_layers() -> void:
	var mask := 1 << (target_visual_layer - 1)
	if _mesh_instance and is_instance_valid(_mesh_instance):
		_mesh_instance.layers = mask
	if _particles and is_instance_valid(_particles):
		_particles.layers = mask


## Signals that a forward attack swing has started.
func start_swing() -> void:
	_is_swing_active = true
	_has_prev_point = false
	if _particles and is_instance_valid(_particles):
		_particles.emitting = true


## Signals that the forward strike phase has ended.
func stop_swing() -> void:
	_is_swing_active = false
	_has_prev_point = false
	if _particles and is_instance_valid(_particles):
		_particles.emitting = false


## Updates the trail geometry for the current frame.
## [param delta] - process delta time
## [param is_striking] - whether the blade is in its active forward slash
## [param current_tip] - weapon tip position (camera space if local, world space if not)
## [param current_base] - weapon base/hilt position (camera space if local, world space if not)
func update_trail(delta: float, is_striking: bool, current_tip: Vector3, current_base: Vector3) -> void:
	_init_components()

	# Update swing activation state
	if is_striking and not _is_swing_active:
		start_swing()
	elif not is_striking and _is_swing_active:
		stop_swing()

	# 1. Age existing sample points
	var i := 0
	while i < _samples.size():
		_samples[i]["age"] += delta
		if _samples[i]["age"] >= max_lifetime:
			_samples.remove_at(i)
		else:
			i += 1

	# 2. Record new points during active strike
	if is_striking:
		if _has_prev_point:
			var tip_dist := _prev_tip.distance_to(current_tip)
			if tip_dist >= MIN_SAMPLE_DISTANCE:
				# If distance is large (fast flick or low FPS), add an interpolated midpoint for smooth curvature
				if tip_dist >= INTERPOLATE_DISTANCE and tip_dist < 2.5:
					var mid_tip := _prev_tip.lerp(current_tip, 0.5)
					var mid_base := _prev_base.lerp(current_base, 0.5)
					_samples.append({
						"tip": mid_tip,
						"base": mid_base,
						"age": delta * 0.5,
					})

				_samples.append({
					"tip": current_tip,
					"base": current_base,
					"age": 0.0,
				})
				_prev_tip = current_tip
				_prev_base = current_base
		else:
			_samples.append({
				"tip": current_tip,
				"base": current_base,
				"age": 0.0,
			})
			_prev_tip = current_tip
			_prev_base = current_base
			_has_prev_point = true

		if _samples.size() > max_samples:
			_samples.remove_at(0)

		# Position particle emitter at weapon tip
		if _particles and is_instance_valid(_particles):
			_particles.position = current_tip
	else:
		_has_prev_point = false

	# 3. Reconstruct ImmediateMesh surface geometry
	_rebuild_mesh()


func _rebuild_mesh() -> void:
	if _immediate_mesh == null:
		return

	_immediate_mesh.clear_surfaces()

	var count := _samples.size()
	if count < 2:
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)

	for idx in range(count - 1):
		var s0: Dictionary = _samples[idx]
		var s1: Dictionary = _samples[idx + 1]

		var t0: Vector3 = s0["tip"]
		var b0: Vector3 = s0["base"]
		var t1: Vector3 = s1["tip"]
		var b1: Vector3 = s1["base"]

		# Progress: 0.0 at oldest tail (expires soon), 1.0 at newest head (just spawned)
		var life_ratio0 := clampf(1.0 - (float(s0["age"]) / max_lifetime), 0.0, 1.0)
		var life_ratio1 := clampf(1.0 - (float(s1["age"]) / max_lifetime), 0.0, 1.0)

		# Ease out the alpha along the tail
		var alpha0 := life_ratio0 * life_ratio0
		var alpha1 := life_ratio1 * life_ratio1

		# Slight aerodynamic width taper near the very tail tip
		var taper0 := clampf(life_ratio0 * 1.35, 0.15, 1.0)
		var taper1 := clampf(life_ratio1 * 1.35, 0.15, 1.0)
		b0 = t0.lerp(b0, taper0)
		b1 = t1.lerp(b1, taper1)

		# Outer edge color (blade tip - bright cutting gleam)
		var col_tip0 := Color(edge_color.r, edge_color.g, edge_color.b, edge_color.a * alpha0)
		var col_tip1 := Color(edge_color.r, edge_color.g, edge_color.b, edge_color.a * alpha1)

		# Inner base color (softer translucent fade)
		var col_base0 := Color(base_color_tint.r, base_color_tint.g, base_color_tint.b, base_color_tint.a * alpha0)
		var col_base1 := Color(base_color_tint.r, base_color_tint.g, base_color_tint.b, base_color_tint.a * alpha1)

		var u0 := float(idx) / float(count - 1)
		var u1 := float(idx + 1) / float(count - 1)

		# Triangle 1: t0 -> b0 -> t1
		_immediate_mesh.surface_set_color(col_tip0)
		_immediate_mesh.surface_set_uv(Vector2(u0, 0.0))
		_immediate_mesh.surface_add_vertex(t0)

		_immediate_mesh.surface_set_color(col_base0)
		_immediate_mesh.surface_set_uv(Vector2(u0, 1.0))
		_immediate_mesh.surface_add_vertex(b0)

		_immediate_mesh.surface_set_color(col_tip1)
		_immediate_mesh.surface_set_uv(Vector2(u1, 0.0))
		_immediate_mesh.surface_add_vertex(t1)

		# Triangle 2: t1 -> b0 -> b1
		_immediate_mesh.surface_set_color(col_tip1)
		_immediate_mesh.surface_set_uv(Vector2(u1, 0.0))
		_immediate_mesh.surface_add_vertex(t1)

		_immediate_mesh.surface_set_color(col_base0)
		_immediate_mesh.surface_set_uv(Vector2(u0, 1.0))
		_immediate_mesh.surface_add_vertex(b0)

		_immediate_mesh.surface_set_color(col_base1)
		_immediate_mesh.surface_set_uv(Vector2(u1, 1.0))
		_immediate_mesh.surface_add_vertex(b1)

	_immediate_mesh.surface_end()


## Clears all active samples and resets the mesh.
func clear() -> void:
	_samples.clear()
	_has_prev_point = false
	if _immediate_mesh:
		_immediate_mesh.clear_surfaces()
	if _particles and is_instance_valid(_particles):
		_particles.emitting = false
