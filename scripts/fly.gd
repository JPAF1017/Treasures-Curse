extends CharacterBody3D

const GRAVITY = 20.0
const WALK_SPEED = 2.0
const DIR_CHANGE_MIN = 1.5
const DIR_CHANGE_MAX = 4.0
const WALK_BEFORE_IDLE_MIN = 1.5
const WALK_BEFORE_IDLE_MAX = 4.5
const IDLE_DURATION_MIN = 0.6
const IDLE_DURATION_MAX = 1.8
const FLOAT_HEIGHT_MIN = 1.5
const FLOAT_HEIGHT_MAX = 1.5
const FLOAT_SPEED = 3.0
const FLOAT_DURATION_MIN = 5.0
const FLOAT_DURATION_MAX = 8.0
const GROUND_WAIT_MIN = 5.0
const GROUND_WAIT_MAX = 5.0
const POSITION_SHIFT_EPSILON = 0.01
const GROUND_RAYCAST_DISTANCE = 50.0
const ASCENT_STOP_EPSILON = 0.02

var move_direction: Vector3 = Vector3.ZERO
var direction_change_timer: float = 0.0
var walk_before_idle_timer: float = 0.0
var idle_timer: float = 0.0
var is_idle: bool = false
var animation_player: AnimationPlayer = null
var ground_collision: CollisionShape3D = null
var vert_fly_collision: CollisionShape3D = null
var hor_fly_collision: CollisionShape3D = null
var target_float_height: float = 0.0
var ground_height: float = 0.0
var is_floating: bool = false
var float_timer: float = 0.0
var max_float_duration: float = 0.0
var float_target_height_set: bool = false
var float_cooldown: float = 0.0
var is_descending: bool = false
var is_preparing_to_fly: bool = false
var is_landing: bool = false
var transition_anim_timer: float = 0.0
var target_height_above_ground: float = 0.0
var last_logged_state: String = ""
var last_logged_position: Vector3 = Vector3.INF

func _ready() -> void:
	randomize()
	animation_player = _find_animation_player(self)
	ground_collision = $ground
	vert_fly_collision = $vertFly
	hor_fly_collision = $horFly
	ground_height = global_position.y
	target_float_height = ground_height
	target_height_above_ground = FLOAT_HEIGHT_MIN
	_pick_new_direction()
	_reset_direction_timer()
	_reset_walk_before_idle_timer()
	_update_collision_mode()
	_play_walk_animation()

func _physics_process(delta: float) -> void:
	# Update float cooldown
	if float_cooldown > 0.0:
		float_cooldown -= delta

	# Let transition labels exist only for the animation clip duration.
	if transition_anim_timer > 0.0:
		transition_anim_timer = max(transition_anim_timer - delta, 0.0)
		if transition_anim_timer <= 0.0:
			is_preparing_to_fly = false
			is_landing = false
	
	# Handle gravity or floating
	if is_floating and float_timer > 0.0:
		# During ascent: actively move to target height
		if not float_target_height_set:
			# Sample ground below and set desired hover height above that ground.
			_update_ground_height_from_raycast()
			target_height_above_ground = randf_range(FLOAT_HEIGHT_MIN, FLOAT_HEIGHT_MAX)
			target_float_height = ground_height + target_height_above_ground
			float_target_height_set = true
			is_descending = false
			print("[FLY FLOAT START] TargetWorldY: %.2f, TargetAboveGround: %.2f, Current: %.2f, Ground: %.2f, Duration: %.2f" % [target_float_height, target_height_above_ground, global_position.y, ground_height, float_timer])
		
		# Re-sample ground while airborne so hover height remains relative to terrain below.
		_update_ground_height_from_raycast()
		var desired_world_height = ground_height + target_height_above_ground
		var height_diff = desired_world_height - global_position.y

		# Stop ascending once we have reached configured hover height above ground.
		if height_diff <= ASCENT_STOP_EPSILON:
			velocity.y = 0.0
		else:
			velocity.y = height_diff * FLOAT_SPEED

		float_timer -= delta
	elif is_floating and float_timer <= 0.0 and not is_descending:
		# During descent: start landing animation and descent at the same time.
		is_landing = true
		is_descending = true
		velocity.x = 0.0
		velocity.z = 0.0
		_play_landing_animation()
	elif is_descending:
		# Apply gravity during descent
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		print("[FLY DESCENDING] Pos: %.2f, Falling" % global_position.y)
		
		# Check if we've reached ground (only during descent)
		if is_on_floor():
			print("[FLY LANDING] Reached ground! Cooldown for 2 seconds.")
			is_floating = false
			is_descending = false
			is_landing = false
			is_preparing_to_fly = false
			transition_anim_timer = 0.0
			float_target_height_set = false
			float_cooldown = 2.0
			velocity.y = 0.0
	else:
		# Not floating: apply normal gravity
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
	
	_update_wander_state(delta)
	_update_collision_mode()
	_move_and_log()

