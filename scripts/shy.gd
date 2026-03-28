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
const LOS_MEMORY_TIME = 10.0
const TRAIL_MEMORY_TIME = 5.0
const TRAIL_SAMPLE_INTERVAL = 0.2
const TRAIL_POINT_SPACING = 0.7
const TRAIL_REACHED_DISTANCE = 0.8
const MEMORY_TARGET_REACHED_DISTANCE = 0.6
const TRAIL_MAX_POINTS = 28
const LOS_LOSS_GRACE_TIME = 0.35
const STAIR_VERTICAL_DELTA = 1.6
const PATH_CACHE_TIME = 1.5
const PATH_CACHE_MAX_POINTS = 10
const STAIR_TRAIL_MAX_POINTS = 14
const MEMORY_LOG_INTERVAL = 0.25
const NAV_LOG_INTERVAL = 0.25
@export var turn_speed: float = 3.0
@export var run_turn_speed: float = 6.0
@export var attack_animation_speed: float = 1.3
@export var debug_memory_logs: bool = true

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
var trail_memory_timer: float = 0.0
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var nav_log_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var los_loss_grace_timer: float = 0.0
var path_cache_timer: float = 0.0
var cached_nav_path: Array[Vector3] = []
var last_reachable_target_position: Vector3 = Vector3.ZERO

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
	trail_memory_timer = max(trail_memory_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	los_loss_grace_timer = max(los_loss_grace_timer - delta, 0.0)
	path_cache_timer = max(path_cache_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)
	nav_log_timer = max(nav_log_timer - delta, 0.0)

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
		los_state_initialized = false
		current_state = State.WANDER
		_reset_direction_timer()
		_pick_new_direction()
		return

	var space_state := get_world_3d().direct_space_state
	var has_line_of_sight := NavigationUtils.has_line_of_sight_to(self, target_player.global_position + Vector3(0, 1.0, 0), space_state, [self, target_player])
	var los_state := NavigationUtils.update_los_trail_state(
		has_line_of_sight,
		los_state_initialized,
		previous_has_line_of_sight,
		trail_memory_timer,
		trail_sample_timer,
		memorized_target_trail,
		last_visible_target_position,
		TRAIL_MEMORY_TIME,
		TRAIL_POINT_SPACING,
		TRAIL_MAX_POINTS,
		los_loss_grace_timer,
		LOS_LOSS_GRACE_TIME,
		STAIR_VERTICAL_DELTA,
		STAIR_TRAIL_MAX_POINTS
	)
	has_line_of_sight = bool(los_state.get("effective_has_line_of_sight", has_line_of_sight))
	los_state_initialized = bool(los_state.get("los_state_initialized", los_state_initialized))
	previous_has_line_of_sight = bool(los_state.get("previous_has_line_of_sight", previous_has_line_of_sight))
	los_loss_grace_timer = float(los_state.get("los_loss_grace_timer", los_loss_grace_timer))
	trail_memory_timer = float(los_state.get("trail_memory_timer", trail_memory_timer))
	trail_sample_timer = float(los_state.get("trail_sample_timer", trail_sample_timer))
	var los_transition := String(los_state.get("transition", ""))
	if los_transition == "LOS_LOST":
		_log_memory_state(has_line_of_sight, "LOS_LOST", target_player.global_position, last_visible_target_position, memorized_target_trail[0] if not memorized_target_trail.is_empty() else Vector3.ZERO, last_visible_target_position, true)

	if has_line_of_sight:
		var snapped_visible := NavigationUtils.snap_position_to_navigation(self, target_player.global_position)
		last_visible_target_position = snapped_visible
		last_reachable_target_position = snapped_visible
		cached_nav_path = NavigationUtils.build_short_path_cache(self, snapped_visible, PATH_CACHE_MAX_POINTS)
		path_cache_timer = PATH_CACHE_TIME
		los_memory_timer = LOS_MEMORY_TIME
		trail_memory_timer = TRAIL_MEMORY_TIME
		if trail_sample_timer <= 0.0:
			NavigationUtils.append_trail_point(memorized_target_trail, snapped_visible, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
			trail_sample_timer = TRAIL_SAMPLE_INTERVAL

	if has_line_of_sight and _is_target_in_attack_range() and attack_cooldown_timer <= 0.0:
		_start_attacking()
		return

	var pursuit_target := target_player.global_position
	var trail_target := Vector3.ZERO
	var memory_source := "LOS"
	if not has_line_of_sight:
		memory_source = "LAST_SEEN"
		var skip_trail_memory := false
		var vertical_mismatch := absf(target_player.global_position.y - last_visible_target_position.y) > STAIR_VERTICAL_DELTA
		if vertical_mismatch:
			memorized_target_trail.clear()
			cached_nav_path.clear()
			path_cache_timer = 0.0
			skip_trail_memory = true
			if last_reachable_target_position != Vector3.ZERO:
				pursuit_target = last_reachable_target_position
				memory_source = "LAST_REACHABLE"
			else:
				pursuit_target = last_visible_target_position

		if not skip_trail_memory and path_cache_timer > 0.0 and not cached_nav_path.is_empty():
			var cached_result := NavigationUtils.get_cached_path_target(global_position, cached_nav_path, TRAIL_REACHED_DISTANCE)
			if bool(cached_result.get("has_target", false)):
				pursuit_target = cached_result["target"]
				memory_source = "PATH_CACHE"
		if not skip_trail_memory and memorized_target_trail.is_empty():
			NavigationUtils.append_trail_point(memorized_target_trail, last_visible_target_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
		if not skip_trail_memory and memory_source != "PATH_CACHE":
			var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
			if trail_memory_timer > 0.0 and bool(trail_result.get("has_target", false)):
				trail_target = trail_result["target"]
				pursuit_target = trail_target
				memory_source = "TRAIL"
			elif trail_memory_timer > 0.0:
				pursuit_target = last_visible_target_position
				memory_source = "LAST_SEEN"
			else:
				_log_memory_state(has_line_of_sight, memory_source, target_player.global_position, last_visible_target_position, trail_target, global_position, true)
				_return_to_wander()
				return

		if absf(target_player.global_position.y - last_visible_target_position.y) > STAIR_VERTICAL_DELTA and last_reachable_target_position != Vector3.ZERO and (memory_source == "LAST_SEEN" or memory_source == "TRAIL" or memory_source == "PATH_CACHE"):
			pursuit_target = last_reachable_target_position
			memory_source = "LAST_REACHABLE"
			NavigationUtils.prune_trail_for_stairs(memorized_target_trail, last_visible_target_position.y, STAIR_VERTICAL_DELTA, STAIR_TRAIL_MAX_POINTS)

		pursuit_target = NavigationUtils.snap_position_to_navigation(self, pursuit_target)
	else:
		pursuit_target = NavigationUtils.snap_position_to_navigation(self, pursuit_target)

	_log_memory_state(has_line_of_sight, memory_source, target_player.global_position, last_visible_target_position, trail_target, pursuit_target)

	var to_target := pursuit_target - global_position
	to_target.y = 0.0

	if to_target.length() <= MEMORY_TARGET_REACHED_DISTANCE:
		velocity.x = 0.0
		velocity.z = 0.0
		if memory_source != "LOS":
			trail_memory_timer = minf(trail_memory_timer, 0.25)
		_log_navigation_state(memory_source, target_player.global_position, pursuit_target, Vector3.ZERO, Vector3.ZERO, 0.0, true)
		_play_run_animation()
		return

	var chase_dir := to_target.normalized()
	var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
	var path_dir: Vector3 = path_result["direction"]
	wall_follow_mode = path_result["wall_follow_mode"]
	if path_dir.length_squared() > 0.001:
		velocity.x = path_dir.x * RUN_SPEED
		velocity.z = path_dir.z * RUN_SPEED
		_log_navigation_state(memory_source, target_player.global_position, pursuit_target, chase_dir, path_dir, to_target.length())
		_face_direction(path_dir, delta, run_turn_speed)
	else:
		velocity.x = chase_dir.x * RUN_SPEED * 0.4
		velocity.z = chase_dir.z * RUN_SPEED * 0.4
		_log_navigation_state(memory_source, target_player.global_position, pursuit_target, chase_dir, path_dir, to_target.length(), true)
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
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	last_reachable_target_position = Vector3.ZERO
	last_visible_target_position = target_player.global_position
	trail_memory_timer = TRAIL_MEMORY_TIME
	trail_sample_timer = 0.0
	memorized_target_trail.clear()
	NavigationUtils.append_trail_point(memorized_target_trail, target_player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
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
		los_state_initialized = false
		current_state = State.WANDER
		_pick_new_direction()
		_reset_direction_timer()
		return

	current_state = State.CHASING
	los_state_initialized = false
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
	los_state_initialized = false
	is_player_in_attack_range = false
	attack_cooldown_timer = 0.0
	attack_count = 0
	trail_memory_timer = 0.0
	trail_sample_timer = 0.0
	los_loss_grace_timer = 0.0
	path_cache_timer = 0.0
	cached_nav_path.clear()
	last_reachable_target_position = Vector3.ZERO
	memorized_target_trail.clear()
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
	print("[ShyMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d trail_timer=%.2f los_timer=%.2f" % [
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

func _log_navigation_state(
	source: String,
	player_pos: Vector3,
	pursuit_target: Vector3,
	chase_dir: Vector3,
	path_dir: Vector3,
	distance_to_target: float,
	force: bool = false
) -> void:
	if not debug_memory_logs:
		return
	if not force and nav_log_timer > 0.0:
		return
	nav_log_timer = NAV_LOG_INTERVAL
	var move_vel := Vector3(velocity.x, 0.0, velocity.z)
	print("[ShyNav] source=%s player=%s memorized_target=%s npc=%s dist=%.2f chase_dir=%s path_dir=%s vel=%s wall_follow=%d trail_size=%d" % [
		source,
		_format_vec3(player_pos),
		_format_vec3(pursuit_target),
		_format_vec3(global_position),
		distance_to_target,
		_format_vec3(chase_dir),
		_format_vec3(path_dir),
		_format_vec3(move_vel),
		wall_follow_mode,
		memorized_target_trail.size(),
	])
