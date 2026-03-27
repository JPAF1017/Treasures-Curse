extends CharacterBody3D

const GRAVITY = 20.0
const WALK_SPEED = 1.5
const RUN_SPEED = 10.0
const DIR_CHANGE_MIN = 1.2
const DIR_CHANGE_MAX = 3.0
const ATTACK_COOLDOWN = 3.0
const MAX_ATTACKS_BEFORE_WANDER = 13
const BUMP_STEP_VELOCITY = 2.0
const BUMP_STEP_COOLDOWN = 0.15
const PATH_RAYCAST_DISTANCE = 3.0
const SIDE_PROBE_DISTANCE = 2.25
const SENSE_RAY_HEIGHT = 0.8
const LOS_MEMORY_TIME = 10.0
@export var turn_speed: float = 3.0
@export var run_turn_speed: float = 6.0
@export var attack_animation_speed: float = 1.3

enum State {
	WANDER,
	SCREAMING,
	CHASING,
	ATTACKING
}

var move_direction: Vector3 = Vector3.ZERO
var direction_change_timer: float = 0.0
var animation_player: AnimationPlayer = null
var seen_area: Area3D = null
var attack_range_area: Area3D = null
var current_state: State = State.WANDER
var target_player: CharacterBody3D = null
var scream_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var is_player_in_attack_range: bool = false
var attack_count: int = 0
var bump_step_timer: float = 0.0
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right
var los_memory_timer: float = 0.0
var last_visible_target_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	randomize()
	floor_snap_length = 0.7
	animation_player = _find_animation_player(self)
	seen_area = get_node_or_null("Seen")
	attack_range_area = get_node_or_null("AttackRange")
	if seen_area:
		seen_area.area_entered.connect(_on_seen_area_entered)
	if attack_range_area:
		attack_range_area.collision_mask = 2
		attack_range_area.collision_layer = 0
		attack_range_area.monitoring = true
		attack_range_area.body_entered.connect(_on_attack_range_body_entered)
		attack_range_area.body_exited.connect(_on_attack_range_body_exited)
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	_play_walk_animation()
	_pick_new_direction()
	_reset_direction_timer()

