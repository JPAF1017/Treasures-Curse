extends CharacterBody3D

const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")

# Movement constants
const WALK_SPEED = 10.0
const GRAVITY = 20.0
const DETECTION_RANGE = 50.0
const VIEW_CONE_ANGLE = 60.0
const WALK_IDLE_FRAME_TIME = 1.0 / 30.0  # Frame 1 at 30 FPS to avoid T-pose while idle
const SOUND_FRAME_1_TIME = 1.0 / 30.0   # Frame 1 at 30 FPS
const SOUND_FRAME_51_TIME = 51.0 / 30.0  # Frame 51 at 30 FPS
const BUMP_STEP_VELOCITY = 2.0
const BUMP_STEP_COOLDOWN = 0.15
const LOS_MEMORY_TIME = 10
const SENSE_RAY_HEIGHT = 0.8
const TRAIL_MEMORY_TIME = 5.0
const TRAIL_SAMPLE_INTERVAL = 0.2
const TRAIL_POINT_SPACING = 0.7
const TRAIL_REACHED_DISTANCE = 0.8
const TRAIL_MAX_POINTS = 28
const LOS_LOSS_CHASE_TIME = 5.0
const MEMORY_LOG_INTERVAL = 0.25
const ATTACK_DAMAGE = 20.0
const ATTACK_INTERVAL = 2.0
@export var debug_memory_logs: bool = false

# References
var player: CharacterBody3D = null
var player_camera: Camera3D = null
var animation_player: AnimationPlayer = null
var detection_area: Area3D = null
var attack_area: Area3D = null
var skeleton: Skeleton3D = null
var head_bone_id: int = -1
var is_moving = false

# Stuck detection and pathfinding
var was_trying_to_move: bool = false
var preferred_direction: Vector3 = Vector3.ZERO  # Remember which way we're trying to go
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right
var bump_step_timer: float = 0.0
var los_lost_timer: float = 0.0
var last_visible_player_position: Vector3 = Vector3.ZERO
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var attack_timer: float = 0.0

# Bone sounds
var bones_sounds: Array[AudioStreamPlayer3D] = []
var sound_triggered_frame1: bool = false
var sound_triggered_frame51: bool = false
var prev_anim_position: float = 0.0

func _ready():
	_setup_bone_sounds()
	call_deferred("_setup_player_reference")
	call_deferred("_setup_animation_player")
	call_deferred("_setup_detection_area")
	call_deferred("_setup_skeleton")
	attack_area = get_node_or_null("Attack")
	
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

func _setup_bone_sounds() -> void:
	for i in range(1, 6):
		var snd := get_node_or_null("Sounds/BonesSound%d" % i) as AudioStreamPlayer3D
		if snd:
			bones_sounds.append(snd)


func _update_bone_sounds() -> void:
	if not animation_player or not is_moving:
		sound_triggered_frame1 = false
		sound_triggered_frame51 = false
		return
	if animation_player.current_animation != "walking" or animation_player.speed_scale == 0.0:
		sound_triggered_frame1 = false
		sound_triggered_frame51 = false
		return

	var pos: float = animation_player.current_animation_position

	# Detect animation loop (position wrapped back to start)
	if pos < prev_anim_position - 0.1:
		sound_triggered_frame1 = false
		sound_triggered_frame51 = false

	if pos >= SOUND_FRAME_1_TIME and not sound_triggered_frame1:
		_play_random_bones_sound()
		sound_triggered_frame1 = true

	if pos >= SOUND_FRAME_51_TIME and not sound_triggered_frame51:
		_play_random_bones_sound()
		sound_triggered_frame51 = true

	prev_anim_position = pos


