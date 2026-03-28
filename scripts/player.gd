extends CharacterBody3D

#variables and constants
const WALK_SPEED = 7.0
const SPRINT_SPEED = 11.0
const JUMP_VELOCITY = 8
const BUMP_STEP_VELOCITY = 2.2
const BUMP_STEP_COOLDOWN = 0.12
const SENSITIVITY = 0.003
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5
const POSITION_LOG_INTERVAL = 0.25
@export_range(2.0, 80.0, 0.5) var vision_distance: float = 20.0
@export_range(0.5, 10.0, 0.1) var vision_radius: float = 3.0
@export var debug_position_logs: bool = true
#------------------------------------------------------
var speed
var t_bob = 0.0
var gravity = 20
var bump_step_timer = 0.0
var position_log_timer = 0.0
var movement_lock_sources: Array[Node] = []
#------------------------------------------------------
@onready var head = $Head
@onready var camera = $Head/playerCamera
@onready var player_model = $PlayerModel
@onready var animation_player = $PlayerModel/AnimationPlayer
@onready var vision_collision_shape: CollisionShape3D = $Head/playerCamera/Vision/CollisionShape3D

#function on startup
func _ready():
	#detects mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_snap_length = 0.7
	_configure_vision_area()
	
	# Initialize model rotation
	if player_model:
		player_model.rotation.y = head.rotation.y
		print("Player model found and initialized")
		# Make player model invisible to player camera
		_set_layer_recursive(player_model, 2)  # Set model to layer 2
		camera.cull_mask = camera.cull_mask & ~2  # Exclude layer 2 from camera
	else:
		print("WARNING: Player model not found!")

func _configure_vision_area():
	if vision_collision_shape == null:
		print("WARNING: Vision collision shape not found!")
		return

	var vision_shape = vision_collision_shape.shape as CapsuleShape3D
	if vision_shape == null:
		print("WARNING: Vision shape is not CapsuleShape3D")
		return

	vision_shape.radius = vision_radius
	vision_shape.height = max(vision_distance - (vision_radius * 2.0), 0.1)

	# Rotate the capsule forward and place its center halfway into view distance.
	vision_collision_shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	vision_collision_shape.position = Vector3(0.0, 0.0, -vision_distance * 0.5)

#camera function
func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(90))
		# Rotate the player model to match head's Y rotation
		if player_model:
			player_model.rotation.y = head.rotation.y

#movement function
func _physics_process(delta):
	bump_step_timer = max(bump_step_timer - delta, 0.0)
	position_log_timer = max(position_log_timer - delta, 0.0)
	var is_movement_locked := _is_movement_locked()

	if not is_on_floor():
		velocity.y -= gravity * delta
#------------------------------------------------------
#jump input
	if not is_movement_locked and Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
#------------------------------------------------------
#sprint input
	if not is_movement_locked and Input.is_action_pressed("shift"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED
#------------------------------------------------------
#wasd direction input and other physics
	var input_dir := Vector2.ZERO
	if not is_movement_locked:
		input_dir = Input.get_vector("a", "d", "w", "s")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Animation handling
	if animation_player:
		if direction and is_on_floor():
			# Player is moving on ground
			if speed == SPRINT_SPEED:
				if animation_player.has_animation("walking"):
					if animation_player.current_animation != "walking":
						animation_player.play("walking")
			else:
				if animation_player.has_animation("walking"):
					if animation_player.current_animation != "walking":
						animation_player.play("walking")
		else:
			# Player is not moving or in air - play idle
			if animation_player.has_animation("idle"):
				if animation_player.current_animation != "idle":
					animation_player.play("idle")
	
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 2.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 2.0)
#------------------------------------------------------
#headbob during movement
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)
#------------------------------------------------------
#fov changing
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	# Update player model rotation to match head
	if player_model:
		player_model.rotation.y = head.rotation.y

	# Step up tiny bumps while moving so movement stays smooth on uneven floors.
	if input_dir != Vector2.ZERO and is_on_floor() and is_on_wall() and velocity.y <= 0.0 and bump_step_timer <= 0.0:
		velocity.y = BUMP_STEP_VELOCITY
		bump_step_timer = BUMP_STEP_COOLDOWN
	
	move_and_slide()
	_log_player_position()

func set_movement_locked_by(locker: Node, locked: bool) -> void:
	if locker == null:
		return

	if locked:
		if not movement_lock_sources.has(locker):
			movement_lock_sources.append(locker)
	else:
		movement_lock_sources.erase(locker)

func _is_movement_locked() -> bool:
	return movement_lock_sources.size() > 0

func is_movement_locked_by_other(locker: Node) -> bool:
	for source in movement_lock_sources:
		if source != locker:
			return true
	return false

#function for head bob
func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

func _format_vec3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _log_player_position() -> void:
	if not debug_position_logs:
		return
	if position_log_timer > 0.0:
		return
	position_log_timer = POSITION_LOG_INTERVAL
	print("[PlayerPos] player=%s velocity=%s on_floor=%s" % [
		_format_vec3(global_position),
		_format_vec3(velocity),
		str(is_on_floor()),
	])

# Debug function to check collision state
func _input(event):
	if event.is_action_pressed("ui_cancel"):  # ESC key - toggle mouse mode for debugging
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if event.is_action_pressed("space"):  # Space key - print debug info
		print("=== PLAYER DEBUG INFO ===")
		print("Position: ", global_position)
		print("Velocity: ", velocity)
		print("Is on floor: ", is_on_floor())
		print("Floor normal: ", get_floor_normal())
		print("Wall normal: ", get_wall_normal())
		print("Slide collision count: ", get_slide_collision_count())
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			print("Collision ", i, ": ", collision.get_collider(), " at ", collision.get_position())

# Helper function to set visual layer for all mesh instances recursively
func _set_layer_recursive(node: Node, layer: int):
	if node is VisualInstance3D:
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_layer_recursive(child, layer)
