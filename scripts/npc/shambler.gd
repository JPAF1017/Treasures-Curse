extends CharacterBody3D

const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")
const EnemyDeathLinger := preload("res://scripts/npc/EnemyDeathLingerComponent.gd")
const SmokeAggro := preload("res://scripts/npc/SmokeAggroComponent.gd")

const GRAVITY := 20.0
const WALK_SPEED := 3.0
const RUN_SPEED := 4.0
const DIR_CHANGE_MIN := 1.2
const DIR_CHANGE_MAX := 3.2
const TURN_SPEED := 4.0
const CHASE_TURN_SPEED := 6.0
const LOS_MEMORY_TIME := 5.0
const PATH_RAYCAST_DISTANCE := 3.5
const SIDE_PROBE_DISTANCE := 2.5
const SENSE_RAY_HEIGHT := 0.8
const BUMP_STEP_VELOCITY := 2.0
const BUMP_STEP_COOLDOWN := 0.15
const ATTACK_COOLDOWN := 2.0
const TRAIL_MEMORY_TIME := 5.0
const TRAIL_SAMPLE_INTERVAL := 0.2
const TRAIL_POINT_SPACING := 0.7
const TRAIL_REACHED_DISTANCE := 0.8
const TRAIL_MAX_POINTS := 28
const LOS_LOSS_CHASE_TIME := 5.0
const MEMORY_LOG_INTERVAL := 0.25
const WALK_MOVE_RANGES: Array[Vector2i] = [
	Vector2i(34, 65),
	Vector2i(93, 116),
]
const CROUCH_DETECTION_RAY_LENGTH := 8.0
const HIT_REACTION_DURATION := 0.3
const DEATH_LINGER_TIME := 5.0
const KICK_DAMAGE := 10.0
const KICK_KNOCKBACK_STRENGTH := 15.0
const SWING_DAMAGE := 20.0
const SMASH_DAMAGE := 20.0
const SMASH_STUN_DURATION := 4.0
const ATTACK1_ACTIVE_FRAMES := Vector2i(33, 37)
const ATTACK2_ACTIVE_FRAMES := Vector2i(26, 32)
const ATTACK3_ACTIVE_FRAMES := Vector2i(44, 53)
const SOUND_STEP_FRAME_1_TIME := 1.0 / 30.0
const SOUND_STEP_FRAME_59_TIME := 59.0 / 30.0
const WANDER_SOUND_INTERVAL := 1.0
const ATTACK1_SOUND_FRAME_TIME := 31.0 / 30.0
const ATTACK2_SOUND_FRAME_TIME := 22.0 / 30.0
const ATTACK3_SOUND_FRAME_TIME := 39.0 / 30.0
const HIT_ANIMATION_START_TIME := 9.0 / 30.0
const STUN_WALK_SPEED_SCALE := 0.4

@export var health: int = 60
@export var facing_offset_degrees: float = 0
@export var walk_animation_fps: float = 30.0
@export var attack_animation_fps: float = 30.0
@export var debug_memory_logs: bool = false

var move_direction: Vector3 = Vector3.ZERO
var direction_change_timer: float = 0.0
var animation_player: AnimationPlayer = null
var detect_area: Area3D = null
var attack_range_area: Area3D = null
var target_player: CharacterBody3D = null
var last_visible_player_position: Vector3 = Vector3.ZERO
var los_lost_timer: float = 0.0
var wall_follow_mode: int = 0
var bump_step_timer: float = 0.0
var space_state: PhysicsDirectSpaceState3D = null
var player_in_attack_range: bool = false
var is_attacking: bool = false
var attack_cooldown_timer: float = 0.0
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var is_dead: bool = false
var is_stunned: bool = false
var stun_timer: float = 0.0
var hit_reaction_timer: float = 0.0
var current_attack_type: int = 0
var has_dealt_damage_this_attack: bool = false
var step_sounds: Array[AudioStreamPlayer3D] = []
var step_triggered_frame1: bool = false
var step_triggered_frame59: bool = false
var prev_walk_anim_position: float = 0.0
var wander_sounds: Array[AudioStreamPlayer3D] = []
var wander_sound_timer: float = 0.0
var attack_sounds: Array[AudioStreamPlayer3D] = []
var attack_sound_triggered: bool = false
var knockback_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	top_level = true
	_fix_glb_metallic(self)
	randomize()
	floor_stop_on_slope = true
	floor_snap_length = 0.7
	space_state = get_world_3d().direct_space_state
	animation_player = _find_animation_player(self)
	detect_area = get_node_or_null("Detect")
	if detect_area:
		detect_area.body_entered.connect(_on_detect_body_entered)
		detect_area.body_exited.connect(_on_detect_body_exited)
	attack_range_area = get_node_or_null("AttackRange")
	if attack_range_area:
		attack_range_area.body_entered.connect(_on_attack_range_body_entered)
		attack_range_area.body_exited.connect(_on_attack_range_body_exited)
	_setup_step_sounds()
	_pick_new_direction()
	_reset_direction_timer()
	_play_walk_animation()