func _play_random_bones_sound() -> void:
	if bones_sounds.is_empty():
		return
	bones_sounds[randi() % bones_sounds.size()].play()


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
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)

	# Apply gravity
	EnemyLocomotion.apply_gravity(self, GRAVITY, delta)

	was_trying_to_move = false
	
	# Chase player if found and in range
	if player and is_instance_valid(player):
		var distance_to_player = global_position.distance_to(player.global_position)
		var space_state := get_world_3d().direct_space_state
		var has_line_of_sight = NavigationUtils.has_line_of_sight_to(self, player.global_position + Vector3(0, 1.0, 0), space_state, [self, player])

		# Track LOS transitions
		if not los_state_initialized:
			previous_has_line_of_sight = has_line_of_sight
			los_state_initialized = true
		if has_line_of_sight and not previous_has_line_of_sight:
			los_lost_timer = 0.0
		elif not has_line_of_sight and previous_has_line_of_sight:
			los_lost_timer = LOS_LOSS_CHASE_TIME
			memorized_target_trail.clear()
			NavigationUtils.append_trail_point(memorized_target_trail, last_visible_player_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
		previous_has_line_of_sight = has_line_of_sight

		if has_line_of_sight:
			los_lost_timer = 0.0
			last_visible_player_position = player.global_position
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
		elif _is_player_in_attack_area():
			# Player is within attack range - stop and wait to strike
			velocity.x = 0
			velocity.z = 0
			_set_idle_pose()
			is_moving = false
		elif distance_to_player <= DETECTION_RANGE and distance_to_player > 1.5:
			# Player NOT looking and in range - move toward player
			if has_line_of_sight:
				# Direct chase toward visible player
				var pursuit_target = player.global_position
				var to_player = pursuit_target - global_position
				to_player.y = 0
				if to_player.length() > 0.3:
					var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
					var move_dir: Vector3 = path_result["direction"]
					wall_follow_mode = path_result["wall_follow_mode"]
					if move_dir.length_squared() > 0.001:
						velocity.x = move_dir.x * WALK_SPEED
						velocity.z = move_dir.z * WALK_SPEED
						was_trying_to_move = true
						_set_animation("walking")
						is_moving = true
						var target_rotation = atan2(move_dir.x, move_dir.z)
						rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
					else:
						var chase_dir := to_player.normalized()
						velocity.x = chase_dir.x * WALK_SPEED * 0.4
						velocity.z = chase_dir.z * WALK_SPEED * 0.4
						was_trying_to_move = true
						_set_animation("walking")
						is_moving = true
						var target_rotation = atan2(chase_dir.x, chase_dir.z)
						rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
				else:
					velocity.x = 0
					velocity.z = 0
					_set_idle_pose()
					is_moving = false
			else:
				# No LOS - follow trail to last known position
				los_lost_timer -= delta
				if los_lost_timer <= 0.0:
					velocity.x = 0
					velocity.z = 0
					_set_idle_pose()
					is_moving = false
					wall_follow_mode = 0
				else:
					var pursuit_target := last_visible_player_position
					var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
					if bool(trail_result.get("has_target", false)):
						pursuit_target = trail_result["target"]

					var to_target := pursuit_target - global_position
					to_target.y = 0
					if to_target.length() <= 0.6:
						velocity.x = 0
						velocity.z = 0
						_set_idle_pose()
						is_moving = false
						wall_follow_mode = 0
					else:
						var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
						var move_dir: Vector3 = path_result["direction"]
						wall_follow_mode = path_result["wall_follow_mode"]
						if move_dir.length_squared() > 0.001:
							velocity.x = move_dir.x * WALK_SPEED
							velocity.z = move_dir.z * WALK_SPEED
							was_trying_to_move = true
							_set_animation("walking")
							is_moving = true
							var target_rotation = atan2(move_dir.x, move_dir.z)
							rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
						else:
							var chase_dir := to_target.normalized()
							velocity.x = chase_dir.x * WALK_SPEED * 0.4
							velocity.z = chase_dir.z * WALK_SPEED * 0.4
							was_trying_to_move = true
							_set_animation("walking")
							is_moving = true
							var target_rotation = atan2(chase_dir.x, chase_dir.z)
							rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
		else:
			# Player too close or out of range with no memory, stop moving
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
	bump_step_timer = EnemyLocomotion.try_bump_step(self, bump_step_timer, BUMP_STEP_VELOCITY, BUMP_STEP_COOLDOWN)

	_process_attack(delta)

	move_and_slide()

func _process(_delta):
	# Head tracking runs in _process AFTER animations update
	# This ensures it's applied on top of animation data
	_update_head_tracking()
	_update_bone_sounds()


func _is_player_in_attack_area() -> bool:
	if attack_area == null or player == null:
		return false
	return attack_area.get_overlapping_bodies().has(player)


func _process_attack(delta: float) -> void:
	attack_timer = max(attack_timer - delta, 0.0)
	if attack_timer > 0.0:
		return
	if attack_area == null or _is_player_looking_at_statue():
		return
	for body in attack_area.get_overlapping_bodies():
		if body == player and is_instance_valid(player):
			_apply_damage_to_player(player, ATTACK_DAMAGE)
			_play_random_bones_sound()
			attack_timer = ATTACK_INTERVAL
			break


func _apply_damage_to_player(target: CharacterBody3D, damage: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_damage"):
		target.call("apply_damage", damage)
		return
	if target.has_method("take_damage"):
		target.call("take_damage", damage)
		return
	var current_health = target.get("health")
	if current_health == null:
		return
	var next_health := maxf(float(current_health) - damage, 0.0)
	target.set("health", next_health)
	if target.has_method("_update_health_ui"):
		target.call("_update_health_ui")

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
	print("[StatueMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d los_lost=%.2f" % [
		source,
		str(has_los),
		_format_vec3(player_pos),
		_format_vec3(last_seen_pos),
		_format_vec3(trail_target),
		_format_vec3(pursuit_target),
		memorized_target_trail.size(),
		los_lost_timer,
	])
