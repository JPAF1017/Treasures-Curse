extends CharacterBody3D

const GRAVITY = 20.0
const SPEED = 5.0
const LUNGE_SPEED = 12.0  # Speed when lunging
const STOP_DISTANCE = 2.0  # Stop this close to the player
const LUNGE_COOLDOWN = 7.0  # Cooldown between lunges in seconds
const WINDUP_TIME = 1.3  # Wind-up time before lunging in seconds
const LUNGE_DURATION = 0.5  # Maximum duration of a lunge in seconds
const LUNGE_DECEL_TIME = 0.75  # Time to decelerate after lunge ends (seconds)
const CIRCLE_RADIUS = 3.0  # Radius of the circle to walk in when idle
const CIRCLE_SPEED = 1.0  # Speed of rotation around the circle (radians per second)

var player: CharacterBody3D = null
var is_player_in_range: bool = false
var is_player_in_lunge_range: bool = false
var animation_player: AnimationPlayer = null
var lunge_timer: float = 0.0  # Time since last lunge
var can_lunge: bool = true  # Whether the charger can lunge
var is_lunging: bool = false  # Currently performing a lunge
var is_winding_up: bool = false  # Currently winding up before lunge
var windup_timer: float = 0.0  # Time spent winding up
var lunge_direction: Vector3 = Vector3.ZERO  # Direction locked in when lunge starts
var lunge_elapsed: float = 0.0  # Time elapsed during current lunge
var is_decelerating: bool = false  # Currently sliding to a stop after lunge
var decel_velocity: Vector3 = Vector3.ZERO  # Velocity at start of deceleration
var decel_timer: float = 0.0  # Time spent decelerating
var circle_angle: float = 0.0  # Current angle in the circle (in radians)
var circle_center: Vector3 = Vector3.ZERO  # Center point of the circle
var last_known_player_position: Vector3 = Vector3.ZERO  # Last known player position for lunging

func _ready():
	# Configure slope handling
	floor_stop_on_slope = true
	floor_snap_length = 0.5
	
	# Connect the detector signals
	$Detector.body_entered.connect(_on_detector_body_entered)
	$Detector.body_exited.connect(_on_detector_body_exited)
	
	# Connect the lunge area signals
	$Lunge.body_entered.connect(_on_lunge_body_entered)
	$Lunge.body_exited.connect(_on_lunge_body_exited)
	
	# Initialize circle center to starting position
	circle_center = global_position
	
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
	if body.is_in_group("player"):
		player = body
		is_player_in_range = true
		print("Player entered charger's detection range")

func _on_detector_body_exited(body):
	if body.is_in_group("player"):
		is_player_in_range = false
		print("Player exited charger's detection range")

func _on_lunge_body_entered(body):
	if body.is_in_group("player"):
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
	"""Start the wind-up phase before lunging"""
	is_winding_up = true
	windup_timer = 0.0
	can_lunge = false  # Prevent multiple wind-ups
	print("Wind-up started! Charger preparing to lunge...")
	
	# Play run animation during wind-up
	if animation_player:
		if animation_player.has_animation("run"):
			animation_player.play("run")
			print("Playing run animation during wind-up")
		elif animation_player.has_animation("walk"):
			animation_player.play("walk")
			animation_player.speed_scale = 1.5
			print("No run animation, using walk at 1.5x speed")

func _end_lunge():
	"""End the lunge and begin decelerating"""
	is_lunging = false
	lunge_elapsed = 0.0
	# Start deceleration phase with current horizontal velocity
	is_decelerating = true
	decel_timer = 0.0
	decel_velocity = Vector3(velocity.x, 0, velocity.z)
	print("Lunge ended, decelerating...")

