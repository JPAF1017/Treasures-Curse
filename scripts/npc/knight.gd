extends CharacterBody3D

const EnemyDeathLinger := preload("res://scripts/npc/EnemyDeathLingerComponent.gd")
const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")
const EnemyPerceptionMemory := preload("res://scripts/npc/EnemyPerceptionMemoryComponent.gd")

const GRAVITY = 20.0
const WALK_SPEED = 2.0
const RUN_SPEED = 7
const DIR_CHANGE_MIN = 1.5
const DIR_CHANGE_MAX = 4.0
const WALK_BEFORE_IDLE_MIN = 1.5
const WALK_BEFORE_IDLE_MAX = 4.5
const IDLE_DURATION_MIN = 0.6
const IDLE_DURATION_MAX = 1.8
const HIT_REACTION_DURATION = 0.3
const DEATH_LINGER_TIME = 5.0
const STRAFE_SPEED = 3.0
const STRAFE_DIR_CHANGE_MIN = 1.5
const STRAFE_DIR_CHANGE_MAX = 4.0
const RETREAT_SPEED = 2.0
const BUMP_STEP_VELOCITY = 2.0
const BUMP_STEP_COOLDOWN = 0.15
const LOS_MEMORY_TIME = 10.0
const TRAIL_MEMORY_TIME = 5.0
const TRAIL_SAMPLE_INTERVAL = 0.2
const TRAIL_POINT_SPACING = 0.7
const TRAIL_REACHED_DISTANCE = 0.8
const TRAIL_MAX_POINTS = 28
const LOS_LOSS_GRACE_TIME = 0.35
const STAIR_VERTICAL_DELTA = 1.6
const PATH_CACHE_TIME = 1.5
const PATH_CACHE_MAX_POINTS = 10
const STAIR_TRAIL_MAX_POINTS = 14

var move_direction: Vector3 = Vector3.ZERO
var direction_change_timer: float = 0.0
var walk_before_idle_timer: float = 0.0
var idle_timer: float = 0.0
var is_idle: bool = false
@export var health: int = 60
@export var debug_attack_logs: bool = true
var is_dead: bool = false
var hit_reaction_timer: float = 0.0
var animation_player: AnimationPlayer = null
var target_player: Node3D = null
var players_in_detection: Array[Node3D] = []
var players_in_sweetspot: Array[Node3D] = []
var is_strafing: bool = false
var strafe_direction: float = 1.0 # 1.0 = right, -1.0 = left
var strafe_dir_change_timer: float = 0.0
var strafe_linger_timer: float = 0.0
var _last_strafe_direction: float = 0.0
const STRAFE_LINGER_TIME = 1.0
var players_in_distance: Array[Node3D] = []
var is_retreating: bool = false
var _was_retreating: bool = false