func _physics_process(delta: float) -> void:
	bump_step_timer = max(bump_step_timer - delta, 0.0)
	los_memory_timer = max(los_memory_timer - delta, 0.0)

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer = max(attack_cooldown_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if current_state == State.SCREAMING:
		_update_scream_state(delta)
	elif current_state == State.ATTACKING:
		_update_attack_state(delta)
	elif current_state == State.CHASING:
		_update_chase_state(delta)
	else:
		_update_wander_state(delta)

	# Step up tiny bumps while moving so AI does not stall on uneven floors.
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.2 and is_on_floor() and is_on_wall() and velocity.y <= 0.0 and bump_step_timer <= 0.0:
		velocity.y = BUMP_STEP_VELOCITY
		bump_step_timer = BUMP_STEP_COOLDOWN

	move_and_slide()

func _update_wander_state(delta: float) -> void:
	direction_change_timer -= delta
	if direction_change_timer <= 0.0 or is_on_wall():
		_pick_new_direction()
		_reset_direction_timer()

	velocity.x = move_direction.x * WALK_SPEED
	velocity.z = move_direction.z * WALK_SPEED

	if move_direction.length_squared() > 0.001:
		_face_direction(move_direction, delta)

	_play_walk_animation()

func _update_scream_state(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	if target_player and is_instance_valid(target_player):
		var to_target := target_player.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			_face_direction(to_target.normalized(), delta)

	_play_scream_animation()

	# Fallback in case scream animation is looping and never emits animation_finished.
	if scream_timer > 0.0:
		scream_timer -= delta
		if scream_timer <= 0.0:
			_start_chasing()

func _update_chase_state(delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		current_state = State.WANDER
		_reset_direction_timer()
		_pick_new_direction()
		return

	var has_line_of_sight := _has_line_of_sight_to(target_player.global_position + Vector3(0, 1.0, 0))
	if has_line_of_sight:
		last_visible_target_position = target_player.global_position
		los_memory_timer = LOS_MEMORY_TIME

	if has_line_of_sight and _is_target_in_attack_range() and attack_cooldown_timer <= 0.0:
		_start_attacking()
		return

	var pursuit_target := target_player.global_position
	if not has_line_of_sight and los_memory_timer > 0.0:
		pursuit_target = last_visible_target_position

	var to_target := pursuit_target - global_position
	to_target.y = 0.0

	if to_target.length_squared() <= 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_run_animation()
		return

	var chase_dir := to_target.normalized()
	var path_dir := _find_path_direction(chase_dir)
	if path_dir.length_squared() > 0.001:
		velocity.x = path_dir.x * RUN_SPEED
		velocity.z = path_dir.z * RUN_SPEED
		_face_direction(path_dir, delta, run_turn_speed)
	else:
		velocity.x = chase_dir.x * RUN_SPEED * 0.4
		velocity.z = chase_dir.z * RUN_SPEED * 0.4
		_face_direction(chase_dir, delta, run_turn_speed)
	_play_run_animation()

func _update_attack_state(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	# Attack is non-interruptible: finish the current animation even if target exits range.

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

func _play_scream_animation() -> void:
	if animation_player and animation_player.has_animation("scream"):
		if animation_player.current_animation != "scream" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("scream")

func _play_run_animation() -> void:
	if not animation_player:
		return

	if animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("run")
	elif animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("walk")

func _play_attack_animation() -> void:
	if not animation_player:
		return

	if animation_player.has_animation("attack"):
		if animation_player.current_animation != "attack" or not animation_player.is_playing():
			animation_player.speed_scale = attack_animation_speed
			animation_player.play("attack")
	else:
		push_warning("Shy missing 'attack' animation; using run fallback")
		# Fallback keeps behavior functional if attack clip is missing.
		_play_run_animation()

func _on_seen_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_vision"):
		return

	if current_state != State.WANDER:
		return

	var player_node := _find_player_from_vision_area(area)
	if player_node == null:
		return

	target_player = player_node
	_start_screaming()

func _start_screaming() -> void:
	current_state = State.SCREAMING
	attack_count = 0
	velocity.x = 0.0
	velocity.z = 0.0

	if animation_player and animation_player.has_animation("scream"):
		animation_player.play("scream")
		var scream_animation := animation_player.get_animation("scream")
		if scream_animation:
			scream_timer = scream_animation.length
		else:
			scream_timer = 0.0
	else:
		scream_timer = 0.0
		_start_chasing()

func _start_chasing() -> void:
	if target_player == null or not is_instance_valid(target_player):
		current_state = State.WANDER
		_pick_new_direction()
		_reset_direction_timer()
		return

	current_state = State.CHASING
	scream_timer = 0.0
	_play_run_animation()

func _start_attacking() -> void:
	current_state = State.ATTACKING
	velocity.x = 0.0
	velocity.z = 0.0
	attack_cooldown_timer = ATTACK_COOLDOWN
	_play_attack_animation()

func _on_animation_finished(anim_name: StringName) -> void:
	if current_state == State.SCREAMING and anim_name == "scream":
		_start_chasing()
	elif current_state == State.ATTACKING and anim_name == "attack":
		attack_count += 1
		if attack_count >= MAX_ATTACKS_BEFORE_WANDER:
			_return_to_wander()
		else:
			_start_chasing()

func _return_to_wander() -> void:
	current_state = State.WANDER
	target_player = null
	is_player_in_attack_range = false
	attack_cooldown_timer = 0.0
	attack_count = 0
	_pick_new_direction()
	_reset_direction_timer()
	_play_walk_animation()

func _face_direction(direction: Vector3, delta: float, speed: float = turn_speed) -> void:
	if direction.length_squared() <= 0.001:
		return
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * speed)

func _find_player_from_vision_area(area: Area3D) -> CharacterBody3D:
	var node: Node = area
	while node:
		if node is CharacterBody3D and node.is_in_group("player"):
			return node
		node = node.get_parent()
	return null

func _on_attack_range_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player"):
		target_player = body
		is_player_in_attack_range = true
		print("Player entered shy attack range")
		if current_state != State.SCREAMING and attack_cooldown_timer <= 0.0:
			_start_attacking()

func _on_attack_range_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player") and body == target_player:
		is_player_in_attack_range = false
		print("Player exited shy attack range")

func _is_target_in_attack_range() -> bool:
	if attack_range_area == null:
		return false
	if target_player == null or not is_instance_valid(target_player):
		return false

	# Keep this robust even if signal timing is missed for one frame.
	if attack_range_area.get_overlapping_bodies().has(target_player):
		is_player_in_attack_range = true
		return true

	return is_player_in_attack_range and attack_range_area.overlaps_body(target_player)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result

	return null

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
