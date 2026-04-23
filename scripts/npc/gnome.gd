extends CharacterBody3D

const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")
const EnemyDeathLinger := preload("res://scripts/npc/EnemyDeathLingerComponent.gd")
const EnemyKnockback := preload("res://scripts/npc/NPCKnockbackComponent.gd")
const SmokeAggro := preload("res://scripts/npc/SmokeAggroComponent.gd")

const HEALTH_MAX := 10.0
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
const LOS_LOSS_CHASE_TIME := 5.0
const MEMORY_LOG_INTERVAL := 0.25
const BUMP_STEP_VELOCITY := 2.0
const BUMP_STEP_COOLDOWN := 0.15
const CROUCH_DETECTION_RAY_LENGTH := 8.0
const ATTACK_SWING_COOLDOWN := 2.0
const ATTACK_SWING_DAMAGE := 5.0
const DEATH_LINGER_TIME := 5.0
const STUN_WALK_ANIMATION_SPEED_SCALE := 0.45
const GRAB_ESCAPE_REQUIRED_JUMPS := 10
const GRAB_REACQUIRE_COOLDOWN := 0.8
const GRAB_INITIAL_DELAY := 1.0
const HIT_REACTION_DURATION := 0.35
const DAMAGE_ACTION_COOLDOWN := 3.0
const HIT_ANIMATION_CANDIDATES: Array[StringName] = [&"damage", &"hurt", &"hit"]
const OINK_SOUND_INTERVAL_MIN := 2.0
const OINK_SOUND_INTERVAL_MAX := 3.0

@export var facing_offset_degrees: float = 180.0
@export var debug_memory_logs: bool = false
@export var debug_damage_logs: bool = true

var move_direction: Vector3 = Vector3.ZERO
var health: float = HEALTH_MAX
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
var los_lost_timer: float = 0.0
var chase_memory_timer: float = 0.0
var last_visible_player_position: Vector3 = Vector3.ZERO
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right
var bump_step_timer: float = 0.0
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var space_state: PhysicsDirectSpaceState3D = null
var attack_swing_cooldown_timer: float = 0.0
var is_dead: bool = false
var is_stunned: bool = false
var stun_timer: float = 0.0
var hit_reaction_timer: float = 0.0
var knockback_component = EnemyKnockback.new()
var damage_action_cooldown_timer: float = 0.0
var stun_walk_visual_active: bool = false
var grab_escape_jump_count: int = 0
var grab_reacquire_timer: float = 0.0
var grab_initial_delay_timer: float = 0.0
var has_dealt_damage_this_attack: bool = false
var oink_player: AudioStreamPlayer3D = null
var oink_streams: Array[AudioStream] = []
var oink_sound_timer: float = 0.0
var pain_player: AudioStreamPlayer3D = null
var grab_sound_player: AudioStreamPlayer3D = null
var grab_sound_timer: float = 0.0
var attack_sound_player: AudioStreamPlayer3D = null
var attack_sound_played_this_swing: bool = false

