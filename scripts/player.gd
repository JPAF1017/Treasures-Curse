extends CharacterBody3D

#variables and constants
const WALK_SPEED = 7.0
const SPRINT_SPEED = 11.0
const CROUCH_SPEED = 3.5
const STAMINA_MAX = 100.0
const STAMINA_WARNING_THRESHOLD = 20.0
const STAMINA_COLOR_NORMAL_INDEX = 18
const STAMINA_COLOR_LOW_INDEX = 17
const HEALTH_MAX = 100.0
const HEALTH_COLOR_NORMAL_INDEX = 23
const STAMINA_PALETTE_PATH = "res://assets/ui/dungeon-pal.png"
const BLOOD_OVERLAY_PATH = "res://assets/ui/BloodOverlay.png"
const DAMAGE_OVERLAY_MAX_ALPHA = 0.7
const DAMAGE_OVERLAY_FADE_TIME = 0.35
const JUMP_STAMINA_COST = 20.0
const TIRED_JUMP_HEIGHT_MULTIPLIER = 1.0 / 3.0
const STAMINA_REFILL_DELAY_SECONDS = 5.0
const STAMINA_DRAIN_PER_SECOND = STAMINA_MAX / 7.0
const STAMINA_REFILL_PER_SECOND = STAMINA_MAX / 10.0
const JUMP_VELOCITY = 11
const JUMP_AIR_LOOP_MIN_FRAME = 4
const JUMP_HOLD_FRAME = 16
const JUMP_ANIMATION_FPS = 30.0
const JUMP_AIR_LOOP_SPEED = 0.45
const BUMP_STEP_VELOCITY = 2.2
const BUMP_STEP_COOLDOWN = 0.12
const SENSITIVITY = 0.003
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5
const POSITION_LOG_INTERVAL = 0.25
const HOTBAR_SLOT_COUNT = 5
const HOTBAR_SELECTED_SCALE = 1.18
const HOTBAR_DEFAULT_SCALE = 1.0
const HOTBAR_ITEM_LABEL_FONT_PATH = "res://assets/ui/dungeon-mode.ttf"
const SHOVEL_ITEM_SCRIPT: Script = preload("res://scripts/items/shovel.gd")
const HEALTH_ITEM_SCRIPT: Script = preload("res://scripts/items/health.gd")
@export_range(2.0, 80.0, 0.5) var vision_distance: float = 20.0
@export_range(0.5, 10.0, 0.1) var vision_radius: float = 3.0
@export var debug_position_logs: bool = false
@export var debug_attack_overlap_logs: bool = true
@export var hide_visual_from_player_camera: bool = true
@export_range(-360.0, 360.0, 1.0) var visual_yaw_offset_degrees: float = 180.0
@export var crouch_head_y: float = -0.111
@export_range(1.0, 30.0, 0.5) var crouch_transition_speed: float = 12.0
@export var visual_root_path: NodePath
@export var animation_player_path: NodePath
#------------------------------------------------------
var speed
var t_bob = 0.0
var gravity = 20
var bump_step_timer = 0.0
var position_log_timer = 0.0
var attack_overlap_log_timer = 0.0
var movement_lock_sources: Array[Node] = []
var initial_head_position: Vector3 = Vector3.ZERO
var target_head_y: float = 0.0
var is_crouching: bool = false
var stamina: float = STAMINA_MAX
var stamina_refill_delay_timer: float = 0.0
var health: float = HEALTH_MAX
var previous_health: float = HEALTH_MAX
var is_sprinting: bool = false
var tired_jump_active: bool = false
var jump_phase: int = 0
var jump_air_loop_frame: float = float(JUMP_AIR_LOOP_MIN_FRAME)
var jump_air_loop_forward: bool = true
var stamina_color_normal: Color = Color(1.0, 1.0, 1.0, 1.0)
var stamina_color_low: Color = Color(1.0, 0.3, 0.3, 1.0)
var health_color_normal: Color = Color(1.0, 1.0, 1.0, 1.0)

const JUMP_PHASE_NONE = 0
const JUMP_PHASE_ACTIVE = 1
#------------------------------------------------------
@onready var head = $Head
@onready var stand_collision: CollisionShape3D = $Stand
@onready var crouch_collision: CollisionShape3D = $Crouch
@onready var camera = $Head/playerCamera
@onready var vision_collision_shape: CollisionShape3D = $Head/playerCamera/Vision/CollisionShape3D
@onready var attack_area: Area3D = $Attack
@onready var visual_root: Node3D = _resolve_visual_root()
@onready var animation_player: AnimationPlayer = _resolve_animation_player()
@onready var stamina_bar_fill: NinePatchRect = $CanvasLayer/Control/Stamina/StaminaBarContainer
@onready var stamina_label_digit: Label = $CanvasLayer/Control/Stamina/LabelDigit
@onready var health_bar_fill: NinePatchRect = $CanvasLayer/Control/Health/HealthBarContainer
@onready var health_label_digit: Label = $CanvasLayer/Control/Health/LabelDigit
@onready var player_canvas_layer: CanvasLayer = $CanvasLayer
@onready var pickup_control: Control = $CanvasLayer/Control/Pickup

