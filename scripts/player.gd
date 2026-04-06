extends CharacterBody3D

# Reusable held item transform component
class HeldItemTransform:
	var local_position: Vector3
	var local_rotation_degrees: Vector3
	var local_scale: float
	var flip_blade_face: bool = false
	var blade_flip_axis: int = 0  # 0=X, 1=Y, 2=Z
	
	func _init(pos: Vector3, rot: Vector3, scale: float, flip: bool = false, axis: int = 0):
		local_position = pos
		local_rotation_degrees = rot
		local_scale = scale
		local_rotation_degrees = rot
		local_scale = scale
		flip_blade_face = flip
		blade_flip_axis = axis

#variables and constants
const WALK_SPEED = 7.0
const SPRINT_SPEED = 11.0
const CROUCH_SPEED = 3.5
const STAMINA_MAX = 100.0
const STAMINA_WARNING_THRESHOLD = 20.0
const STAMINA_COLOR_NORMAL_INDEX = 18
const STAMINA_COLOR_LOW_INDEX = 17
const ITEM_WINDUP_COLOR_START_INDEX = 17
const ITEM_WINDUP_COLOR_END_INDEX = 22
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
const AXE_SCENE_PATH = "res://assets/items/axe.tscn"
const AXE_ATTACHMENT_NODE_NAME = "RightHandAxeAttachment"
const SWING_ANIMATION_NAME = "swing"
const SWING_ANIMATION_FPS = 30.0
const SWING_WINDUP_END_FRAME = 57
const SWING_RELEASE_FRAME = 58
const SWING_RELEASE_SPEED_MULTIPLIER = 1.3
const SWING_DAMAGE_FULL = 20.0
const SWING_DAMAGE_INCOMPLETE = 7.0
const AXE_ITEM_ICON: Texture2D = preload("res://assets/ui/axe.png")
const HOTBAR_SLOT_COUNT = 5
const HOTBAR_SELECTED_SCALE = 1.18
const HOTBAR_DEFAULT_SCALE = 1.0
const HOTBAR_ITEM_LABEL_FONT_PATH = "res://assets/ui/dungeon-mode.ttf"
const ITEM_DROP_FORWARD_DISTANCE = 1.0
const ITEM_DROP_DOWN_OFFSET = -0.25
const ITEM_DROP_FORWARD_SPEED = 2.0
const ITEM_DROP_UPWARD_SPEED = 0.5
@export_range(2.0, 80.0, 0.5) var vision_distance: float = 20.0
@export_range(0.5, 10.0, 0.1) var vision_radius: float = 3.0
@export var debug_position_logs: bool = false
@export var hide_visual_from_player_camera: bool = true
@export_range(-360.0, 360.0, 1.0) var visual_yaw_offset_degrees: float = 180.0
@export_range(0.5, 5.0, 0.1) var axe_pickup_max_distance: float = 2.0
@export var axe_equip_action_name: StringName = &"interact"
@export var right_hand_bone_name: String = "mixamorig_RightHand"
# Axe held item configuration (position, rotation, scale, flip blade, flip axis)
@export var axe_held_item_position: Vector3 = Vector3(0.03, 0.07, -0.04)
@export var axe_held_item_rotation_degrees: Vector3 = Vector3(-88.0, 90.0, 276.0)
@export_range(0.1, 2.0, 0.1) var axe_held_item_scale: float = 0.7
@export var axe_held_item_flip_blade: bool = true
@export_enum("X", "Y", "Z") var axe_held_item_flip_axis: int = 0
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
var is_swing_attacking: bool = false
var swing_in_progress: bool = false
var swing_animation_finished: bool = false
var swing_force_release: bool = false
var swing_was_released_early: bool = false
var swing_damage_ready: bool = false
var current_swing_damage: float = SWING_DAMAGE_INCOMPLETE
var jump_phase: int = 0
var jump_air_loop_frame: float = float(JUMP_AIR_LOOP_MIN_FRAME)
var jump_air_loop_forward: bool = true
var stamina_color_normal: Color = Color(1.0, 1.0, 1.0, 1.0)
var stamina_color_low: Color = Color(1.0, 0.3, 0.3, 1.0)
var health_color_normal: Color = Color(1.0, 1.0, 1.0, 1.0)
var item_windup_color_start: Color = Color(1.0, 0.3, 0.3, 1.0)
var item_windup_color_end: Color = Color(0.3, 1.0, 0.3, 1.0)

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
var equipped_axe: RigidBody3D = null
var right_hand_attachment: BoneAttachment3D = null
var equip_key_was_down: bool = false
var hotbar_slots: Array[NinePatchRect] = []
var hotbar_slot_base_scales: Array[Vector2] = []
var hotbar_item_icons: Array[TextureRect] = []
var hotbar_item_models: Array[Node3D] = []
var selected_hotbar_slot_index: int = 0
var axe_inventory_slot_index: int = -1
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
	_setup_item_windup_palette_colors()
	_setup_damage_overlay()
	_setup_hotbar_ui()
	_select_hotbar_slot(0)
	_update_stamina_ui()
	_update_health_ui()
	
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
				if not _can_trigger_swing_from_selected_slot():
					is_swing_attacking = false
					return

				if not swing_in_progress:
					swing_animation_finished = false
					is_swing_attacking = true
					swing_in_progress = true
					swing_force_release = false
					swing_was_released_early = false
					swing_damage_ready = false
					current_swing_damage = SWING_DAMAGE_INCOMPLETE
					set_movement_locked_by(self, true)
				elif swing_in_progress and _is_swing_in_windup():
					swing_force_release = true
					swing_was_released_early = true
			else:
				is_swing_attacking = false
				if swing_in_progress and _is_swing_in_windup():
					swing_force_release = true
					swing_was_released_early = true
				# Rearm input for the next click once not in-progress.
				if not swing_in_progress:
					swing_animation_finished = false
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
	_update_held_item_visibility_for_sprint()
	_update_hotbar_windup_indicator()
	_update_stamina_ui()