func _ready() -> void:
	top_level = true
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
	_setup_oink_sounds()
	_play_walk_animation()
	_setup_damage_debug()
	add_to_group("gnome")

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	stun_timer = max(stun_timer - delta, 0.0)
	is_stunned = stun_timer > 0.0

	bump_step_timer = max(bump_step_timer - delta, 0.0)
	chase_memory_timer = max(chase_memory_timer - delta, 0.0)
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)
	attack_swing_cooldown_timer = max(attack_swing_cooldown_timer - delta, 0.0)
	grab_reacquire_timer = max(grab_reacquire_timer - delta, 0.0)
	damage_action_cooldown_timer = max(damage_action_cooldown_timer - delta, 0.0)
	_refresh_player_detection()
	SmokeAggro.suppress_aggro_if_in_smoke(self)

	EnemyLocomotion.apply_gravity(self, GRAVITY, delta)

	if knockback_component.is_active():
		knockback_component.update(delta)
		move_and_slide()
		return

	if hit_reaction_timer > 0.0:
		hit_reaction_timer = max(hit_reaction_timer - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	if is_stunned:
		_lock_grabbed_player(false)
		grabbed_player = null
		target_player = null
		attack_range_player = null
		is_player_in_detect = false
		is_player_in_chase = false
		is_player_in_attack_range = false
		velocity.x = 0.0
		velocity.z = 0.0
		_play_stunned_walk_animation()
		move_and_slide()
		return
	elif stun_walk_visual_active:
		_restore_walk_animation_speed()

	if is_player_in_attack_range and _has_valid_attack_range_player():
		_update_attack_range_state(delta)
		if damage_action_cooldown_timer > 0.0:
			pass  # recovering from a hit — do not start new attacks or grabs
		elif _has_valid_grabbed_player() and grabbed_player == attack_range_player:
			_play_grab_animation()
			_try_grab_damage()
		elif _is_player_grabbed_by_another_gnome(attack_range_player):
			_play_attack_animation()
		# else: no other gnome has grabbed yet — wait, face the player
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
	if los_lost_timer > 0.0 and not memorized_target_trail.is_empty():
		return true
	return chase_memory_timer > 0.0

func _should_walk_chase() -> bool:
	if is_player_in_detect and _has_valid_target_player():
		return true
	if los_lost_timer > 0.0 and not memorized_target_trail.is_empty():
		return true
	return los_lost_timer > 0.0

func _is_player_grabbed_by_another_gnome(player: CharacterBody3D) -> bool:
	if player == null:
		return false
	for gnome in get_tree().get_nodes_in_group("gnome"):
		if gnome == self:
			continue
		if not is_instance_valid(gnome):
			continue
		var gp = gnome.get("grabbed_player")
		if gp != null and gp == player:
			return true
	return false

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
		los_lost_timer = 0.0
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
			return

		var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
		var path_dir: Vector3 = path_result["direction"]
		wall_follow_mode = path_result["wall_follow_mode"]
		if path_dir.length_squared() <= 0.001:
			path_dir = to_target.normalized() * 0.4

		velocity.x = path_dir.x * move_speed
		velocity.z = path_dir.z * move_speed
		_face_direction(path_dir, delta)
	else:
		# No LOS - follow trail to last known position
		los_lost_timer -= delta
		if los_lost_timer <= 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
			wall_follow_mode = 0
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
	if is_stunned:
		return

	grab_initial_delay_timer = max(grab_initial_delay_timer - delta, 0.0)

	if damage_action_cooldown_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		var cooldown_target := attack_range_player if _has_valid_attack_range_player() else target_player
		if cooldown_target and is_instance_valid(cooldown_target):
			var dir_to_player := cooldown_target.global_position - global_position
			dir_to_player.y = 0.0
			if dir_to_player.length_squared() > 0.001:
				_face_direction(dir_to_player.normalized(), delta)
		return

	if _has_valid_grabbed_player() and not _can_grab_player_on_ground(grabbed_player):
		_interrupt_grab()

	if _has_valid_grabbed_player() and Input.is_action_just_pressed("ui_accept"):
		grab_escape_jump_count += 1
		if grab_escape_jump_count >= GRAB_ESCAPE_REQUIRED_JUMPS:
			_interrupt_grab()

	if grabbed_player == null and grab_reacquire_timer <= 0.0 and _has_valid_attack_range_player() and _can_grab_player_on_ground(attack_range_player) and _can_lock_player(attack_range_player):
		grabbed_player = attack_range_player
		_lock_grabbed_player(true)
		grab_escape_jump_count = 0

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

func _setup_damage_debug() -> void:
	var hurtbox := get_node_or_null("Hurtbox") as Area3D
	if hurtbox:
		print("[GnomeDmg] Hurtbox found — layer=%d mask=%d monitorable=%s" % [
			hurtbox.collision_layer, hurtbox.collision_mask, str(hurtbox.monitorable)])
		if not hurtbox.area_entered.is_connected(_on_hurtbox_area_entered):
			hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	else:
		print("[GnomeDmg] WARNING: No Hurtbox node found — weapons cannot hit this gnome!")
	print("[GnomeDmg] Gnome ready — health=%.1f damage_cooldown=%.2f hit_timer=%.2f" % [
		health, damage_action_cooldown_timer, hit_reaction_timer])

func _on_hurtbox_area_entered(area: Area3D) -> void:
	if not debug_damage_logs:
		return
	var parent_name: String = str(area.get_parent().name) if area.get_parent() else "<none>"
	print("[GnomeDmg] hurtbox overlapped by area '%s' (parent: %s) layer=%d mask=%d" % [
		area.name, parent_name, area.collision_layer, area.collision_mask])

func _setup_oink_sounds() -> void:
	var s1 := get_node_or_null("Sounds/OinkSound1") as AudioStreamPlayer3D
	var s2 := get_node_or_null("Sounds/OinkSound2") as AudioStreamPlayer3D
	var sp := get_node_or_null("Sounds/PainSound") as AudioStreamPlayer3D
	if sp:
		pain_player = sp
	var sg := get_node_or_null("Sounds/GrabSound") as AudioStreamPlayer3D
	if sg:
		grab_sound_player = sg
	var sa := get_node_or_null("Sounds/AttackSound") as AudioStreamPlayer3D
	if sa:
		attack_sound_player = sa
	if s1:
		oink_streams.append(s1.stream)
		if oink_player == null:
			oink_player = s1
	if s2:
		oink_streams.append(s2.stream)
		if oink_player == null:
			oink_player = s2
	if oink_player == null:
		# Fallback: create at runtime if scene nodes are missing
		var fs1 := load("res://sounds/gnome/oink1.mp3") as AudioStream
		var fs2 := load("res://sounds/gnome/oink2.mp3") as AudioStream
		if fs1:
			oink_streams.append(fs1)
		if fs2:
			oink_streams.append(fs2)
		if not oink_streams.is_empty():
			oink_player = AudioStreamPlayer3D.new()
			add_child(oink_player)

func _update_oink_sounds() -> void:
	if oink_player == null or oink_streams.is_empty():
		return
	oink_sound_timer = max(oink_sound_timer - get_physics_process_delta_time(), 0.0)
	if oink_sound_timer <= 0.0 and not oink_player.playing:
		oink_sound_timer = randf_range(OINK_SOUND_INTERVAL_MIN, OINK_SOUND_INTERVAL_MAX)
		oink_player.stream = oink_streams[randi() % oink_streams.size()]
		oink_player.play()

func _play_walk_animation() -> void:
	if animation_player and animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("walk")
	_update_oink_sounds()

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
	_update_oink_sounds()

func _update_grab_sound(delta: float) -> void:
	if grab_sound_player == null:
		return
	grab_sound_timer = max(grab_sound_timer - delta, 0.0)
	if grab_sound_timer <= 0.0 and not grab_sound_player.playing:
		grab_sound_player.play()
		grab_sound_timer = 1.0

func _try_grab_damage() -> void:
	if attack_swing_cooldown_timer > 0.0:
		return
	_try_apply_attack_swing_damage()
	attack_swing_cooldown_timer = ATTACK_SWING_COOLDOWN

func _play_grab_animation() -> void:
	if not animation_player:
		return

	_update_grab_sound(get_physics_process_delta_time())

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
	if is_stunned:
		return

	if attack_swing_cooldown_timer > 0.0:
		if animation_player.current_animation == "attack" and animation_player.is_playing():
			if not has_dealt_damage_this_attack:
				_try_frame_gated_attack_damage()
			_try_play_attack_sound()
		return

	if animation_player.has_animation("attack"):
		if animation_player.current_animation != "attack" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("attack")
			attack_swing_cooldown_timer = ATTACK_SWING_COOLDOWN
			has_dealt_damage_this_attack = false
			attack_sound_played_this_swing = false
	elif animation_player.has_animation("run"):
		if animation_player.current_animation != "run" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("run")

func _try_play_attack_sound() -> void:
	if attack_sound_played_this_swing:
		return
	if attack_sound_player == null:
		return
	var anim := animation_player.get_animation("attack")
	if anim == null:
		return
	var fps := 30.0
	if anim.step > 0.0:
		fps = 1.0 / anim.step
	if animation_player.current_animation_position >= 14.0 / fps:
		attack_sound_player.play()
		attack_sound_played_this_swing = true

func _try_frame_gated_attack_damage() -> void:
	if has_dealt_damage_this_attack:
		return
	if not animation_player or not animation_player.is_playing():
		return
	var anim := animation_player.get_animation("attack")
	if anim == null:
		return
	if animation_player.current_animation_position < anim.length * 0.5:
		return
	_try_apply_attack_swing_damage()
	has_dealt_damage_this_attack = true

func _try_apply_attack_swing_damage() -> void:
	if attack_range_area == null:
		return

	for body in attack_range_area.get_overlapping_bodies():
		if not (body is CharacterBody3D):
			continue
		if body == self:
			continue
		if not body.is_in_group("player"):
			continue
		_apply_damage_to_player(body, ATTACK_SWING_DAMAGE)

func _apply_damage_to_player(target: CharacterBody3D, damage: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	if target.has_method("apply_damage"):
		target.call("apply_damage", damage)
		return
	if target.has_method("take_damage"):
		target.call("take_damage", damage)
		return

	var current_health = target.get("health")
	if current_health == null:
		return

	var next_health := maxf(float(current_health) - damage, 0.0)
	target.set("health", next_health)
	if target.has_method("_update_health_ui"):
		target.call("_update_health_ui")

func _on_detect_body_entered(body: Node3D) -> void:
	if is_dead:
		return
	if is_stunned:
		return
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return

	target_player = body
	los_state_initialized = false
	los_lost_timer = 0.0
	is_player_in_detect = true
	last_visible_player_position = target_player.global_position
	trail_sample_timer = 0.0
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
	los_lost_timer = LOS_LOSS_CHASE_TIME
	los_state_initialized = false
	if not is_player_in_chase:
		target_player = null

func _on_chase_body_entered(body: Node3D) -> void:
	if is_dead:
		return
	if is_stunned:
		return
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return

	target_player = body
	los_state_initialized = false
	los_lost_timer = 0.0
	is_player_in_chase = true
	chase_memory_timer = CHASE_MEMORY_TIME
	last_visible_player_position = target_player.global_position
	trail_sample_timer = 0.0
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
	los_lost_timer = LOS_LOSS_CHASE_TIME
	los_state_initialized = false
	if not is_player_in_detect:
		target_player = null

func _on_attack_range_body_entered(body: Node3D) -> void:
	if is_dead:
		return
	if is_stunned:
		return
	if not (body is CharacterBody3D):
		return
	if not body.is_in_group("player"):
		return

	attack_range_player = body
	grabbed_player = null
	grab_initial_delay_timer = GRAB_INITIAL_DELAY
	target_player = body
	is_player_in_attack_range = true
	last_visible_player_position = attack_range_player.global_position

func _on_attack_range_body_exited(body: Node3D) -> void:
	if attack_range_player == null:
		return
	if body != attack_range_player:
		return

	_interrupt_grab(false)
	is_player_in_attack_range = false
	attack_range_player = null
	grab_initial_delay_timer = 0.0

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

func _can_grab_player_on_ground(player: CharacterBody3D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return player.is_on_floor()

func _exit_tree() -> void:
	_interrupt_grab(false)

func apply_damage(amount: float) -> void:
	if debug_damage_logs:
		print("[GnomeDmg] apply_damage called — amount=%.1f health=%.1f is_dead=%s hit_timer=%.2f dmg_cooldown=%.2f stun=%.2f" % [
			amount, health, str(is_dead), hit_reaction_timer, damage_action_cooldown_timer, stun_timer])
	if is_dead:
		if debug_damage_logs:
			print("[GnomeDmg] blocked — already dead")
		return
	if amount <= 0.0:
		if debug_damage_logs:
			print("[GnomeDmg] blocked — amount <= 0")
		return

	_interrupt_grab()
	_begin_hit_reaction()
	damage_action_cooldown_timer = DAMAGE_ACTION_COOLDOWN
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_die()

func apply_stun_state(duration: float) -> void:
	if is_dead:
		return
	if duration <= 0.0:
		return

	stun_timer = max(stun_timer, duration)
	is_stunned = true
	_interrupt_grab()
	attack_range_player = null
	target_player = null
	is_player_in_detect = false
	is_player_in_chase = false
	is_player_in_attack_range = false


func apply_knockback(direction: Vector3, strength: float) -> void:
	if is_dead:
		return
	knockback_component.begin_knockback(self, direction, strength, 0.35, 0.18)


func _begin_hit_reaction() -> void:
	hit_reaction_timer = max(hit_reaction_timer, _get_hit_reaction_duration())
	velocity.x = 0.0
	velocity.z = 0.0
	if pain_player:
		pain_player.stop()
		pain_player.play()
	var hit_animation_name := _get_hit_animation_name()
	if animation_player and hit_animation_name != StringName():
		animation_player.speed_scale = 1.0
		animation_player.play(hit_animation_name)
		animation_player.seek(0.0, true)

func _get_hit_reaction_duration() -> float:
	if animation_player == null:
		return HIT_REACTION_DURATION

	var hit_animation_name := _get_hit_animation_name()
	if hit_animation_name == StringName():
		return HIT_REACTION_DURATION

	var hit_animation := animation_player.get_animation(hit_animation_name)
	if hit_animation:
		return max(HIT_REACTION_DURATION, hit_animation.length)

	return HIT_REACTION_DURATION

func _get_hit_animation_name() -> StringName:
	if animation_player == null:
		return StringName()

	for anim_name in HIT_ANIMATION_CANDIDATES:
		if animation_player.has_animation(anim_name):
			return anim_name

	return StringName()


func _play_hit_animation() -> void:
	if animation_player == null:
		return

	var hit_animation_name := _get_hit_animation_name()
	if hit_animation_name == StringName():
		return

	# Only restart if a different animation is active — do not restart a finished hit anim.
	if animation_player.current_animation != hit_animation_name:
		animation_player.speed_scale = 1.0
		animation_player.play(hit_animation_name)
		animation_player.seek(0.0, true)

func _play_stunned_walk_animation() -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation("walk"):
		return

	var walk_animation := animation_player.get_animation("walk")
	if walk_animation and walk_animation.loop_mode == Animation.LOOP_NONE:
		walk_animation.loop_mode = Animation.LOOP_LINEAR

	if animation_player.current_animation != "walk":
		animation_player.play("walk")
	elif not animation_player.is_playing():
		animation_player.play("walk")

	animation_player.speed_scale = STUN_WALK_ANIMATION_SPEED_SCALE
	stun_walk_visual_active = true

func _restore_walk_animation_speed() -> void:
	stun_walk_visual_active = false
	if animation_player:
		animation_player.speed_scale = 1.0

func _die() -> void:
	if is_dead:
		return

	is_dead = true
	health = 0.0
	is_stunned = false
	stun_timer = 0.0
	_restore_walk_animation_speed()
	_interrupt_grab(false)
	target_player = null
	attack_range_player = null
	is_player_in_detect = false
	is_player_in_chase = false
	is_player_in_attack_range = false
	velocity = Vector3.ZERO
	attack_swing_cooldown_timer = ATTACK_SWING_COOLDOWN

	if detect_area:
		detect_area.monitoring = false
	if chase_area:
		chase_area.monitoring = false
	if attack_range_area:
		attack_range_area.monitoring = false

	await EnemyDeathLinger.run_death_linger(
		self,
		animation_player,
		DEATH_LINGER_TIME,
		[detect_area, chase_area, attack_range_area],
		[&"death", &"die"]
	)

func _interrupt_grab(start_reacquire_cooldown: bool = true) -> void:
	_lock_grabbed_player(false)
	grabbed_player = null
	grab_escape_jump_count = 0
	if start_reacquire_cooldown:
		grab_reacquire_timer = GRAB_REACQUIRE_COOLDOWN

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
	print("[GnomeMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d los_lost=%.2f" % [
		source,
		str(has_los),
		_format_vec3(player_pos),
		_format_vec3(last_seen_pos),
		_format_vec3(trail_target),
		_format_vec3(pursuit_target),
		memorized_target_trail.size(),
		los_lost_timer,
	])
