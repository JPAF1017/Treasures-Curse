class_name ExhaustionBreathEffect
extends RefCounted

## Exhaustion & Heavy Breathing Particle Visual Effect.
## Emits:
## 1. 3D Cold Condensation Breath: Soft mist puffs exhaled in front of the first-person camera.
## 2. 2D Screen-space Sweat/Fatigue Droplets: Micro perspiration beads dripping along the screen borders.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"

const BREATH_AMOUNT := 8
const BREATH_LIFETIME := 0.78
const BREATH_EFFECT_DURATION := 1.2

const SWEAT_AMOUNT_MIN := 5
const SWEAT_AMOUNT_MAX := 9
const SWEAT_LIFETIME := 1.25

static var _droplet_texture: Texture2D = null


## Spawns a cold breath condensation puff in front of the active camera.
## [param camera] - Active Camera3D reference
static func spawn_breath(camera: Camera3D) -> void:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return

	var root := camera.get_tree().current_scene
	if root == null:
		return

	var cam_basis: Basis = camera.global_transform.basis
	# Spawn lower down and slightly in front of camera (natural mouth/chest level)
	var spawn_pos: Vector3 = camera.global_position + (-cam_basis.z * 0.38) + (-cam_basis.y * 0.28)
	spawn_pos += cam_basis.x * randf_range(-0.025, 0.025)

	var container := Node3D.new()
	container.name = "ExhaustionBreathFX"
	root.add_child(container)
	container.global_position = spawn_pos

	var breath := CPUParticles3D.new()
	breath.name = "BreathPuff"
	breath.emitting = false
	breath.one_shot = true
	breath.amount = BREATH_AMOUNT
	breath.lifetime = BREATH_LIFETIME
	breath.explosiveness = 0.82
	breath.lifetime_randomness = 0.35

	breath.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	breath.emission_sphere_radius = 0.05

	# Direction: forward along look vector with slight upward drift
	var forward_dir := (-cam_basis.z * 0.75 + Vector3.UP * 0.25).normalized()
	breath.direction = forward_dir
	breath.spread = 32.0
	breath.initial_velocity_min = 0.7
	breath.initial_velocity_max = 1.6
	breath.damping_min = 1.4
	breath.damping_max = 2.4
	breath.gravity = Vector3(0.0, 0.18, 0.0) # gentle warm air rise

	# Scale curve: expands from compact mouth puff into soft billowy mist
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.22))
	scale_curve.add_point(Vector2(0.3, 1.15))
	scale_curve.add_point(Vector2(1.0, 1.65))
	breath.scale_amount_curve = scale_curve
	breath.scale_amount_min = 0.45
	breath.scale_amount_max = 0.95

	# Translucent cold frost/condensation gradient
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(0.92, 0.96, 1.0, 0.0),
		Color(0.88, 0.94, 0.98, 0.32),
		Color(0.82, 0.90, 0.96, 0.18),
		Color(0.78, 0.86, 0.94, 0.0),
	])
	breath.color_ramp = grad

	# Billboard QuadMesh with smoke texture (decreased by 30%: 0.45 -> 0.315)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.315, 0.315)

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
	breath.mesh = quad

	container.add_child(breath)
	breath.position = Vector3.ZERO
	breath.restart()
	breath.emitting = true

	# Cleanup container
	var timer := camera.get_tree().create_timer(BREATH_EFFECT_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)


## Spawns subtle 2D sweat/fatigue droplets dripping down the edges of the HUD.
## [param player] - Player node reference
static func spawn_sweat_droplets(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return

	if player.is_inside_tree() and player.has_method("is_multiplayer_authority") and not player.is_multiplayer_authority():
		return

	var canvas := _resolve_canvas_layer(player)
	if canvas == null:
		return

	var viewport_size := Vector2(1280.0, 960.0)
	var viewport := player.get_viewport()
	if viewport != null:
		var rect := viewport.get_visible_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			viewport_size = rect.size

	# Left side perspiration
	_create_sweat_emitter(canvas, Vector2(viewport_size.x * 0.08, 12.0), viewport_size.x * 0.07)
	# Right side perspiration
	_create_sweat_emitter(canvas, Vector2(viewport_size.x * 0.92, 12.0), viewport_size.x * 0.07)


static func _create_sweat_emitter(parent: Node, spawn_pos: Vector2, width_extent: float) -> void:
	var droplets := CPUParticles2D.new()
	droplets.name = "SweatDroplets"
	droplets.z_index = 99
	droplets.emitting = false
	droplets.one_shot = true
	droplets.amount = randi_range(SWEAT_AMOUNT_MIN, SWEAT_AMOUNT_MAX)
	droplets.lifetime = SWEAT_LIFETIME
	droplets.explosiveness = 0.2
	droplets.lifetime_randomness = 0.4

	droplets.texture = _get_droplet_texture()

	# Emission along top edge
	droplets.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	droplets.emission_rect_extents = Vector2(width_extent, 4.0)
	droplets.position = spawn_pos

	# Gravity pulls droplets down the screen
	droplets.direction = Vector2(0.0, 1.0)
	droplets.spread = 15.0
	droplets.initial_velocity_min = 25.0
	droplets.initial_velocity_max = 75.0
	droplets.gravity = Vector2(0.0, 140.0)
	droplets.damping_min = 10.0
	droplets.damping_max = 25.0

	# Scale
	droplets.scale_amount_min = 0.2
	droplets.scale_amount_max = 0.45

	# Clear water / subtle blue tint fading out
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.94, 1.0, 0.0))
	ramp.set_color(1, Color(0.75, 0.88, 1.0, 0.0))
	ramp.add_point(0.2, Color(0.88, 0.95, 1.0, 0.5))
	ramp.add_point(0.75, Color(0.82, 0.92, 1.0, 0.35))
	droplets.color_ramp = ramp

	parent.add_child(droplets)
	droplets.restart()
	droplets.emitting = true

	var tree := parent.get_tree()
	if tree != null:
		tree.create_timer(SWEAT_LIFETIME + 0.3).timeout.connect(func() -> void:
			if is_instance_valid(droplets):
				droplets.queue_free()
		)


static func _resolve_canvas_layer(player: Node) -> CanvasLayer:
	var canvas := player.get("player_canvas_layer") as CanvasLayer
	if canvas != null and is_instance_valid(canvas):
		return canvas

	if player.has_node("CanvasLayer"):
		return player.get_node("CanvasLayer") as CanvasLayer

	for child in player.get_children():
		if child is CanvasLayer:
			return child as CanvasLayer

	return null


static func _get_droplet_texture() -> Texture2D:
	if _droplet_texture != null:
		return _droplet_texture

	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (float(size) - 1.0) * 0.5

	for y in range(size):
		for x in range(size):
			var nx := (float(x) - center) / center
			var ny := (float(y) - center) / center
			var dist := sqrt(nx * nx + ny * ny)

			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			alpha = alpha * alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_droplet_texture = ImageTexture.create_from_image(img)
	return _droplet_texture