#------------------------------------------------------
#wasd direction input and other physics
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Animation handling
	if animation_player:
		var swing_anim_active := _update_swing_animation()
		var jump_anim_active := _update_jump_animation_phase(delta)
		var is_walking_forward := input_dir.y < 0.0
		var is_walking_backward := input_dir.y > 0.0
		var is_strafing_left := input_dir.x < 0.0
		var is_strafing_right := input_dir.x > 0.0
		var wants_run := is_sprinting
		var grounded_animation_state := is_on_floor() or tired_jump_active
		if swing_anim_active:
			pass
		elif jump_anim_active:
			pass
		elif grounded_animation_state:
			if is_crouching:
				if is_walking_forward and animation_player.has_animation("crouchWalk"):
					if animation_player.current_animation != "crouchWalk" or animation_player.speed_scale < 0.0:
						animation_player.play("crouchWalk")
				elif is_walking_backward and animation_player.has_animation("crouchWalk"):
					if animation_player.current_animation != "crouchWalk" or animation_player.speed_scale > 0.0:
						animation_player.play_backwards("crouchWalk")
				elif is_strafing_right and animation_player.has_animation("crouchStrafeRight"):
					if animation_player.current_animation != "crouchStrafeRight":
						animation_player.play("crouchStrafeRight")
				elif is_strafing_left and animation_player.has_animation("crouchStrafeLeft"):
					if animation_player.current_animation != "crouchStrafeLeft":
						animation_player.play("crouchStrafeLeft")
				elif animation_player.has_animation("crouchIdle") and animation_player.current_animation != "crouchIdle":
					animation_player.play("crouchIdle")
			elif animation_player.has_animation("walk"):
				if is_walking_forward:
					if wants_run and animation_player.has_animation("run"):
						if animation_player.current_animation != "run":
							animation_player.play("run")
					elif animation_player.current_animation != "walk" or animation_player.speed_scale < 0.0:
						animation_player.play("walk")
				elif is_walking_backward:
					if animation_player.current_animation != "walk" or animation_player.speed_scale > 0.0:
						animation_player.play_backwards("walk")
				elif is_strafing_left and animation_player.has_animation("leftStrafe"):
					if animation_player.current_animation != "leftStrafe":
						animation_player.play("leftStrafe")
				elif is_strafing_right and animation_player.has_animation("rightStrafe"):
					if animation_player.current_animation != "rightStrafe":
						animation_player.play("rightStrafe")
				elif animation_player.has_animation("idle") and animation_player.current_animation != "idle":
					animation_player.play("idle")
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
	_try_auto_equip_axe()
	_log_player_position()

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
		item_icon.texture = AXE_ITEM_ICON
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

	_refresh_axe_inventory_state()
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