var stamina_bar_initial_scale: Vector2 = Vector2.ONE
var health_bar_initial_scale: Vector2 = Vector2.ONE
var damage_overlay: TextureRect = null
var damage_overlay_tween: Tween = null
var hotbar_slots: Array[NinePatchRect] = []
var hotbar_slot_base_scales: Array[Vector2] = []
var hotbar_item_icons: Array[TextureRect] = []
var hotbar_item_models: Array[Node3D] = []
var selected_hotbar_slot_index: int = 0
var hotbar_font: FontFile = null

#function on startup
func _ready():
	#detects mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_snap_length = 0.7
	_configure_vision_area()
	_set_control_mouse_filter_recursive(pickup_control, Control.MOUSE_FILTER_IGNORE)
	initial_head_position = head.position
	target_head_y = initial_head_position.y
	_setup_stamina_ui()
	_setup_health_ui()
	_setup_damage_overlay()
	_setup_hotbar_ui()
	_select_hotbar_slot(0)
	_update_stamina_ui()
	_update_health_ui()
	_setup_attack_overlap_debug()
	
	# Initialize player visual rotation.
	if visual_root:
		visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)
		_configure_player_visual_visibility()
	else:
		print("WARNING: Player visual root not found!")

func _configure_player_visual_visibility() -> void:
	if visual_root == null or camera == null:
		return

	if hide_visual_from_player_camera:
		# Put player visuals on layer 2 and hide that layer from this camera.
		_set_layer_recursive(visual_root, 2)
		camera.cull_mask = camera.cull_mask & ~2
	else:
		# Keep visuals on default layer so the player model is visible for animation testing.
		_set_layer_recursive(visual_root, 1)
		camera.cull_mask = camera.cull_mask | 1

func _configure_vision_area():
	if vision_collision_shape == null:
		print("WARNING: Vision collision shape not found!")
		return

	var vision_shape = vision_collision_shape.shape as CapsuleShape3D
	if vision_shape == null:
		print("WARNING: Vision shape is not CapsuleShape3D")
		return

	vision_shape.radius = vision_radius
	vision_shape.height = max(vision_distance - (vision_radius * 2.0), 0.1)

	# Rotate the capsule forward and place its center halfway into view distance.
	vision_collision_shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	vision_collision_shape.position = Vector3(0.0, 0.0, -vision_distance * 0.5)

#camera function
func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(90))
		_sync_visual_rotation_to_head()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var selected_item := _get_selected_primary_item()
				if selected_item == null or not bool(selected_item.call("begin_primary_action", self)):
					return
			else:
				var selected_item := _get_selected_primary_item()
				if selected_item:
					selected_item.call("release_primary_action", self)
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_select_hotbar_slot((selected_hotbar_slot_index - 1 + HOTBAR_SLOT_COUNT) % HOTBAR_SLOT_COUNT)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_select_hotbar_slot((selected_hotbar_slot_index + 1) % HOTBAR_SLOT_COUNT)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_drop_selected_hotbar_item()
			return

		var slot_index := _hotbar_index_from_keycode(event.keycode)
		if slot_index != -1:
			_select_hotbar_slot(slot_index)

#movement function
func _physics_process(delta):
	bump_step_timer = max(bump_step_timer - delta, 0.0)
	position_log_timer = max(position_log_timer - delta, 0.0)
	attack_overlap_log_timer = max(attack_overlap_log_timer - delta, 0.0)
	var is_movement_locked := _is_movement_locked()
	var input_dir := Vector2.ZERO
	if not is_movement_locked:
		input_dir = Input.get_vector("a", "d", "w", "s")

	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_crouch_state(Input.is_action_pressed("Ctrl"))
	_update_head_height(delta)
#------------------------------------------------------
#jump input
	var jump_pressed := not is_movement_locked and Input.is_action_just_pressed("ui_accept")
	if jump_pressed and is_on_floor():
		if stamina >= JUMP_STAMINA_COST:
			stamina = max(stamina - JUMP_STAMINA_COST, 0.0)
			if stamina <= 0.0:
				stamina_refill_delay_timer = STAMINA_REFILL_DELAY_SECONDS
			tired_jump_active = false
			jump_phase = JUMP_PHASE_ACTIVE
			velocity.y = JUMP_VELOCITY
			jump_air_loop_frame = float(JUMP_AIR_LOOP_MIN_FRAME)
			jump_air_loop_forward = true
			if animation_player and animation_player.has_animation("jump"):
				animation_player.play("jump")
				animation_player.seek(0.0, true)
		else:
			# Tired jump: reduced jump height and no jump animation.
			if stamina > 0.0:
				stamina = 0.0
				stamina_refill_delay_timer = STAMINA_REFILL_DELAY_SECONDS
			tired_jump_active = true
			jump_phase = JUMP_PHASE_NONE
			velocity.y = JUMP_VELOCITY * TIRED_JUMP_HEIGHT_MULTIPLIER
