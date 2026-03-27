extends CharacterBody3D

# Movement constants
const WALK_SPEED = 10.0
const GRAVITY = 20.0
const DETECTION_RANGE = 50.0
const VIEW_CONE_ANGLE = 60.0
const WALK_IDLE_FRAME_TIME = 1.0 / 30.0  # Frame 1 at 30 FPS to avoid T-pose while idle
const BUMP_STEP_VELOCITY = 2.0
const BUMP_STEP_COOLDOWN = 0.15
const LOS_MEMORY_TIME = 10
const SENSE_RAY_HEIGHT = 0.8
const TRAIL_MEMORY_TIME = 5.0
const TRAIL_SAMPLE_INTERVAL = 0.2
const TRAIL_POINT_SPACING = 0.7
const TRAIL_REACHED_DISTANCE = 0.8
const TRAIL_MAX_POINTS = 28
const MEMORY_LOG_INTERVAL = 0.25
@export var debug_memory_logs: bool = false

# References
var player: CharacterBody3D = null
var player_camera: Camera3D = null
var animation_player: AnimationPlayer = null
var detection_area: Area3D = null
var skeleton: Skeleton3D = null
var head_bone_id: int = -1
var is_moving = false

# Stuck detection and pathfinding
var was_trying_to_move: bool = false
var preferred_direction: Vector3 = Vector3.ZERO  # Remember which way we're trying to go
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right
var bump_step_timer: float = 0.0
var los_memory_timer: float = 0.0
var last_visible_player_position: Vector3 = Vector3.ZERO
var trail_memory_timer: float = 0.0
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false

func _ready():
	call_deferred("_setup_player_reference")
	call_deferred("_setup_animation_player")
	call_deferred("_setup_detection_area")
	call_deferred("_setup_skeleton")
	
	# Configure CharacterBody3D for better corner and slope handling
	floor_max_angle = deg_to_rad(46)  # Allow steeper slopes
	floor_snap_length = 0.7  # Better slope adhesion
	wall_min_slide_angle = deg_to_rad(15)  # Slide along walls more easily

func _setup_player_reference():
	# Wait for the first physics frame
	await get_tree().physics_frame
	
	# Find the player in the scene
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		# Try to find player by type
		var nodes = get_tree().get_nodes_in_group("player")
		if nodes.size() > 0:
			player = nodes[0]
		else:
			# Search manually if not in group
			player = _find_player(get_tree().root)
	
	if player:
		print("Statue found player: ", player.name, " at position: ", player.global_position)
		# Find the player's camera
		player_camera = _find_camera(player)
		if player_camera:
			print("Statue found player camera")
		else:
			print("WARNING: Could not find player camera!")
	else:
		print("WARNING: Statue could not find player!")
	
	print("Statue ready at position: ", global_position)

func _setup_animation_player():
	# Find the AnimationPlayer in the statue model
	animation_player = _find_animation_player(self)
	if animation_player:
		print("Statue found AnimationPlayer")
		_set_idle_pose()
	else:
		print("WARNING: Could not find AnimationPlayer in statue!")

func _setup_detection_area():
	# Find the Area3D for obstacle detection
	detection_area = _find_area3d(self)
	if detection_area:
		print("Statue found Area3D for navigation detection")
	else:
		print("WARNING: Could not find Area3D in statue!")

func _setup_skeleton():
	# Find the Skeleton3D and head bone for head tracking
	skeleton = _find_skeleton(self)
	if skeleton:
		print("Statue found Skeleton3D")
		print("Available bones in skeleton:")
		for i in range(skeleton.get_bone_count()):
			print("  Bone ", i, ": ", skeleton.get_bone_name(i))
		
		# Try common head bone names
		var head_bone_names = ["mixamorig_Head", "mixamorig:Head", "Head", "head", "HEAD", "Armature_Head", "Bone_Head"]
		for bone_name in head_bone_names:
			head_bone_id = skeleton.find_bone(bone_name)
			if head_bone_id != -1:
				print("Statue found head bone: ", bone_name, " at index ", head_bone_id)
				break
		if head_bone_id == -1:
			print("WARNING: Could not find head bone. Tried: ", head_bone_names)
	else:
		print("WARNING: Could not find Skeleton3D in statue!")

func _find_skeleton(node: Node) -> Skeleton3D:
	# Recursively search for Skeleton3D
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null

func _find_area3d(node: Node) -> Area3D:
	# Recursively search for Area3D
	if node is Area3D:
		return node
	for child in node.get_children():
		var result = _find_area3d(child)
		if result:
			return result
	return null

func _find_camera(node: Node) -> Camera3D:
	# Recursively search for camera
	if node is Camera3D:
		return node
	for child in node.get_children():
		var result = _find_camera(child)
		if result:
			return result
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	# Recursively search for AnimationPlayer
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null

