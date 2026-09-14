class_name HealParticleEffect
extends RefCounted

## Visual healing particle effect.
## Emits glowing green crosses that float upwards from the bottom of the screen
## and fade out over time when the player consumes a healing potion.

const PARTICLE_COUNT_MIN := 24
const PARTICLE_COUNT_MAX := 34
const LIFETIME := 2.2
const TEXTURE_PATH := "res://assets/ui/green_cross.png"

static var _cross_texture: Texture2D = null


## Spawns the green cross floating particle effect on the player's active HUD canvas.
static func spawn(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return

	# Only authority / local player needs full screen-space HUD particle effect
	if player.is_inside_tree() and player.has_method("is_multiplayer_authority") and not player.is_multiplayer_authority():
		return

	var canvas: CanvasLayer = _resolve_canvas_layer(player)
	if canvas == null:
		return

	# Determine viewport bounds
	var viewport_size := Vector2(1280.0, 960.0)
	var viewport := player.get_viewport()
	if viewport != null:
		var rect := viewport.get_visible_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			viewport_size = rect.size

	var particles := CPUParticles2D.new()
	particles.name = "HealCrossParticles"
	particles.z_index = 101
	particles.emitting = false
	particles.one_shot = true
	particles.amount = randi_range(PARTICLE_COUNT_MIN, PARTICLE_COUNT_MAX)
	particles.lifetime = LIFETIME
	particles.explosiveness = 0.2
	particles.lifetime_randomness = 0.35

	var tex := _get_texture()
	if tex != null:
		particles.texture = tex

	# Emission area: spans the bottom border of the viewport
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(viewport_size.x * 0.46, 10.0)
	particles.position = Vector2(viewport_size.x * 0.5, viewport_size.y + 8.0)

	# Movement: floats upward with gentle drift and slight negative gravity
	particles.direction = Vector2(0.0, -1.0)
	particles.spread = 18.0
	particles.gravity = Vector2(0.0, -12.0)
	particles.initial_velocity_min = 180.0
	particles.initial_velocity_max = 310.0

	# Subtle orientation and size variance
	particles.angular_velocity_min = -25.0
	particles.angular_velocity_max = 25.0
	particles.angle_min = -12.0
	particles.angle_max = 12.0
	particles.scale_amount_min = 0.65
	particles.scale_amount_max = 1.15

	# Color and alpha fade ramp: start transparent at screen edge, bright fade in, gentle linger, fade away
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.95, 0.4, 0.0))
	ramp.set_color(1, Color(0.1, 0.75, 0.3, 0.0))
	ramp.add_point(0.12, Color(0.25, 1.0, 0.45, 0.95))
	ramp.add_point(0.68, Color(0.18, 0.9, 0.38, 0.85))
	particles.color_ramp = ramp

	canvas.add_child(particles)
	particles.emitting = true

	# Auto clean-up
	particles.finished.connect(particles.queue_free)
	var tree: SceneTree = null
	if canvas.is_inside_tree():
		tree = canvas.get_tree()
	elif player.is_inside_tree():
		tree = player.get_tree()

	if tree != null:
		tree.create_timer(LIFETIME + 0.5).timeout.connect(func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
		)


static func _resolve_canvas_layer(player: Node) -> CanvasLayer:
	var canvas := player.get("player_canvas_layer") as CanvasLayer
	if canvas != null and is_instance_valid(canvas):
		return canvas

	var direct_canvas := player.get_node_or_null("CanvasLayer") as CanvasLayer
	if direct_canvas != null:
		return direct_canvas

	for child in player.get_children():
		if child is CanvasLayer:
			return child

	var tree := player.get_tree()
	if tree != null and tree.current_scene != null:
		var scene_canvas := tree.current_scene.get_node_or_null("CanvasLayer") as CanvasLayer
		if scene_canvas != null:
			return scene_canvas

	return null


static func _get_texture() -> Texture2D:
	if _cross_texture != null:
		return _cross_texture

	if ResourceLoader.exists(TEXTURE_PATH):
		var res := load(TEXTURE_PATH)
		if res is Texture2D:
			_cross_texture = res
			return _cross_texture

	var global_path := ProjectSettings.globalize_path(TEXTURE_PATH)
	if FileAccess.file_exists(global_path):
		var img := Image.load_from_file(global_path)
		if img != null and not img.is_empty():
			_cross_texture = ImageTexture.create_from_image(img)
			return _cross_texture

	# Procedural fallback cross if texture cannot be loaded
	_cross_texture = _generate_fallback_cross_texture()
	return _cross_texture


static func _generate_fallback_cross_texture() -> Texture2D:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var green := Color(0.2, 0.9, 0.35, 1.0)
	var glow := Color(0.1, 0.7, 0.25, 0.4)

	for y in size:
		for x in size:
			var in_v_bar := (x >= 12 and x <= 19 and y >= 4 and y <= 27)
			var in_h_bar := (x >= 4 and x <= 27 and y >= 12 and y <= 19)
			var in_glow_v := (x >= 10 and x <= 21 and y >= 2 and y <= 29)
			var in_glow_h := (x >= 2 and x <= 29 and y >= 10 and y <= 21)

			if in_v_bar or in_h_bar:
				img.set_pixel(x, y, green)
			elif in_glow_v or in_glow_h:
				img.set_pixel(x, y, glow)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)
