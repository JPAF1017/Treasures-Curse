extends CharacterBody3D

const GRAVITY := 20.0
const WALK_SPEED := 1.8
const RUN_SPEED := 4.0
const DIR_CHANGE_MIN := 1.2
const DIR_CHANGE_MAX := 3.2
const TURN_SPEED := 4.0
const LOS_MEMORY_TIME := 5.0
const CHASE_MEMORY_TIME := 3.0
const PATH_RAYCAST_DISTANCE := 3.5
const SIDE_PROBE_DISTANCE := 2.5
const SENSE_RAY_HEIGHT := 0.8
const BUMP_STEP_VELOCITY := 2.0
const BUMP_STEP_COOLDOWN := 0.15

@export var facing_offset_degrees: float = -90.0

var move_direction: Vector3 = Vector3.ZERO
var direction_change_timer: float = 0.0
var animation_player: AnimationPlayer = null
var detect_area: Area3D = null
var chase_area: Area3D = null
var attack_range_area: Area3D = null
var target_player: CharacterBody3D = null
var attack_range_player: CharacterBody3D = null
var grabbed_player: CharacterBody3D = null
var is_player_in_detect: bool = false
var is_player_in_chase: bool = false
var is_player_in_attack_range: bool = false
var los_memory_timer: float = 0.0
var chase_memory_timer: float = 0.0
var last_visible_player_position: Vector3 = Vector3.ZERO
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right
var bump_step_timer: float = 0.0

func _ready() -> void:
	randomize()
	floor_stop_on_slope = true
	floor_snap_length = 0.7
	animation_player = _find_animation_player(self)
	detect_area = get_node_or_null("Detect")
	chase_area = get_node_or_null("Chase")
	attack_range_area = get_node_or_null("AttackRange")
	if detect_area:
		detect_area.body_entered.connect(_on_detect_body_entered)
		detect_area.body_exited.connect(_on_detect_body_exited)
	if chase_area:
		chase_area.body_entered.connect(_on_chase_body_entered)
		chase_area.body_exited.connect(_on_chase_body_exited)
	if attack_range_area:
		attack_range_area.body_entered.connect(_on_attack_range_body_entered)
		attack_range_area.body_exited.connect(_on_attack_range_body_exited)
	_pick_new_direction()
	_reset_direction_timer()
	_play_walk_animation()

func _physics_process(delta: float) -> void:
	bump_step_timer = max(bump_step_timer - delta, 0.0)
	los_memory_timer = max(los_memory_timer - delta, 0.0)
	chase_memory_timer = max(chase_memory_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if is_player_in_attack_range and _has_valid_attack_range_player():
		_update_attack_range_state(delta)
		if _has_valid_grabbed_player() and grabbed_player == attack_range_player:
			_play_grab_animation()
		else:
			_play_attack_animation()
	elif _should_run_chase():
		_update_pursuit_movement(delta, RUN_SPEED)
		_play_run_animation()
	elif _should_walk_chase():
		_update_pursuit_movement(delta, WALK_SPEED)
		_play_walk_animation()
	else:
		_update_wander_movement(delta)
		_play_walk_animation()

	# Step up tiny bumps while moving so the gnome does not stall on uneven floors.
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.2 and is_on_floor() and is_on_wall() and velocity.y <= 0.0 and bump_step_timer <= 0.0:
		velocity.y = BUMP_STEP_VELOCITY
		bump_step_timer = BUMP_STEP_COOLDOWN

	move_and_slide()

func _should_run_chase() -> bool:
	if is_player_in_chase and _has_valid_target_player():
		return true
	return chase_memory_timer > 0.0

func _should_walk_chase() -> bool:
	if is_player_in_detect and _has_valid_target_player():
		return true
	return los_memory_timer > 0.0

func _has_valid_target_player() -> bool:
	if target_player == null:
		return false
	return is_instance_valid(target_player)

func _has_valid_grabbed_player() -> bool:
	if grabbed_player == null:
		return false
	return is_instance_valid(grabbed_player)

func _has_valid_attack_range_player() -> bool:
	if attack_range_player == null:
		return false
	return is_instance_valid(attack_range_player)

func _update_pursuit_movement(delta: float, move_speed: float) -> void:
	var has_target := _has_valid_target_player()
	var has_line_of_sight := false

	if has_target:
		var target_eye := target_player.global_position + Vector3(0, 1.0, 0)
		has_line_of_sight = _has_line_of_sight_to(target_eye)
		if has_line_of_sight:
			last_visible_player_position = target_player.global_position
			los_memory_timer = LOS_MEMORY_TIME

	var pursuit_target := last_visible_player_position
	if has_target:
		pursuit_target = target_player.global_position
		if not has_line_of_sight and los_memory_timer > 0.0:
			pursuit_target = last_visible_player_position

	var to_target := pursuit_target - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var path_dir := _find_path_direction(to_target.normalized())
	if path_dir.length_squared() <= 0.001:
		path_dir = to_target.normalized() * 0.4

	velocity.x = path_dir.x * move_speed
	velocity.z = path_dir.z * move_speed
	_face_direction(path_dir, delta)

func _update_wander_movement(delta: float) -> void:
	direction_change_timer -= delta
	if direction_change_timer <= 0.0 or is_on_wall():
		_pick_new_direction()
		_reset_direction_timer()

	velocity.x = move_direction.x * WALK_SPEED
	velocity.z = move_direction.z * WALK_SPEED
	_face_direction(move_direction, delta)

func _update_attack_range_state(delta: float) -> void:
	if grabbed_player == null and _has_valid_attack_range_player() and _can_lock_player(attack_range_player):
		grabbed_player = attack_range_player
		_lock_grabbed_player(true)

	velocity.x = 0.0
	velocity.z = 0.0

	var to_player := attack_range_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.001:
		_face_direction(to_player.normalized(), delta)

func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.001:
		return
	var target_yaw := atan2(direction.x, direction.z) + deg_to_rad(facing_offset_degrees)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * TURN_SPEED)

