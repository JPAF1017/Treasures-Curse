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
const AXE_SCENE_PATH = "res://assets/items/axe.tscn"
const AXE_ATTACHMENT_NODE_NAME = "RightHandAxeAttachment"
const HOTBAR_SLOT_COUNT = 5
const HOTBAR_SELECTED_SCALE = 1.18
const HOTBAR_DEFAULT_SCALE = 1.0
const HOTBAR_ITEM_LABEL_FONT_PATH = "res://assets/ui/dungeon-mode.ttf"
@export_range(2.0, 80.0, 0.5) var vision_distance: float = 20.0
@export_range(0.5, 10.0, 0.1) var vision_radius: float = 3.0
@export var debug_position_logs: bool = false
@export var hide_visual_from_player_camera: bool = false
@export_range(-360.0, 360.0, 1.0) var visual_yaw_offset_degrees: float = 180.0
@export_range(0.5, 5.0, 0.1) var axe_pickup_max_distance: float = 2.0
@export var axe_equip_action_name: StringName = &"interact"
@export var right_hand_bone_name: String = "mixamorig_RightHand"
@export var axe_hand_local_position: Vector3 = Vector3(0.03, 0.07, -0.04)
@export var axe_hand_local_rotation_degrees: Vector3 = Vector3(-88.0, 3.0, 276.0)
@export_range(0.1, 2.0, 0.1) var axe_hand_local_scale: float = 0.7
@export var axe_flip_blade_face: bool = true
@export_enum("X", "Y", "Z") var axe_blade_flip_axis: int = 0
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
@onready var visual_root: Node3D = _resolve_visual_root()
@onready var animation_player: AnimationPlayer = _resolve_animation_player()
@onready var stamina_bar_fill: NinePatchRect = $CanvasLayer/Control/Stamina/StaminaBarContainer
@onready var stamina_label_digit: Label = $CanvasLayer/Control/Stamina/LabelDigit
@onready var health_bar_fill: NinePatchRect = $CanvasLayer/Control/Health/HealthBarContainer
@onready var health_label_digit: Label = $CanvasLayer/Control/Health/LabelDigit
@onready var player_canvas_layer: CanvasLayer = $CanvasLayer

var stamina_bar_initial_scale: Vector2 = Vector2.ONE
var health_bar_initial_scale: Vector2 = Vector2.ONE
var damage_overlay: TextureRect = null
var damage_overlay_tween: Tween = null
var equipped_axe: RigidBody3D = null
var right_hand_attachment: BoneAttachment3D = null
var equip_key_was_down: bool = false
var hotbar_slots: Array[NinePatchRect] = []
var hotbar_slot_base_scales: Array[Vector2] = []
var hotbar_item_labels: Array[Label] = []
var hotbar_item_ids: Array[String] = []
var selected_hotbar_slot_index: int = 0
var axe_inventory_slot_index: int = -1
var hotbar_font: FontFile = null

#function on startup
func _ready():
	#detects mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_snap_length = 0.7
	_configure_vision_area()
	initial_head_position = head.position
	target_head_y = initial_head_position.y
	_setup_stamina_ui()
	_setup_health_ui()
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
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_hotbar_slot((selected_hotbar_slot_index - 1 + HOTBAR_SLOT_COUNT) % HOTBAR_SLOT_COUNT)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_hotbar_slot((selected_hotbar_slot_index + 1) % HOTBAR_SLOT_COUNT)
	elif event is InputEventKey and event.pressed and not event.echo:
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
	_update_stamina_ui()
#------------------------------------------------------
#wasd direction input and other physics
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Animation handling
	if animation_player:
		var jump_anim_active := _update_jump_animation_phase(delta)
		var is_walking_forward := input_dir.y < 0.0
		var is_walking_backward := input_dir.y > 0.0
		var is_strafing_left := input_dir.x < 0.0
		var is_strafing_right := input_dir.x > 0.0
		var wants_run := is_sprinting
		var grounded_animation_state := is_on_floor() or tired_jump_active
		if jump_anim_active:
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
	hotbar_item_labels.clear()
	hotbar_item_ids = []

	for slot in hotbar_slots:
		slot.pivot_offset = slot.size * 0.5
		hotbar_slot_base_scales.append(slot.scale)
		hotbar_item_ids.append("")
		var item_label := slot.get_node_or_null("ItemLabel") as Label
		if item_label == null:
			item_label = Label.new()
			item_label.name = "ItemLabel"
			item_label.anchor_left = 0.0
			item_label.anchor_top = 0.0
			item_label.anchor_right = 1.0
			item_label.anchor_bottom = 1.0
			item_label.offset_left = 0.0
			item_label.offset_top = 0.0
			item_label.offset_right = 0.0
			item_label.offset_bottom = 0.0
			item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if hotbar_font:
				item_label.add_theme_font_override("font", hotbar_font)
			slot.add_child(item_label)
		item_label.visible = false
		hotbar_item_labels.append(item_label)

