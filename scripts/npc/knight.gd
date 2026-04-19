extends CharacterBody3D

const EnemyDeathLinger := preload("res://scripts/npc/EnemyDeathLingerComponent.gd")
const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")

const GRAVITY = 20.0
const WALK_SPEED = 4.0
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
const LOS_LOSS_CHASE_TIME = 5.0
const SLIDE_ATTACK_COOLDOWN = 30.0
const SLIDE_ATTACK_SPEED = 9.0
const SLIDE_ATTACK_DURATION = 0.6
const SLIDE_ATTACK_DAMAGE = 25.0
const SLIDE_ATTACK_KNOCKBACK = 12.0
const SLIDE_ATTACK_ACTIVE_FRAMES = Vector2i(44, 53)
const SLIDE_ATTACK_ANIMATION_FPS = 30.0
const ATTACK_COOLDOWN = 2.0
const ATTACK_ANIMATION_FPS = 30.0
const KICK_DAMAGE = 10.0
const KICK_KNOCKBACK_STRENGTH = 20.0
const KICK_ACTIVE_FRAMES = Vector2i(18, 26)
const VERT_SLASH_DAMAGE = 20.0
const VERT_SLASH_ACTIVE_FRAMES = Vector2i(24, 30)
const HEAVY_SMASH_DAMAGE = 50.0
const HEAVY_SMASH_ACTIVE_FRAMES = Vector2i(58, 68)

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

# Slide attack
var slide_attack_cooldown_timer: float = 0.0
var is_slide_attacking: bool = false
var slide_attack_timer: float = 0.0
var slide_attack_direction: Vector3 = Vector3.ZERO
var has_dealt_slide_damage: bool = false
var slide_slash_area: Area3D = null
var slide_slash_activate_area: Area3D = null
var players_in_slide_activate: Array[Node3D] = []

# Melee attacks (VertSlash, Kick, HeavySmash)
var attack_cooldown_timer: float = 0.0
var is_attacking: bool = false
var current_attack_type: int = 0 # 1=kick, 2=vertSlash, 3=heavySmash
var has_dealt_damage_this_attack: bool = false
var attacks_activation_area: Area3D = null
var vert_slash_area: Area3D = null
var kick_area: Area3D = null
var heavy_smash_area: Area3D = null
var players_in_attacks_activation: Array[Node3D] = []

# Pathfinding / perception
var space_state: PhysicsDirectSpaceState3D = null
var bump_step_timer: float = 0.0
var wall_follow_mode: int = 0
var los_lost_timer: float = 0.0
var trail_sample_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var last_visible_player_position: Vector3 = Vector3.ZERO
var memorized_target_trail: Array[Vector3] = []

