extends CharacterBody3D

# Movement constants
const WALK_SPEED = 10.0
const JUMP_VELOCITY = 6.0
const GRAVITY = 20.0
const DETECTION_RANGE = 50.0
const VIEW_CONE_ANGLE = 60.0
const STUCK_THRESHOLD = 0.3  # If moved less than this, consider stuck
const STUCK_TIME_BEFORE_JUMP = 0.5  # Seconds stuck before jumping
const RAYCAST_DISTANCE = 3.0  # How far to check for obstacles
const SIDE_RAYCAST_DISTANCE = 2.0  # Shorter side checks
const CORNER_DETECT_DISTANCE = 1.5  # Distance to detect corners

# References
var player: CharacterBody3D = null
var player_camera: Camera3D = null
var animation_player: AnimationPlayer = null
var detection_area: Area3D = null
var skeleton: Skeleton3D = null
var head_bone_id: int = -1
var is_moving = false

# Stuck detection and pathfinding
var last_position: Vector3 = Vector3.ZERO
var stuck_timer: float = 0.0
var was_trying_to_move: bool = false
var preferred_direction: Vector3 = Vector3.ZERO  # Remember which way we're trying to go
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right

func _ready():
	call_deferred("_setup_player_reference")
	call_deferred("_setup_animation_player")
	call_deferred("_setup_detection_area")
	call_deferred("_setup_skeleton")
	
	# Configure CharacterBody3D for better corner and slope handling
	floor_max_angle = deg_to_rad(46)  # Allow steeper slopes
	floor_snap_length = 0.5  # Better slope adhesion
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

func _raycast_check(from: Vector3, to: Vector3) -> bool:
	"""Returns true if there's an obstacle between from and to"""
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = 1  # Only check walls/obstacles
	
	var result = space_state.intersect_ray(query)
	return not result.is_empty()

func _check_direction_clear(direction: Vector3, distance: float = RAYCAST_DISTANCE) -> bool:
	"""Check if a direction is clear using raycasting"""
	var check_heights = [0.5, 1.0, 1.5]  # Low, middle, high
	
	for height in check_heights:
		var start = global_position + Vector3(0, height, 0)
		var end = start + direction.normalized() * distance
		if _raycast_check(start, end):
			return false
	
	return true

func _find_best_direction(target_direction: Vector3) -> Vector3:
	"""Smart pathfinding that finds the best direction around obstacles"""
	target_direction.y = 0
	target_direction = target_direction.normalized()
	
	# Check if direct path is clear
	if _check_direction_clear(target_direction):
		wall_follow_mode = 0  # Not following a wall
		return target_direction
	
	# Direct path blocked - try multiple angles
	var angles_to_try = [
		15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 90, -90, 
		105, -105, 120, -120, 135, -135, 150, -150
	]
	
	var best_direction = Vector3.ZERO
	var best_score = -999.0
	
	for angle_deg in angles_to_try:
		var angle_rad = deg_to_rad(angle_deg)
		var test_direction = target_direction.rotated(Vector3.UP, angle_rad)
		
		# Check if this direction is clear
		if _check_direction_clear(test_direction, SIDE_RAYCAST_DISTANCE):
			# Score based on how close to target direction
			var dot = test_direction.dot(target_direction)
			var score = dot
			
			# Prefer continuing in wall follow direction if we were following a wall
			if wall_follow_mode != 0:
				var follow_bonus = sign(angle_deg) == wall_follow_mode
				if follow_bonus:
					score += 0.3
			
			if score > best_score:
				best_score = score
				best_direction = test_direction
				# Remember which side we're going around
				if angle_deg > 0:
					wall_follow_mode = 1  # Following left
				elif angle_deg < 0:
					wall_follow_mode = -1  # Following right
	
	return best_direction

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0
	
	# Track if we're stuck
	var current_position = global_position
	var distance_moved = current_position.distance_to(last_position)
	
	if was_trying_to_move and is_on_floor():
		if distance_moved < STUCK_THRESHOLD * delta:
			stuck_timer += delta
			if stuck_timer >= STUCK_TIME_BEFORE_JUMP:
				# We're stuck, try jumping!
				velocity.y = JUMP_VELOCITY
				stuck_timer = 0.0
		else:
			stuck_timer = 0.0
	else:
		stuck_timer = 0.0
	
	last_position = current_position
	was_trying_to_move = false
	
	# Chase player if found and in range
	if player and is_instance_valid(player):
		var distance_to_player = global_position.distance_to(player.global_position)
		
		# Weeping Angel behavior - freeze if player is looking at statue
		if _is_player_looking_at_statue():
			# Player is looking - freeze completely
			velocity.x = 0
			velocity.z = 0
			_freeze_animation()
			is_moving = false
		elif distance_to_player <= DETECTION_RANGE and distance_to_player > 1.5:
			# Player NOT looking and in range - move toward player
			# Get direction to player
			var direction_to_player = (player.global_position - global_position)
			direction_to_player.y = 0
			direction_to_player = direction_to_player.normalized()
			
			# Find best direction using smart pathfinding
			var move_direction = _find_best_direction(direction_to_player)
			
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
				# If pathfinding blocked, still try to move toward player at reduced speed
				# This helps slide past corners using move_and_slide's collision response
				was_trying_to_move = true
				velocity.x = direction_to_player.x * WALK_SPEED * 0.5
				velocity.z = direction_to_player.z * WALK_SPEED * 0.5
				_set_animation("walking")
				is_moving = true
		else:
			# Player too close or out of range, stop moving
			velocity.x = 0
			velocity.z = 0
			_stop_animation()
			is_moving = false
	else:
		# No player, stop moving
		velocity.x = 0
		velocity.z = 0
		_stop_animation()
		is_moving = false
	
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
