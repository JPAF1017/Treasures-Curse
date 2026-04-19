extends CharacterBody3D

const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")
const EnemyDeathLinger := preload("res://scripts/npc/EnemyDeathLingerComponent.gd")
const EnemyKnockback := preload("res://scripts/npc/NPCKnockbackComponent.gd")

const HEALTH_MAX = 20.0
const GRAVITY = 20.0
const SPEED = 5.0
const LUNGE_SPEED = 12.0  # Speed when lunging
const STOP_DISTANCE = 2.0  # Stop this close to the player
const LUNGE_COOLDOWN = 1.0  # Cooldown between lunges in seconds
const BACKUP_INITIATE_COOLDOWN = 0  # Cooldown before starting backup/windup again
const BACKUP_TIME = 2.0  # How long to walk backwards (seconds)
const BACKUP_SPEED = 3.0  # Speed when walking backwards
const COOLDOWN_RETREAT_SPEED = 3.2
const CHARGE_TIME = 0.6  # How long to run forward before lunging (seconds) — shorter to simulate same distance at higher speed
const CHARGE_SPEED = 10.0  # Speed when running forward to lunge
const LUNGE_DURATION = 0.5  # Maximum duration of a lunge in seconds
const LUNGE_DECEL_TIME = 0.75  # Time to decelerate after lunge ends (seconds)
const LUNGE_DAMAGE = 10.0
const LUNGE_KNOCKBACK_STRENGTH = 15.0
const CIRCLE_RADIUS = 3.0  # Radius of the circle to walk in when idle
const CIRCLE_SPEED = 1.0  # Speed of rotation around the circle (radians per second)
const BUMP_STEP_VELOCITY = 2.0
const BUMP_STEP_COOLDOWN = 0.15
const PATH_RAYCAST_DISTANCE = 3.5
const SIDE_PROBE_DISTANCE = 2.5
const SENSE_RAY_HEIGHT = 0.8
const LOS_MEMORY_TIME = 10.0
const TRAIL_MEMORY_TIME = 5.0
const TRAIL_SAMPLE_INTERVAL = 0.2
const TRAIL_POINT_SPACING = 0.7
const TRAIL_REACHED_DISTANCE = 0.8
const TRAIL_MAX_POINTS = 28
const LOS_LOSS_CHASE_TIME = 5.0
const MEMORY_LOG_INTERVAL = 0.25
const DEBUG_LOG_INTERVAL = 0.35
const CROUCH_DETECTION_RAY_LENGTH = 8.0
const RUN_TURN_SPEED_MULTIPLIER = 0.55
const HIT_REACTION_DURATION = 0.3
const DEATH_LINGER_TIME = 5.0
const STUN_WALK_ANIMATION_SPEED_SCALE = 0.45

@export var debug_navigation_logs: bool = false
@export var facing_offset_degrees: float = 0

var health: float = HEALTH_MAX
var player: CharacterBody3D = null
var is_player_in_range: bool = false
var is_player_in_lunge_range: bool = false
var attack_area: Area3D = null
var animation_player: AnimationPlayer = null
var lunge_timer: float = 0.0  # Time since last lunge
var backup_initiate_cooldown_timer: float = 0.0
var can_lunge: bool = true  # Whether the charger can lunge
var is_lunging: bool = false  # Currently performing a lunge
var is_backing_up: bool = false  # Phase 1: walking backwards
var is_charging: bool = false  # Phase 2: running forward toward memorized position
var backup_timer: float = 0.0  # Time spent backing up
var charge_timer: float = 0.0  # Time spent charging forward
var memorized_direction: Vector3 = Vector3.ZERO  # Direction toward player when windup started
var charge_direction: Vector3 = Vector3.ZERO  # Locked movement direction while in charge phase
var lunge_direction: Vector3 = Vector3.ZERO  # Direction locked in when lunge starts
var lunge_elapsed: float = 0.0  # Time elapsed during current lunge
var has_damaged_during_lunge: bool = false
var is_decelerating: bool = false  # Currently sliding to a stop after lunge
var decel_velocity: Vector3 = Vector3.ZERO  # Velocity at start of deceleration
var decel_timer: float = 0.0  # Time spent decelerating
var circle_angle: float = 0.0  # Current angle in the circle (in radians)
var circle_center: Vector3 = Vector3.ZERO  # Center point of the circle
var last_known_player_position: Vector3 = Vector3.ZERO  # Last known player position for lunging
var bump_step_timer: float = 0.0
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right
var los_lost_timer: float = 0.0
var last_visible_player_position: Vector3 = Vector3.ZERO
var debug_log_timer: float = 0.0
var debug_los_initialized: bool = false
var debug_previous_los: bool = false
var space_state: PhysicsDirectSpaceState3D = null
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var cooldown_spacing_mode: String = ""
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var is_dead: bool = false
var hit_reaction_timer: float = 0.0
var is_stunned: bool = false
var stun_timer: float = 0.0
var knockback_component = EnemyKnockback.new()
var stun_walk_visual_active: bool = false