func _update_wander_state(delta: float) -> void:
	# While landing/descending, do not allow movement-state changes until grounded.
	if is_landing or is_descending:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var can_ground_wander := is_on_floor() and not is_floating and not is_descending and not is_preparing_to_fly and not is_landing

	# Start floating if not already (and cooldown has expired)
	if can_ground_wander and not is_idle and float_cooldown <= 0.0:
		if randf() < 0.02:  # Random chance each frame to start floating
			is_preparing_to_fly = true
			is_floating = true
			is_descending = false
			is_landing = false
			float_target_height_set = false
			max_float_duration = randf_range(FLOAT_DURATION_MIN, FLOAT_DURATION_MAX)
			float_timer = max_float_duration
			# Stop movement immediately
			velocity.x = 0.0
			velocity.z = 0.0
			move_direction = Vector3.ZERO
			_play_takeoff_animation()
			print("Preparing to fly for %.2f seconds" % max_float_duration)
	
	if is_idle and can_ground_wander:
		idle_timer = max(idle_timer - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		_play_idle_animation()
		if idle_timer <= 0.0:
			is_idle = false
			_reset_walk_before_idle_timer()
			_pick_new_direction()
			_reset_direction_timer()
		return
	elif is_idle and not can_ground_wander:
		# Never keep idle state active while airborne or during flight transitions.
		is_idle = false

	if can_ground_wander:
		walk_before_idle_timer = max(walk_before_idle_timer - delta, 0.0)
	else:
		walk_before_idle_timer = max(walk_before_idle_timer, 0.1)

	if can_ground_wander and walk_before_idle_timer <= 0.0:
		is_idle = true
		idle_timer = randf_range(IDLE_DURATION_MIN, IDLE_DURATION_MAX)
		velocity.x = 0.0
		velocity.z = 0.0
		_play_idle_animation()
		return

	direction_change_timer -= delta
	if direction_change_timer <= 0.0 or is_on_wall():
		_pick_new_direction()
		_reset_direction_timer()

	velocity.x = move_direction.x * WALK_SPEED
	velocity.z = move_direction.z * WALK_SPEED

	if move_direction.length_squared() > 0.001:
		_face_direction(move_direction, delta)

	# While transition clip is active, do not override it with other animations.
	if is_preparing_to_fly or is_landing:
		pass
	# Walk animation should only run while grounded.
	elif is_on_floor() and not is_floating and not is_descending:
		_play_walk_animation()
	else:
		_play_air_animation()

func _pick_new_direction() -> void:
	var angle := randf_range(0.0, TAU)
	move_direction = Vector3(sin(angle), 0.0, cos(angle)).normalized()

func _reset_direction_timer() -> void:
	direction_change_timer = randf_range(DIR_CHANGE_MIN, DIR_CHANGE_MAX)

func _reset_walk_before_idle_timer() -> void:
	walk_before_idle_timer = randf_range(WALK_BEFORE_IDLE_MIN, WALK_BEFORE_IDLE_MAX)

func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.001:
		var target_angle := atan2(direction.x, direction.z)
		var current_angle := atan2(transform.basis.z.x, transform.basis.z.z)
		var angle_diff := angle_difference(current_angle, target_angle)
		var turn_speed := 3.0
		var new_angle := current_angle + angle_diff * delta * turn_speed
		transform.basis = Basis.from_euler(Vector3(0, new_angle, 0))

func _play_walk_animation() -> void:
	if animation_player and animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("walk")

func _play_idle_animation() -> void:
	if not animation_player:
		return

	if animation_player.has_animation("idle"):
		if animation_player.current_animation != "idle" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("idle")
	else:
		_play_walk_animation()

func _play_air_animation() -> void:
	if not animation_player:
		return

	# Prefer a dedicated flying/air animation when available.
	if animation_player.has_animation("idleFly"):
		if animation_player.current_animation != "idleFly" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("idleFly")
	elif animation_player.has_animation("fly"):
		if animation_player.current_animation != "fly" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("fly")
	elif animation_player.has_animation("idle"):
		if animation_player.current_animation != "idle" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("idle")

func _play_takeoff_animation() -> void:
	transition_anim_timer = 0.0
	if not animation_player:
		print("[FLY ANIM] prepareToFly (takeoff) NOT played: AnimationPlayer missing")
		return

	if animation_player.has_animation("prepareToFly"):
		print("[FLY ANIM] prepareToFly PLAY takeoff at t=%d pos=(%.2f, %.2f, %.2f)" % [
			Time.get_ticks_msec(),
			global_position.x,
			global_position.y,
			global_position.z,
		])
		animation_player.speed_scale = 1.0
		animation_player.play("prepareToFly")
		transition_anim_timer = animation_player.get_animation("prepareToFly").length
	else:
		print("[FLY ANIM] prepareToFly (takeoff) NOT played: animation missing")

func _play_landing_animation() -> void:
	transition_anim_timer = 0.0
	if not animation_player:
		print("[FLY ANIM] prepareToFly (landing reverse) NOT played: AnimationPlayer missing")
		return

	if animation_player.has_animation("prepareToFly"):
		print("[FLY ANIM] prepareToFly PLAY landing_reverse at t=%d pos=(%.2f, %.2f, %.2f)" % [
			Time.get_ticks_msec(),
			global_position.x,
			global_position.y,
			global_position.z,
		])
		animation_player.play_backwards("prepareToFly")
		transition_anim_timer = animation_player.get_animation("prepareToFly").length
	else:
		print("[FLY ANIM] prepareToFly (landing reverse) NOT played: animation missing")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null

func _update_collision_mode() -> void:
	if not ground_collision or not hor_fly_collision:
		return

	# Switch collision EARLY: use ground collision when landing/descending starts
	# This ensures ground collision is active BEFORE the creature reaches the floor
	var use_hor_fly := is_floating and not is_landing and not is_descending and is_on_floor() == false
	var old_ground_disabled := ground_collision.disabled
	var old_horfly_disabled := hor_fly_collision.disabled
	
	ground_collision.disabled = use_hor_fly
	hor_fly_collision.disabled = not use_hor_fly
	
	# Log state changes
	if ground_collision.disabled != old_ground_disabled or hor_fly_collision.disabled != old_horfly_disabled:
		print("[COLLISION] floating=%s landing=%s descending=%s on_floor=%s => ground=%s horFly=%s" % [
			is_floating, is_landing, is_descending, is_on_floor(),
			"DISABLED" if ground_collision.disabled else "ENABLED",
			"DISABLED" if hor_fly_collision.disabled else "ENABLED"
		])

func _update_ground_height_from_raycast() -> void:
	var space_state := get_world_3d().direct_space_state
	var ray_start := global_position + Vector3.UP * 0.5
	var ray_end := global_position + Vector3.DOWN * GROUND_RAYCAST_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [self]
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		ground_height = hit.position.y

func _move_and_log() -> void:
	move_and_slide()
	_log_state_change_if_needed()
	_log_position_shift_if_needed()

func _get_fly_state() -> String:
	if is_preparing_to_fly:
		return "preparing_to_fly"
	if is_landing:
		return "landing_animation"
	if is_descending:
		return "descending"
	if is_floating:
		return "floating"
	if is_idle:
		return "idle"
	return "walking"

func _log_state_change_if_needed() -> void:
	var current_state := _get_fly_state()
	if current_state != last_logged_state:
		print("[FLY STATE] %s -> %s" % [last_logged_state if last_logged_state != "" else "(init)", current_state])
		last_logged_state = current_state

func _log_position_shift_if_needed() -> void:
	if last_logged_position == Vector3.INF:
		last_logged_position = global_position
		print("[FLY POS] x=%.2f y=%.2f z=%.2f" % [global_position.x, global_position.y, global_position.z])
		return

	if global_position.distance_to(last_logged_position) >= POSITION_SHIFT_EPSILON:
		print("[FLY POS] x=%.2f y=%.2f z=%.2f" % [global_position.x, global_position.y, global_position.z])
		last_logged_position = global_position

func angle_difference(from: float, to: float) -> float:
	var diff := fmod(to - from + PI, TAU) - PI
	return diff if diff >= -PI else diff + TAU
