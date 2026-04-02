extends CharacterBody3D

const EnemyLocomotion := preload("res://scripts/EnemyLocomotionComponent.gd")
const EnemyPerceptionMemory := preload("res://scripts/EnemyPerceptionMemoryComponent.gd")

const GRAVITY := 20.0
const WALK_SPEED := 1.8
const RUN_SPEED := 4.0
const DIR_CHANGE_MIN := 1.2
const DIR_CHANGE_MAX := 3.2
const TURN_SPEED := 4.0
const LOS_MEMORY_TIME := 5.0
const CHASE_MEMORY_TIME := 3.0
const TRAIL_MEMORY_TIME := 5.0
const TRAIL_SAMPLE_INTERVAL := 0.2
const TRAIL_POINT_SPACING := 0.7
const TRAIL_REACHED_DISTANCE := 0.8
const TRAIL_MAX_POINTS := 28
const LOS_LOSS_GRACE_TIME := 0.35
const STAIR_VERTICAL_DELTA := 1.6
const PATH_CACHE_TIME := 1.5
const PATH_CACHE_MAX_POINTS := 10
const STAIR_TRAIL_MAX_POINTS := 14
const MEMORY_LOG_INTERVAL := 0.25
const BUMP_STEP_VELOCITY := 2.0
const BUMP_STEP_COOLDOWN := 0.15
const CROUCH_DETECTION_RAY_LENGTH := 8.0

@export var facing_offset_degrees: float = -90.0
@export var debug_memory_logs: bool = false

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
var trail_memory_timer: float = 0.0
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var los_loss_grace_timer: float = 0.0
var path_cache_timer: float = 0.0
var cached_nav_path: Array[Vector3] = []
var last_reachable_target_position: Vector3 = Vector3.ZERO
var space_state: PhysicsDirectSpaceState3D = null