# Pathfinding / perception
var space_state: PhysicsDirectSpaceState3D = null
var bump_step_timer: float = 0.0
var wall_follow_mode: int = 0
var los_memory_timer: float = 0.0
var trail_memory_timer: float = 0.0
var trail_sample_timer: float = 0.0
var los_loss_grace_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var last_visible_player_position: Vector3 = Vector3.ZERO
var memorized_target_trail: Array[Vector3] = []
var path_cache_timer: float = 0.0
var cached_nav_path: Array[Vector3] = []
var last_reachable_target_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	randomize()
	space_state = get_world_3d().direct_space_state
	animation_player = _find_animation_player(self)
	_log_attack("ready node=%s health=%d" % [name, health])
	_pick_new_direction()
	_reset_direction_timer()
	_reset_walk_before_idle_timer()
	_play_walk_animation()
	var detection: Area3D = $Detection
	detection.body_entered.connect(_on_detection_body_entered)
	detection.body_exited.connect(_on_detection_body_exited)
	var sweetspot: Area3D = $Sweetspot
	sweetspot.body_entered.connect(_on_sweetspot_body_entered)
	sweetspot.body_exited.connect(_on_sweetspot_body_exited)
	var distance: Area3D = $Distance
	distance.body_entered.connect(_on_distance_body_entered)
	distance.body_exited.connect(_on_distance_body_exited)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	bump_step_timer = max(bump_step_timer - delta, 0.0)
	los_memory_timer = max(los_memory_timer - delta, 0.0)
	trail_memory_timer = max(trail_memory_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	los_loss_grace_timer = max(los_loss_grace_timer - delta, 0.0)
	path_cache_timer = max(path_cache_timer - delta, 0.0)

	# Apply gravity
	EnemyLocomotion.apply_gravity(self, GRAVITY, delta)

	hit_reaction_timer = max(hit_reaction_timer - delta, 0.0)
	if hit_reaction_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_hit_animation()
		move_and_slide()
		return
	
	_update_target()
	if target_player and _is_player_in_distance(target_player):
		_update_retreat_state(delta)
	elif target_player and _is_player_in_sweetspot(target_player):
		strafe_linger_timer = STRAFE_LINGER_TIME
		_update_strafe_state(delta)
	elif target_player and is_strafing and strafe_linger_timer > 0.0:
		strafe_linger_timer -= delta
		_update_strafe_state(delta)
	elif target_player:
		is_strafing = false
		is_retreating = false
		_update_chase_state(delta)
	else:
		is_strafing = false
		is_retreating = false
		_update_wander_state(delta)
	_play_animation()
	bump_step_timer = EnemyLocomotion.try_bump_step(self, bump_step_timer, BUMP_STEP_VELOCITY, BUMP_STEP_COOLDOWN)
	move_and_slide()

func apply_damage(amount: float) -> void:
	_log_attack("apply_damage called amount=%.2f health_before=%d" % [amount, health])

	if is_dead:
		_log_attack("ignored damage because knight is already dead")
		return
	if amount <= 0.0:
		_log_attack("ignored non-positive damage amount=%.2f" % amount)
		return

	health = maxi(health - int(round(amount)), 0)
	_log_attack("damage applied health_after=%d" % health)
	if health <= 0:
		_log_attack("health reached 0, triggering death")
		_die()
		return

	hit_reaction_timer = max(hit_reaction_timer, HIT_REACTION_DURATION)
	_play_hit_animation()

func take_damage(amount: float) -> void:
	_log_attack("take_damage forwarded amount=%.2f" % amount)
	apply_damage(amount)

func _die() -> void:
	if is_dead:
		_log_attack("_die called again while already dead")
		return

	is_dead = true
	health = 0
	hit_reaction_timer = 0.0
	is_idle = false
	velocity = Vector3.ZERO

	await EnemyDeathLinger.run_death_linger(
		self,
		animation_player,
		DEATH_LINGER_TIME,
		[],
		[&"death", &"die"]
	)

func _log_attack(message: String) -> void:
	print("[KnightAttack] %s" % message)

func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body not in players_in_detection:
		players_in_detection.append(body)
		# Reset perception state for new detection
		los_state_initialized = false
		los_loss_grace_timer = 0.0
		path_cache_timer = 0.0
		cached_nav_path.clear()
		last_reachable_target_position = Vector3.ZERO
		trail_memory_timer = TRAIL_MEMORY_TIME
		trail_sample_timer = 0.0
		memorized_target_trail.clear()
		NavigationUtils.append_trail_point(memorized_target_trail, body.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)

func _on_detection_body_exited(body: Node3D) -> void:
	players_in_detection.erase(body)
	if target_player == body:
		target_player = null
		los_state_initialized = false
		los_loss_grace_timer = 0.0
		path_cache_timer = 0.0
		cached_nav_path.clear()
		last_reachable_target_position = Vector3.ZERO
		trail_memory_timer = TRAIL_MEMORY_TIME

func _on_sweetspot_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body not in players_in_sweetspot:
		players_in_sweetspot.append(body)

func _on_sweetspot_body_exited(body: Node3D) -> void:
	players_in_sweetspot.erase(body)

func _is_player_in_sweetspot(player: Node3D) -> bool:
	players_in_sweetspot = players_in_sweetspot.filter(func(p): return is_instance_valid(p))
	return player in players_in_sweetspot

func _on_distance_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body not in players_in_distance:
		players_in_distance.append(body)

func _on_distance_body_exited(body: Node3D) -> void:
	players_in_distance.erase(body)

func _is_player_in_distance(player: Node3D) -> bool:
	players_in_distance = players_in_distance.filter(func(p): return is_instance_valid(p))
	return player in players_in_distance

func _update_target() -> void:
	# Remove freed players
	players_in_detection = players_in_detection.filter(func(p): return is_instance_valid(p))
	if players_in_detection.is_empty():
		target_player = null
		return
	var closest: Node3D = null
	var closest_dist := INF
	for p in players_in_detection:
		var dist := global_position.distance_squared_to(p.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = p
	target_player = closest

func _update_retreat_state(delta: float) -> void:
	if not is_on_floor():
		return
	is_idle = false
	is_strafing = false
	is_retreating = true

	# Face the player
	var to_player := (target_player.global_position - global_position)
	to_player.y = 0.0
	if to_player.length_squared() < 0.001:
		return
	var forward := to_player.normalized()
	_face_direction(forward, delta)

	# Move away from the player (backwards)
	velocity.x = -forward.x * RETREAT_SPEED
	velocity.z = -forward.z * RETREAT_SPEED

func _update_strafe_state(delta: float) -> void:
	if not is_on_floor():
		return
	is_idle = false
	is_retreating = false
	if not is_strafing:
		is_strafing = true
		strafe_direction = [-1.0, 1.0].pick_random()
		strafe_dir_change_timer = randf_range(STRAFE_DIR_CHANGE_MIN, STRAFE_DIR_CHANGE_MAX)

	# Randomly flip strafe direction
	strafe_dir_change_timer -= delta
	if strafe_dir_change_timer <= 0.0:
		strafe_direction = -strafe_direction
		strafe_dir_change_timer = randf_range(STRAFE_DIR_CHANGE_MIN, STRAFE_DIR_CHANGE_MAX)

	# Face the player
	var to_player := (target_player.global_position - global_position)
	to_player.y = 0.0
	if to_player.length_squared() < 0.001:
		return
	var forward := to_player.normalized()
	_face_direction(forward, delta)

	# Move perpendicular (strafe)
	var strafe_vec := Vector3(-forward.z, 0.0, forward.x) * strafe_direction
	velocity.x = strafe_vec.x * STRAFE_SPEED
	velocity.z = strafe_vec.z * STRAFE_SPEED

func _update_chase_state(delta: float) -> void:
	if not is_on_floor():
		return
	is_idle = false
	is_strafing = false

	var pursuit_target := _get_pursuit_target()
	var nav_result := NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
	var dir: Vector3 = nav_result.get("direction", Vector3.ZERO)
	wall_follow_mode = int(nav_result.get("wall_follow_mode", 0))

	if dir.length_squared() > 0.001:
		dir = dir.normalized()
		velocity.x = dir.x * RUN_SPEED
		velocity.z = dir.z * RUN_SPEED
		_face_direction(dir, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _get_pursuit_target() -> Vector3:
	if not target_player or not is_instance_valid(target_player):
		# Fall back to last known position or trail
		return _get_memory_pursuit_target()

	var has_los := NavigationUtils.has_line_of_sight_to(self, target_player.global_position + Vector3(0, 1.0, 0), space_state, [self, target_player])
	var los_state := EnemyPerceptionMemory.update_los_trail_state(
		has_los,
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
	has_los = bool(los_state.get("effective_has_line_of_sight", has_los))
	los_state_initialized = bool(los_state.get("los_state_initialized", los_state_initialized))
	previous_has_line_of_sight = bool(los_state.get("previous_has_line_of_sight", previous_has_line_of_sight))
	los_loss_grace_timer = float(los_state.get("los_loss_grace_timer", los_loss_grace_timer))
	trail_memory_timer = float(los_state.get("trail_memory_timer", trail_memory_timer))
	trail_sample_timer = float(los_state.get("trail_sample_timer", trail_sample_timer))

	if has_los:
		var snapped := NavigationUtils.snap_position_to_navigation(self, target_player.global_position)
		last_visible_player_position = snapped
		last_reachable_target_position = snapped
		cached_nav_path = NavigationUtils.build_short_path_cache(self, snapped, PATH_CACHE_MAX_POINTS)
		path_cache_timer = PATH_CACHE_TIME
		los_memory_timer = LOS_MEMORY_TIME
		trail_memory_timer = TRAIL_MEMORY_TIME
		if trail_sample_timer <= 0.0:
			NavigationUtils.append_trail_point(memorized_target_trail, target_player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
			trail_sample_timer = TRAIL_SAMPLE_INTERVAL
		return snapped

	# No LOS — use memory
	return _get_memory_pursuit_target()

func _get_memory_pursuit_target() -> Vector3:
	var pursuit_target := last_visible_player_position

	if path_cache_timer > 0.0 and not cached_nav_path.is_empty():
		var cache_result := NavigationUtils.get_cached_path_target(global_position, cached_nav_path, TRAIL_REACHED_DISTANCE)
		if bool(cache_result.get("has_target", false)):
			pursuit_target = cache_result["target"]
			return NavigationUtils.snap_position_to_navigation(self, pursuit_target)

	if trail_memory_timer > 0.0 and not memorized_target_trail.is_empty():
		var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
		if bool(trail_result.get("has_target", false)):
			pursuit_target = trail_result["target"]

	return NavigationUtils.snap_position_to_navigation(self, pursuit_target)

func _update_wander_state(delta: float) -> void:
	# Can only wander when on the ground
	var can_wander := is_on_floor()
	
	if is_idle and can_wander:
		idle_timer = max(idle_timer - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		if idle_timer <= 0.0:
			is_idle = false
			_reset_walk_before_idle_timer()
			_pick_new_direction()
			_reset_direction_timer()
		return
	elif is_idle and not can_wander:
		# Stop idling if airborne
		is_idle = false
	
	if can_wander:
		walk_before_idle_timer = max(walk_before_idle_timer - delta, 0.0)
	else:
		walk_before_idle_timer = max(walk_before_idle_timer, 0.1)
	
	# Transition to idle if walk timer expired
	if can_wander and walk_before_idle_timer <= 0.0:
		is_idle = true
		idle_timer = randf_range(IDLE_DURATION_MIN, IDLE_DURATION_MAX)
		velocity.x = 0.0
		velocity.z = 0.0
		return
	
	# Update direction
	direction_change_timer -= delta
	if direction_change_timer <= 0.0 or is_on_wall():
		_pick_new_direction()
		_reset_direction_timer()
	
	# Apply movement
	velocity.x = move_direction.x * WALK_SPEED
	velocity.z = move_direction.z * WALK_SPEED
	
	if move_direction.length_squared() > 0.001:
		_face_direction(move_direction, delta)

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

func _play_animation() -> void:
	if animation_player and animation_player.current_animation == "hit" and animation_player.is_playing():
		return
	if is_retreating and is_on_floor():
		_play_retreat_animation()
	elif is_strafing and is_on_floor():
		_play_strafe_animation()
	elif target_player and is_on_floor():
		_play_run_animation()
	elif is_idle:
		_play_idle_animation()
	elif is_on_floor():
		_play_walk_animation()

func _play_retreat_animation() -> void:
	if not animation_player:
		return
	if animation_player.has_animation("walk"):
		var state_changed := not _was_retreating
		_was_retreating = true
		var needs_restart := animation_player.current_animation != "walk" or not animation_player.is_playing() or state_changed
		if needs_restart:
			animation_player.speed_scale = 1.0
			animation_player.play_backwards("walk")

func _play_strafe_animation() -> void:
	if not animation_player:
		return
	if animation_player.has_animation("strafe"):
		var direction_changed := strafe_direction != _last_strafe_direction
		_last_strafe_direction = strafe_direction
		var needs_restart := animation_player.current_animation != "strafe" or not animation_player.is_playing() or direction_changed
		if strafe_direction > 0.0:
			if needs_restart:
				animation_player.speed_scale = 1.0
				animation_player.play_backwards("strafe")
		else:
			if needs_restart:
				animation_player.speed_scale = 1.0
				animation_player.play("strafe")
	else:
		_play_walk_animation()

func _play_run_animation() -> void:
	if not animation_player:
		return
	# Use "run" animation if available, otherwise speed up "walk"
	if animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("run")
	else:
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.play("walk")
		animation_player.speed_scale = RUN_SPEED / WALK_SPEED

func _play_walk_animation() -> void:
	if animation_player and animation_player.has_animation("walk"):
		var was_retreat := _was_retreating
		_was_retreating = false
		if animation_player.current_animation != "walk" or not animation_player.is_playing() or was_retreat:
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

func _play_hit_animation() -> void:
	if not animation_player:
		return
	if not animation_player.has_animation("hit"):
		return

	if animation_player.current_animation != "hit" or not animation_player.is_playing():
		animation_player.speed_scale = 1.0
		animation_player.play("hit")
		animation_player.seek(0.0, true)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null

func angle_difference(from: float, to: float) -> float:
	var diff := fmod(to - from + PI, TAU) - PI
	return diff if diff >= -PI else diff + TAU