func _fix_glb_metallic(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in mesh_inst.get_surface_override_material_count():
			var mat: Material = mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var std_mat := mat as StandardMaterial3D
				if std_mat.metallic > 0.0:
					var fixed := std_mat.duplicate() as StandardMaterial3D
					fixed.metallic = 0.0
					fixed.metallic_specular = 0.5
					mesh_inst.set_surface_override_material(i, fixed)
	for child in node.get_children():
		_fix_glb_metallic(child)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	stun_timer = max(stun_timer - delta, 0.0)
	is_stunned = stun_timer > 0.0

	hit_reaction_timer = max(hit_reaction_timer - delta, 0.0)
	if hit_reaction_timer > 0.0:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, delta * 12.0)
		EnemyLocomotion.apply_gravity(self, GRAVITY, delta)
		move_and_slide()
		return

	if is_stunned:
		is_attacking = false
		target_player = null
		player_in_attack_range = false
		los_lost_timer = 0.0
		los_state_initialized = false
		knockback_velocity = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		_play_stunned_walk_animation()
		EnemyLocomotion.apply_gravity(self, GRAVITY, delta)
		move_and_slide()
		return

	bump_step_timer = max(bump_step_timer - delta, 0.0)
	attack_cooldown_timer = max(attack_cooldown_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)
	_refresh_player_detection()
	SmokeAggro.suppress_aggro_if_in_smoke(self)

	EnemyLocomotion.apply_gravity(self, GRAVITY, delta)

	# Check if attack animation has finished
	if is_attacking and animation_player:
		if not animation_player.is_playing():
			is_attacking = false
			attack_cooldown_timer = ATTACK_COOLDOWN  # Start cooldown when attack finishes

	# Continue attacking if animation is playing, even if player left attack range
	if is_attacking:
		_update_attack_movement(delta)
	elif attack_cooldown_timer > 0.0 and target_player and is_instance_valid(target_player):
		_update_chase_movement(delta)
	elif player_in_attack_range and target_player and is_instance_valid(target_player) and NavigationUtils.has_line_of_sight_to(self, target_player.global_position, space_state, [self, target_player]) and _is_target_in_front_of_entity(target_player) and attack_cooldown_timer <= 0.0:
		_update_attack_movement(delta)
	elif target_player and is_instance_valid(target_player):
		_update_chase_movement(delta)
	elif los_lost_timer > 0.0:
		_update_chase_movement(delta)
	else:
		_update_wander_movement(delta)

	bump_step_timer = EnemyLocomotion.try_bump_step(self, bump_step_timer, BUMP_STEP_VELOCITY, BUMP_STEP_COOLDOWN)

	if not is_attacking and hit_reaction_timer <= 0.0:
		_update_step_sounds()

	if is_attacking:
		_update_attack_sounds()

	move_and_slide()

func _on_detect_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return
	if not _can_detect_crouching_player(body):
		return
	if target_player != null:
		return

	target_player = body
	los_state_initialized = false
	los_lost_timer = 0.0
	last_visible_player_position = target_player.global_position
	trail_sample_timer = 0.0
	memorized_target_trail.clear()
	NavigationUtils.append_trail_point(memorized_target_trail, last_visible_player_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)

func _on_detect_body_exited(body: Node3D) -> void:
	if target_player == null:
		return
	if body != target_player:
		return

	if is_instance_valid(target_player):
		last_visible_player_position = target_player.global_position
	los_lost_timer = LOS_LOSS_CHASE_TIME
	los_state_initialized = false
	target_player = null

