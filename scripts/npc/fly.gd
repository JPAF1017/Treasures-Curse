extends CharacterBody3D

const EnemyDeathLinger := preload("res://scripts/npc/EnemyDeathLingerComponent.gd")
const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")

const GRAVITY = 20.0
const WALK_SPEED = 2.0
const FLY_SPEED = 3.5
const DIR_CHANGE_MIN = 1.5
const DIR_CHANGE_MAX = 4.0
const WALK_BEFORE_IDLE_MIN = 1.5
const WALK_BEFORE_IDLE_MAX = 4.5
const IDLE_DURATION_MIN = 0.6
const IDLE_DURATION_MAX = 1.8
const FLOAT_HEIGHT_MIN = 1.5
const FLOAT_HEIGHT_MAX = 3.0
const FLOAT_SPEED = 3.0
const GROUND_RAYCAST_DISTANCE = 50.0
const ASCENT_STOP_EPSILON = 0.02
const HIT_REACTION_DURATION = 0.3
const DEATH_LINGER_TIME = 5.0
const FLY_THRESHOLD = 10
const CHASE_SPEED = 3.0
const CHASE_FLY_SPEED = 5.0
const BITE_DAMAGE = 10.0
const BITE_KNOCKBACK = 6.0
const BITE_ACTIVE_FRAMES = Vector2i(8, 24)
const BITE_ANIMATION_FPS = 30.0
const BITE_COOLDOWN = 3.0
const BUMP_STEP_VELOCITY = 2.0
const BUMP_STEP_COOLDOWN = 0.15
const LOS_MEMORY_TIME = 10.0
const TRAIL_MEMORY_TIME = 5.0
const TRAIL_SAMPLE_INTERVAL = 0.2
const TRAIL_POINT_SPACING = 0.7
const TRAIL_REACHED_DISTANCE = 0.8
const TRAIL_MAX_POINTS = 28
const LOS_LOSS_CHASE_TIME = 5.0

@export var health: int = 20
var move_direction: Vector3 = Vector3.ZERO
var direction_change_timer: float = 0.0
var walk_before_idle_timer: float = 0.0
var idle_timer: float = 0.0
var is_idle: bool = false
var is_dead: bool = false
var hit_reaction_timer: float = 0.0
var animation_player: AnimationPlayer = null
var ground_collision: CollisionShape3D = null
var vert_fly_collision: CollisionShape3D = null
var hor_fly_collision: CollisionShape3D = null
var hurtbox_ground: Area3D = null
var hurtbox_vert_fly: Area3D = null
var ground_height: float = 0.0
var is_floating: bool = false
var target_height_above_ground: float = 0.0
var is_preparing_to_fly: bool = false
var transition_anim_timer: float = 0.0
var has_taken_off: bool = false
var is_falling_dead: bool = false
var detection_area: Area3D = null
var bite_area: Area3D = null
var players_in_detection: Array = []
var target_player: Node3D = null
var is_biting: bool = false
var has_dealt_bite_damage: bool = false
var bite_cooldown_timer: float = 0.0
var space_state: PhysicsDirectSpaceState3D = null
var bump_step_timer: float = 0.0
var los_lost_timer: float = 0.0
var last_visible_player_position: Vector3 = Vector3.ZERO
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var wall_follow_mode: int = 0

func _ready() -> void:
	randomize()
	space_state = get_world_3d().direct_space_state
	animation_player = _find_animation_player(self)
	ground_collision = $ground
	vert_fly_collision = $vertFly
	hor_fly_collision = $horFly
	var hurtbox: Node3D = get_node_or_null("Hurtbox")
	if hurtbox:
		hurtbox_ground = hurtbox.get_node_or_null("Ground")
		hurtbox_vert_fly = hurtbox.get_node_or_null("VertFly")
	if hurtbox_ground:
		hurtbox_ground.add_to_group("hurtbox")
		hurtbox_ground.collision_layer = 2
		hurtbox_ground.collision_mask = 0
	if hurtbox_vert_fly:
		hurtbox_vert_fly.add_to_group("hurtbox")
		hurtbox_vert_fly.collision_layer = 2
		hurtbox_vert_fly.collision_mask = 0
	detection_area = get_node_or_null("Detection")
	bite_area = get_node_or_null("Attacks/Bite")
	if detection_area:
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)
	ground_height = global_position.y
	_pick_new_direction()
	_reset_direction_timer()
	_reset_walk_before_idle_timer()
	_update_collision_mode()
	_play_walk_animation()