func _can_trigger_swing_from_selected_slot() -> bool:
	if selected_hotbar_slot_index < 0 or selected_hotbar_slot_index >= hotbar_item_models.size():
		return false

	var selected_item := hotbar_item_models[selected_hotbar_slot_index]
	if selected_item == null or not is_instance_valid(selected_item):
		return false

	# Swing is only valid when the selected slot corresponds to the currently equipped held item.
	return selected_item == equipped_axe

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
	if selected_hotbar_slot_index < 0 or selected_hotbar_slot_index >= hotbar_item_models.size():
		return

	var selected_item_model := hotbar_item_models[selected_hotbar_slot_index]
	if selected_item_model == null or not is_instance_valid(selected_item_model):
		return

	if selected_item_model == equipped_axe:
		_drop_axe_from_slot(selected_hotbar_slot_index)
	else:
		push_warning("Drop not implemented for selected item model: %s" % selected_item_model.name)

func _drop_axe_from_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_item_models.size():
		return

	if equipped_axe == null:
		_set_hotbar_item(slot_index, null, null)
		axe_inventory_slot_index = -1
		_update_pickup_prompt_visibility()
		return

	var dropped_item := equipped_axe
	var world_root := get_tree().current_scene
	if world_root == null:
		world_root = get_parent()

	var drop_origin := dropped_item.global_position
	if camera:
		drop_origin = camera.global_position + (-camera.global_transform.basis.z * ITEM_DROP_FORWARD_DISTANCE) + Vector3(0.0, ITEM_DROP_DOWN_OFFSET, 0.0)

	var old_parent := dropped_item.get_parent()
	if old_parent:
		old_parent.remove_child(dropped_item)

	if world_root:
		world_root.add_child(dropped_item)
	else:
		add_child(dropped_item)

	dropped_item.global_position = drop_origin
	_set_item_visuals_visible(dropped_item, true)
	_set_item_physics_enabled(dropped_item, true)

	if dropped_item is RigidBody3D:
		var dropped_rigid_body := dropped_item as RigidBody3D
		var forward := -global_transform.basis.z
		if camera:
			forward = -camera.global_transform.basis.z
		dropped_rigid_body.linear_velocity = (forward * ITEM_DROP_FORWARD_SPEED) + (Vector3.UP * ITEM_DROP_UPWARD_SPEED)

	_set_hotbar_item(slot_index, null, null)
	axe_inventory_slot_index = -1
	equipped_axe = null
	_update_pickup_prompt_visibility()

func _pickup_axe_into_hotbar(axe_body: RigidBody3D) -> void:
	if axe_body == null or equipped_axe != null:
		return

	var slot_index := _find_first_empty_hotbar_slot()
	if slot_index == -1:
		push_warning("Hotbar is full. Cannot pick up axe.")
		return

	equipped_axe = axe_body
	axe_inventory_slot_index = slot_index
	_set_hotbar_item(slot_index, axe_body, AXE_ITEM_ICON)
	_move_axe_into_inventory()
	_refresh_axe_inventory_state()
	_update_pickup_prompt_visibility()

func _move_axe_into_inventory() -> void:
	if equipped_axe == null:
		return

	var old_parent := equipped_axe.get_parent()
	if old_parent:
		old_parent.remove_child(equipped_axe)
	add_child(equipped_axe)
	_set_item_physics_enabled(equipped_axe, false)
	_set_item_visuals_visible(equipped_axe, false)

func _refresh_axe_inventory_state() -> void:
	if equipped_axe == null:
		return

	if axe_inventory_slot_index == selected_hotbar_slot_index:
		_equip_axe_to_right_hand(equipped_axe)
	else:
		_detach_axe_from_hand()

	_update_held_item_visibility_for_sprint()

func _update_held_item_visibility_for_sprint() -> void:
	if equipped_axe == null:
		return

	var should_be_visible := axe_inventory_slot_index == selected_hotbar_slot_index and not is_sprinting
	_set_item_visuals_visible(equipped_axe, should_be_visible)