func _ready() -> void:
	randomize()
	floor_stop_on_slope = true
	floor_snap_length = 0.7
	space_state = get_world_3d().direct_space_state
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
	trail_memory_timer = max(trail_memory_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	los_loss_grace_timer = max(los_loss_grace_timer - delta, 0.0)
	path_cache_timer = max(path_cache_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)
	_refresh_player_detection()

	EnemyLocomotion.apply_gravity(self, GRAVITY, delta)

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
	bump_step_timer = EnemyLocomotion.try_bump_step(self, bump_step_timer, BUMP_STEP_VELOCITY, BUMP_STEP_COOLDOWN)

	move_and_slide()

func _should_run_chase() -> bool:
	if is_player_in_chase and _has_valid_target_player():
		return true
	if trail_memory_timer > 0.0 and not memorized_target_trail.is_empty():
		return true
	return chase_memory_timer > 0.0

func _should_walk_chase() -> bool:
	if is_player_in_detect and _has_valid_target_player():
		return true
	if trail_memory_timer > 0.0 and not memorized_target_trail.is_empty():
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

func _refresh_player_detection() -> void:
	if _has_valid_target_player() and _is_crouched_player_hidden(target_player):
		los_state_initialized = false
		previous_has_line_of_sight = false
		los_loss_grace_timer = 0.0
		path_cache_timer = 0.0
		cached_nav_path.clear()
		last_reachable_target_position = Vector3.ZERO
		is_player_in_detect = false
		is_player_in_chase = false
		is_player_in_attack_range = false
		target_player = null

	if _has_valid_target_player():
		is_player_in_detect = _is_body_overlapping_area(detect_area, target_player)
		is_player_in_chase = _is_body_overlapping_area(chase_area, target_player)
		is_player_in_attack_range = _is_body_overlapping_area(attack_range_area, target_player)
		return

	var detectable_player := _find_detectable_player_in_area(detect_area)
	if detectable_player:
		target_player = detectable_player
		los_state_initialized = false
		previous_has_line_of_sight = false
		los_loss_grace_timer = 0.0
		path_cache_timer = 0.0
		cached_nav_path.clear()
		last_reachable_target_position = Vector3.ZERO
		is_player_in_detect = true
		is_player_in_chase = _is_body_overlapping_area(chase_area, target_player)
		is_player_in_attack_range = _is_body_overlapping_area(attack_range_area, target_player)

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

func _is_crouched_player_hidden(body: Node3D) -> bool:
	return _is_player_crouching(body) and not _is_player_in_front_by_raycast(body)

func _is_player_crouching(body: Node) -> bool:
	return body != null and bool(body.get("is_crouching"))

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

func _update_pursuit_movement(delta: float, move_speed: float) -> void:
	var has_target := _has_valid_target_player()
	var has_line_of_sight := false
	var space_state := get_world_3d().direct_space_state

	if has_target:
		var target_eye := target_player.global_position + Vector3(0, 1.0, 0)
		has_line_of_sight = NavigationUtils.has_line_of_sight_to(self, target_eye, space_state, [self, target_player])
		var los_state := EnemyPerceptionMemory.update_los_trail_state(
			has_line_of_sight,
			{
				"los_state_initialized": los_state_initialized,
				"previous_has_line_of_sight": previous_has_line_of_sight,
				"trail_memory_timer": trail_memory_timer,
				"trail_sample_timer": trail_sample_timer,
				"los_loss_grace_timer": los_loss_grace_timer,
			},
			memorized_target_trail,
			last_visible_player_position,
			{
				"trail_memory_time": TRAIL_MEMORY_TIME,
				"trail_point_spacing": TRAIL_POINT_SPACING,
				"trail_max_points": TRAIL_MAX_POINTS,
				"los_loss_grace_time": LOS_LOSS_GRACE_TIME,
				"stair_vertical_delta": STAIR_VERTICAL_DELTA,
				"stair_trail_max_points": STAIR_TRAIL_MAX_POINTS,
			}
		)
		has_line_of_sight = bool(los_state.get("effective_has_line_of_sight", has_line_of_sight))
		los_state_initialized = bool(los_state.get("los_state_initialized", los_state_initialized))
		previous_has_line_of_sight = bool(los_state.get("previous_has_line_of_sight", previous_has_line_of_sight))
		los_loss_grace_timer = float(los_state.get("los_loss_grace_timer", los_loss_grace_timer))
		trail_memory_timer = float(los_state.get("trail_memory_timer", trail_memory_timer))
		trail_sample_timer = float(los_state.get("trail_sample_timer", trail_sample_timer))
		if has_line_of_sight:
			var snapped_visible := NavigationUtils.snap_position_to_navigation(self, target_player.global_position)
			last_visible_player_position = snapped_visible
			last_reachable_target_position = snapped_visible
			cached_nav_path = NavigationUtils.build_short_path_cache(self, snapped_visible, PATH_CACHE_MAX_POINTS)
			path_cache_timer = PATH_CACHE_TIME
			los_memory_timer = LOS_MEMORY_TIME
			trail_memory_timer = TRAIL_MEMORY_TIME
			if trail_sample_timer <= 0.0:
				NavigationUtils.append_trail_point(memorized_target_trail, snapped_visible, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
				trail_sample_timer = TRAIL_SAMPLE_INTERVAL

	var pursuit_target := last_visible_player_position
	var trail_target := Vector3.ZERO
	var memory_source := "LAST_SEEN"
	if has_target and has_line_of_sight:
		pursuit_target = NavigationUtils.snap_position_to_navigation(self, target_player.global_position)
		memory_source = "LOS"
	else:
		var vertical_mismatch := has_target and absf(target_player.global_position.y - last_visible_player_position.y) > STAIR_VERTICAL_DELTA
		if vertical_mismatch:
			memorized_target_trail.clear()
			cached_nav_path.clear()
			path_cache_timer = 0.0
			if last_reachable_target_position != Vector3.ZERO:
				pursuit_target = last_reachable_target_position
				memory_source = "LAST_REACHABLE"
			else:
				pursuit_target = last_visible_player_position

		if path_cache_timer > 0.0 and not cached_nav_path.is_empty():
			var cached_result := NavigationUtils.get_cached_path_target(global_position, cached_nav_path, TRAIL_REACHED_DISTANCE)
			if bool(cached_result.get("has_target", false)):
				pursuit_target = cached_result["target"]
				memory_source = "PATH_CACHE"

		if memory_source != "PATH_CACHE":
			var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
			if trail_memory_timer > 0.0 and bool(trail_result.get("has_target", false)):
				trail_target = trail_result["target"]
				pursuit_target = trail_target
				memory_source = "TRAIL"
			elif trail_memory_timer > 0.0:
				pursuit_target = last_visible_player_position
				memory_source = "LAST_SEEN"
			else:
				_log_memory_state(has_line_of_sight, memory_source, target_player.global_position if has_target else Vector3.ZERO, last_visible_player_position, trail_target, global_position, true)
				velocity.x = 0.0
				velocity.z = 0.0
				if not is_player_in_detect and not is_player_in_chase:
					target_player = null
				memorized_target_trail.clear()
				wall_follow_mode = 0
				return

		if has_target and absf(target_player.global_position.y - last_visible_player_position.y) > STAIR_VERTICAL_DELTA and last_reachable_target_position != Vector3.ZERO and (memory_source == "LAST_SEEN" or memory_source == "TRAIL" or memory_source == "PATH_CACHE"):
			pursuit_target = last_reachable_target_position
			memory_source = "LAST_REACHABLE"
			NavigationUtils.prune_trail_for_stairs(memorized_target_trail, last_visible_player_position.y, STAIR_VERTICAL_DELTA, STAIR_TRAIL_MAX_POINTS)

		pursuit_target = NavigationUtils.snap_position_to_navigation(self, pursuit_target)

	_log_memory_state(has_line_of_sight, memory_source, target_player.global_position if has_target else Vector3.ZERO, last_visible_player_position, trail_target, pursuit_target)

	var to_target := pursuit_target - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
	var path_dir: Vector3 = path_result["direction"]
	wall_follow_mode = path_result["wall_follow_mode"]
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
	los_state_initialized = false
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	last_reachable_target_position = Vector3.ZERO
	is_player_in_detect = true
	last_visible_player_position = target_player.global_position
	los_memory_timer = LOS_MEMORY_TIME
	trail_memory_timer = TRAIL_MEMORY_TIME
	trail_sample_timer = 0.0
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	memorized_target_trail.clear()
	NavigationUtils.append_trail_point(memorized_target_trail, last_visible_player_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)

func _on_detect_body_exited(body: Node3D) -> void:
	if target_player == null:
		return
	if body != target_player:
		return

	is_player_in_detect = false
	if is_instance_valid(target_player):
		last_visible_player_position = target_player.global_position
	los_memory_timer = LOS_MEMORY_TIME
	trail_memory_timer = TRAIL_MEMORY_TIME
	los_state_initialized = false
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	last_reachable_target_position = Vector3.ZERO
	if not is_player_in_chase:
		target_player = null

func _on_chase_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return

	target_player = body
	los_state_initialized = false
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	last_reachable_target_position = Vector3.ZERO
	is_player_in_chase = true
	chase_memory_timer = CHASE_MEMORY_TIME
	last_visible_player_position = target_player.global_position
	trail_memory_timer = TRAIL_MEMORY_TIME
	trail_sample_timer = 0.0
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	memorized_target_trail.clear()
	NavigationUtils.append_trail_point(memorized_target_trail, last_visible_player_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)

func _on_chase_body_exited(body: Node3D) -> void:
	if target_player == null:
		return
	if body != target_player:
		return

	is_player_in_chase = false
	if is_instance_valid(target_player):
		last_visible_player_position = target_player.global_position
	chase_memory_timer = CHASE_MEMORY_TIME
	trail_memory_timer = TRAIL_MEMORY_TIME
	los_state_initialized = false
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	last_reachable_target_position = Vector3.ZERO
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

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found

	return null

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
	print("[GnomeMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d trail_timer=%.2f los_timer=%.2f" % [
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