func _select_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_slots.size():
		return

	selected_hotbar_slot_index = slot_index
	for i in hotbar_slots.size():
		var slot := hotbar_slots[i]
		var base_scale := hotbar_slot_base_scales[i] if i < hotbar_slot_base_scales.size() else Vector2.ONE
		slot.scale = base_scale * (HOTBAR_SELECTED_SCALE if i == selected_hotbar_slot_index else HOTBAR_DEFAULT_SCALE)
		var item_label := hotbar_item_labels[i]
		if item_label:
			item_label.modulate = Color(1.0, 1.0, 1.0, 1.0 if i == selected_hotbar_slot_index else 0.85)

	_refresh_axe_inventory_state()

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

func _set_hotbar_item(slot_index: int, item_id: String, label_text: String) -> void:
	if slot_index < 0 or slot_index >= hotbar_item_ids.size():
		return

	hotbar_item_ids[slot_index] = item_id
	var item_label := hotbar_item_labels[slot_index] if slot_index < hotbar_item_labels.size() else null
	if item_label:
		item_label.text = label_text
		item_label.visible = not item_id.is_empty()

func _find_first_empty_hotbar_slot() -> int:
	for i in hotbar_item_ids.size():
		if hotbar_item_ids[i].is_empty():
			return i
	return -1

func _pickup_axe_into_hotbar(axe_body: RigidBody3D) -> void:
	if axe_body == null or equipped_axe != null:
		return

	var slot_index := _find_first_empty_hotbar_slot()
	if slot_index == -1:
		push_warning("Hotbar is full. Cannot pick up axe.")
		return

	equipped_axe = axe_body
	axe_inventory_slot_index = slot_index
	_set_hotbar_item(slot_index, "axe", "Axe")
	_move_axe_into_inventory()
	_refresh_axe_inventory_state()

func _move_axe_into_inventory() -> void:
	if equipped_axe == null:
		return

	var old_parent := equipped_axe.get_parent()
	if old_parent:
		old_parent.remove_child(equipped_axe)
	add_child(equipped_axe)
	_equipped_axe_set_physics_enabled(false)
	_set_axe_visuals_visible(false)

func _refresh_axe_inventory_state() -> void:
	if equipped_axe == null:
		return

	if axe_inventory_slot_index == selected_hotbar_slot_index:
		_equip_axe_to_right_hand(equipped_axe)
	else:
		_detach_axe_from_hand()

func _detach_axe_from_hand() -> void:
	if equipped_axe == null:
		return

	var desired_parent := self
	if equipped_axe.get_parent() != desired_parent:
		var old_parent := equipped_axe.get_parent()
		if old_parent:
			old_parent.remove_child(equipped_axe)
		add_child(equipped_axe)
	_equipped_axe_set_physics_enabled(false)
	_set_axe_visuals_visible(false)

func _equipped_axe_set_physics_enabled(enabled: bool) -> void:
	if equipped_axe == null:
		return

	equipped_axe.freeze = not enabled
	equipped_axe.sleeping = not enabled
	equipped_axe.linear_velocity = Vector3.ZERO
	equipped_axe.angular_velocity = Vector3.ZERO
	equipped_axe.collision_layer = 0
	equipped_axe.collision_mask = 0
	var axe_collision := equipped_axe.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if axe_collision:
		axe_collision.disabled = true

func _set_axe_visuals_visible(visible: bool) -> void:
	if equipped_axe == null:
		return
	_set_visual_children_visible(equipped_axe, visible)

func _set_visual_children_visible(node: Node, visible: bool) -> void:
	if node is VisualInstance3D:
		node.visible = visible
	for child in node.get_children():
		_set_visual_children_visible(child, visible)

func _try_auto_equip_axe() -> void:
	if equipped_axe != null:
		return
	if camera == null:
		return
	if not _is_equip_input_just_pressed():
		return

	var origin: Vector3 = camera.global_transform.origin
	var end: Vector3 = origin + (-camera.global_transform.basis.z * axe_pickup_max_distance)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider := result.get("collider") as Node
	if collider == null:
		return

	var axe_body := _find_axe_rigidbody_from_node(collider)
	if axe_body == null:
		return

	_pickup_axe_into_hotbar(axe_body)

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

	var attachment := _get_or_create_right_hand_attachment()
	if attachment == null:
		push_warning("Could not attach axe: right hand bone attachment is missing.")
		return

	var old_parent := axe_body.get_parent()
	if old_parent:
		old_parent.remove_child(axe_body)
	attachment.add_child(axe_body)

	_equipped_axe_set_physics_enabled(false)
	_set_axe_visuals_visible(true)

	axe_body.position = axe_hand_local_position
	axe_body.rotation = Vector3(
		deg_to_rad(axe_hand_local_rotation_degrees.x),
		deg_to_rad(axe_hand_local_rotation_degrees.y),
		deg_to_rad(axe_hand_local_rotation_degrees.z)
	)
	axe_body.scale = Vector3.ONE * axe_hand_local_scale
	_apply_axe_blade_face_flip(axe_body)

	equipped_axe = axe_body

func _apply_axe_blade_face_flip(axe_body: Node3D) -> void:
	if axe_body == null or not axe_flip_blade_face:
		return

	match axe_blade_flip_axis:
		0:
			axe_body.rotate_object_local(Vector3.RIGHT, PI)
		1:
			axe_body.rotate_object_local(Vector3.UP, PI)
		2:
			axe_body.rotate_object_local(Vector3.FORWARD, PI)

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