func _detach_axe_from_hand() -> void:
	if equipped_axe == null:
		return

	var desired_parent := self
	if equipped_axe.get_parent() != desired_parent:
		var old_parent := equipped_axe.get_parent()
		if old_parent:
			old_parent.remove_child(equipped_axe)
		add_child(equipped_axe)
	_set_item_physics_enabled(equipped_axe, false)
	_set_item_visuals_visible(equipped_axe, false)

func _set_visual_children_visible(node: Node, visible: bool) -> void:
	if node is VisualInstance3D:
		node.visible = visible
	for child in node.get_children():
		_set_visual_children_visible(child, visible)

func _try_auto_equip_axe() -> void:
	if equipped_axe != null:
		return
	if not _is_equip_input_just_pressed():
		return

	var axe_body := _get_pickup_candidate()
	if axe_body == null:
		return

	_pickup_axe_into_hotbar(axe_body)

func _get_pickup_candidate() -> RigidBody3D:
	if camera == null:
		return null

	var origin: Vector3 = camera.global_transform.origin
	var end: Vector3 = origin + (-camera.global_transform.basis.z * axe_pickup_max_distance)
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

	return _find_axe_rigidbody_from_node(collider)

func _update_pickup_prompt_visibility() -> void:
	if pickup_control == null:
		return

	pickup_control.visible = equipped_axe == null and _get_pickup_candidate() != null

func _set_control_mouse_filter_recursive(node: Control, mouse_filter: int) -> void:
	if node == null:
		return

	node.mouse_filter = mouse_filter
	for child in node.get_children():
		if child is Control:
			_set_control_mouse_filter_recursive(child as Control, mouse_filter)

func _is_equip_input_just_pressed() -> bool:
	if not axe_equip_action_name.is_empty() and InputMap.has_action(axe_equip_action_name):
		return Input.is_action_just_pressed(axe_equip_action_name)

	# Fallback to physical E key if no action is configured.
	var is_down := Input.is_physical_key_pressed(KEY_E)
	var just_pressed := is_down and not equip_key_was_down
	equip_key_was_down = is_down
	return just_pressed

func _find_axe_rigidbody_from_node(node: Node) -> RigidBody3D:
	var current: Node = node
	while current != null:
		if current is RigidBody3D:
			var body := current as RigidBody3D
			if _is_axe_node(body):
				return body
		if current is Node3D and _is_axe_node(current):
			for child in current.get_children():
				if child is RigidBody3D and _is_axe_node(child):
					return child as RigidBody3D
		current = current.get_parent()
	return null

func _is_axe_node(node: Node) -> bool:
	if node == null:
		return false

	if node.scene_file_path == AXE_SCENE_PATH:
		return true

	var lower_name := node.name.to_lower()
	if lower_name == "axe" or lower_name.ends_with("axe"):
		return true

	return false

func _equip_axe_to_right_hand(axe_body: RigidBody3D) -> void:
	if axe_body == null:
		return

	var held_item := HeldItemTransform.new(
		axe_held_item_position,
		axe_held_item_rotation_degrees,
		axe_held_item_scale,
		axe_held_item_flip_blade,
		axe_held_item_flip_axis
	)
	_equip_item_to_hand(axe_body, held_item)
	equipped_axe = axe_body

func _equip_item_to_hand(item_body: Node3D, held_item: HeldItemTransform) -> void:
	if item_body == null or held_item == null:
		return

	var attachment := _get_or_create_right_hand_attachment()
	if attachment == null:
		push_warning("Could not attach item: right hand bone attachment is missing.")
		return

	var old_parent := item_body.get_parent()
	if old_parent:
		old_parent.remove_child(item_body)
	attachment.add_child(item_body)

	_set_item_physics_enabled(item_body, false)
	_set_item_visuals_visible(item_body, true)

	item_body.position = held_item.local_position
	item_body.rotation = Vector3(
		deg_to_rad(held_item.local_rotation_degrees.x),
		deg_to_rad(held_item.local_rotation_degrees.y),
		deg_to_rad(held_item.local_rotation_degrees.z)
	)
	item_body.scale = Vector3.ONE * held_item.local_scale
	_apply_item_blade_flip(item_body, held_item)