func _execute_lunge(direction: Vector3):
	"""Execute the actual lunge attack"""
	is_winding_up = false
	is_lunging = true
	lunge_timer = 0.0
	lunge_elapsed = 0.0
	lunge_direction = direction
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
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0
	
	# Update lunge cooldown timer
	if not can_lunge and not is_winding_up:
		lunge_timer += delta
		if lunge_timer >= LUNGE_COOLDOWN:
			can_lunge = true
			lunge_timer = 0.0
			print("Lunge ready!")
	
	# Update lunge duration and end lunge if time exceeded
	if is_lunging:
		lunge_elapsed += delta
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
	
	# Update wind-up timer
	if is_winding_up:
		windup_timer += delta
		
		# Keep run animation looping during wind-up
		if animation_player:
			if animation_player.has_animation("run"):
				if not animation_player.is_playing() or animation_player.current_animation != "run":
					animation_player.play("run")
			elif animation_player.has_animation("walk"):
				if not animation_player.is_playing() or animation_player.current_animation != "walk":
					animation_player.play("walk")
					animation_player.speed_scale = 1.5
		
		if windup_timer >= WINDUP_TIME:
			# Wind-up complete, execute the lunge
			var direction: Vector3
			if player and is_instance_valid(player):
				last_known_player_position = player.global_position
				direction = (player.global_position - global_position)
			else:
				# Player lost — lunge at last known position
				direction = (last_known_player_position - global_position)
			direction.y = 0
			if direction.length() > 0.1:
				direction = direction.normalized()
				_execute_lunge(direction)
			else:
				# Too close to target, cancel
				is_winding_up = false
				windup_timer = 0.0
				can_lunge = true
	
	# Follow the player if in range
	if is_player_in_range and player and is_instance_valid(player):
		# Track last known player position
		last_known_player_position = player.global_position
		
		# Calculate direction to player (horizontal only)
		var direction_to_player = (player.global_position - global_position)
		direction_to_player.y = 0  # Ignore vertical difference
		var distance_to_player = direction_to_player.length()  # Horizontal distance only
		direction_to_player = direction_to_player.normalized()
		
		# Only rotate if not lunging and not decelerating
		# But allow rotation during wind-up to track player
		if not is_lunging and not is_decelerating:
			# Calculate target rotation
			if direction_to_player.length() > 0.1:
				var target_rotation = atan2(direction_to_player.x, direction_to_player.z)
				# Smoothly rotate to face the player
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
		
		# Move toward player if not too close
		if distance_to_player > STOP_DISTANCE:
			# Check if decelerating (let inertia handle movement)
			if is_decelerating:
				pass  # Velocity is handled in deceleration section above
			# Check if winding up (stop moving but keep rotating)
			elif is_winding_up:
				# Stop movement during wind-up
				velocity.x = 0
				velocity.z = 0
			# Check if currently lunging (continue lunge until animation ends)
			elif is_lunging:
				# Continue lunging in the locked direction at high speed
				velocity.x = lunge_direction.x * LUNGE_SPEED
				velocity.z = lunge_direction.z * LUNGE_SPEED
			# Check if player is in lunge range and lunge is ready (start wind-up)
			elif is_player_in_lunge_range and can_lunge:
				# Start wind-up phase
				_start_lunge_windup()
			elif is_player_in_lunge_range and not can_lunge:
				# Player is in lunge range but lunge on cooldown — stop and wait
				velocity.x = 0
				velocity.z = 0
				# Keep walk animation playing (e.g. pacing in place)
				if animation_player:
					if animation_player.has_animation("walk"):
						if not animation_player.is_playing() or animation_player.current_animation != "walk":
							animation_player.play("walk")
						animation_player.speed_scale = 1.0
			else:
				# Regular walking speed (outside lunge range)
				velocity.x = direction_to_player.x * SPEED
				velocity.z = direction_to_player.z * SPEED
				
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
			
			# Cancel wind-up if player gets too close
			if is_winding_up:
				is_winding_up = false
				windup_timer = 0.0
				can_lunge = true  # Allow trying again
				print("Wind-up cancelled - player too close!")
			
			# Stop animation
			if animation_player and animation_player.is_playing():
				animation_player.stop()
	else:
		# Not in range — but if winding up, lunging, or decelerating, let it finish
		if is_winding_up:
			# Keep facing last known player position during wind-up
			var dir_to_last = (last_known_player_position - global_position)
			dir_to_last.y = 0
			if dir_to_last.length() > 0.1:
				var target_rotation = atan2(dir_to_last.normalized().x, dir_to_last.normalized().z)
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
			velocity.x = 0
			velocity.z = 0
		elif is_lunging:
			# Continue lunging in locked direction
			velocity.x = lunge_direction.x * LUNGE_SPEED
			velocity.z = lunge_direction.z * LUNGE_SPEED
		elif is_decelerating:
			pass  # Deceleration is handled above
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
				var target_rotation = atan2(direction.x, direction.z)
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
				
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
	
	# Apply physics movement
	move_and_slide()

func _enable_shadows(node: Node):
	# Recursively enable shadow casting on all MeshInstance3D nodes
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	for child in node.get_children():
		_enable_shadows(child)