func _pick_new_direction() -> void:
	var angle := randf_range(0.0, TAU)
	move_direction = Vector3(sin(angle), 0.0, cos(angle)).normalized()

func _reset_direction_timer() -> void:
	direction_change_timer = randf_range(DIR_CHANGE_MIN, DIR_CHANGE_MAX)

func _play_walk_animation() -> void:
	if animation_player and animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("walk")

func _play_run_animation() -> void:
	if not animation_player:
		return

	if animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("run")
	elif animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.speed_scale = 1.6
			animation_player.play("walk")

func _play_grab_animation() -> void:
	if not animation_player:
		return

	if animation_player.has_animation("grab"):
		if animation_player.current_animation != "grab" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("grab")
		var current_anim := animation_player.get_animation("grab")
		if current_anim:
			current_anim.loop_mode = Animation.LOOP_LINEAR
	elif animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 0.8
			animation_player.play("run")

func _play_attack_animation() -> void:
	if not animation_player:
		return

	if animation_player.has_animation("attack"):
		if animation_player.current_animation != "attack" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("attack")
	elif animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("run")

func _on_detect_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return

	target_player = body
	is_player_in_detect = true
	last_visible_player_position = target_player.global_position
	los_memory_timer = LOS_MEMORY_TIME

func _on_detect_body_exited(body: Node3D) -> void:
	if target_player == null:
		return
	if body != target_player:
		return

	is_player_in_detect = false
	if is_instance_valid(target_player):
		last_visible_player_position = target_player.global_position
	los_memory_timer = LOS_MEMORY_TIME
	if not is_player_in_chase:
		target_player = null

func _on_chase_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return

	target_player = body
	is_player_in_chase = true
	chase_memory_timer = CHASE_MEMORY_TIME
	last_visible_player_position = target_player.global_position

func _on_chase_body_exited(body: Node3D) -> void:
	if target_player == null:
		return
	if body != target_player:
		return

	is_player_in_chase = false
	if is_instance_valid(target_player):
		last_visible_player_position = target_player.global_position
	chase_memory_timer = CHASE_MEMORY_TIME
	if not is_player_in_detect:
		target_player = null

func _on_attack_range_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return

	attack_range_player = body
	if _can_lock_player(attack_range_player):
		grabbed_player = attack_range_player
		_lock_grabbed_player(true)
	else:
		grabbed_player = null
	target_player = body
	is_player_in_attack_range = true
	last_visible_player_position = attack_range_player.global_position

func _on_attack_range_body_exited(body: Node3D) -> void:
	if attack_range_player == null:
		return
	if body != attack_range_player:
		return

	_lock_grabbed_player(false)
	is_player_in_attack_range = false
	attack_range_player = null
	grabbed_player = null

func _lock_grabbed_player(locked: bool) -> void:
	if grabbed_player == null:
		return
	if grabbed_player.has_method("set_movement_locked_by"):
		grabbed_player.call("set_movement_locked_by", self, locked)

func _can_lock_player(player: CharacterBody3D) -> bool:
	if player == null:
		return false
	if not player.has_method("is_movement_locked_by_other"):
		return true
	return not bool(player.call("is_movement_locked_by_other", self))

func _exit_tree() -> void:
	_lock_grabbed_player(false)

func _has_line_of_sight_to(target_position: Vector3) -> bool:
	var from_pos := global_position + Vector3(0, SENSE_RAY_HEIGHT, 0)
	return not _raycast_blocked(from_pos, target_position, [self, target_player])

func _raycast_blocked(from_pos: Vector3, to_pos: Vector3, excluded_bodies: Array) -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = excluded_bodies
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)
	return not result.is_empty()

func _is_direction_clear(direction: Vector3, distance: float = PATH_RAYCAST_DISTANCE) -> bool:
	if direction.length_squared() <= 0.001:
		return false
	var start := global_position + Vector3(0, SENSE_RAY_HEIGHT, 0)
	var end := start + direction.normalized() * distance
	return not _raycast_blocked(start, end, [self])

func _find_path_direction(target_direction: Vector3) -> Vector3:
	target_direction.y = 0.0
	if target_direction.length_squared() <= 0.001:
		return Vector3.ZERO
	target_direction = target_direction.normalized()

	if _is_direction_clear(target_direction):
		wall_follow_mode = 0
		return target_direction

	var angles_to_try := [20.0, -20.0, 35.0, -35.0, 50.0, -50.0, 70.0, -70.0, 90.0, -90.0, 120.0, -120.0, 145.0, -145.0]
	var best_direction := Vector3.ZERO
	var best_score := -999.0

	for angle_deg in angles_to_try:
		var angle_rad := deg_to_rad(angle_deg)
		var test_direction := target_direction.rotated(Vector3.UP, angle_rad)
		if _is_direction_clear(test_direction, SIDE_PROBE_DISTANCE):
			var score := test_direction.dot(target_direction)
			if wall_follow_mode != 0 and signf(angle_deg) == float(wall_follow_mode):
				score += 0.2
			if score > best_score:
				best_score = score
				best_direction = test_direction
				if angle_deg > 0.0:
					wall_follow_mode = 1
				elif angle_deg < 0.0:
					wall_follow_mode = -1

	return best_direction

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found

	return null