func _physics_process(delta: float) -> void:
	if is_dead and is_falling_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		if is_on_floor():
			is_falling_dead = false
			_finish_death()
		return
	if is_dead:
		return

	_update_target_player()
	bite_cooldown_timer = max(bite_cooldown_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)

	# Bite attack — plays to completion
	if is_biting:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_floating:
			if not is_on_floor():
				velocity.y -= GRAVITY * delta
			else:
				velocity.y = 0.0
		if not has_dealt_bite_damage:
			_try_apply_bite_damage()
		if animation_player and not animation_player.is_playing():
			is_biting = false
			has_dealt_bite_damage = false
			bite_cooldown_timer = BITE_COOLDOWN
		move_and_slide()
		return

	hit_reaction_timer = max(hit_reaction_timer - delta, 0.0)
	var hit_anim_playing := animation_player and (
		(animation_player.current_animation == "hitReaction" and animation_player.is_playing()) or
		(animation_player.current_animation == "idleFlyHitReaction" and animation_player.is_playing())
	)
	if hit_reaction_timer > 0.0 or hit_anim_playing:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_hit_animation()
		if not is_floating:
			if not is_on_floor():
				velocity.y -= GRAVITY * delta
			else:
				velocity.y = 0.0
		move_and_slide()
		return

	# Trigger flight when HP drops to threshold
	if not has_taken_off and health <= FLY_THRESHOLD and health > 0:
		_start_flying()

	# Handle takeoff transition animation
	if is_preparing_to_fly:
		transition_anim_timer = max(transition_anim_timer - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		if transition_anim_timer <= 0.0:
			is_preparing_to_fly = false
			is_floating = true
			_update_ground_height_from_raycast()
			target_height_above_ground = randf_range(FLOAT_HEIGHT_MIN, FLOAT_HEIGHT_MAX)
		move_and_slide()
		return

	# Check for bite attack
	if not is_biting and _can_bite():
		_start_bite()
		move_and_slide()
		return

	var pursuit_target := _compute_pursuit_target()

	if is_floating:
		if target_player or pursuit_target != Vector3.ZERO:
			_update_chase_float_state(delta, pursuit_target)
		else:
			_update_float_state(delta)
	else:
		# Ground gravity
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		if target_player or pursuit_target != Vector3.ZERO:
			_update_chase_ground_state(delta, pursuit_target)
		else:
			_update_wander_state(delta)

	bump_step_timer = EnemyLocomotion.try_bump_step(self, bump_step_timer, BUMP_STEP_VELOCITY, BUMP_STEP_COOLDOWN)
	_update_collision_mode()
	move_and_slide()

func _update_float_state(delta: float) -> void:
	# Hover at target height above ground
	_update_ground_height_from_raycast()
	var desired_world_height = ground_height + target_height_above_ground
	var height_diff = desired_world_height - global_position.y
	if abs(height_diff) <= ASCENT_STOP_EPSILON:
		velocity.y = 0.0
	else:
		velocity.y = height_diff * FLOAT_SPEED

	# Wander while flying
	direction_change_timer -= delta
	if direction_change_timer <= 0.0:
		_pick_new_direction()
		_reset_direction_timer()

	velocity.x = move_direction.x * FLY_SPEED
	velocity.z = move_direction.z * FLY_SPEED

	if move_direction.length_squared() > 0.001:
		_face_direction(move_direction, delta)

	_play_air_animation()

func _update_wander_state(delta: float) -> void:
	var can_wander := is_on_floor()

	if is_idle and can_wander:
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
	elif is_idle and not can_wander:
		is_idle = false

	if can_wander:
		walk_before_idle_timer = max(walk_before_idle_timer - delta, 0.0)
	else:
		walk_before_idle_timer = max(walk_before_idle_timer, 0.1)

	if can_wander and walk_before_idle_timer <= 0.0:
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

	_play_walk_animation()

func _update_chase_ground_state(delta: float, pursuit_target: Vector3) -> void:
	var dir_to_target := pursuit_target - global_position
	dir_to_target.y = 0.0
	if dir_to_target.length() <= 0.4:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_idle_animation()
		return
	var path_result := NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
	var path_dir: Vector3 = path_result["direction"]
	wall_follow_mode = path_result["wall_follow_mode"]
	if path_dir.length_squared() > 0.001:
		velocity.x = path_dir.x * CHASE_SPEED
		velocity.z = path_dir.z * CHASE_SPEED
		_face_direction(path_dir, delta)
	else:
		var fallback := dir_to_target.normalized()
		velocity.x = fallback.x * CHASE_SPEED * 0.4
		velocity.z = fallback.z * CHASE_SPEED * 0.4
		_face_direction(fallback, delta)
	_play_walk_animation()

func _update_chase_float_state(delta: float, pursuit_target: Vector3) -> void:
	# Hover
	_update_ground_height_from_raycast()
	var desired_world_height = ground_height + target_height_above_ground
	var height_diff = desired_world_height - global_position.y
	if abs(height_diff) <= ASCENT_STOP_EPSILON:
		velocity.y = 0.0
	else:
		velocity.y = height_diff * FLOAT_SPEED
	# Chase horizontally with pathfinding
	var dir_to_target := pursuit_target - global_position
	dir_to_target.y = 0.0
	if dir_to_target.length() <= 0.4:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_air_animation()
		return
	var path_result := NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
	var path_dir: Vector3 = path_result["direction"]
	wall_follow_mode = path_result["wall_follow_mode"]
	if path_dir.length_squared() > 0.001:
		velocity.x = path_dir.x * CHASE_FLY_SPEED
		velocity.z = path_dir.z * CHASE_FLY_SPEED
		_face_direction(path_dir, delta)
	else:
		var fallback := dir_to_target.normalized()
		velocity.x = fallback.x * CHASE_FLY_SPEED * 0.4
		velocity.z = fallback.z * CHASE_FLY_SPEED * 0.4
		_face_direction(fallback, delta)
	_play_air_animation()

func _start_flying() -> void:
	has_taken_off = true
	is_preparing_to_fly = true
	is_idle = false
	velocity.x = 0.0
	velocity.z = 0.0
	move_direction = Vector3.ZERO
	_play_takeoff_animation()

# --- Damage / Death ---

func apply_damage(amount: float) -> void:
	if is_dead:
		return
	if amount <= 0.0:
		return
	health = maxi(health - int(round(amount)), 0)
	if health <= 0:
		_die()
		return
	hit_reaction_timer = max(hit_reaction_timer, HIT_REACTION_DURATION)
	_play_hit_animation()

func take_damage(amount: float) -> void:
	apply_damage(amount)

# --- Detection / Targeting ---

func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body not in players_in_detection:
		players_in_detection.append(body)

func _on_detection_body_exited(body: Node3D) -> void:
	players_in_detection.erase(body)
	if target_player == body:
		target_player = null
		los_state_initialized = false
		los_lost_timer = LOS_LOSS_CHASE_TIME

func _update_target_player() -> void:
	# Remove invalid entries
	players_in_detection = players_in_detection.filter(func(p): return is_instance_valid(p))
	if players_in_detection.is_empty():
		target_player = null
		return
	var closest: Node3D = null
	var closest_dist := INF
	for p in players_in_detection:
		var d := global_position.distance_squared_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = p
	if closest != target_player:
		los_state_initialized = false
		previous_has_line_of_sight = false
		los_lost_timer = 0.0
		memorized_target_trail.clear()
	target_player = closest

# --- Pursuit / Pathfinding ---

func _compute_pursuit_target() -> Vector3:
	if not target_player or not is_instance_valid(target_player):
		# No active target — follow trail if timer still running
		if los_lost_timer > 0.0:
			los_lost_timer -= get_physics_process_delta_time()
			if los_lost_timer <= 0.0:
				return Vector3.ZERO
			var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
			if bool(trail_result.get("has_target", false)):
				return trail_result["target"]
			if last_visible_player_position != Vector3.ZERO:
				var to_last := last_visible_player_position - global_position
				to_last.y = 0.0
				if to_last.length() > 0.4:
					return last_visible_player_position
		return Vector3.ZERO

	# Has active target — check LOS
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

	# Lost LOS — follow trail for up to LOS_LOSS_CHASE_TIME seconds
	los_lost_timer -= get_physics_process_delta_time()
	if los_lost_timer <= 0.0:
		return Vector3.ZERO

	var pursuit := last_visible_player_position
	var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
	if bool(trail_result.get("has_target", false)):
		pursuit = trail_result["target"]

	var to_target := pursuit - global_position
	to_target.y = 0.0
	if to_target.length() <= 0.6:
		return Vector3.ZERO

	return pursuit

# --- Bite Attack ---

func _can_bite() -> bool:
	if not bite_area:
		return false
	if bite_cooldown_timer > 0.0:
		return false
	for body in bite_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false

func _start_bite() -> void:
	is_biting = true
	has_dealt_bite_damage = false
	velocity.x = 0.0
	velocity.z = 0.0
	if animation_player and animation_player.has_animation("bite"):
		animation_player.speed_scale = 1.0
		animation_player.play("bite")

func _try_apply_bite_damage() -> void:
	if not _is_in_bite_active_frames():
		return
	if not bite_area:
		return
	for body in bite_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			if body.has_method("apply_damage"):
				body.apply_damage(BITE_DAMAGE)
			if body.has_method("apply_knockback"):
				var kb_dir := (body.global_position - global_position).normalized()
				body.apply_knockback(kb_dir, BITE_KNOCKBACK)
			has_dealt_bite_damage = true
			return

func _is_in_bite_active_frames() -> bool:
	if not animation_player or animation_player.current_animation != "bite":
		return false
	var anim := animation_player.get_animation("bite")
	if not anim:
		return false
	var total_frames := int(round(anim.length * BITE_ANIMATION_FPS))
	var current_frame := int(round(animation_player.current_animation_position * BITE_ANIMATION_FPS))
	current_frame = int(posmod(current_frame, total_frames))
	return current_frame >= BITE_ACTIVE_FRAMES.x and current_frame <= BITE_ACTIVE_FRAMES.y

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	health = 0
	hit_reaction_timer = 0.0
	is_idle = false
	var was_floating := is_floating
	is_floating = false
	is_preparing_to_fly = false
	velocity = Vector3.ZERO

	if was_floating:
		# Fall to the ground first
		is_falling_dead = true
		if ground_collision:
			ground_collision.disabled = false
		if hor_fly_collision:
			hor_fly_collision.disabled = true
		if animation_player and animation_player.has_animation("idleFlyDeath"):
			animation_player.speed_scale = 1.0
			animation_player.play("idleFlyDeath")
	else:
		await EnemyDeathLinger.run_death_linger(
			self,
			animation_player,
			DEATH_LINGER_TIME,
			[],
			[&"death"]
		)

func _finish_death() -> void:
	velocity = Vector3.ZERO
	await EnemyDeathLinger.run_death_linger(
		self,
		null,
		DEATH_LINGER_TIME,
		[],
		[]
	)

# --- Movement helpers ---

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

# --- Animations ---

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

func _play_hit_animation() -> void:
	if not animation_player:
		return
	var anim_name: String
	if is_floating:
		anim_name = "idleFlyHitReaction"
	else:
		anim_name = "hitReaction"
	if not animation_player.has_animation(anim_name):
		return
	if animation_player.current_animation != anim_name or not animation_player.is_playing():
		animation_player.speed_scale = 1.0
		animation_player.play(anim_name)
		animation_player.seek(0.0, true)

func _play_takeoff_animation() -> void:
	transition_anim_timer = 0.0
	if not animation_player:
		return
	if animation_player.has_animation("prepareToFly"):
		animation_player.speed_scale = 1.0
		animation_player.play("prepareToFly")
		transition_anim_timer = animation_player.get_animation("prepareToFly").length
	else:
		# No takeoff animation — go straight to flying
		transition_anim_timer = 0.0
		is_preparing_to_fly = false
		is_floating = true
		_update_ground_height_from_raycast()
		target_height_above_ground = randf_range(FLOAT_HEIGHT_MIN, FLOAT_HEIGHT_MAX)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null

# --- Collision ---

func _update_collision_mode() -> void:
	if not ground_collision or not hor_fly_collision:
		return
	var use_fly := is_floating and not is_on_floor()
	ground_collision.disabled = use_fly
	hor_fly_collision.disabled = not use_fly
	if hurtbox_ground:
		hurtbox_ground.monitoring = not use_fly
		hurtbox_ground.monitorable = not use_fly
	if hurtbox_vert_fly:
		hurtbox_vert_fly.monitoring = use_fly
		hurtbox_vert_fly.monitorable = use_fly

func _update_ground_height_from_raycast() -> void:
	var space := get_world_3d().direct_space_state
	var ray_start := global_position + Vector3.UP * 0.5
	var ray_end := global_position + Vector3.DOWN * GROUND_RAYCAST_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		ground_height = hit.position.y

func angle_difference(from: float, to: float) -> float:
	var diff := fmod(to - from + PI, TAU) - PI
	return diff if diff >= -PI else diff + TAU
