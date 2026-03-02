extends CharacterBody3D

const GRAVITY = 20.0
const SPEED = 5.0
const LUNGE_SPEED = 12.0  # Speed when lunging
const STOP_DISTANCE = 2.0  # Stop this close to the player
const LUNGE_COOLDOWN = 7.0  # Cooldown between lunges in seconds

var player: CharacterBody3D = null
var is_player_in_range: bool = false
var is_player_in_lunge_range: bool = false
var animation_player: AnimationPlayer = null
var lunge_timer: float = 0.0  # Time since last lunge
var can_lunge: bool = true  # Whether the charger can lunge
var is_lunging: bool = false  # Currently performing a lunge
var lunge_direction: Vector3 = Vector3.ZERO  # Direction locked in when lunge starts

func _ready():
	# Connect the detector signals
	$Detector.body_entered.connect(_on_detector_body_entered)
	$Detector.body_exited.connect(_on_detector_body_exited)
	
	# Connect the lunge area signals
	$Lunge.body_entered.connect(_on_lunge_body_entered)
	$Lunge.body_exited.connect(_on_lunge_body_exited)
	
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
		is_lunging = false
		print("Lunge animation finished")

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0
	
	# Update lunge cooldown timer
	if not can_lunge:
		lunge_timer += delta
		if lunge_timer >= LUNGE_COOLDOWN:
			can_lunge = true
			lunge_timer = 0.0
			print("Lunge ready!")
	
	# Follow the player if in range
	if is_player_in_range and player and is_instance_valid(player):
		# Calculate direction to player
		var direction_to_player = (player.global_position - global_position)
		var distance_to_player = direction_to_player.length()
		direction_to_player.y = 0  # Ignore vertical difference
		direction_to_player = direction_to_player.normalized()
		
		# Only rotate if not lunging (lock rotation during lunge)
		if not is_lunging:
			# Calculate target rotation
			if direction_to_player.length() > 0.1:
				var target_rotation = atan2(direction_to_player.x, direction_to_player.z)
				# Smoothly rotate to face the player
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
		
		# Move toward player if not too close
		if distance_to_player > STOP_DISTANCE:
			# Check if currently lunging (continue lunge until animation ends)
			if is_lunging:
				# Continue lunging in the locked direction at high speed
				velocity.x = lunge_direction.x * LUNGE_SPEED
				velocity.z = lunge_direction.z * LUNGE_SPEED
			# Check if player is in lunge range and lunge is ready (start new lunge)
			elif is_player_in_lunge_range and can_lunge:
				# Lock in the lunge direction at the moment of attack
				lunge_direction = direction_to_player
				
				# Start lunging in the locked direction
				velocity.x = lunge_direction.x * LUNGE_SPEED
				velocity.z = lunge_direction.z * LUNGE_SPEED
				
				# Start cooldown and lunge state immediately
				can_lunge = false
				is_lunging = true
				lunge_timer = 0.0
				print("Starting lunge! Direction locked: ", lunge_direction, " Speed: ", velocity.length())
				
				# Play lunge animation if it exists, otherwise use walk at faster speed
				if animation_player:
					if animation_player.has_animation("lunge"):
						animation_player.play("lunge")
						print("Playing lunge animation")
					elif animation_player.has_animation("walk"):
						# Use walk animation but faster as fallback
						animation_player.play("walk")
						animation_player.speed_scale = 2.0  # Play walk faster for lunge effect
						print("No lunge animation found, using walk at 2x speed")
					else:
						print("WARNING: Neither lunge nor walk animation found!")
			else:
				# Regular walking speed (either outside lunge range or on cooldown)
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
			
			# Stop animation
			if animation_player and animation_player.is_playing():
				animation_player.stop()
	else:
		# Not in range, don't move
		velocity.x = 0
		velocity.z = 0
		
		# Stop animation
		if animation_player and animation_player.is_playing():
			animation_player.stop()
	
	# Apply physics movement
	move_and_slide()

func _enable_shadows(node: Node):
	# Recursively enable shadow casting on all MeshInstance3D nodes
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	for child in node.get_children():
		_enable_shadows(child)
