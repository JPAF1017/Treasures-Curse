extends CharacterBody3D

#variables and constants
const WALK_SPEED = 7.0
const SPRINT_SPEED = 11.0
const CROUCH_SPEED = 3.5
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
@export var debug_position_logs: bool = false
@export var hide_visual_from_player_camera: bool = false
@export_range(-360.0, 360.0, 1.0) var visual_yaw_offset_degrees: float = 180.0
@export var crouch_head_y: float = -0.111
@export_range(1.0, 30.0, 0.5) var crouch_transition_speed: float = 12.0
@export var visual_root_path: NodePath
@export var animation_player_path: NodePath
#------------------------------------------------------
var speed
var t_bob = 0.0
var gravity = 20
var bump_step_timer = 0.0
var position_log_timer = 0.0
var movement_lock_sources: Array[Node] = []
var initial_head_position: Vector3 = Vector3.ZERO
var target_head_y: float = 0.0
var is_crouching: bool = false
#------------------------------------------------------
@onready var head = $Head
@onready var stand_collision: CollisionShape3D = $Stand
@onready var crouch_collision: CollisionShape3D = $Crouch
@onready var camera = $Head/playerCamera
@onready var vision_collision_shape: CollisionShape3D = $Head/playerCamera/Vision/CollisionShape3D
@onready var visual_root: Node3D = _resolve_visual_root()
@onready var animation_player: AnimationPlayer = _resolve_animation_player()

#function on startup
func _ready():
	#detects mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_snap_length = 0.7
	_configure_vision_area()
	initial_head_position = head.position
	target_head_y = initial_head_position.y
	
	# Initialize player visual rotation.
	if visual_root:
		visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)
		_configure_player_visual_visibility()
	else:
		print("WARNING: Player visual root not found!")

func _configure_player_visual_visibility() -> void:
	if visual_root == null or camera == null:
		return

	if hide_visual_from_player_camera:
		# Put player visuals on layer 2 and hide that layer from this camera.
		_set_layer_recursive(visual_root, 2)
		camera.cull_mask = camera.cull_mask & ~2
	else:
		# Keep visuals on default layer so the player model is visible for animation testing.
		_set_layer_recursive(visual_root, 1)
		camera.cull_mask = camera.cull_mask | 1

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
		_sync_visual_rotation_to_head()

#movement function
func _physics_process(delta):
	bump_step_timer = max(bump_step_timer - delta, 0.0)
	position_log_timer = max(position_log_timer - delta, 0.0)
	var is_movement_locked := _is_movement_locked()
	var input_dir := Vector2.ZERO
	if not is_movement_locked:
		input_dir = Input.get_vector("a", "d", "w", "s")

	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_crouch_state(Input.is_action_pressed("Ctrl"))
	_update_head_height(delta)
#------------------------------------------------------
#jump input
	if not is_movement_locked and Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
#------------------------------------------------------
#sprint input
	# Sprint is only valid while moving forward (including forward diagonals) and not crouching.
	var can_sprint := input_dir.y < 0.0 and not is_crouching
	if is_crouching:
		speed = CROUCH_SPEED
	elif not is_movement_locked and Input.is_action_pressed("shift") and can_sprint:
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED
#------------------------------------------------------
#wasd direction input and other physics
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Animation handling
	if animation_player:
		var is_walking_forward := input_dir.y < 0.0
		var is_walking_backward := input_dir.y > 0.0
		var is_strafing_left := input_dir.x < 0.0
		var is_strafing_right := input_dir.x > 0.0
		var wants_run := Input.is_action_pressed("shift") and can_sprint
		if is_on_floor():
			if is_crouching:
				if is_walking_forward and animation_player.has_animation("crouchWalk"):
					if animation_player.current_animation != "crouchWalk" or animation_player.speed_scale < 0.0:
						animation_player.play("crouchWalk")
				elif is_walking_backward and animation_player.has_animation("crouchWalk"):
					if animation_player.current_animation != "crouchWalk" or animation_player.speed_scale > 0.0:
						animation_player.play_backwards("crouchWalk")
				elif is_strafing_right and animation_player.has_animation("crouchStrafeRight"):
					if animation_player.current_animation != "crouchStrafeRight":
						animation_player.play("crouchStrafeRight")
				elif is_strafing_left and animation_player.has_animation("crouchStrafeLeft"):
					if animation_player.current_animation != "crouchStrafeLeft":
						animation_player.play("crouchStrafeLeft")
				elif animation_player.has_animation("crouchIdle") and animation_player.current_animation != "crouchIdle":
					animation_player.play("crouchIdle")
			elif animation_player.has_animation("walk"):
				if is_walking_forward:
					if wants_run and animation_player.has_animation("run"):
						if animation_player.current_animation != "run":
							animation_player.play("run")
					elif animation_player.current_animation != "walk" or animation_player.speed_scale < 0.0:
						animation_player.play("walk")
				elif is_walking_backward:
					if animation_player.current_animation != "walk" or animation_player.speed_scale > 0.0:
						animation_player.play_backwards("walk")
				elif is_strafing_left and animation_player.has_animation("leftStrafe"):
					if animation_player.current_animation != "leftStrafe":
						animation_player.play("leftStrafe")
				elif is_strafing_right and animation_player.has_animation("rightStrafe"):
					if animation_player.current_animation != "rightStrafe":
						animation_player.play("rightStrafe")
				elif animation_player.has_animation("idle") and animation_player.current_animation != "idle":
					animation_player.play("idle")
		elif animation_player.has_animation("idle") and animation_player.current_animation != "idle":
			# In air - keep a neutral animation state.
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
	
	_sync_visual_rotation_to_head()

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

func _update_crouch_state(wants_crouch: bool) -> void:
	if wants_crouch and not is_crouching:
		_enter_crouch()
	elif not wants_crouch and is_crouching:
		_exit_crouch()

func _enter_crouch() -> void:
	if crouch_collision:
		crouch_collision.disabled = false
	if stand_collision:
		stand_collision.disabled = true
	target_head_y = crouch_head_y
	is_crouching = true

func _exit_crouch() -> void:
	if stand_collision:
		stand_collision.disabled = false
	if crouch_collision:
		crouch_collision.disabled = true
	target_head_y = initial_head_position.y
	is_crouching = false

func _update_head_height(delta: float) -> void:
	if head == null:
		return

	head.position.y = lerp(head.position.y, target_head_y, delta * crouch_transition_speed)
	if abs(head.position.y - target_head_y) < 0.001:
		head.position.y = target_head_y

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

func _resolve_visual_root() -> Node3D:
	if not visual_root_path.is_empty():
		var configured_visual_root := get_node_or_null(visual_root_path) as Node3D
		if configured_visual_root:
			return configured_visual_root

	for child in get_children():
		if child is Node3D and child != head and _has_visual_descendant(child):
			return child as Node3D

	return null

func _resolve_animation_player() -> AnimationPlayer:
	if not animation_player_path.is_empty():
		var configured_animation_player := get_node_or_null(animation_player_path) as AnimationPlayer
		if configured_animation_player:
			return configured_animation_player

	if visual_root:
		return _find_animation_player_recursive(visual_root)

	return null

func _sync_visual_rotation_to_head() -> void:
	if visual_root:
		visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)

func _has_visual_descendant(node: Node) -> bool:
	if node is VisualInstance3D:
		return true
	for child in node.get_children():
		if _has_visual_descendant(child):
			return true
	return false

func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player_recursive(child)
		if found:
			return found
	return null