# Slope alignment
var ground_normal: Vector3 = Vector3.UP  # Smoothed ground normal
var original_dog_transform: Transform3D  # Dog's original local transform
var original_collision_transform: Transform3D  # CollisionShape3D's original local transform
const SLOPE_ALIGN_SPEED = 10.0  # How fast to tilt toward the slope

func _ready():
	top_level = true
	# Configure slope handling
	floor_stop_on_slope = true
	floor_snap_length = 0.7
	space_state = get_world_3d().direct_space_state
	backup_initiate_cooldown_timer = BACKUP_INITIATE_COOLDOWN
	
	# Connect the detector signals
	$Detector.body_entered.connect(_on_detector_body_entered)
	$Detector.body_exited.connect(_on_detector_body_exited)
	
	# Connect the lunge area signals
	$Lunge.body_entered.connect(_on_lunge_body_entered)
	$Lunge.body_exited.connect(_on_lunge_body_exited)
	attack_area = get_node_or_null("AttackArea") as Area3D
	
	# Initialize circle center to starting position
	circle_center = global_position
	
	# Store original child transforms for slope tilting
	original_dog_transform = $Dog.transform
	original_collision_transform = $CollisionShape3D.transform
	
	# Get the AnimationPlayer from the dog node
	animation_player = $Dog/AnimationPlayer
	if animation_player == null:
		push_warning("AnimationPlayer not found in Dog node")
	else:
		# Print available animations for debugging
		print("Available animations in dog model:")
		var animations = animation_player.get_animation_list()
		for anim in animations:
			print("  - ", anim)
		
		# Connect to animation finished signal to know when lunge ends
		animation_player.animation_finished.connect(_on_animation_finished)
	
	# Enable shadows on all mesh instances in the dog model
	_enable_shadows($Dog)

