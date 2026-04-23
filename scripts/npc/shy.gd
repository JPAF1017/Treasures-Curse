extends CharacterBody3D

const EnemyLocomotion := preload("res://scripts/npc/EnemyLocomotionComponent.gd")
const SmokeAggro := preload("res://scripts/npc/SmokeAggroComponent.gd")

const GRAVITY = 20.0
const WALK_SPEED = 1.5
const RUN_SPEED = 10.0
const DIR_CHANGE_MIN = 1.2
const DIR_CHANGE_MAX = 3.0
const ATTACK_COOLDOWN = 3.0
const MAX_ATTACKS_BEFORE_WANDER = 13
const ATTACK_DAMAGE = 20.0
const ATTACK_KNOCKBACK_STRENGTH = 15.0
const ATTACK_ACTIVE_FRAMES = Vector2i(38, 44)
const ATTACK_ANIMATION_FPS = 30.0
const RUN_ANIMATION_FPS = 30.0
const STEP_FRAMES: Array[int] = [7, 16, 24, 34]
const BUMP_STEP_VELOCITY = 2.0
const BUMP_STEP_COOLDOWN = 0.15
const LOS_MEMORY_TIME = 5.0
const TRAIL_MEMORY_TIME = 5.0
const TRAIL_SAMPLE_INTERVAL = 0.2
const TRAIL_POINT_SPACING = 0.7
const TRAIL_REACHED_DISTANCE = 0.8
const TRAIL_MAX_POINTS = 28
const LOS_LOSS_CHASE_TIME = 5.0
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
var scream_sound: AudioStreamPlayer3D = null
var chase_sound: AudioStreamPlayer3D = null
var attack_sounds: Array[AudioStreamPlayer3D] = []
var breath_sounds: Array[AudioStreamPlayer3D] = []
var step_sounds: Array[AudioStreamPlayer3D] = []
var breath_timer: float = 0.0
const BREATH_INTERVAL = 1.5
var seen_area: Area3D = null
var attack_range_area: Area3D = null
var current_state: State = State.WANDER
var target_player: CharacterBody3D = null
var should_wander_after_scream: bool = false
var scream_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var is_player_in_attack_range: bool = false
var attack_count: int = 0
var has_dealt_damage_this_attack: bool = false
var has_played_attack_sound: bool = false
var bump_step_timer: float = 0.0
var wall_follow_mode: int = 0  # 0 = none, 1 = left, -1 = right
var los_lost_timer: float = 0.0
var last_visible_target_position: Vector3 = Vector3.ZERO
var trail_sample_timer: float = 0.0
var memorized_target_trail: Array[Vector3] = []
var memory_log_timer: float = 0.0
var nav_log_timer: float = 0.0
var los_state_initialized: bool = false
var previous_has_line_of_sight: bool = false
var last_run_frame: int = -1
var triggered_step_frames: Array[int] = []