#------------------------------------------------------
#sprint input
	# Sprint is only valid while moving forward (including forward diagonals) and not crouching.
	var sprint_input := not is_movement_locked and Input.is_action_pressed("shift")
	var can_sprint := input_dir.y < 0.0 and not is_crouching
	is_sprinting = false
	if tired_jump_active:
		speed = CROUCH_SPEED
	elif is_crouching:
		speed = CROUCH_SPEED
	elif sprint_input and can_sprint and stamina > 0.0:
		is_sprinting = true
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	if is_sprinting:
		stamina = max(stamina - STAMINA_DRAIN_PER_SECOND * delta, 0.0)
		if stamina <= 0.0:
			stamina_refill_delay_timer = STAMINA_REFILL_DELAY_SECONDS
			is_sprinting = false
			speed = WALK_SPEED

	if stamina_refill_delay_timer > 0.0:
		stamina_refill_delay_timer = max(stamina_refill_delay_timer - delta, 0.0)
	elif not is_sprinting:
		stamina = min(stamina + STAMINA_REFILL_PER_SECOND * delta, STAMINA_MAX)
	_update_pickup_prompt_visibility()
	_refresh_selected_item_state()
	_update_hotbar_windup_indicator()
	_update_stamina_ui()
#------------------------------------------------------
#wasd direction input and other physics
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Animation handling
	if animation_player:
		var swing_anim_active := _update_selected_item_action(delta)
		var jump_anim_active := _update_jump_animation_phase(delta)
		var is_walking_forward := input_dir.y < 0.0
		var is_walking_backward := input_dir.y > 0.0
		var is_strafing_left := input_dir.x < 0.0
		var is_strafing_right := input_dir.x > 0.0
		var wants_run := is_sprinting
		var grounded_animation_state := is_on_floor() or tired_jump_active
		var _hold_item := _is_health_item_model(_get_selected_hotbar_item())
		if swing_anim_active:
			pass
		elif jump_anim_active:
			pass
		elif grounded_animation_state:
			if is_crouching:
				if is_walking_forward and animation_player.has_animation("crouchWalk"):
					var _anim := "crouchWalkHold" if _hold_item and animation_player.has_animation("crouchWalkHold") else "crouchWalk"
					if animation_player.current_animation != _anim or animation_player.speed_scale < 0.0:
						animation_player.play(_anim)
				elif is_walking_backward and animation_player.has_animation("crouchWalk"):
					var _anim := "crouchWalkBackHold" if _hold_item and animation_player.has_animation("crouchWalkBackHold") else "crouchWalk"
					if _hold_item and animation_player.has_animation("crouchWalkBackHold"):
						if animation_player.current_animation != _anim:
							animation_player.play(_anim)
					else:
						if animation_player.current_animation != _anim or animation_player.speed_scale > 0.0:
							animation_player.play_backwards(_anim)
				elif is_strafing_right and animation_player.has_animation("crouchStrafeRight"):
					var _anim := "crouchStrafeRightHold" if _hold_item and animation_player.has_animation("crouchStrafeRightHold") else "crouchStrafeRight"
					if animation_player.current_animation != _anim:
						animation_player.play(_anim)
				elif is_strafing_left and animation_player.has_animation("crouchStrafeLeft"):
					var _anim := "crouchStrafeLeftHold" if _hold_item and animation_player.has_animation("crouchStrafeLeftHold") else "crouchStrafeLeft"
					if animation_player.current_animation != _anim:
						animation_player.play(_anim)
				else:
					var _anim := "crouchIdleHold" if _hold_item and animation_player.has_animation("crouchIdleHold") else "crouchIdle"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
			elif animation_player.has_animation("walk"):
				if is_walking_forward:
					if wants_run and animation_player.has_animation("run"):
						if animation_player.current_animation != "run":
							animation_player.play("run")
					else:
						var _anim := "walkHold" if _hold_item and animation_player.has_animation("walkHold") else "walk"
						if animation_player.current_animation != _anim or animation_player.speed_scale < 0.0:
							animation_player.play(_anim)
				elif is_walking_backward:
					var _anim := "walkBackHold" if _hold_item and animation_player.has_animation("walkBackHold") else "walk"
					if _hold_item and animation_player.has_animation("walkBackHold"):
						if animation_player.current_animation != _anim:
							animation_player.play(_anim)
					else:
						if animation_player.current_animation != _anim or animation_player.speed_scale > 0.0:
							animation_player.play_backwards(_anim)
				elif is_strafing_left:
					var _anim := "leftStrafeHold" if _hold_item and animation_player.has_animation("leftStrafeHold") else "leftStrafe"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
				elif is_strafing_right:
					var _anim := "rightStrafeHold" if _hold_item and animation_player.has_animation("rightStrafeHold") else "rightStrafe"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
				else:
					var _anim := "idleHold" if _hold_item and animation_player.has_animation("idleHold") else "idle"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
		elif animation_player.has_animation("jump") and jump_phase != JUMP_PHASE_NONE:
			if animation_player.current_animation != "jump":
				animation_player.play("jump")
		elif animation_player.has_animation("idle") and animation_player.current_animation != "idle":
			# Fallback when no jump animation exists.
			animation_player.play("idle")
	
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 2.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 2.0)
#------------------------------------------------------
#headbob during movement
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)
#------------------------------------------------------
#fov changing
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	_sync_visual_rotation_to_head()

	# Step up tiny bumps while moving so movement stays smooth on uneven floors.
	if input_dir != Vector2.ZERO and is_on_floor() and is_on_wall() and velocity.y <= 0.0 and bump_step_timer <= 0.0:
		velocity.y = BUMP_STEP_VELOCITY
		bump_step_timer = BUMP_STEP_COOLDOWN
	
	move_and_slide()
	if tired_jump_active and is_on_floor():
		tired_jump_active = false
	_try_auto_equip_item()
	_log_player_position()
	_log_attack_overlap_snapshot()