func _on_detector_body_entered(body):
	if body.is_in_group("player") and _can_detect_crouching_player(body):
		player = body
		los_state_initialized = false
		los_lost_timer = 0.0
		is_player_in_range = true
		trail_sample_timer = 0.0
		memorized_target_trail.clear()
		NavigationUtils.append_trail_point(memorized_target_trail, player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
		print("Player entered charger's detection range")

func _on_detector_body_exited(body):
	if body.is_in_group("player"):
		is_player_in_range = false
		los_state_initialized = false
		los_lost_timer = LOS_LOSS_CHASE_TIME
		print("Player exited charger's detection range")

func _on_lunge_body_entered(body):
	if body.is_in_group("player") and _can_detect_crouching_player(body):
		is_player_in_lunge_range = true
		print("Player entered lunge range!")

func _on_lunge_body_exited(body):
	if body.is_in_group("player"):
		is_player_in_lunge_range = false
		print("Player exited lunge range")

func _on_animation_finished(anim_name: String):
	if anim_name == "lunge":
		_end_lunge()
		print("Lunge animation finished")

func _start_lunge_windup():
	"""Start the windup — memorize player direction, then walk backwards"""
	can_lunge = false
	
	# Memorize the player's position and direction
	if player and is_instance_valid(player):
		last_known_player_position = player.global_position
		var dir_to_player = (player.global_position - global_position)
		dir_to_player.y = 0
		if dir_to_player.length() > 0.1:
			memorized_direction = dir_to_player.normalized()
		else:
			memorized_direction = -global_transform.basis.z  # fallback: forward
	
	# Start backing up
	is_backing_up = true
	backup_timer = 0.0
	
	print("Windup started! Charger backing up from memorized position...")
	
	# Play walk animation in reverse
	if animation_player:
		if animation_player.has_animation("walk"):
			animation_player.play_backwards("walk")
			print("Playing walk animation in reverse")

func _start_charge():
	"""Phase 2: Run forward for a shorter time to simulate same distance at higher speed"""
	is_backing_up = false
	is_charging = true
	charge_timer = 0.0
	charge_direction = memorized_direction
	if charge_direction.length_squared() <= 0.001:
		charge_direction = -global_transform.basis.z
	else:
		charge_direction = charge_direction.normalized()
	rotation.y = _yaw_with_facing_offset(charge_direction)
	
	print("Charging forward toward memorized position!")
	
	# Play run animation (or fast walk) forward
	if animation_player:
		if animation_player.has_animation("run"):
			animation_player.play("run")
			animation_player.speed_scale = 1.0
		elif animation_player.has_animation("walk"):
			animation_player.play("walk")
			animation_player.speed_scale = 2.0

func _end_lunge():
	"""End the lunge and begin decelerating"""
	is_lunging = false
	lunge_elapsed = 0.0
	has_damaged_during_lunge = false
	backup_initiate_cooldown_timer = BACKUP_INITIATE_COOLDOWN
	# Start deceleration phase with current horizontal velocity
	is_decelerating = true
	decel_timer = 0.0
	decel_velocity = Vector3(velocity.x, 0, velocity.z)
	print("Lunge ended, decelerating...")

func _execute_lunge(direction: Vector3):
	"""Execute the actual lunge attack"""
	is_backing_up = false
	is_charging = false
	is_lunging = true
	has_damaged_during_lunge = false
	lunge_timer = 0.0
	lunge_elapsed = 0.0
	lunge_direction = direction
	
	# Snap rotation to face the lunge direction immediately
	rotation.y = _yaw_with_facing_offset(lunge_direction)
	print("Executing lunge! Direction locked: ", lunge_direction)
	
	# Play lunge animation
	if animation_player:
		if animation_player.has_animation("lunge"):
			animation_player.play("lunge")
			animation_player.speed_scale = 1.0
			print("Playing lunge animation")
		elif animation_player.has_animation("walk"):
			animation_player.play("walk")
			animation_player.speed_scale = 2.0
			print("No lunge animation, using walk at 2x speed")

func _physics_process(delta):
	if is_dead:
		return

	bump_step_timer = max(bump_step_timer - delta, 0.0)
	stun_timer = max(stun_timer - delta, 0.0)
	is_stunned = stun_timer > 0.0
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	debug_log_timer = max(debug_log_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)
	backup_initiate_cooldown_timer = max(backup_initiate_cooldown_timer - delta, 0.0)
	_refresh_player_detection()

	# Apply gravity
	EnemyLocomotion.apply_gravity(self, GRAVITY, delta)

	if knockback_component.is_active():
		knockback_component.update(delta)
		move_and_slide()
		_align_to_slope(delta)
		return

	hit_reaction_timer = max(hit_reaction_timer - delta, 0.0)
	if hit_reaction_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_hurt_animation()
		move_and_slide()
		_align_to_slope(delta)
		return

	if is_stunned:
		is_backing_up = false
		is_charging = false
		is_lunging = false
		is_decelerating = false
		has_damaged_during_lunge = false
		velocity.x = 0.0
		velocity.z = 0.0
		_play_stunned_walk_animation()
		move_and_slide()
		_align_to_slope(delta)
		return
	elif stun_walk_visual_active:
		_restore_walk_animation_speed()
	
	# Update lunge cooldown timer
	if not can_lunge and not is_backing_up and not is_charging:
		lunge_timer += delta
		if lunge_timer >= LUNGE_COOLDOWN:
			can_lunge = true
			lunge_timer = 0.0
			print("Lunge ready!")
	
	# Update lunge duration and end lunge if time exceeded
	if is_lunging:
		lunge_elapsed += delta
		_try_apply_lunge_damage()
		if lunge_elapsed >= LUNGE_DURATION:
			_end_lunge()
	
	# Handle post-lunge deceleration (inertia)
	if is_decelerating:
		decel_timer += delta
		var t = clamp(decel_timer / LUNGE_DECEL_TIME, 0.0, 1.0)
		velocity.x = decel_velocity.x * (1.0 - t)
		velocity.z = decel_velocity.z * (1.0 - t)
		if t >= 1.0:
			is_decelerating = false
			velocity.x = 0
			velocity.z = 0
			print("Deceleration complete")
	
	# Handle backing up (Phase 1 of windup)
	if is_backing_up:
		backup_timer += delta
		
		# Keep tracking the player direction if still valid
		if player and is_instance_valid(player):
			var dir_to_player = (player.global_position - global_position)
			dir_to_player.y = 0
			if dir_to_player.length() > 0.1:
				memorized_direction = dir_to_player.normalized()
		
		# Walk backwards (away from current player direction)
		var away_dir = -memorized_direction
		
		# Face the player while walking backwards
		rotation.y = lerp_angle(rotation.y, _yaw_with_facing_offset(memorized_direction), delta * 8.0)
		
		# Move backwards
		velocity.x = away_dir.x * BACKUP_SPEED
		velocity.z = away_dir.z * BACKUP_SPEED
		
		# Keep reversed walk animation playing
		if animation_player:
			if animation_player.has_animation("walk"):
				if not animation_player.is_playing() or animation_player.current_animation != "walk":
					animation_player.play_backwards("walk")
		
		# Check if backup time is up
		if backup_timer >= BACKUP_TIME:
			_start_charge()
	
	# Handle charging forward (Phase 2 of windup)
	if is_charging:
		charge_timer += delta

		# Keep the locked direction for the full charge phase.
		rotation.y = _yaw_with_facing_offset(charge_direction)
		
		# Run forward in the locked charge direction.
		velocity.x = charge_direction.x * CHARGE_SPEED
		velocity.z = charge_direction.z * CHARGE_SPEED
		
		# Keep run animation playing
		if animation_player:
			if animation_player.has_animation("run"):
				if not animation_player.is_playing() or animation_player.current_animation != "run":
					animation_player.play("run")
			elif animation_player.has_animation("walk"):
				if not animation_player.is_playing() or animation_player.current_animation != "walk":
					animation_player.play("walk")
				animation_player.speed_scale = 2.0
		
		# Check if charge time is up — lunge!
		if charge_timer >= CHARGE_TIME:
			is_charging = false
			_execute_lunge(charge_direction)
	
	# Follow the player if in range
	if is_player_in_range and player and is_instance_valid(player):
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

		if not debug_los_initialized or has_line_of_sight != debug_previous_los:
			_debug_nav_log("LOS changed -> %s" % [str(has_line_of_sight)], true)
			debug_los_initialized = true
			debug_previous_los = has_line_of_sight

		if has_line_of_sight:
			los_lost_timer = 0.0
			last_visible_player_position = player.global_position
			if trail_sample_timer <= 0.0:
				NavigationUtils.append_trail_point(memorized_target_trail, player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
				trail_sample_timer = TRAIL_SAMPLE_INTERVAL
			# Track last known player position for lunge logic
			last_known_player_position = player.global_position

		var pursuit_target = player.global_position
		if not has_line_of_sight:
			# No LOS - follow trail to last known position
			los_lost_timer -= delta
			if los_lost_timer <= 0.0:
				pursuit_target = global_position
				wall_follow_mode = 0
				_debug_nav_log("Memory expired without LOS, stopping chase", true)
			else:
				pursuit_target = last_visible_player_position
				var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
				if bool(trail_result.get("has_target", false)):
					pursuit_target = trail_result["target"]
		
		# Calculate direction to player (horizontal only)
		var direction_to_player = (pursuit_target - global_position)
		direction_to_player.y = 0  # Ignore vertical difference
		var distance_to_player = direction_to_player.length()  # Horizontal distance only
		direction_to_player = direction_to_player.normalized()
		
		# Only rotate if not lunging, not decelerating, not backing up, not charging
		if not is_lunging and not is_decelerating and not is_backing_up and not is_charging:
			# Calculate target rotation
			if direction_to_player.length() > 0.1:
				# Smoothly rotate to face the player
				rotation.y = lerp_angle(rotation.y, _yaw_with_facing_offset(direction_to_player), delta * _get_turn_speed(5.0))
		
		# Move toward player if not too close
		if _update_cooldown_chase_movement(direction_to_player, distance_to_player, delta):
			pass
		elif distance_to_player > STOP_DISTANCE:
			# Check if decelerating (let inertia handle movement)
			if is_decelerating:
				pass  # Velocity is handled in deceleration section above
			# Check if backing up or charging (handled above)
			elif is_backing_up or is_charging:
				pass  # Movement handled in backup/charge sections
			# Check if currently lunging (continue lunge until animation ends)
			elif is_lunging:
				# Continue lunging in the locked direction at high speed
				velocity.x = lunge_direction.x * LUNGE_SPEED
				velocity.z = lunge_direction.z * LUNGE_SPEED
			# Check if player is in lunge range and lunge is ready (start wind-up)
			elif is_player_in_lunge_range and can_lunge and has_line_of_sight and backup_initiate_cooldown_timer <= 0.0:
				# Start wind-up phase
				_start_lunge_windup()
			else:
				# Regular walking speed (outside lunge range)
				var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
				var path_direction: Vector3 = path_result["direction"]
				wall_follow_mode = path_result["wall_follow_mode"]
				if path_direction.length_squared() > 0.001:
					_debug_nav_log("Path dir chosen | dist %.2f | wall_follow %d" % [distance_to_player, wall_follow_mode])
					velocity.x = path_direction.x * SPEED
					velocity.z = path_direction.z * SPEED
					rotation.y = lerp_angle(rotation.y, _yaw_with_facing_offset(path_direction), delta * _get_turn_speed(5.0))
				else:
					_debug_nav_log("No path dir | LOS %s | on_wall %s | slides %d | dist %.2f" % [str(has_line_of_sight), str(is_on_wall()), get_slide_collision_count(), distance_to_player], true)
					velocity.x = direction_to_player.x * SPEED * 0.4
					velocity.z = direction_to_player.z * SPEED * 0.4
				
				# Play walk animation at normal speed
				if animation_player:
					if animation_player.has_animation("walk"):
						if not animation_player.is_playing() or animation_player.current_animation != "walk":
							animation_player.play("walk")
						animation_player.speed_scale = 1.0  # Ensure normal speed
					else:
						print("WARNING: Walk animation not found!")
		else:
			# Stop moving if close enough
			velocity.x = 0
			velocity.z = 0
			
			# Cancel backup if player gets too close
			if is_backing_up:
				is_backing_up = false
				can_lunge = true
				backup_initiate_cooldown_timer = BACKUP_INITIATE_COOLDOWN
				print("Backup cancelled - player too close!")
			
			# Stop animation
			if animation_player and animation_player.is_playing():
				animation_player.stop()
	else:
		# Not in range — but if backing up, charging, lunging, or decelerating, let it finish
		if is_backing_up or is_charging:
			pass  # Movement handled in backup/charge sections above
		elif is_lunging:
			# Continue lunging in locked direction
			velocity.x = lunge_direction.x * LUNGE_SPEED
			velocity.z = lunge_direction.z * LUNGE_SPEED
		elif is_decelerating:
			pass  # Deceleration is handled above
		elif los_lost_timer > 0.0:
			# Keep moving along memorized target path when LOS is lost.
			los_lost_timer -= delta
			if los_lost_timer <= 0.0:
				velocity.x = 0
				velocity.z = 0
			else:
				var pursuit := last_visible_player_position
				var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
				if bool(trail_result.get("has_target", false)):
					pursuit = trail_result["target"]

				var to_memory = pursuit - global_position
				to_memory.y = 0
				if to_memory.length() > 0.4:
					var memory_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit, space_state, wall_follow_mode)
					var memory_dir: Vector3 = memory_result["direction"]
					wall_follow_mode = memory_result["wall_follow_mode"]
					if memory_dir.length_squared() > 0.001:
						_debug_nav_log("Memory chase | remaining %.2f" % [los_lost_timer])
						velocity.x = memory_dir.x * SPEED
						velocity.z = memory_dir.z * SPEED
						var memory_rot = _yaw_with_facing_offset(memory_dir)
						rotation.y = lerp_angle(rotation.y, memory_rot, delta * _get_turn_speed(5.0))
					else:
						_debug_nav_log("Memory blocked | remaining %.2f" % [los_lost_timer], true)
						velocity.x = 0
						velocity.z = 0
				else:
					velocity.x = 0
					velocity.z = 0
		else:
			# Idle — walk in circles
			# Update circle angle
			circle_angle += CIRCLE_SPEED * delta
			if circle_angle > TAU:  # TAU is 2*PI in Godot
				circle_angle -= TAU
			
			# Calculate target position on circle
			var target_x = circle_center.x + cos(circle_angle) * CIRCLE_RADIUS
			var target_z = circle_center.z + sin(circle_angle) * CIRCLE_RADIUS
			var target_position = Vector3(target_x, global_position.y, target_z)
			
			# Calculate direction to next point on circle
			var direction = (target_position - global_position)
			direction.y = 0
			
			if direction.length() > 0.1:
				direction = direction.normalized()
				
				# Rotate to face the direction of movement
				rotation.y = lerp_angle(rotation.y, _yaw_with_facing_offset(direction), delta * 5.0)
				
				# Move along the circle
				velocity.x = direction.x * SPEED * 0.5  # Move at half speed when circling
				velocity.z = direction.z * SPEED * 0.5
			else:
				velocity.x = 0
				velocity.z = 0
			
			# Play walk animation while circling
			if animation_player:
				if animation_player.has_animation("walk"):
					if not animation_player.is_playing() or animation_player.current_animation != "walk":
						animation_player.play("walk")
					animation_player.speed_scale = 0.5  # Slower animation for slower movement

	# Step up tiny bumps while moving instead of getting stuck on their edges.
	bump_step_timer = EnemyLocomotion.try_bump_step(self, bump_step_timer, BUMP_STEP_VELOCITY, BUMP_STEP_COOLDOWN)
	
	# Apply physics movement
	move_and_slide()
	
	# Align visuals and collision to slope
	_align_to_slope(delta)

func apply_damage(amount: float) -> void:
	if is_dead:
		return
	if amount <= 0.0:
		return

	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_die()
		return

	_begin_hit_reaction()

func take_damage(amount: float) -> void:
	apply_damage(amount)

func apply_stun_state(duration: float) -> void:
	if is_dead:
		return
	if duration <= 0.0:
		return

	stun_timer = max(stun_timer, duration)
	is_stunned = true
	is_backing_up = false
	is_charging = false
	is_lunging = false
	is_decelerating = false
	has_damaged_during_lunge = false
	player = null
	is_player_in_range = false
	is_player_in_lunge_range = false

func apply_knockback(direction: Vector3, strength: float) -> void:
	if is_dead:
		return
	knockback_component.begin_knockback(self, direction, strength, 0.35, 0.18)

func _begin_hit_reaction() -> void:
	hit_reaction_timer = max(hit_reaction_timer, _get_hurt_reaction_duration())
	# Hurt should take priority over ongoing charge/lunge logic.
	is_backing_up = false
	is_charging = false
	is_lunging = false
	is_decelerating = false
	has_damaged_during_lunge = false
	velocity.x = 0.0
	velocity.z = 0.0
	_play_hurt_animation()

func _get_hurt_reaction_duration() -> float:
	if animation_player == null:
		return HIT_REACTION_DURATION

	var duration := HIT_REACTION_DURATION
	var hurt_candidates: Array[StringName] = [&"hurt", &"hit", &"damage"]
	for anim_name in hurt_candidates:
		if animation_player.has_animation(anim_name):
			var anim := animation_player.get_animation(anim_name)
			if anim:
				duration = max(duration, anim.length)
			break

	return duration

func _play_hurt_animation() -> void:
	if animation_player == null:
		return

	var hurt_candidates: Array[StringName] = [&"hurt", &"hit", &"damage"]
	for anim_name in hurt_candidates:
		if animation_player.has_animation(anim_name):
			if animation_player.current_animation != anim_name or not animation_player.is_playing():
				animation_player.speed_scale = 1.0
				animation_player.play(anim_name)
				animation_player.seek(0.0, true)
			return

func _play_stunned_walk_animation() -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation("walk"):
		return

	var walk_animation := animation_player.get_animation("walk")
	if walk_animation and walk_animation.loop_mode == Animation.LOOP_NONE:
		walk_animation.loop_mode = Animation.LOOP_LINEAR

	if animation_player.current_animation != "walk":
		animation_player.play("walk")
	elif not animation_player.is_playing():
		animation_player.play("walk")

	animation_player.speed_scale = STUN_WALK_ANIMATION_SPEED_SCALE
	stun_walk_visual_active = true

func _restore_walk_animation_speed() -> void:
	stun_walk_visual_active = false
	if animation_player:
		animation_player.speed_scale = 1.0

func _die() -> void:
	if is_dead:
		return

	is_dead = true
	health = 0.0
	hit_reaction_timer = 0.0
	is_stunned = false
	stun_timer = 0.0
	_restore_walk_animation_speed()
	is_player_in_range = false
	is_player_in_lunge_range = false
	can_lunge = false
	is_lunging = false
	is_backing_up = false
	is_charging = false
	is_decelerating = false
	has_damaged_during_lunge = false
	velocity = Vector3.ZERO

	await EnemyDeathLinger.run_death_linger(
		self,
		animation_player,
		DEATH_LINGER_TIME,
		[$Detector, $Lunge, attack_area],
		[&"death", &"die"]
	)

func _debug_nav_log(message: String, force: bool = false) -> void:
	if not debug_navigation_logs:
		return
	if not force and debug_log_timer > 0.0:
		return
	print("[ChargerNav] ", message)
	debug_log_timer = DEBUG_LOG_INTERVAL

func _format_vec3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _log_memory_state(
	has_los: bool,
	source: String,
	player_pos: Vector3,
	last_seen_pos: Vector3,
	trail_target: Vector3,
	pursuit_target: Vector3
) -> void:
	if not debug_navigation_logs:
		return
	if memory_log_timer > 0.0:
		return
	memory_log_timer = MEMORY_LOG_INTERVAL
	print("[ChargerMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d los_lost=%.2f" % [
		source,
		str(has_los),
		_format_vec3(player_pos),
		_format_vec3(last_seen_pos),
		_format_vec3(trail_target),
		_format_vec3(pursuit_target),
		memorized_target_trail.size(),
		los_lost_timer,
	])

func _refresh_player_detection() -> void:
	if player != null and is_instance_valid(player) and _is_crouched_player_hidden(player):
		player = null
		is_player_in_range = false
		is_player_in_lunge_range = false
		los_state_initialized = false
		previous_has_line_of_sight = false

	if player != null and is_instance_valid(player):
		is_player_in_range = _is_body_overlapping_area($Detector, player)
		is_player_in_lunge_range = _is_body_overlapping_area($Lunge, player)
		return

	var detectable_player := _find_detectable_player_in_area($Detector)
	if detectable_player:
		player = detectable_player
		is_player_in_range = true
		is_player_in_lunge_range = _is_body_overlapping_area($Lunge, player)
		los_state_initialized = false
		previous_has_line_of_sight = false
		los_lost_timer = 0.0

func _find_detectable_player_in_area(area: Area3D) -> CharacterBody3D:
	if area == null:
		return null

	for body in area.get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("player") and _can_detect_crouching_player(body):
			return body

	return null

func _can_detect_crouching_player(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not body.is_in_group("player"):
		return false
	if not _is_player_crouching(body):
		return true
	return _is_player_in_front_by_raycast(body)

func _is_player_crouching(body: Node) -> bool:
	return body != null and bool(body.get("is_crouching"))

func _is_crouched_player_hidden(body: Node3D) -> bool:
	return _is_player_crouching(body) and not _is_player_in_front_by_raycast(body)

func _is_player_in_front_by_raycast(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if space_state == null:
		return false

	var origin := global_position + Vector3.UP * 1.0
	var target_position := body.global_position + Vector3.UP * 1.0
	var to_target := target_position - origin
	if to_target.length_squared() <= 0.001:
		return true

	var forward := -global_transform.basis.z
	if forward.dot(to_target.normalized()) <= 0.0:
		return false

	var ray_direction := to_target.normalized() * minf(to_target.length(), CROUCH_DETECTION_RAY_LENGTH)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray_direction)
	query.exclude = [self]
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := space_state.intersect_ray(query)
	return hit.has("collider") and hit["collider"] == body

func _is_body_overlapping_area(area: Area3D, body: Node3D) -> bool:
	if area == null or body == null or not is_instance_valid(body):
		return false
	return area.get_overlapping_bodies().has(body)

func _try_apply_lunge_damage() -> void:
	if not is_lunging or has_damaged_during_lunge:
		return

	var active_attack_area := attack_area
	if active_attack_area == null:
		active_attack_area = $Lunge
	if active_attack_area == null:
		return

	for body in active_attack_area.get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("player"):
			_apply_damage_to_player(body, LUNGE_DAMAGE)
			has_damaged_during_lunge = true
			return

func _apply_damage_to_player(target: CharacterBody3D, damage: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	if target.has_method("apply_damage"):
		target.call("apply_damage", damage)
	elif target.has_method("take_damage"):
		target.call("take_damage", damage)
	else:
		var current_health = target.get("health")
		if current_health != null:
			var next_health := maxf(float(current_health) - damage, 0.0)
			target.set("health", next_health)
			if target.has_method("_update_health_ui"):
				target.call("_update_health_ui")

	if target.has_method("apply_knockback"):
		var knock_dir := (target.global_position - global_position).normalized()
		target.call("apply_knockback", knock_dir, LUNGE_KNOCKBACK_STRENGTH)

func _update_cooldown_chase_movement(direction_to_player: Vector3, distance_to_player: float, delta: float) -> bool:
	var spacing_active := not can_lunge and not is_backing_up and not is_charging and not is_lunging and not is_decelerating
	if not spacing_active:
		if cooldown_spacing_mode != "":
			print("[ChargerCooldown] mode=NONE")
			cooldown_spacing_mode = ""
		return false

	if is_player_in_lunge_range:
		if cooldown_spacing_mode != "RETREAT":
			print("[ChargerCooldown] mode=RETREAT dist=%.2f" % [distance_to_player])
			cooldown_spacing_mode = "RETREAT"

		var away_dir := -direction_to_player
		if away_dir.length_squared() <= 0.001:
			away_dir = global_transform.basis.z
		else:
			away_dir = away_dir.normalized()

		velocity.x = away_dir.x * COOLDOWN_RETREAT_SPEED
		velocity.z = away_dir.z * COOLDOWN_RETREAT_SPEED

		# Keep facing the player while backing away to maintain pressure.
		rotation.y = lerp_angle(rotation.y, atan2(direction_to_player.x, direction_to_player.z), delta * _get_turn_speed(5.0))
		if animation_player and animation_player.has_animation("walk"):
			if not animation_player.is_playing() or animation_player.current_animation != "walk":
				animation_player.play("walk")
			animation_player.speed_scale = 1.0
		return true

	if cooldown_spacing_mode != "APPROACH":
		print("[ChargerCooldown] mode=APPROACH dist=%.2f" % [distance_to_player])
		cooldown_spacing_mode = "APPROACH"

	velocity.x = direction_to_player.x * SPEED
	velocity.z = direction_to_player.z * SPEED
	rotation.y = lerp_angle(rotation.y, atan2(direction_to_player.x, direction_to_player.z), delta * _get_turn_speed(5.0))

	if animation_player and animation_player.has_animation("walk"):
		if not animation_player.is_playing() or animation_player.current_animation != "walk":
			animation_player.play("walk")
		animation_player.speed_scale = 1.0

	return true

func _get_turn_speed(base_speed: float) -> float:
	if animation_player and animation_player.is_playing() and animation_player.current_animation == "run":
		return base_speed * RUN_TURN_SPEED_MULTIPLIER
	return base_speed

func _yaw_with_facing_offset(direction: Vector3) -> float:
	var flat_dir := Vector3(direction.x, 0.0, direction.z)
	if flat_dir.length_squared() <= 0.001:
		return rotation.y
	return atan2(flat_dir.x, flat_dir.z) + deg_to_rad(facing_offset_degrees)

func _align_to_slope(delta: float):
	"""Tilt the Dog visual and CollisionShape3D to match the ground slope."""
	var target_normal = Vector3.UP
	if is_on_floor():
		target_normal = get_floor_normal()
	
	# Smoothly interpolate toward the target ground normal
	ground_normal = ground_normal.lerp(target_normal, delta * SLOPE_ALIGN_SPEED).normalized()
	
	# Convert world-space ground normal into the CharacterBody3D's local space
	# (this removes the Y-rotation so the tilt is relative to the body)
	var local_normal = global_transform.basis.inverse() * ground_normal
	
	# Compute the rotation that takes local UP -> local_normal
	var cross = Vector3.UP.cross(local_normal)
	if cross.length() > 0.001:
		var tilt_axis = cross.normalized()
		var tilt_angle = Vector3.UP.angle_to(local_normal)
		var tilt_basis = Basis(tilt_axis, tilt_angle)
		var tilt_xform = Transform3D(tilt_basis, Vector3.ZERO)
		
		# Apply tilt on top of the original transforms
		$Dog.transform = tilt_xform * original_dog_transform
		$CollisionShape3D.transform = tilt_xform * original_collision_transform
	else:
		# No tilt needed (flat ground or perfectly upright)
		$Dog.transform = original_dog_transform
		$CollisionShape3D.transform = original_collision_transform

func _enable_shadows(node: Node):
	# Recursively enable shadow casting on all MeshInstance3D nodes
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	for child in node.get_children():
		_enable_shadows(child)