func _on_attack_range_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return
	if not _can_detect_crouching_player(body):
		return
	player_in_attack_range = true

func _on_attack_range_body_exited(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return
	player_in_attack_range = false

func _update_chase_movement(delta: float) -> void:
	var has_target := target_player != null and is_instance_valid(target_player)
	var has_line_of_sight := false

	if has_target:
		var target_eye := target_player.global_position + Vector3(0, 1.0, 0)
		has_line_of_sight = NavigationUtils.has_line_of_sight_to(self, target_eye, space_state, [self, target_player])

	# Track LOS transitions
	if not los_state_initialized:
		previous_has_line_of_sight = has_line_of_sight
		los_state_initialized = true
	if has_line_of_sight and not previous_has_line_of_sight:
		los_lost_timer = 0.0
	elif not has_line_of_sight and previous_has_line_of_sight:
		los_lost_timer = LOS_LOSS_CHASE_TIME
		memorized_target_trail.clear()
		NavigationUtils.append_trail_point(memorized_target_trail, last_visible_player_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
	previous_has_line_of_sight = has_line_of_sight

	if has_line_of_sight:
		los_lost_timer = 0.0
		last_visible_player_position = target_player.global_position
		if trail_sample_timer <= 0.0:
			NavigationUtils.append_trail_point(memorized_target_trail, target_player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
			trail_sample_timer = TRAIL_SAMPLE_INTERVAL

		# Direct chase toward visible player
		var pursuit_target := target_player.global_position
		var to_target := pursuit_target - global_position
		to_target.y = 0.0
		if to_target.length_squared() <= 0.001:
			velocity.x = 0.0
			velocity.z = 0.0
			_play_walk_animation()
			return

		var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
		var path_dir: Vector3 = path_result["direction"]
		wall_follow_mode = path_result["wall_follow_mode"]
		if path_dir.length_squared() <= 0.001:
			path_dir = to_target.normalized() * 0.4

		_play_run_animation()
		var is_playing_walk := animation_player and animation_player.current_animation == "walk"
		if is_playing_walk and _is_in_walk_move_frame_window():
			velocity.x = path_dir.x * RUN_SPEED
			velocity.z = path_dir.z * RUN_SPEED
		elif is_playing_walk:
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			velocity.x = path_dir.x * RUN_SPEED
			velocity.z = path_dir.z * RUN_SPEED
		_face_direction_with_speed(path_dir, delta, CHASE_TURN_SPEED)
	else:
		# No LOS - follow trail to last known position
		los_lost_timer -= delta
		if los_lost_timer <= 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
			wall_follow_mode = 0
			_play_walk_animation()
			return

		var pursuit_target := last_visible_player_position
		var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
		if bool(trail_result.get("has_target", false)):
			pursuit_target = trail_result["target"]

		var to_target := pursuit_target - global_position
		to_target.y = 0.0
		if to_target.length() <= 0.6:
			velocity.x = 0.0
			velocity.z = 0.0
			wall_follow_mode = 0
			_play_walk_animation()
			return

		var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
		var path_dir: Vector3 = path_result["direction"]
		wall_follow_mode = path_result["wall_follow_mode"]
		if path_dir.length_squared() <= 0.001:
			path_dir = to_target.normalized() * 0.4

		_play_run_animation()
		var is_playing_walk := animation_player and animation_player.current_animation == "walk"
		if is_playing_walk and _is_in_walk_move_frame_window():
			velocity.x = path_dir.x * RUN_SPEED
			velocity.z = path_dir.z * RUN_SPEED
		elif is_playing_walk:
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			velocity.x = path_dir.x * RUN_SPEED
			velocity.z = path_dir.z * RUN_SPEED
		_face_direction_with_speed(path_dir, delta, CHASE_TURN_SPEED)

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
	print("[ShamblerMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d los_lost=%.2f" % [
		source,
		str(has_los),
		_format_vec3(player_pos),
		_format_vec3(last_seen_pos),
		_format_vec3(trail_target),
		_format_vec3(pursuit_target),
		memorized_target_trail.size(),
		los_lost_timer,
	])

func _refresh_player_detection() -> void:
	if target_player != null and is_instance_valid(target_player) and _is_crouched_player_hidden(target_player):
		target_player = null
		player_in_attack_range = false
		los_state_initialized = false
		previous_has_line_of_sight = false

	if target_player != null and is_instance_valid(target_player):
		player_in_attack_range = _is_body_overlapping_area(attack_range_area, target_player)
		return

	var detectable_player := _find_detectable_player_in_area(detect_area)
	if detectable_player:
		target_player = detectable_player
		last_visible_player_position = target_player.global_position
		trail_sample_timer = 0.0
		memorized_target_trail.clear()
		NavigationUtils.append_trail_point(memorized_target_trail, last_visible_player_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
		player_in_attack_range = _is_body_overlapping_area(attack_range_area, target_player)
		los_state_initialized = false
		previous_has_line_of_sight = false
		los_lost_timer = 0.0

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

func _is_player_crouching(body: Node) -> bool:
	return body != null and bool(body.get("is_crouching"))

func _is_crouched_player_hidden(body: Node3D) -> bool:
	return _is_player_crouching(body) and not _is_player_in_front_by_raycast(body)

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

func _update_attack_movement(delta: float) -> void:
	# Stop all movement
	velocity.x = 0.0
	velocity.z = 0.0
	
	# Try to deal damage during attack animation
	if is_attacking and not has_dealt_damage_this_attack:
		_try_apply_attack_damage()
	
	# Face the target and play animation only when initiating attack (not during animation)
	if not is_attacking:
		if target_player and is_instance_valid(target_player):
			var to_target := target_player.global_position - global_position
			to_target.y = 0.0
			if to_target.length_squared() > 0.001:
				_face_direction(to_target.normalized(), delta)
		_play_random_attack_animation()

func _update_wander_movement(delta: float) -> void:
	direction_change_timer -= delta
	if direction_change_timer <= 0.0 or is_on_wall():
		_pick_new_direction()
		_reset_direction_timer()

	_play_walk_animation()

	var in_move_window := _is_in_walk_move_frame_window()
	if in_move_window:
		velocity.x = move_direction.x * WALK_SPEED
		velocity.z = move_direction.z * WALK_SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_face_direction(move_direction, delta)

func _face_direction(direction: Vector3, delta: float) -> void:
	_face_direction_with_speed(direction, delta, TURN_SPEED)

func _face_direction_with_speed(direction: Vector3, delta: float, turn_speed: float) -> void:
	if direction.length_squared() <= 0.001:
		return
	var target_yaw := atan2(direction.x, direction.z) + deg_to_rad(facing_offset_degrees)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * turn_speed)

func _pick_new_direction() -> void:
	var angle := randf_range(0.0, TAU)
	move_direction = Vector3(sin(angle), 0.0, cos(angle)).normalized()

func _reset_direction_timer() -> void:
	direction_change_timer = randf_range(DIR_CHANGE_MIN, DIR_CHANGE_MAX)

func _play_walk_animation() -> void:
	if animation_player and animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.play("walk")
		animation_player.speed_scale = 1.0

func _play_run_animation() -> void:
	if not animation_player:
		return

	if animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("run")
	elif animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.play("walk")
		animation_player.speed_scale = 1.6

func _play_random_attack_animation() -> void:
	if not animation_player:
		return
	
	var attack_number := randi_range(1, 3)
	var attack_name := "attack%d" % attack_number
	
	if animation_player.has_animation(attack_name):
		animation_player.speed_scale = 1.0
		animation_player.play(attack_name)
		is_attacking = true
		current_attack_type = attack_number
		has_dealt_damage_this_attack = false
		attack_sound_triggered = false

func _try_apply_attack_damage() -> void:
	if attack_range_area == null:
		return
	if current_attack_type == 1 and not _is_in_attack_active_frames(ATTACK1_ACTIVE_FRAMES):
		return
	if current_attack_type == 2 and not _is_in_attack_active_frames(ATTACK2_ACTIVE_FRAMES):
		return
	if current_attack_type == 3 and not _is_in_attack_active_frames(ATTACK3_ACTIVE_FRAMES):
		return
	for body in attack_range_area.get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("player"):
			_apply_attack_effect(body)
			has_dealt_damage_this_attack = true
			return

func _apply_attack_effect(target: CharacterBody3D) -> void:
	match current_attack_type:
		1:  # Kick: knockback + 10 damage
			if target.has_method("apply_damage"):
				target.call("apply_damage", KICK_DAMAGE)
			if target.has_method("apply_knockback"):
				var knock_dir := (target.global_position - global_position).normalized()
				target.call("apply_knockback", knock_dir, KICK_KNOCKBACK_STRENGTH)
		2:  # Swing: 20 damage
			if target.has_method("apply_damage"):
				target.call("apply_damage", SWING_DAMAGE)
		3:  # Heavy smash: 20 damage + stun
			if target.has_method("apply_damage"):
				target.call("apply_damage", SMASH_DAMAGE)
			if target.has_method("apply_stun_state"):
				target.call("apply_stun_state", SMASH_STUN_DURATION)

func _is_in_attack_active_frames(frame_range: Vector2i) -> bool:
	if animation_player == null or not animation_player.is_playing():
		return false
	if attack_animation_fps <= 0.0:
		return false
	var anim := animation_player.get_animation(animation_player.current_animation)
	if anim == null:
		return false
	var total_frames := int(round(anim.length * attack_animation_fps))
	if total_frames < 1:
		total_frames = 1
	var current_frame := int(round(animation_player.current_animation_position * attack_animation_fps))
	current_frame = int(posmod(current_frame, total_frames))
	return current_frame >= frame_range.x and current_frame <= frame_range.y

func _is_in_walk_move_frame_window() -> bool:
	if animation_player == null:
		return false
	if animation_player.current_animation != "walk":
		return false
	if not animation_player.is_playing():
		return false
	if walk_animation_fps <= 0.0:
		return false
	var walk_animation := animation_player.get_animation("walk")
	if walk_animation == null:
		return false

	var total_frames: int = int(round(walk_animation.length * walk_animation_fps))
	if total_frames < 1:
		total_frames = 1
	var current_frame: int = int(round(animation_player.current_animation_position * walk_animation_fps))
	current_frame = int(posmod(current_frame, total_frames))

	var in_range := false
	for move_range in WALK_MOVE_RANGES:
		if _is_frame_in_range(current_frame, move_range.x, move_range.y, total_frames):
			in_range = true
			break

	return in_range

func _is_frame_in_range(frame: int, start_frame: int, end_frame: int, total_frames: int) -> bool:
	var start: int = int(posmod(start_frame, total_frames))
	var finish: int = int(posmod(end_frame, total_frames))

	if start <= finish:
		return frame >= start and frame <= finish

	# Wrap-around range (e.g. 116 -> 34 in a looping animation).
	return frame >= start or frame <= finish

func apply_stun_state(duration: float) -> void:
	if is_dead:
		return
	if duration <= 0.0:
		return
	stun_timer = max(stun_timer, duration)
	is_stunned = true
	is_attacking = false
	target_player = null
	player_in_attack_range = false
	los_lost_timer = 0.0
	los_state_initialized = false
	hit_reaction_timer = max(hit_reaction_timer, HIT_REACTION_DURATION)
	_play_hit_animation()

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
	_play_random_attack_sound()

func take_damage(amount: float) -> void:
	apply_damage(amount)

func apply_knockback(direction: Vector3, strength: float) -> void:
	if is_dead:
		return
	knockback_velocity.x = direction.x * strength
	knockback_velocity.z = direction.z * strength
	velocity.y = maxf(velocity.y, strength * 0.15)

func _die() -> void:
	if is_dead:
		return

	is_dead = true
	GameStats.record_kill("shambler")
	health = 0
	hit_reaction_timer = 0.0
	is_attacking = false
	velocity = Vector3.ZERO

	var areas_to_disable: Array[Area3D] = []
	if detect_area:
		areas_to_disable.append(detect_area)
	if attack_range_area:
		areas_to_disable.append(attack_range_area)

	await EnemyDeathLinger.run_death_linger(
		self,
		animation_player,
		DEATH_LINGER_TIME,
		areas_to_disable,
		[&"death", &"die"]
	)

func _play_stunned_walk_animation() -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation("walk"):
		return
	if animation_player.current_animation != "walk" or not animation_player.is_playing():
		animation_player.play("walk")
	animation_player.speed_scale = STUN_WALK_SPEED_SCALE

func _play_hit_animation() -> void:
	if not animation_player:
		return
	for anim_name in [&"hurt", &"hit", &"damage"]:
		if animation_player.has_animation(anim_name):
			var anim_length: float = animation_player.get_animation(anim_name).length
			var remaining_length := maxf(anim_length - HIT_ANIMATION_START_TIME, 0.0)
			hit_reaction_timer = max(hit_reaction_timer, remaining_length)
			if animation_player.current_animation != String(anim_name):
				animation_player.speed_scale = 1.0
				animation_player.play(anim_name)
				animation_player.seek(HIT_ANIMATION_START_TIME, true)
			return

func _is_target_in_front_of_entity(target: Node3D) -> bool:
	# Check if target is roughly in front of the shambler (within 120-degree cone)
	# This prevents attacks from behind
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	
	var distance := to_target.length()
	
	# If target is very close (within 2.5 units), allow attack regardless of facing
	if distance <= 2.5:
		return true
	
	if distance <= 0.001:
		return true  # Target at same position, allow attack
	
	# Get shambler's forward direction
	var forward := -global_transform.basis.z  # Negative Z is forward in Godot
	
	# Dot product: > cos(60°) ≈ 0.5 means within ~120-degree cone
	var dot_product := forward.normalized().dot(to_target.normalized())
	return dot_product > 0.5  # ~120-degree cone of vision

func _setup_step_sounds() -> void:
	for i in range(1, 4):
		var node := get_node_or_null("Sounds/StepSound%d" % i)
		if node is AudioStreamPlayer3D:
			step_sounds.append(node)
	for i in range(1, 6):
		var node := get_node_or_null("Sounds/WanderSound%d" % i)
		if node is AudioStreamPlayer3D:
			wander_sounds.append(node)
	for i in range(1, 7):
		var node := get_node_or_null("Sounds/AttackSound%d" % i)
		if node is AudioStreamPlayer3D:
			attack_sounds.append(node)

func _update_step_sounds() -> void:
	if not animation_player or animation_player.current_animation != "walk" or not animation_player.is_playing():
		prev_walk_anim_position = 0.0
		step_triggered_frame1 = false
		step_triggered_frame59 = false
		return

	var pos := animation_player.current_animation_position

	# Detect loop wrap (position jumped backwards)
	if pos < prev_walk_anim_position - 0.1:
		step_triggered_frame1 = false
		step_triggered_frame59 = false

	if pos >= SOUND_STEP_FRAME_1_TIME and not step_triggered_frame1:
		step_triggered_frame1 = true
		_play_random_step_sound()

	if pos >= SOUND_STEP_FRAME_59_TIME and not step_triggered_frame59:
		step_triggered_frame59 = true
		_play_random_step_sound()

	wander_sound_timer -= get_physics_process_delta_time()
	if wander_sound_timer <= 0.0 and not _is_any_wander_sound_playing():
		wander_sound_timer = WANDER_SOUND_INTERVAL
		_play_random_wander_sound()

	prev_walk_anim_position = pos

func _play_random_step_sound() -> void:
	if step_sounds.is_empty():
		return
	var snd: AudioStreamPlayer3D = step_sounds[randi() % step_sounds.size()]
	if snd and not snd.playing:
		snd.play()

func _play_random_wander_sound() -> void:
	if wander_sounds.is_empty():
		return
	var snd: AudioStreamPlayer3D = wander_sounds[randi() % wander_sounds.size()]
	if snd and not snd.playing:
		snd.play()

func _is_any_wander_sound_playing() -> bool:
	for snd in wander_sounds:
		if snd and snd.playing:
			return true
	return false

func _update_attack_sounds() -> void:
	if not animation_player or not animation_player.is_playing():
		return
	if attack_sound_triggered:
		return
	var pos := animation_player.current_animation_position
	var trigger_time: float
	match current_attack_type:
		1: trigger_time = ATTACK1_SOUND_FRAME_TIME
		2: trigger_time = ATTACK2_SOUND_FRAME_TIME
		3: trigger_time = ATTACK3_SOUND_FRAME_TIME
		_: return
	if pos >= trigger_time:
		attack_sound_triggered = true
		_play_random_attack_sound()

func _play_random_attack_sound() -> void:
	if attack_sounds.is_empty():
		return
	var snd: AudioStreamPlayer3D = attack_sounds[randi() % attack_sounds.size()]
	if snd and not snd.playing:
		snd.play()

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found

	return null