func _setup_attack_overlap_debug() -> void:
	if attack_area == null:
		return

	if not attack_area.area_entered.is_connected(_on_attack_area_entered):
		attack_area.area_entered.connect(_on_attack_area_entered)
	if not attack_area.area_exited.is_connected(_on_attack_area_exited):
		attack_area.area_exited.connect(_on_attack_area_exited)
	if not attack_area.body_entered.is_connected(_on_attack_body_entered):
		attack_area.body_entered.connect(_on_attack_body_entered)
	if not attack_area.body_exited.is_connected(_on_attack_body_exited):
		attack_area.body_exited.connect(_on_attack_body_exited)

	print("[AttackDebug] attack area ready monitoring=%s monitorable=%s layer=%d mask=%d" % [
		str(attack_area.monitoring),
		str(attack_area.monitorable),
		attack_area.collision_layer,
		attack_area.collision_mask,
	])

func _on_attack_area_entered(area: Area3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if area == null:
		return
	print("[AttackDebug] area entered: %s parent=%s" % [area.name, area.get_parent().name if area.get_parent() else "<none>"])

func _on_attack_area_exited(area: Area3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if area == null:
		return
	print("[AttackDebug] area exited: %s parent=%s" % [area.name, area.get_parent().name if area.get_parent() else "<none>"])

func _on_attack_body_entered(body: Node3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if body == null:
		return
	print("[AttackDebug] body entered: %s" % body.name)

func _on_attack_body_exited(body: Node3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if body == null:
		return
	print("[AttackDebug] body exited: %s" % body.name)

func _log_attack_overlap_snapshot() -> void:
	if not debug_attack_overlap_logs:
		return
	if attack_area == null:
		return
	if attack_overlap_log_timer > 0.0:
		return

	attack_overlap_log_timer = 0.25
	var overlapping_areas := attack_area.get_overlapping_areas()
	var overlapping_bodies := attack_area.get_overlapping_bodies()
	var knight_hurtbox_overlap := false

	for area in overlapping_areas:
		if area == null:
			continue
		var parent := area.get_parent()
		if area.name.to_lower().contains("hurtbox") or (parent and parent.name.to_lower().contains("knight")):
			knight_hurtbox_overlap = true
			break

	print("[AttackDebug] snapshot areas=%d bodies=%d knight_hurtbox_overlap=%s" % [
		overlapping_areas.size(),
		overlapping_bodies.size(),
		str(knight_hurtbox_overlap),
	])

func set_movement_locked_by(locker: Node, locked: bool) -> void:
	if locker == null:
		return

	if locked:
		if not movement_lock_sources.has(locker):
			movement_lock_sources.append(locker)
	else:
		movement_lock_sources.erase(locker)

func _is_movement_locked() -> bool:
	return movement_lock_sources.size() > 0

func is_movement_locked_by_other(locker: Node) -> bool:
	for source in movement_lock_sources:
		if source != locker:
			return true
	return false

#function for head bob
func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

func _format_vec3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _update_crouch_state(wants_crouch: bool) -> void:
	if wants_crouch and not is_crouching:
		_enter_crouch()
	elif not wants_crouch and is_crouching:
		_exit_crouch()

func _enter_crouch() -> void:
	if crouch_collision:
		crouch_collision.disabled = false
	if stand_collision:
		stand_collision.disabled = true
	target_head_y = crouch_head_y
	is_crouching = true

func _exit_crouch() -> void:
	if stand_collision:
		stand_collision.disabled = false
	if crouch_collision:
		crouch_collision.disabled = true
	target_head_y = initial_head_position.y
	is_crouching = false

func _update_head_height(delta: float) -> void:
	if head == null:
		return

	head.position.y = lerp(head.position.y, target_head_y, delta * crouch_transition_speed)
	if abs(head.position.y - target_head_y) < 0.001:
		head.position.y = target_head_y

func _setup_stamina_ui() -> void:
	_setup_stamina_palette_colors()

	if stamina_bar_fill == null:
		return

	stamina_bar_initial_scale = stamina_bar_fill.scale
	stamina_bar_fill.pivot_offset = Vector2(0.0, stamina_bar_fill.size.y * 0.5)

func _setup_health_ui() -> void:
	_setup_health_palette_colors()

	if health_bar_fill == null:
		return

	health_bar_initial_scale = health_bar_fill.scale
	health_bar_fill.pivot_offset = Vector2(0.0, health_bar_fill.size.y * 0.5)

func _update_stamina_ui() -> void:
	var stamina_points: int = int(round(clampf(stamina, 0.0, STAMINA_MAX)))
	var active_color: Color = stamina_color_normal if stamina_points >= int(STAMINA_WARNING_THRESHOLD) else stamina_color_low

	if stamina_label_digit != null:
		stamina_label_digit.text = str(stamina_points)
		stamina_label_digit.modulate = active_color

	if stamina_bar_fill == null:
		return

	var stamina_ratio: float = clampf(stamina / STAMINA_MAX, 0.0, 1.0)
	stamina_bar_fill.scale = Vector2(stamina_bar_initial_scale.x * stamina_ratio, stamina_bar_initial_scale.y)
	stamina_bar_fill.modulate = active_color

func _update_health_ui() -> void:
	if health < previous_health - 0.001:
		_show_damage_overlay()

	var health_points: int = int(round(clampf(health, 0.0, HEALTH_MAX)))

	if health_label_digit != null:
		health_label_digit.text = str(health_points)
		health_label_digit.modulate = health_color_normal

	if health_bar_fill == null:
		return

	var health_ratio: float = clampf(health / HEALTH_MAX, 0.0, 1.0)
	health_bar_fill.scale = Vector2(health_bar_initial_scale.x * health_ratio, health_bar_initial_scale.y)
	health_bar_fill.modulate = health_color_normal
	previous_health = health

func _setup_damage_overlay() -> void:
	previous_health = health
	if player_canvas_layer == null:
		return

	var blood_texture := load(BLOOD_OVERLAY_PATH) as Texture2D
	if blood_texture == null:
		push_warning("Blood overlay texture not found at: %s" % BLOOD_OVERLAY_PATH)
		return

	damage_overlay = TextureRect.new()
	damage_overlay.name = "DamageOverlay"
	damage_overlay.texture = blood_texture
	damage_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_overlay.z_index = 100
	player_canvas_layer.add_child(damage_overlay)

func _show_damage_overlay() -> void:
	if damage_overlay == null:
		return

	if damage_overlay_tween:
		damage_overlay_tween.kill()

	var color := damage_overlay.modulate
	color.a = DAMAGE_OVERLAY_MAX_ALPHA
	damage_overlay.modulate = color

	damage_overlay_tween = create_tween()
	damage_overlay_tween.tween_property(damage_overlay, "modulate:a", 0.0, DAMAGE_OVERLAY_FADE_TIME)

func _setup_hotbar_ui() -> void:
	hotbar_font = load(HOTBAR_ITEM_LABEL_FONT_PATH) as FontFile
	hotbar_slots = [
		$CanvasLayer/Control/Hotbar/Slot1,
		$CanvasLayer/Control/Hotbar/Slot2,
		$CanvasLayer/Control/Hotbar/Slot3,
		$CanvasLayer/Control/Hotbar/Slot4,
		$CanvasLayer/Control/Hotbar/Slot5,
	]
	hotbar_slot_base_scales.clear()
	hotbar_item_icons.clear()
	hotbar_item_models = []

	for slot in hotbar_slots:
		slot.pivot_offset = slot.size * 0.5
		hotbar_slot_base_scales.append(slot.scale)
		hotbar_item_models.append(null)
		var item_icon := slot.get_node_or_null("ItemIcon") as TextureRect
		if item_icon == null:
			item_icon = TextureRect.new()
			item_icon.name = "ItemIcon"
			item_icon.anchor_left = 0.0
			item_icon.anchor_top = 0.0
			item_icon.anchor_right = 1.0
			item_icon.anchor_bottom = 1.0
			item_icon.offset_left = 4.0
			item_icon.offset_top = 4.0
			item_icon.offset_right = -4.0
			item_icon.offset_bottom = -4.0
			item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(item_icon)
		item_icon.texture = null
		item_icon.visible = false
		hotbar_item_icons.append(item_icon)

func _select_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_slots.size():
		return

	selected_hotbar_slot_index = slot_index
	for i in hotbar_slots.size():
		var slot := hotbar_slots[i]
		var base_scale := hotbar_slot_base_scales[i] if i < hotbar_slot_base_scales.size() else Vector2.ONE
		slot.scale = base_scale * (HOTBAR_SELECTED_SCALE if i == selected_hotbar_slot_index else HOTBAR_DEFAULT_SCALE)

	_refresh_selected_item_state()
	_update_hotbar_windup_indicator()

func _hotbar_index_from_keycode(keycode: int) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		_:
			return -1

func _set_hotbar_item(slot_index: int, item_model: Node3D, item_icon_texture: Texture2D) -> void:
	if slot_index < 0 or slot_index >= hotbar_item_models.size():
		return

	hotbar_item_models[slot_index] = item_model
	var item_icon := hotbar_item_icons[slot_index] if slot_index < hotbar_item_icons.size() else null
	if item_icon:
		item_icon.texture = item_icon_texture
		item_icon.visible = item_icon_texture != null

func _find_first_empty_hotbar_slot() -> int:
	for i in hotbar_item_models.size():
		var item_model := hotbar_item_models[i]
		if item_model == null or not is_instance_valid(item_model):
			return i
	return -1

func _get_selected_hotbar_item() -> Node3D:
	if selected_hotbar_slot_index < 0 or selected_hotbar_slot_index >= hotbar_item_models.size():
		return null

	var selected_item := hotbar_item_models[selected_hotbar_slot_index]
	if selected_item == null or not is_instance_valid(selected_item):
		return null

	return selected_item

func _is_primary_item_model(item_model: Node) -> bool:
	return item_model is Axe or item_model is Bat or _is_shovel_item_model(item_model) or _is_health_item_model(item_model)

func _is_shovel_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == SHOVEL_ITEM_SCRIPT

func _is_health_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == HEALTH_ITEM_SCRIPT

func _get_selected_primary_item() -> Node:
	var selected_item := _get_selected_hotbar_item()
	if _is_primary_item_model(selected_item):
		return selected_item
	return null

func _has_item_in_hotbar(item: Node) -> bool:
	if item == null:
		return false

	for hotbar_item in hotbar_item_models:
		if hotbar_item == item and is_instance_valid(hotbar_item):
			return true
	return false

func _refresh_selected_item_state() -> void:
	for item_model in hotbar_item_models:
		if _is_primary_item_model(item_model) and is_instance_valid(item_model):
			item_model.call("refresh_inventory_state", self, selected_hotbar_slot_index, is_sprinting)

func _update_selected_item_action(delta: float) -> bool:
	var selected_item := _get_selected_primary_item()
	if selected_item == null:
		return false

	return bool(selected_item.call("update_primary_action", self, delta))

func _can_trigger_swing_from_selected_slot() -> bool:
	var selected_item := _get_selected_primary_item()
	return selected_item != null and bool(selected_item.call("can_start_primary_action"))

func _get_item_display_name_from_model(item_node: Node) -> String:
	if item_node == null:
		return "Item"

	var raw_name := item_node.name
	if raw_name.is_empty():
		return "Item"

	var words := raw_name.replace("-", " ").replace("_", " ").split(" ", false)
	if words.is_empty():
		return raw_name

	for i in words.size():
		words[i] = words[i].capitalize()

	return " ".join(words)

func _drop_selected_hotbar_item() -> void:
	var selected_item := _get_selected_hotbar_item()
	if selected_item == null:
		return

	if _is_primary_item_model(selected_item):
		if bool(selected_item.call("drop_from_hotbar", self)):
			_set_hotbar_item(selected_hotbar_slot_index, null, null)
			_refresh_selected_item_state()
			_update_pickup_prompt_visibility()
	else:
		push_warning("Drop not implemented for selected item model: %s" % selected_item.name)


func _pickup_item_into_hotbar(item_body: Node3D) -> void:
	if item_body == null:
		return

	if item_body is Axe or item_body is Bat or _is_shovel_item_model(item_body) or _is_health_item_model(item_body):
		if _has_item_in_hotbar(item_body):
			return

		var slot_index := _find_first_empty_hotbar_slot()
		if slot_index == -1:
			push_warning("Hotbar is full. Cannot pick up item.")
			return

		if bool(item_body.call("pick_up_into_hotbar", self, slot_index)):
			_set_hotbar_item(slot_index, item_body, item_body.call("get_hotbar_icon_texture"))
			_refresh_selected_item_state()
			_update_pickup_prompt_visibility()
	else:
		push_warning("Pickup not implemented for item model: %s" % item_body.name)

func _try_auto_equip_item() -> void:
	if _find_first_empty_hotbar_slot() == -1:
		return
	if not (Axe.is_equip_input_just_pressed() or bool(SHOVEL_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(HEALTH_ITEM_SCRIPT.call("is_equip_input_just_pressed"))):
		return

	var item_body := _get_pickup_candidate()
	if item_body == null:
		return

	_pickup_item_into_hotbar(item_body)

func _set_visual_children_visible(node: Node, visibility: bool) -> void:
	if node is VisualInstance3D:
		node.visible = visibility
	for child in node.get_children():
		_set_visual_children_visible(child, visibility)

func _get_pickup_candidate() -> RigidBody3D:
	if camera == null:
		return null

	var origin: Vector3 = camera.global_transform.origin
	var pickup_distance: float = maxf(Axe.get_pickup_max_distance(), maxf(Bat.get_pickup_max_distance(), maxf(float(SHOVEL_ITEM_SCRIPT.call("get_pickup_max_distance")), float(HEALTH_ITEM_SCRIPT.call("get_pickup_max_distance")))))
	var end: Vector3 = origin + (-camera.global_transform.basis.z * pickup_distance)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider := result.get("collider") as Node
	if collider == null:
		return null

	var bat_candidate := Bat.find_bat_rigidbody_from_node(collider)
	if bat_candidate:
		return bat_candidate

	var axe_candidate := Axe.find_axe_rigidbody_from_node(collider)
	if axe_candidate:
		return axe_candidate

	var shovel_candidate := SHOVEL_ITEM_SCRIPT.call("find_shovel_rigidbody_from_node", collider) as RigidBody3D
	if shovel_candidate:
		return shovel_candidate

	return HEALTH_ITEM_SCRIPT.call("find_health_rigidbody_from_node", collider) as RigidBody3D

func _update_pickup_prompt_visibility() -> void:
	if pickup_control == null:
		return

	pickup_control.visible = _find_first_empty_hotbar_slot() != -1 and _get_pickup_candidate() != null

func _has_any_primary_item_in_hotbar() -> bool:
	for item_model in hotbar_item_models:
		if _is_primary_item_model(item_model) and is_instance_valid(item_model):
			return true
	return false

func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_update_health_ui()

func _setup_stamina_palette_colors() -> void:
	var palette_texture := load(STAMINA_PALETTE_PATH) as Texture2D
	if palette_texture == null:
		push_warning("Stamina palette texture not found at: %s" % STAMINA_PALETTE_PATH)
		return

	var palette_image := palette_texture.get_image()
	if palette_image == null or palette_image.is_empty():
		push_warning("Stamina palette image is empty: %s" % STAMINA_PALETTE_PATH)
		return

	stamina_color_normal = _get_palette_color(palette_image, STAMINA_COLOR_NORMAL_INDEX, stamina_color_normal)
	stamina_color_low = _get_palette_color(palette_image, STAMINA_COLOR_LOW_INDEX, stamina_color_low)

func _setup_health_palette_colors() -> void:
	var palette_texture := load(STAMINA_PALETTE_PATH) as Texture2D
	if palette_texture == null:
		push_warning("Health palette texture not found at: %s" % STAMINA_PALETTE_PATH)
		return

	var palette_image := palette_texture.get_image()
	if palette_image == null or palette_image.is_empty():
		push_warning("Health palette image is empty: %s" % STAMINA_PALETTE_PATH)
		return

	health_color_normal = _get_palette_color(palette_image, HEALTH_COLOR_NORMAL_INDEX, health_color_normal)

func _update_hotbar_windup_indicator() -> void:
	for i in hotbar_item_icons.size():
		var item_icon := hotbar_item_icons[i]
		if item_icon == null:
			continue

		var alpha := 1.0 if i == selected_hotbar_slot_index else 0.85
		var icon_color := Color(1.0, 1.0, 1.0, alpha)

		if i == selected_hotbar_slot_index:
			var selected_item := _get_selected_primary_item()
			if selected_item != null:
				icon_color = selected_item.call("get_hotbar_icon_modulate", alpha)

		item_icon.modulate = icon_color

func _get_palette_color(palette_image: Image, one_based_index: int, fallback: Color) -> Color:
	if one_based_index <= 0:
		return fallback

	var width := palette_image.get_width()
	var height := palette_image.get_height()
	if width <= 0 or height <= 0:
		return fallback

	var max_colors := width * height
	if one_based_index > max_colors:
		return fallback

	var linear_index := one_based_index - 1
	var pixel_x := linear_index % width
	var pixel_y := int(float(linear_index) / float(width))
	return palette_image.get_pixel(pixel_x, pixel_y)

func _set_control_mouse_filter_recursive(node: Control, mouse_filter: Control.MouseFilter) -> void:
	if node == null:
		return

	node.mouse_filter = mouse_filter
	for child in node.get_children():
		if child is Control:
			_set_control_mouse_filter_recursive(child as Control, mouse_filter)

func _log_player_position() -> void:
	if not debug_position_logs:
		return
	if position_log_timer > 0.0:
		return
	position_log_timer = POSITION_LOG_INTERVAL
	print("[PlayerPos] player=%s velocity=%s on_floor=%s" % [
		_format_vec3(global_position),
		_format_vec3(velocity),
		str(is_on_floor()),
	])

# Debug function to check collision state
func _input(event):
	if event.is_action_pressed("ui_cancel"):  # ESC key - toggle mouse mode for debugging
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if event.is_action_pressed("space"):  # Space key - print debug info
		print("=== PLAYER DEBUG INFO ===")
		print("Position: ", global_position)
		print("Velocity: ", velocity)
		print("Is on floor: ", is_on_floor())
		print("Floor normal: ", get_floor_normal())
		print("Wall normal: ", get_wall_normal())
		print("Slide collision count: ", get_slide_collision_count())
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			print("Collision ", i, ": ", collision.get_collider(), " at ", collision.get_position())

# Helper function to set visual layer for all mesh instances recursively
func _set_layer_recursive(node: Node, layer: int):
	if node is VisualInstance3D:
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_layer_recursive(child, layer)

func _resolve_visual_root() -> Node3D:
	if not visual_root_path.is_empty():
		var configured_visual_root := get_node_or_null(visual_root_path) as Node3D
		if configured_visual_root:
			return configured_visual_root

	for child in get_children():
		if child is Node3D and child != head and _has_visual_descendant(child):
			return child as Node3D

	return null

func _resolve_animation_player() -> AnimationPlayer:
	if not animation_player_path.is_empty():
		var configured_animation_player := get_node_or_null(animation_player_path) as AnimationPlayer
		if configured_animation_player:
			return configured_animation_player

	if visual_root:
		return _find_animation_player_recursive(visual_root)

	return null

func _sync_visual_rotation_to_head() -> void:
	if visual_root:
		visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)

func _has_visual_descendant(node: Node) -> bool:
	if node is VisualInstance3D:
		return true
	for child in node.get_children():
		if _has_visual_descendant(child):
			return true
	return false

func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player_recursive(child)
		if found:
			return found
	return null

func _update_jump_animation_phase(delta: float) -> bool:
	if animation_player == null:
		jump_phase = JUMP_PHASE_NONE
		return false
	if not animation_player.has_animation("jump"):
		jump_phase = JUMP_PHASE_NONE
		return false

	if jump_phase == JUMP_PHASE_NONE:
		return false

	if animation_player.current_animation != "jump":
		animation_player.play("jump")
	animation_player.speed_scale = 1.0

	var jump_animation := animation_player.get_animation("jump")
	if jump_animation == null:
		jump_phase = JUMP_PHASE_NONE
		return false

	var min_loop_frame := float(JUMP_AIR_LOOP_MIN_FRAME)
	var hold_frame := float(JUMP_HOLD_FRAME)
	var frame_step := JUMP_ANIMATION_FPS * delta * JUMP_AIR_LOOP_SPEED
	if not is_on_floor():
		if jump_air_loop_forward:
			jump_air_loop_frame += frame_step
			if jump_air_loop_frame >= hold_frame:
				jump_air_loop_frame = hold_frame
				jump_air_loop_forward = false
		else:
			jump_air_loop_frame -= frame_step
			if jump_air_loop_frame <= min_loop_frame:
				jump_air_loop_frame = min_loop_frame
				jump_air_loop_forward = true

		var loop_time := (jump_air_loop_frame - 1.0) / JUMP_ANIMATION_FPS
		animation_player.seek(loop_time, true)
	else:
		var hold_time := (hold_frame - 1.0) / JUMP_ANIMATION_FPS
		if animation_player.current_animation_position < hold_time:
			animation_player.seek(hold_time, true)

	if animation_player.current_animation_position >= jump_animation.length - 0.02:
		jump_phase = JUMP_PHASE_NONE
		jump_air_loop_frame = float(JUMP_AIR_LOOP_MIN_FRAME)
		jump_air_loop_forward = true
		return false

	return true