func _ready() -> void:
	top_level = true
	randomize()
	floor_snap_length = 0.7
	animation_player = _find_animation_player(self)
	scream_sound = get_node_or_null("Sounds/ScreamSound")
	chase_sound = get_node_or_null("Sounds/ChaseSound")
	for i in range(1, 5):
		var snd := get_node_or_null("Sounds/AttackSound%d" % i) as AudioStreamPlayer3D
		if snd:
			attack_sounds.append(snd)
	for i in range(1, 6):
		var snd := get_node_or_null("Sounds/BreathSound%d" % i) as AudioStreamPlayer3D
		if snd:
			breath_sounds.append(snd)
	for i in range(1, 4):
		var snd := get_node_or_null("Sounds/StepSound%d" % i) as AudioStreamPlayer3D
		if snd:
			step_sounds.append(snd)
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
	trail_sample_timer = max(trail_sample_timer - delta, 0.0)
	memory_log_timer = max(memory_log_timer - delta, 0.0)
	nav_log_timer = max(nav_log_timer - delta, 0.0)

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer = max(attack_cooldown_timer - delta, 0.0)

	EnemyLocomotion.apply_gravity(self, GRAVITY, delta)

	_update_step_sounds()

	if SmokeAggro.suppress_aggro_if_in_smoke(self):
		current_state = State.WANDER

	if current_state == State.SCREAMING:
		_update_scream_state(delta)
	elif current_state == State.ATTACKING:
		_update_attack_state(delta)
	elif current_state == State.CHASING:
		_update_chase_state(delta)
	else:
		_update_wander_state(delta)

	# Step up tiny bumps while moving so AI does not stall on uneven floors.
	bump_step_timer = EnemyLocomotion.try_bump_step(self, bump_step_timer, BUMP_STEP_VELOCITY, BUMP_STEP_COOLDOWN)

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

	breath_timer -= delta
	if breath_timer <= 0.0 and not _is_any_breath_playing():
		_play_random_breath_sound()
		breath_timer = BREATH_INTERVAL

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

	# Track LOS transitions
	if not los_state_initialized:
		previous_has_line_of_sight = has_line_of_sight
		los_state_initialized = true
	if has_line_of_sight and not previous_has_line_of_sight:
		# Regained LOS - reset lost timer
		los_lost_timer = 0.0
	elif not has_line_of_sight and previous_has_line_of_sight:
		# Just lost LOS - start the countdown and record trail
		los_lost_timer = LOS_LOSS_CHASE_TIME
		memorized_target_trail.clear()
		NavigationUtils.append_trail_point(memorized_target_trail, last_visible_target_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
	previous_has_line_of_sight = has_line_of_sight

	if has_line_of_sight:
		los_lost_timer = 0.0
		last_visible_target_position = target_player.global_position
		if trail_sample_timer <= 0.0:
			NavigationUtils.append_trail_point(memorized_target_trail, target_player.global_position, TRAIL_MAX_POINTS, TRAIL_POINT_SPACING)
			trail_sample_timer = TRAIL_SAMPLE_INTERVAL

		if _is_target_in_attack_range() and attack_cooldown_timer <= 0.0:
			_start_attacking()
			return

		# Chase directly toward the player
		var to_player := target_player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.3:
			var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, target_player.global_position, space_state, wall_follow_mode)
			var path_dir: Vector3 = path_result["direction"]
			wall_follow_mode = path_result["wall_follow_mode"]
			if path_dir.length_squared() > 0.001:
				velocity.x = path_dir.x * RUN_SPEED
				velocity.z = path_dir.z * RUN_SPEED
				_face_direction(path_dir, delta, run_turn_speed)
			else:
				var chase_dir := to_player.normalized()
				velocity.x = chase_dir.x * RUN_SPEED * 0.4
				velocity.z = chase_dir.z * RUN_SPEED * 0.4
				_face_direction(chase_dir, delta, run_turn_speed)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		_play_run_animation()
	else:
		# No LOS - follow the trail to last known position
		los_lost_timer -= delta
		if los_lost_timer <= 0.0:
			_return_to_wander()
			return

		var pursuit_target := last_visible_target_position
		var trail_result := NavigationUtils.get_trail_follow_target(global_position, memorized_target_trail, TRAIL_REACHED_DISTANCE)
		if bool(trail_result.get("has_target", false)):
			pursuit_target = trail_result["target"]

		var to_target := pursuit_target - global_position
		to_target.y = 0.0

		if to_target.length() <= 0.6:
			# Reached last known position, give up
			_return_to_wander()
			return

		var path_result: Dictionary = NavigationUtils.find_path_direction_to_target(self, pursuit_target, space_state, wall_follow_mode)
		var path_dir: Vector3 = path_result["direction"]
		wall_follow_mode = path_result["wall_follow_mode"]
		if path_dir.length_squared() > 0.001:
			velocity.x = path_dir.x * RUN_SPEED
			velocity.z = path_dir.z * RUN_SPEED
			_face_direction(path_dir, delta, run_turn_speed)
		else:
			var chase_dir := to_target.normalized()
			velocity.x = chase_dir.x * RUN_SPEED * 0.4
			velocity.z = chase_dir.z * RUN_SPEED * 0.4
			_face_direction(chase_dir, delta, run_turn_speed)
		_play_run_animation()