func _apply_item_blade_flip(item_body: Node3D, held_item: HeldItemTransform) -> void:
	if item_body == null or not held_item.flip_blade_face:
		return

	match held_item.blade_flip_axis:
		0:
			item_body.rotate_object_local(Vector3.RIGHT, PI)
		1:
			item_body.rotate_object_local(Vector3.UP, PI)
		2:
			item_body.rotate_object_local(Vector3.FORWARD, PI)

func _set_item_physics_enabled(item_body: Node3D, enabled: bool) -> void:
	if item_body == null:
		return

	if item_body is RigidBody3D:
		var rigid_body = item_body as RigidBody3D
		rigid_body.freeze = not enabled
		rigid_body.sleeping = not enabled
		rigid_body.linear_velocity = Vector3.ZERO
		rigid_body.angular_velocity = Vector3.ZERO
		rigid_body.collision_layer = 0 if not enabled else 1
		rigid_body.collision_mask = 0 if not enabled else 1
		var item_collision := rigid_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if item_collision:
			item_collision.disabled = not enabled

func _set_item_visuals_visible(item_body: Node3D, visible: bool) -> void:
	if item_body == null:
		return
	_set_visual_children_visible(item_body, visible)

func _get_or_create_right_hand_attachment() -> BoneAttachment3D:
	if right_hand_attachment and is_instance_valid(right_hand_attachment):
		return right_hand_attachment

	var skeleton := _find_skeleton_recursive(visual_root)
	if skeleton == null:
		return null

	var existing := skeleton.get_node_or_null(AXE_ATTACHMENT_NODE_NAME) as BoneAttachment3D
	if existing:
		right_hand_attachment = existing
		return right_hand_attachment

	var resolved_bone_name := _resolve_right_hand_bone_name(skeleton)
	if resolved_bone_name.is_empty():
		return null

	var attachment := BoneAttachment3D.new()
	attachment.name = AXE_ATTACHMENT_NODE_NAME
	attachment.bone_name = resolved_bone_name
	skeleton.add_child(attachment)
	right_hand_attachment = attachment
	return right_hand_attachment

func _resolve_right_hand_bone_name(skeleton: Skeleton3D) -> String:
	if skeleton == null:
		return ""

	if not right_hand_bone_name.is_empty() and skeleton.find_bone(right_hand_bone_name) != -1:
		return right_hand_bone_name

	var fallback_bone := ""
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		var lower_name := bone_name.to_lower()
		if lower_name.contains("right") and lower_name.contains("hand"):
			return bone_name
		if fallback_bone.is_empty() and lower_name.contains("hand"):
			fallback_bone = bone_name

	return fallback_bone

