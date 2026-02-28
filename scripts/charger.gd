extends CharacterBody3D

const GRAVITY = 20.0

var player: CharacterBody3D = null
var is_player_in_range: bool = false

func _ready():
	# Connect the detector signals
	$Detector.body_entered.connect(_on_detector_body_entered)
	$Detector.body_exited.connect(_on_detector_body_exited)

func _on_detector_body_entered(body):
	if body.is_in_group("player"):
		player = body
		is_player_in_range = true
		print("Player entered charger's detection range")

func _on_detector_body_exited(body):
	if body.is_in_group("player"):
		is_player_in_range = false
		print("Player exited charger's detection range")

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0
	
	# Face the player if in range
	if is_player_in_range and player and is_instance_valid(player):
		# Calculate direction to player
		var direction_to_player = (player.global_position - global_position)
		direction_to_player.y = 0  # Ignore vertical difference
		direction_to_player = direction_to_player.normalized()
		
		# Calculate target rotation
		if direction_to_player.length() > 0.1:
			var target_rotation = atan2(direction_to_player.x, direction_to_player.z)
			# Smoothly rotate to face the player
			rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
	
	# Apply physics movement
	move_and_slide()