func _update_attack_state(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	if not has_played_attack_sound and _is_at_or_past_frame(ATTACK_ACTIVE_FRAMES.x):
		_play_random_attack_sound()
		has_played_attack_sound = true

	if not has_dealt_damage_this_attack:
		_try_apply_attack_damage()

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
			if chase_sound and not chase_sound.playing:
				chase_sound.play()
	elif animation_player.has_animation("walk"):
		if animation_player.current_animation != "walk" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("walk")
			if chase_sound and not chase_sound.playing:
				chase_sound.play()

func _play_attack_animation() -> void:
	if not animation_player:
		return

	if not animation_player.has_animation("attack"):
		push_warning("Shy missing 'attack' animation; using run fallback")
		_play_run_animation()
		return

	animation_player.speed_scale = attack_animation_speed
	animation_player.play("attack")

func _is_at_or_past_frame(frame: int) -> bool:
	if animation_player == null or not animation_player.is_playing():
		return false
	var current_frame := int(round(animation_player.current_animation_position * ATTACK_ANIMATION_FPS))
	return current_frame >= frame

func _play_random_attack_sound() -> void:
	if attack_sounds.is_empty():
		return
	var snd: AudioStreamPlayer3D = attack_sounds[randi() % attack_sounds.size()]
	snd.play()

func _update_step_sounds() -> void:
	if step_sounds.is_empty():
		return
	if animation_player == null or not animation_player.is_playing():
		return
	if animation_player.current_animation != "run":
		last_run_frame = -1
		triggered_step_frames.clear()
		return
	var current_frame := int(animation_player.current_animation_position * RUN_ANIMATION_FPS)
	if current_frame < last_run_frame:
		triggered_step_frames.clear()
	last_run_frame = current_frame
	for frame in STEP_FRAMES:
		if current_frame >= frame and frame not in triggered_step_frames:
			triggered_step_frames.append(frame)
			step_sounds[randi() % step_sounds.size()].play()
			break

func _play_random_breath_sound() -> void:
	if breath_sounds.is_empty():
		return
	var snd: AudioStreamPlayer3D = breath_sounds[randi() % breath_sounds.size()]
	snd.play()

func _is_any_breath_playing() -> bool:
	for snd in breath_sounds:
		if snd.playing:
			return true
	return false

func _on_seen_area_entered(area: Area3D) -> void:
	if not area.is_in_group("player_vision"):
		return

	if current_state != State.WANDER:
		return

	var player_node := _find_player_from_vision_area(area)
	if player_node == null:
		return

	target_player = player_node
	los_lost_timer = 0.0
	last_visible_target_position = target_player.global_position
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
		if scream_sound and scream_sound.stream:
			var anim_length := animation_player.get_animation("scream").length if animation_player.get_animation("scream") else 0.0
			var sound_length := scream_sound.stream.get_length()
			if anim_length > 0.0 and sound_length > 0.0:
				scream_sound.pitch_scale = sound_length / anim_length
			scream_sound.play()
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
	los_lost_timer = LOS_LOSS_CHASE_TIME
	scream_timer = 0.0
	_play_run_animation()

func _start_attacking() -> void:
	current_state = State.ATTACKING
	velocity.x = 0.0
	velocity.z = 0.0
	attack_cooldown_timer = ATTACK_COOLDOWN
	has_dealt_damage_this_attack = false
	has_played_attack_sound = false
	_play_attack_animation()

func _on_animation_finished(anim_name: StringName) -> void:
	if current_state == State.SCREAMING and anim_name == "scream":
		if should_wander_after_scream:
			should_wander_after_scream = false
			_finish_wandering()
		else:
			_start_chasing()
	elif current_state == State.ATTACKING and anim_name == "attack":
		attack_count += 1
		if attack_count >= MAX_ATTACKS_BEFORE_WANDER:
			_return_to_wander()
		else:
			_start_chasing()

func _return_to_wander() -> void:
	current_state = State.SCREAMING
	should_wander_after_scream = true
	velocity.x = 0.0
	velocity.z = 0.0
	if chase_sound and chase_sound.playing:
		chase_sound.stop()
	_play_scream_animation()

func _finish_wandering() -> void:
	current_state = State.WANDER
	target_player = null
	los_state_initialized = false
	is_player_in_attack_range = false
	attack_cooldown_timer = 0.0
	attack_count = 0
	trail_sample_timer = 0.0
	los_lost_timer = 0.0
	memorized_target_trail.clear()
	if chase_sound and chase_sound.playing:
		chase_sound.stop()
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

func _try_apply_attack_damage() -> void:
	if attack_range_area == null:
		return
	if not _is_in_attack_active_frames():
		return
	for body in attack_range_area.get_overlapping_bodies():
		if body is CharacterBody3D and body.is_in_group("player"):
			if body.has_method("apply_damage"):
				body.call("apply_damage", ATTACK_DAMAGE)
			if body.has_method("apply_knockback"):
				var knock_dir := (body.global_position - global_position).normalized()
				body.call("apply_knockback", knock_dir, ATTACK_KNOCKBACK_STRENGTH)
			has_dealt_damage_this_attack = true
			return

func _is_in_attack_active_frames() -> bool:
	if animation_player == null or not animation_player.is_playing():
		return false
	var anim := animation_player.get_animation(animation_player.current_animation)
	if anim == null:
		return false
	var total_frames := int(round(anim.length * ATTACK_ANIMATION_FPS))
	if total_frames < 1:
		total_frames = 1
	var current_frame := int(round(animation_player.current_animation_position * ATTACK_ANIMATION_FPS))
	current_frame = int(posmod(current_frame, total_frames))
	return current_frame >= ATTACK_ACTIVE_FRAMES.x and current_frame <= ATTACK_ACTIVE_FRAMES.y

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
	print("[ShyMemory] source=%s los=%s player=%s last_seen=%s trail_target=%s pursuit=%s trail_size=%d los_lost_timer=%.2f" % [
		source,
		str(has_los),
		_format_vec3(player_pos),
		_format_vec3(last_seen_pos),
		_format_vec3(trail_target),
		_format_vec3(pursuit_target),
		memorized_target_trail.size(),
		los_lost_timer,
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