func _ready() -> void:
	top_level = true
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
	var slide_slash_node: Node3D = get_node_or_null("SlideSlash")
	if slide_slash_node:
		slide_slash_area = slide_slash_node.get_node_or_null("SlideSlash")
		slide_slash_activate_area = slide_slash_node.get_node_or_null("SlideSlashActivate")
	if slide_slash_activate_area:
		slide_slash_activate_area.body_entered.connect(_on_slide_activate_body_entered)
		slide_slash_activate_area.body_exited.connect(_on_slide_activate_body_exited)
	var attacks_node: Node3D = get_node_or_null("Attacks")
	if attacks_node:
		vert_slash_area = attacks_node.get_node_or_null("VertSlash")
		kick_area = attacks_node.get_node_or_null("Kick")
		heavy_smash_area = attacks_node.get_node_or_null("HeavySmash")
		attacks_activation_area = attacks_node.get_node_or_null("AttacksActivation")
	if attacks_activation_area:
		attacks_activation_area.body_entered.connect(_on_attacks_activation_body_entered)
		attacks_activation_area.body_exited.connect(_on_attacks_activation_body_exited)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	bump_step_timer = max(bump_step_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	slide_attack_cooldown_timer = max(slide_attack_cooldown_timer - delta, 0.0)
	attack_cooldown_timer = max(attack_cooldown_timer - delta, 0.0)

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

	# Slide attack in progress takes priority
	if is_slide_attacking:
		_update_slide_attack(delta)
		_play_animation()
		move_and_slide()
		return

	# Check if we should initiate a slide attack
	if _can_start_slide_attack():
		_start_slide_attack()
		_update_slide_attack(delta)
		_play_animation()
		move_and_slide()
		return

	# Melee attack in progress — let animation finish
	if is_attacking and animation_player:
		if not animation_player.is_playing():
			is_attacking = false
			attack_cooldown_timer = ATTACK_COOLDOWN
	if is_attacking:
		_update_attack_state(delta)
		_play_animation()
		move_and_slide()
		return

	# Check if we should initiate a melee attack
	if _can_start_melee_attack():
		_start_melee_attack(delta)
		_play_animation()
		move_and_slide()
		return

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
		los_lost_timer = 0.0
		trail_sample_timer = 0.0
		memorized_target_trail.clear()
		NavigationUtils.append_trail_point(memorized_target_trail, body.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)

func _on_detection_body_exited(body: Node3D) -> void:
	players_in_detection.erase(body)
	if target_player == body:
		target_player = null
		los_state_initialized = false
		los_lost_timer = LOS_LOSS_CHASE_TIME

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
		# No target - follow trail or last known position
		return _get_memory_pursuit_target()

	var has_los := NavigationUtils.has_line_of_sight_to(self, target_player.global_position + Vector3(0, 1.0, 0), space_state, [self, target_player])

	# Track LOS transitions
	if not los_state_initialized:
		previous_has_line_of_sight = has_los
		los_state_initialized = true
	if has_los and not previous_has_line_of_sight:
		los_lost_timer = 0.0
	elif not has_los and previous_has_line_of_sight:
		los_lost_timer = LOS_LOSS_CHASE_TIME
		memorized_target_trail.clear()
		NavigationUtils.append_trail_point(memorized_target_trail, last_visible_player_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
	previous_has_line_of_sight = has_los

	if has_los:
		los_lost_timer = 0.0
		last_visible_player_position = target_player.global_position
		if trail_sample_timer <= 0.0:
			NavigationUtils.append_trail_point(memorized_target_trail, target_player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
			trail_sample_timer = TRAIL_SAMPLE_INTERVAL
		return target_player.global_position

	# No LOS — use memory
	return _get_memory_pursuit_target()

func _get_memory_pursuit_target() -> Vector3:
	los_lost_timer -= get_physics_process_delta_time()
	if los_lost_timer <= 0.0:
		return global_position

	var pursuit_target := last_visible_player_position
	var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
	if bool(trail_result.get("has_target", false)):
		pursuit_target = trail_result["target"]

	var to_target := pursuit_target - global_position
	to_target.y = 0.0
	if to_target.length() <= 0.6:
		return global_position

	return pursuit_target

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
	if is_slide_attacking:
		_play_slide_attack_animation()
	elif is_attacking:
		pass # Attack animation already playing, don't interrupt
	elif is_retreating and is_on_floor():
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

func _play_slide_attack_animation() -> void:
	if not animation_player:
		return
	# Use "slideSlash" if available, otherwise speed up "run"
	if animation_player.has_animation("slideSlash"):
		if animation_player.current_animation != "slideSlash" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("slideSlash")
	elif animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 1.8
			animation_player.play("run")
	elif animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.speed_scale = 2.5
			animation_player.play("walk")

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

# --- Slide Attack ---

func _on_slide_activate_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body not in players_in_slide_activate:
		players_in_slide_activate.append(body)

func _on_slide_activate_body_exited(body: Node3D) -> void:
	players_in_slide_activate.erase(body)

func _can_start_slide_attack() -> bool:
	if slide_attack_cooldown_timer > 0.0:
		return false
	if not target_player or not is_instance_valid(target_player):
		return false
	players_in_slide_activate = players_in_slide_activate.filter(func(p): return is_instance_valid(p))
	if target_player not in players_in_slide_activate:
		return false
	if not is_on_floor():
		return false
	return true

func _start_slide_attack() -> void:
	is_slide_attacking = true
	slide_attack_timer = SLIDE_ATTACK_DURATION
	has_dealt_slide_damage = false
	is_idle = false
	is_strafing = false
	is_retreating = false

	var to_player := (target_player.global_position - global_position)
	to_player.y = 0.0
	if to_player.length_squared() > 0.001:
		slide_attack_direction = to_player.normalized()
	else:
		slide_attack_direction = -transform.basis.z.normalized()

	_log_attack("slide_attack started direction=(%.2f, %.2f, %.2f)" % [slide_attack_direction.x, slide_attack_direction.y, slide_attack_direction.z])
	_play_slide_attack_animation()

func _update_slide_attack(delta: float) -> void:
	# Face slide direction
	if slide_attack_direction.length_squared() > 0.001:
		_face_direction(slide_attack_direction, delta)

	# Slide forward
	velocity.x = slide_attack_direction.x * SLIDE_ATTACK_SPEED
	velocity.z = slide_attack_direction.z * SLIDE_ATTACK_SPEED

	# Try to deal damage
	if not has_dealt_slide_damage:
		_try_apply_slide_damage()

	# End slide attack when animation finishes
	var anim_playing := animation_player and animation_player.current_animation == "slideSlash" and animation_player.is_playing()
	if not anim_playing:
		_end_slide_attack()

func _is_in_slide_active_frames() -> bool:
	if not animation_player or animation_player.current_animation != "slideSlash":
		return false
	var pos := animation_player.current_animation_position
	var current_frame := int(pos * SLIDE_ATTACK_ANIMATION_FPS)
	return current_frame >= SLIDE_ATTACK_ACTIVE_FRAMES.x and current_frame <= SLIDE_ATTACK_ACTIVE_FRAMES.y

func _try_apply_slide_damage() -> void:
	if slide_slash_area == null:
		return
	if not _is_in_slide_active_frames():
		return
	for body in slide_slash_area.get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("player"):
			if body.has_method("apply_damage"):
				body.call("apply_damage", SLIDE_ATTACK_DAMAGE)
				_log_attack("slide_attack hit player damage=%.1f" % SLIDE_ATTACK_DAMAGE)
			if body.has_method("apply_knockback"):
				var knock_dir := (body.global_position - global_position).normalized()
				body.call("apply_knockback", knock_dir, SLIDE_ATTACK_KNOCKBACK)
			has_dealt_slide_damage = true
			return

func _end_slide_attack() -> void:
	is_slide_attacking = false
	slide_attack_timer = 0.0
	slide_attack_cooldown_timer = SLIDE_ATTACK_COOLDOWN
	velocity.x = 0.0
	velocity.z = 0.0
	_log_attack("slide_attack ended cooldown=%.1fs" % SLIDE_ATTACK_COOLDOWN)

# --- Melee Attacks (Kick, VertSlash, HeavySmash) ---

func _on_attacks_activation_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body not in players_in_attacks_activation:
		players_in_attacks_activation.append(body)

func _on_attacks_activation_body_exited(body: Node3D) -> void:
	players_in_attacks_activation.erase(body)

func _can_start_melee_attack() -> bool:
	if attack_cooldown_timer > 0.0:
		return false
	if is_attacking or is_slide_attacking:
		return false
	if not target_player or not is_instance_valid(target_player):
		return false
	players_in_attacks_activation = players_in_attacks_activation.filter(func(p): return is_instance_valid(p))
	if target_player not in players_in_attacks_activation:
		return false
	if not is_on_floor():
		return false
	return true

func _start_melee_attack(delta: float) -> void:
	is_attacking = true
	has_dealt_damage_this_attack = false
	is_idle = false
	is_strafing = false
	is_retreating = false
	velocity.x = 0.0
	velocity.z = 0.0

	# Face the target
	var to_player := (target_player.global_position - global_position)
	to_player.y = 0.0
	if to_player.length_squared() > 0.001:
		_face_direction(to_player.normalized(), delta)

	# Pick a random attack: 1=kick, 2=vertSlash, 3=heavySmash
	# Kick is more frequent when slide attack is off cooldown
	if slide_attack_cooldown_timer <= 0.0:
		var roll := randi_range(1, 5)
		if roll <= 3:
			current_attack_type = 1 # kick (60%)
		elif roll == 4:
			current_attack_type = 2 # vertSlash (20%)
		else:
			current_attack_type = 3 # heavySmash (20%)
	else:
		current_attack_type = randi_range(1, 3)
	var attack_name: String
	match current_attack_type:
		1:
			attack_name = "kick"
		2:
			attack_name = "vertSlash"
		3:
			attack_name = "heavySmash"
		_:
			attack_name = "kick"

	if animation_player and animation_player.has_animation(attack_name):
		animation_player.speed_scale = 1.0
		animation_player.play(attack_name)
		_log_attack("melee_attack started type=%s" % attack_name)
	else:
		# Animation missing, cancel attack
		is_attacking = false
		attack_cooldown_timer = ATTACK_COOLDOWN
		_log_attack("melee_attack cancelled — animation '%s' not found" % attack_name)

func _update_attack_state(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	# Try to deal damage during active frames
	if not has_dealt_damage_this_attack:
		_try_apply_melee_damage()

func _get_active_attack_area() -> Area3D:
	match current_attack_type:
		1:
			return kick_area
		2:
			return vert_slash_area
		3:
			return heavy_smash_area
	return null

func _get_active_frames_for_attack() -> Vector2i:
	match current_attack_type:
		1:
			return KICK_ACTIVE_FRAMES
		2:
			return VERT_SLASH_ACTIVE_FRAMES
		3:
			return HEAVY_SMASH_ACTIVE_FRAMES
	return Vector2i(0, 0)

func _is_in_melee_active_frames() -> bool:
	if animation_player == null or not animation_player.is_playing():
		return false
	if ATTACK_ANIMATION_FPS <= 0.0:
		return false
	var anim := animation_player.get_animation(animation_player.current_animation)
	if anim == null:
		return false
	var total_frames := int(round(anim.length * ATTACK_ANIMATION_FPS))
	if total_frames < 1:
		total_frames = 1
	var current_frame := int(round(animation_player.current_animation_position * ATTACK_ANIMATION_FPS))
	current_frame = int(posmod(current_frame, total_frames))
	var frame_range := _get_active_frames_for_attack()
	return current_frame >= frame_range.x and current_frame <= frame_range.y

func _try_apply_melee_damage() -> void:
	var area := _get_active_attack_area()
	if area == null:
		return
	if not _is_in_melee_active_frames():
		return
	for body in area.get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("player"):
			_apply_melee_effect(body)
			has_dealt_damage_this_attack = true
			return

func _apply_melee_effect(target: CharacterBody3D) -> void:
	match current_attack_type:
		1: # Kick: 10 damage + knockback
			if target.has_method("apply_damage"):
				target.call("apply_damage", KICK_DAMAGE)
				_log_attack("kick hit player damage=%.1f" % KICK_DAMAGE)
			if target.has_method("apply_knockback"):
				var knock_dir := (target.global_position - global_position).normalized()
				target.call("apply_knockback", knock_dir, KICK_KNOCKBACK_STRENGTH)
		2: # VertSlash: 20 damage
			if target.has_method("apply_damage"):
				target.call("apply_damage", VERT_SLASH_DAMAGE)
				_log_attack("vertSlash hit player damage=%.1f" % VERT_SLASH_DAMAGE)
		3: # HeavySmash: 50 damage
			if target.has_method("apply_damage"):
				target.call("apply_damage", HEAVY_SMASH_DAMAGE)
				_log_attack("heavySmash hit player damage=%.1f" % HEAVY_SMASH_DAMAGE)