func _find_skeleton_recursive(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton_recursive(child)
		if found:
			return found
	return null

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

func _setup_item_windup_palette_colors() -> void:
	var palette_texture := load(STAMINA_PALETTE_PATH) as Texture2D
	if palette_texture == null:
		push_warning("Item windup palette texture not found at: %s" % STAMINA_PALETTE_PATH)
		return

	var palette_image := palette_texture.get_image()
	if palette_image == null or palette_image.is_empty():
		push_warning("Item windup palette image is empty: %s" % STAMINA_PALETTE_PATH)
		return

	item_windup_color_start = _get_palette_color(palette_image, ITEM_WINDUP_COLOR_START_INDEX, item_windup_color_start)
	item_windup_color_end = _get_palette_color(palette_image, ITEM_WINDUP_COLOR_END_INDEX, item_windup_color_end)

func _update_hotbar_windup_indicator() -> void:
	for i in hotbar_item_icons.size():
		var item_icon := hotbar_item_icons[i]
		if item_icon == null:
			continue

		var alpha := 1.0 if i == selected_hotbar_slot_index else 0.85
		var icon_color := Color(1.0, 1.0, 1.0, alpha)

		if i == selected_hotbar_slot_index and hotbar_item_models[i] == equipped_axe and equipped_axe != null:
			if _is_swing_windup_active():
				var windup_percent := _get_swing_windup_percent()
				var windup_color := item_windup_color_start.lerp(item_windup_color_end, windup_percent)
				icon_color = Color(windup_color.r, windup_color.g, windup_color.b, alpha)

		item_icon.modulate = icon_color

func _get_swing_windup_percent() -> float:
	if not _is_swing_windup_active():
		return 0.0

	var release_time := _swing_frame_to_time(SWING_RELEASE_FRAME)
	if release_time <= 0.0:
		return 0.0

	return clampf(animation_player.current_animation_position / release_time, 0.0, 1.0)

func _is_swing_windup_active() -> bool:
	if not swing_in_progress or animation_player == null:
		return false
	if animation_player.current_animation != SWING_ANIMATION_NAME:
		return false

	return animation_player.current_animation_position < _swing_frame_to_time(SWING_RELEASE_FRAME)

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
	var pixel_y := linear_index / width
	return palette_image.get_pixel(pixel_x, pixel_y)

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

func _update_swing_animation() -> bool:
	if animation_player == null:
		if swing_in_progress:
			swing_in_progress = false
			swing_force_release = false
			swing_damage_ready = false
			set_movement_locked_by(self, false)
		return false
	if not animation_player.has_animation(SWING_ANIMATION_NAME):
		if swing_in_progress:
			swing_in_progress = false
			swing_force_release = false
			swing_damage_ready = false
			set_movement_locked_by(self, false)
		return false
	
	if swing_in_progress:
		if animation_player.current_animation != SWING_ANIMATION_NAME:
			animation_player.play(SWING_ANIMATION_NAME)
		
		var swing_animation := animation_player.get_animation(SWING_ANIMATION_NAME)
		if swing_animation == null:
			swing_in_progress = false
			swing_force_release = false
			swing_damage_ready = false
			set_movement_locked_by(self, false)
			return false

		var release_time := _swing_frame_to_time(SWING_RELEASE_FRAME)
		if animation_player.current_animation_position < release_time and swing_force_release:
			animation_player.seek(release_time, true)
			swing_force_release = false
			swing_was_released_early = true

		# Keep windup at normal speed, then speed up committed swing by 30%.
		animation_player.speed_scale = SWING_RELEASE_SPEED_MULTIPLIER if animation_player.current_animation_position >= release_time else 1.0

		if not swing_damage_ready and animation_player.current_animation_position >= release_time:
			swing_damage_ready = true
			current_swing_damage = SWING_DAMAGE_INCOMPLETE if swing_was_released_early else SWING_DAMAGE_FULL
			stamina = max(stamina - 60.0, 0.0)
			if stamina <= 0.0:
				stamina_refill_delay_timer = STAMINA_REFILL_DELAY_SECONDS
			_apply_attack_damage(current_swing_damage)
		
		# Check if animation is finished
		if animation_player.current_animation_position >= swing_animation.length - 0.02:
			swing_in_progress = false
			swing_animation_finished = true
			swing_force_release = false
			animation_player.speed_scale = 1.0
			set_movement_locked_by(self, false)
			return false
		
		return true

	return false

func _swing_frame_to_time(frame: int) -> float:
	return max(frame - 1, 0) / SWING_ANIMATION_FPS

func _is_swing_in_windup() -> bool:
	if not swing_in_progress or animation_player == null:
		return false
	if animation_player.current_animation != SWING_ANIMATION_NAME:
		return true

	return animation_player.current_animation_position < _swing_frame_to_time(SWING_RELEASE_FRAME)

func _apply_attack_damage(amount: float) -> void:
	if attack_area == null or amount <= 0.0:
		return

	var damaged_nodes: Array[Node] = []
	for body in attack_area.get_overlapping_bodies():
		var target := _find_damage_target(body)
		if target != null and not damaged_nodes.has(target):
			if target.has_method("apply_damage"):
				target.call("apply_damage", amount)
				damaged_nodes.append(target)

	for area in attack_area.get_overlapping_areas():
		var target := _find_damage_target(area)
		if target != null and not damaged_nodes.has(target):
			if target.has_method("apply_damage"):
				target.call("apply_damage", amount)
				damaged_nodes.append(target)

func _find_damage_target(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if current == self:
			return null
		if current.has_method("apply_damage"):
			return current
		current = current.get_parent()
	return null
