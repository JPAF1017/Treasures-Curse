extends CharacterBody3D

const EnemyDeathLinger := preload("res://scripts/npc/EnemyDeathLingerComponent.gd")

const GRAVITY = 20.0
const WALK_SPEED = 2.0
const DIR_CHANGE_MIN = 1.5
const DIR_CHANGE_MAX = 4.0
const WALK_BEFORE_IDLE_MIN = 1.5
const WALK_BEFORE_IDLE_MAX = 4.5
const IDLE_DURATION_MIN = 0.6
const IDLE_DURATION_MAX = 1.8
const HIT_REACTION_DURATION = 0.3
const DEATH_LINGER_TIME = 5.0

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

func _ready() -> void:
	randomize()
	animation_player = _find_animation_player(self)
	_log_attack("ready node=%s health=%d" % [name, health])
	_pick_new_direction()
	_reset_direction_timer()
	_reset_walk_before_idle_timer()
	_play_walk_animation()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	hit_reaction_timer = max(hit_reaction_timer - delta, 0.0)
	if hit_reaction_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_hit_animation()
		move_and_slide()
		return
	
	_update_wander_state(delta)
	_play_animation()
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
	if is_idle:
		_play_idle_animation()
	elif is_on_floor():
		_play_walk_animation()

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