func _find_player(node: Node) -> CharacterBody3D:
	# Recursively search for player node
	if node.name == "Player" or node.name == "player" or node.get_script() == preload("res://scripts/player.gd"):
		return node
	for child in node.get_children():
		var result = _find_player(child)
		if result:
			return result
	return null

func _is_player_looking_at_statue() -> bool:
	if not player_camera or not player:
		return false
	
	# Get direction from camera to statue
	var direction_to_statue = (global_position - player_camera.global_position).normalized()
	
	# Get the camera's forward direction
	var camera_forward = -player_camera.global_transform.basis.z.normalized()
	
	# Calculate the angle between camera forward and direction to statue
	var dot_product = camera_forward.dot(direction_to_statue)
	var angle = rad_to_deg(acos(dot_product))
	
	# Check if statue is within the view cone
	if angle <= VIEW_CONE_ANGLE:
		# Do a raycast to check if there's line of sight
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(player_camera.global_position, global_position)
		query.exclude = [player, self]  # Exclude player and statue from raycast
		var result = space_state.intersect_ray(query)
		
		# If raycast didn't hit anything, player has clear line of sight
		if result.is_empty():
			return true
	
	return false

func _physics_process(delta):
	bump_step_timer = max(bump_step_timer - delta, 0.0)
	los_memory_timer = max(los_memory_timer - delta, 0.0)
	trail_memory_timer = max(trail_memory_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0

	was_trying_to_move = false
	
	# Chase player if found and in range
	if player and is_instance_valid(player):
		var distance_to_player = global_position.distance_to(player.global_position)
		var space_state := get_world_3d().direct_space_state
		var has_line_of_sight = NavigationUtils.has_line_of_sight_to(self, player.global_position + Vector3(0, 1.0, 0), space_state, [self, player])
		var los_state := NavigationUtils.update_los_trail_state(
			has_line_of_sight,
			los_state_initialized,
			previous_has_line_of_sight,
			trail_memory_timer,
			trail_sample_timer,
			memorized_target_trail,
			last_visible_player_position,
			TRAIL_MEMORY_TIME,
			TRAIL_POINT_SPACING,
			TRAIL_MAX_POINTS
		)
		los_state_initialized = bool(los_state.get("los_state_initialized", los_state_initialized))
		previous_has_line_of_sight = bool(los_state.get("previous_has_line_of_sight", previous_has_line_of_sight))
		trail_memory_timer = float(los_state.get("trail_memory_timer", trail_memory_timer))
		trail_sample_timer = float(los_state.get("trail_sample_timer", trail_sample_timer))
		if has_line_of_sight:
			last_visible_player_position = player.global_position
			los_memory_timer = LOS_MEMORY_TIME
			trail_memory_timer = TRAIL_MEMORY_TIME
			if trail_sample_timer <= 0.0:
				NavigationUtils.append_trail_point(memorized_target_trail, player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
				trail_sample_timer = TRAIL_SAMPLE_INTERVAL
		
		# Weeping Angel behavior - freeze if player is looking at statue
		if _is_player_looking_at_statue():
			# Player is looking - freeze completely
			velocity.x = 0
			velocity.z = 0
			_freeze_animation()
			is_moving = false
		elif distance_to_player <= DETECTION_RANGE and distance_to_player > 1.5:
			# Player NOT looking and in range - move toward player
			var pursuit_target = player.global_position
			var trail_target := Vector3.ZERO
			var memory_source := "LOS"
			if not has_line_of_sight:
				memory_source = "LAST_SEEN"
				var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
				if trail_memory_timer > 0.0 and bool(trail_result.get("has_target", false)):
					trail_target = trail_result["target"]
					pursuit_target = trail_target
					memory_source = "TRAIL"
				else:
					_log_memory_state(has_line_of_sight, memory_source, player.global_position, last_visible_player_position, trail_target, global_position, true)
					velocity.x = 0
					velocity.z = 0
					_set_idle_pose()
					is_moving = false
					wall_follow_mode = 0
					move_and_slide()
					return

			_log_memory_state(has_line_of_sight, memory_source, player.global_position, last_visible_player_position, trail_target, pursuit_target)

			# Get direction to current pursuit target
			var direction_to_player = (pursuit_target - global_position)
			direction_to_player.y = 0
			if direction_to_player.length_squared() <= 0.001:
				velocity.x = 0
				velocity.z = 0
				_set_idle_pose()
				is_moving = false
				move_and_slide()
				return
			direction_to_player = direction_to_player.normalized()

			var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
			var move_direction: Vector3 = path_result["direction"]
			wall_follow_mode = path_result["wall_follow_mode"]
			if move_direction.length() <= 0.1:
				move_direction = direction_to_player * 0.4
			
			if move_direction.length() > 0.1:
				was_trying_to_move = true
				
				# Move in the best direction - let move_and_slide handle corner sliding
				velocity.x = move_direction.x * WALK_SPEED
				velocity.z = move_direction.z * WALK_SPEED
				
				# Play walking animation
				_set_animation("walking")
				is_moving = true
				
				# Rotate to face movement direction
				var target_rotation = atan2(move_direction.x, move_direction.z)
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
			else:
				# Fully blocked: stop instead of pushing forever into a wall.
				velocity.x = 0
				velocity.z = 0
				_set_idle_pose()
				is_moving = false
		else:
			# Player too close or out of range, stop moving
			velocity.x = 0
			velocity.z = 0
			_set_idle_pose()
			is_moving = false
	else:
		# No player, stop moving
		velocity.x = 0
		velocity.z = 0
		_set_idle_pose()
		is_moving = false

	# Step up tiny bumps while moving so statue keeps advancing on uneven ground.
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.2 and is_on_floor() and is_on_wall() and velocity.y <= 0.0 and bump_step_timer <= 0.0:
		velocity.y = BUMP_STEP_VELOCITY
		bump_step_timer = BUMP_STEP_COOLDOWN
	
	move_and_slide()

func _process(_delta):
	# Head tracking runs in _process AFTER animations update
	# This ensures it's applied on top of animation data
	_update_head_tracking()

func _update_head_tracking():
	"""Make the statue's head look at the player (works even when frozen)"""
	if not skeleton or head_bone_id == -1 or not player or not is_instance_valid(player):
		return
	
	# Get rest pose - we'll preserve position and scale
	var rest_pose = skeleton.get_bone_rest(head_bone_id)
	
	# Get the global transform of the head bone
	var head_global_pose = skeleton.get_bone_global_pose(head_bone_id)
	var head_world_pos = (skeleton.global_transform * head_global_pose).origin
	
	# Player target position
	var player_target = player.global_position + Vector3(0, 1.6, 0)
	
	# Direction to look at in world space
	var look_direction = (player_target - head_world_pos).normalized()
	
	# Get parent bone to convert to local space
	var neck_id = skeleton.get_bone_parent(head_bone_id)
	if neck_id != -1:
		var neck_global = skeleton.get_bone_global_pose(neck_id)
		var neck_world = skeleton.global_transform * neck_global
		
		# Convert look direction to neck's local space
		var local_look = neck_world.basis.inverse() * look_direction
		
		# Create a rotation basis that looks in this direction
		# Preserve the original "up" orientation from rest pose
		var up = rest_pose.basis.y.normalized()
		var forward = -local_look.normalized()
		var right = up.cross(forward).normalized()
		if right.length() < 0.01:  # Handle edge case where up and forward are parallel
			right = Vector3.RIGHT
		up = forward.cross(right).normalized()
		
		var look_basis = Basis(right, up, forward)
		
		# Blend with rest pose basis (50% tracking)
		var final_basis = rest_pose.basis.slerp(look_basis, 0.5)
		
		# Create final transform: blended rotation + original position
		var final_transform = Transform3D(final_basis, rest_pose.origin)
		skeleton.set_bone_pose(head_bone_id, final_transform)

func _set_animation(anim_name: String):
	# Helper function to play animations safely
	if animation_player and animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			# Playing a new animation
			animation_player.play(anim_name)
			animation_player.speed_scale = 1.0
		elif not animation_player.is_playing():
			# Animation not playing, start it
			animation_player.play(anim_name)
			animation_player.speed_scale = 1.0
		else:
			# Same animation already playing - just ensure it's at normal speed (unfreezing)
			animation_player.speed_scale = 1.0

func _freeze_animation():
	# Freeze animation at current frame (for Weeping Angel effect)
	if animation_player and animation_player.is_playing():
		animation_player.speed_scale = 0.0

func _stop_animation():
	# Helper function to stop animations
	if animation_player:
		animation_player.stop()
		animation_player.speed_scale = 1.0

func _set_idle_pose():
	# Keep a non-T-pose idle by holding walking animation on frame 1.
	if not animation_player or not animation_player.has_animation("walking"):
		return

	if animation_player.current_animation != "walking" or not animation_player.is_playing():
		animation_player.play("walking")

	animation_player.seek(WALK_IDLE_FRAME_TIME, true)
	animation_player.speed_scale = 0.0

func _format_vec3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _log_memory_state(
	has_los: bool,
	source: String,
	player_pos: Vector3,
	last_seen_pos: Vector3,
	trail_target: Vector3,
	pursuit_target: Vector3,
	force: bool = false
) -> void:
	if not debug_memory_logs:
		return
	if not force and memory_log_timer > 0.0:
		return
	memory_log_timer = MEMORY_LOG_INTERVAL
	print("[StatueMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d trail_timer=%.2f los_timer=%.2f" % [
		source,
		str(has_los),
		_format_vec3(player_pos),
		_format_vec3(last_seen_pos),
		_format_vec3(trail_target),
		_format_vec3(pursuit_target),
		memorized_target_trail.size(),
		trail_memory_timer,
		los_memory_timer,
	])
