class_name Bat
extends RigidBody3D

# Reusable held item transform component.
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
		flip_blade_face = flip
		blade_flip_axis = axis

const BAT_SCENE_PATH := "res://assets/items/bat.tscn"
const BAT_ATTACHMENT_NODE_NAME := "RightHandBatAttachment"
static var melee_shared = preload("res://scripts/items/MeleeItemSharedComponent.gd").new()
const BAT_ITEM_ICON: Texture2D = preload("res://assets/ui/axe.png")
const BAT_MODEL_SCENE: PackedScene = preload("res://assets/items assets/axe.glb")
const ViewmodelComponent = preload("res://scripts/items/MeleeViewmodelComponent.gd")
var _viewmodel = ViewmodelComponent.new(BAT_MODEL_SCENE, "BatViewmodel")
const STAMINA_PALETTE_PATH := "res://assets/ui/dungeon-pal.png"
const ITEM_DURABILITY_COLOR_START_INDEX := 17
const ITEM_DURABILITY_COLOR_END_INDEX := 22
const SWING_ANIMATION_NAME := "swing"
const SWING_ANIMATION_FPS := 30.0
const SWING_RELEASE_FRAME := 58
const SWING_STOP_FRAME := 100
const SWING_RELEASE_SPEED_MULTIPLIER := 1.3
const SWING_DAMAGE_FULL := 10.0
const SWING_DAMAGE_INCOMPLETE := 3.0
const BAT_KNOCKBACK_INCOMPLETE := 40.0
const BAT_KNOCKBACK_FULL := BAT_KNOCKBACK_INCOMPLETE * 3.0
const BAT_KNOCKBACK_DURATION := 0.18
const BAT_KNOCKBACK_POSITION_SCALE := 0.04
const BAT_KNOCKBACK_UPWARD_RATIO := 1
const ITEM_DROP_FORWARD_DISTANCE := 1.0
const ITEM_DROP_DOWN_OFFSET := -0.25
const ITEM_DROP_FORWARD_SPEED := 2.0
const ITEM_DROP_UPWARD_SPEED := 0.5
const SWING_MOMENTUM_SPEED := 30.0
const MAX_USES: int = 10
const BAT_PHYSICS_COLLISION_LAYER := 3
const BAT_PHYSICS_COLLISION_MASK := 3
const BAT_PHYSICS_MASS := 0.1
const BAT_PHYSICS_LINEAR_DAMP := 0.2
const BAT_PHYSICS_ANGULAR_DAMP := 0.4

static var equip_key_was_down: bool = false

@export var right_hand_bone_name: String = "mixamorig_RightHand"
@export var held_item_position: Vector3 = Vector3(0.03, 0.07, -0.04)
@export var held_item_rotation_degrees: Vector3 = Vector3(-88.0, 90.0, 276.0)
@export_range(0.1, 2.0, 0.1) var held_item_scale: float = 1.4
@export var held_item_flip_blade: bool = true
@export_enum("X", "Y", "Z") var held_item_flip_axis: int = 0

@export_group("Viewmodel")
@export var viewmodel_position: Vector3 = Vector3(0.5, -0.4, -0.45)
@export var viewmodel_rotation_degrees: Vector3 = Vector3(-20.0, -10.0, 10.0)
@export_range(0.01, 2.0, 0.01) var viewmodel_scale: float = 1

var inventory_slot_index: int = -1
var right_hand_attachment: BoneAttachment3D = null
var swing_in_progress: bool = false
var swing_animation_finished: bool = false
var swing_force_release: bool = false
var swing_was_released_early: bool = false
var swing_damage_ready: bool = false
var swing_momentum_applied: bool = false
var swing_momentum_applied_dir: Vector3 = Vector3.ZERO
var current_swing_damage: float = SWING_DAMAGE_INCOMPLETE
var current_swing_knockback: float = BAT_KNOCKBACK_INCOMPLETE
var swing_damaged_targets: Dictionary = {}
var npc_knockback_states: Dictionary = {}
var uses_left: int = MAX_USES
var item_durability_color_start: Color = Color(1.0, 0.3, 0.3, 1.0)
var item_durability_color_end: Color = Color(0.3, 1.0, 0.3, 1.0)


func _ready() -> void:
	_configure_item_physics()
	_setup_item_durability_palette_colors()


func _physics_process(delta: float) -> void:
	_update_npc_knockback_states(delta)


static func get_pickup_max_distance() -> float:
	return melee_shared.get_pickup_max_distance()


static func get_equip_action_name() -> StringName:
	return melee_shared.get_equip_action_name()


static func get_scene_path() -> String:
	return BAT_SCENE_PATH


static func get_item_icon() -> Texture2D:
	return BAT_ITEM_ICON


static func is_bat_node(node: Node) -> bool:
	return melee_shared.is_item_node(node, BAT_SCENE_PATH, "bat")


static func find_bat_rigidbody_from_node(node: Node) -> RigidBody3D:
	return melee_shared.find_item_rigidbody_from_node(node, BAT_SCENE_PATH, "bat")


static func is_equip_input_just_pressed() -> bool:
	var equip_input: Dictionary = melee_shared.read_equip_input(get_equip_action_name(), equip_key_was_down)
	equip_key_was_down = bool(equip_input.get("is_down", equip_key_was_down))
	return bool(equip_input.get("just_pressed", false))


func get_hotbar_icon_texture() -> Texture2D:
	return BAT_ITEM_ICON


func get_hotbar_icon_modulate(alpha: float) -> Color:
	var durability_percent := clampf(float(uses_left) / float(MAX_USES), 0.0, 1.0)
	var dur_color := item_durability_color_start.lerp(item_durability_color_end, durability_percent)
	return Color(dur_color.r, dur_color.g, dur_color.b, alpha)


func can_start_primary_action() -> bool:
	return inventory_slot_index >= 0 and swing_in_progress == false and is_equipped_in_hand() and _is_wielding_player_on_floor()


func begin_primary_action(player: Node) -> bool:
	if not can_start_primary_action():
		return false

	swing_animation_finished = false
	swing_in_progress = true
	swing_force_release = false
	swing_was_released_early = false
	swing_damage_ready = false
	swing_damaged_targets.clear()
	current_swing_damage = SWING_DAMAGE_INCOMPLETE
	current_swing_knockback = BAT_KNOCKBACK_INCOMPLETE
	if player and player.has_method("set_movement_locked_by"):
		player.call("set_movement_locked_by", self, true)

	var animation_player := _get_player_animation_player(player)
	if animation_player and animation_player.has_animation(SWING_ANIMATION_NAME):
		animation_player.play(SWING_ANIMATION_NAME)
		animation_player.seek(0.0, true)

	return true


func release_primary_action(player: Node) -> void:
	if not swing_in_progress:
		return

	if _is_swing_in_windup(player):
		swing_force_release = true
		swing_was_released_early = true


func update_primary_action(player: Node, _delta: float) -> bool:
	_viewmodel.update_bob(player, _delta, viewmodel_position)
	_viewmodel.shaking = swing_in_progress and _is_swing_in_windup(player)
	var animation_player := _get_player_animation_player(player)
	if animation_player == null:
		if swing_in_progress:
			_reset_swing_state(player)
		return false

	if not animation_player.has_animation(SWING_ANIMATION_NAME):
		if swing_in_progress:
			_reset_swing_state(player)
		return false

	if not swing_in_progress:
		return false

	if animation_player.current_animation != SWING_ANIMATION_NAME:
		_reset_swing_state(player)
		return false

	var swing_animation := animation_player.get_animation(SWING_ANIMATION_NAME)
	if swing_animation == null:
		_reset_swing_state(player)
		return false

	var release_time := _swing_frame_to_time(SWING_RELEASE_FRAME)
	if animation_player.current_animation_position < release_time and swing_force_release:
		animation_player.seek(release_time, true)
		swing_force_release = false
		swing_was_released_early = true

	animation_player.speed_scale = SWING_RELEASE_SPEED_MULTIPLIER if animation_player.current_animation_position >= release_time else 1.0

	if not swing_damage_ready and animation_player.current_animation_position >= release_time:
		swing_damage_ready = true
		current_swing_damage = SWING_DAMAGE_INCOMPLETE if swing_was_released_early else SWING_DAMAGE_FULL
		current_swing_knockback = BAT_KNOCKBACK_INCOMPLETE if swing_was_released_early else BAT_KNOCKBACK_FULL
		_consume_player_stamina(player, 40.0)
		_viewmodel.start_swing()
		if not swing_momentum_applied:
			_apply_swing_momentum(player)
			swing_momentum_applied = true

	# Stop forward momentum on contact with a hurtbox.
	if swing_momentum_applied_dir != Vector3.ZERO and _attack_area_has_hurtbox(player):
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity.x = 0.0
			(player as CharacterBody3D).velocity.z = 0.0
		swing_momentum_applied_dir = Vector3.ZERO

	if swing_damage_ready and animation_player.current_animation_position < _swing_frame_to_time(SWING_STOP_FRAME):
		_apply_attack_damage(player, current_swing_damage, current_swing_knockback)

	var stop_time := minf(_swing_frame_to_time(SWING_STOP_FRAME), swing_animation.length)
	if animation_player.current_animation_position >= stop_time:
		animation_player.seek(stop_time, true)
		_reset_swing_state(player)
		animation_player.speed_scale = 1.0
		return false

	if animation_player.current_animation_position >= swing_animation.length - 0.02:
		_reset_swing_state(player)
		animation_player.speed_scale = 1.0
		return false

	return true


func is_swing_windup_active() -> bool:
	var animation_player := _get_self_animation_player()
	if not swing_in_progress or animation_player == null:
		return false
	if animation_player.current_animation != SWING_ANIMATION_NAME:
		return false
	return animation_player.current_animation_position < _swing_frame_to_time(SWING_RELEASE_FRAME)


func get_swing_windup_percent() -> float:
	if not is_swing_windup_active():
		return 0.0

	var animation_player := _get_self_animation_player()
	if animation_player == null:
		return 0.0

	var release_time := _swing_frame_to_time(SWING_RELEASE_FRAME)
	if release_time <= 0.0:
		return 0.0

	return clampf(animation_player.current_animation_position / release_time, 0.0, 1.0)


func pick_up_into_hotbar(player: Node, slot_index: int) -> bool:
	if player == null:
		return false
	if inventory_slot_index != -1:
		return false
	if slot_index < 0:
		return false

	inventory_slot_index = slot_index
	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	player.add_child(self)
	_set_item_physics_enabled(false)
	_set_item_visuals_visible(false)
	return true


func drop_from_hotbar(player: Node) -> bool:
	if player == null:
		return false
	if inventory_slot_index < 0:
		return false

	_reset_swing_state(player)

	_viewmodel.hide()

	var world_root: Node = null
	if player.has_method("get_tree"):
		var tree := player.get_tree()
		if tree:
			world_root = tree.current_scene
	if world_root == null:
		world_root = player.get_parent()
	if world_root == null:
		world_root = player

	var drop_origin := global_position
	var camera := _get_player_camera(player)
	if camera:
		drop_origin = camera.global_position + (-camera.global_transform.basis.z * ITEM_DROP_FORWARD_DISTANCE) + Vector3(0.0, ITEM_DROP_DOWN_OFFSET, 0.0)

	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	if world_root:
		world_root.add_child(self, true)
	else:
		player.add_child(self)

	global_position = drop_origin
	ViewmodelComponent.set_visual_layer_recursive(self, 1)
	_set_item_visuals_visible(true)
	_set_item_physics_enabled(true)
	var player_node := player as Node3D
	var forward := Vector3.FORWARD
	if player_node:
		forward = -player_node.global_transform.basis.z
	if camera:
		forward = -camera.global_transform.basis.z
	linear_velocity = (forward * ITEM_DROP_FORWARD_SPEED) + (Vector3.UP * ITEM_DROP_UPWARD_SPEED)
	inventory_slot_index = -1
	right_hand_attachment = null
	return true


func refresh_inventory_state(player: Node, selected_slot_index: int, _is_sprinting: bool) -> void:
	if player == null or inventory_slot_index < 0:
		return

	if inventory_slot_index == selected_slot_index:
		_equip_to_right_hand(player)
		_set_item_visuals_visible(true)
		_viewmodel.show(player, viewmodel_position, viewmodel_rotation_degrees, viewmodel_scale)
	else:
		_detach_from_hand(player)
		_viewmodel.hide()


func is_equipped_in_hand() -> bool:
	if inventory_slot_index < 0:
		return false
	var parent := get_parent()
	return parent != null and parent == right_hand_attachment


func _setup_item_durability_palette_colors() -> void:
	var palette_texture := load(STAMINA_PALETTE_PATH) as Texture2D
	if palette_texture == null:
		return

	var palette_image := palette_texture.get_image()
	if palette_image == null or palette_image.is_empty():
		return

	item_durability_color_start = _get_palette_color(palette_image, ITEM_DURABILITY_COLOR_START_INDEX, item_durability_color_start)
	item_durability_color_end = _get_palette_color(palette_image, ITEM_DURABILITY_COLOR_END_INDEX, item_durability_color_end)


func _consume_player_stamina(player: Node, amount: float) -> void:
	if player == null or amount <= 0.0:
		return

	var stamina := float(player.get("stamina"))
	var refill_delay := float(player.get("stamina_refill_delay_timer"))
	stamina = maxf(stamina - amount, 0.0)
	if stamina <= 0.0:
		refill_delay = 5.0
	player.set("stamina", stamina)
	player.set("stamina_refill_delay_timer", refill_delay)
	if player.has_method("_update_stamina_ui"):
		player.call("_update_stamina_ui")


func _apply_attack_damage(player: Node, amount: float, knockback_strength: float) -> void:
	if player == null or amount <= 0.0:
		return

	var attack_area := _get_player_attack_area(player)
	if attack_area == null:
		return

	var targets: Array[Node] = melee_shared.collect_hurtbox_damage_targets(attack_area, self, player, swing_damaged_targets)
	var dealt_damage: bool = false
	for target: Node in targets:
		if target.has_method("apply_damage"):
			target.call("apply_damage", amount)
			GameStats.record_damage(amount)
			_apply_npc_knockback(target, player, knockback_strength)
			swing_damaged_targets[target.get_instance_id()] = true
			dealt_damage = true

	if dealt_damage:
		uses_left -= 1
		if uses_left <= 0:
			_delete_item()


func _delete_item() -> void:
	if inventory_slot_index >= 0:
		var parent := get_parent()
		var player: Node = null
		while parent:
			if parent.has_method("_set_hotbar_item"):
				player = parent
				break
			parent = parent.get_parent()
		if player == null and right_hand_attachment:
			parent = right_hand_attachment
			while parent:
				if parent.has_method("_set_hotbar_item"):
					player = parent
					break
				parent = parent.get_parent()
		if player:
			player.call("_set_hotbar_item", inventory_slot_index, null, null)
			if player.has_method("_refresh_selected_item_state"):
				player.call("_refresh_selected_item_state")
			if player.has_method("_update_pickup_prompt_visibility"):
				player.call("_update_pickup_prompt_visibility")

	_viewmodel.hide()
	queue_free()


func _apply_npc_knockback(target: Node, player: Node, knockback_strength: float) -> void:
	if knockback_strength <= 0.0:
		return
	if not _is_knockbackable_npc_target(target, player):
		return

	if target.has_method("apply_knockback"):
		target.call("apply_knockback", _get_knockback_direction(target, player), knockback_strength)
		return

	if target is CharacterBody3D:
		var body := target as CharacterBody3D
		var knockback_direction := _get_knockback_direction(body, player)
		if knockback_direction == Vector3.ZERO:
			return

		var launch_velocity := knockback_direction * knockback_strength
		launch_velocity.y = knockback_strength * BAT_KNOCKBACK_UPWARD_RATIO

		var target_id := body.get_instance_id()
		npc_knockback_states[target_id] = {
			"target": body,
			"direction": knockback_direction,
			"strength": knockback_strength,
			"launch_velocity": launch_velocity,
			"time_left": BAT_KNOCKBACK_DURATION,
		}
		_apply_knockback_to_body(body, knockback_direction, knockback_strength, launch_velocity, true, get_physics_process_delta_time())


func _update_npc_knockback_states(delta: float) -> void:
	if npc_knockback_states.is_empty():
		return

	var expired_ids: Array[int] = []
	for target_id in npc_knockback_states.keys():
		var state: Dictionary = npc_knockback_states.get(target_id, {})
		var target := state.get("target") as CharacterBody3D
		if target == null or not is_instance_valid(target):
			expired_ids.append(int(target_id))
			continue

		var time_left := float(state.get("time_left", 0.0)) - delta
		if time_left <= 0.0:
			expired_ids.append(int(target_id))
			continue

		state["time_left"] = time_left
		npc_knockback_states[target_id] = state
		_apply_knockback_to_body(
			target,
			state.get("direction") as Vector3,
			float(state.get("strength", 0.0)),
			state.get("launch_velocity") as Vector3,
			false,
			delta
		)

	for target_id in expired_ids:
		npc_knockback_states.erase(target_id)


func _apply_knockback_to_body(body: CharacterBody3D, knockback_direction: Vector3, knockback_strength: float, launch_velocity: Vector3, apply_vertical_launch: bool, delta: float) -> void:
	if body == null or knockback_direction == Vector3.ZERO or knockback_strength <= 0.0:
		return

	var new_velocity := body.velocity
	new_velocity.x += knockback_direction.x * knockback_strength
	new_velocity.z += knockback_direction.z * knockback_strength
	if apply_vertical_launch:
		new_velocity.y = maxf(new_velocity.y, launch_velocity.y)
	body.velocity = new_velocity
	body.global_position += knockback_direction * knockback_strength * BAT_KNOCKBACK_POSITION_SCALE * maxf(delta, 0.016)


func _get_knockback_direction(target: Node, player: Node) -> Vector3:
	if target == null:
		return Vector3.ZERO

	var target_node := target as Node3D
	if target_node == null:
		return Vector3.ZERO

	var source_position := Vector3.ZERO
	var player_node := player as Node3D
	if player_node:
		source_position = player_node.global_position
	else:
		var camera := _get_player_camera(player)
		if camera:
			source_position = camera.global_position

	var direction := target_node.global_position - source_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		var camera_fallback := _get_player_camera(player)
		if camera_fallback:
			direction = -camera_fallback.global_transform.basis.z
			direction.y = 0.0

	if direction.length_squared() <= 0.0001:
		return Vector3.ZERO

	return direction.normalized()


func _apply_swing_momentum(player: Node) -> void:
	if player == null:
		return

	var camera := _get_player_camera(player)
	if camera == null:
		return

	# Skip momentum if the attack area already contains a hurtbox.
	if _attack_area_has_hurtbox(player):
		return

	# Apply forward momentum in the direction the camera is facing.
	var forward_direction := -camera.global_transform.basis.z
	var momentum := forward_direction * SWING_MOMENTUM_SPEED

	# Add momentum to player velocity.
	if player is CharacterBody3D:
		var char_player := player as CharacterBody3D
		var new_velocity := char_player.velocity
		new_velocity.x += momentum.x
		new_velocity.z += momentum.z
		char_player.velocity = new_velocity
		swing_momentum_applied_dir = momentum


func _attack_area_has_hurtbox(player: Node) -> bool:
	var attack_area := player.get_node_or_null("Attack") as Area3D
	if attack_area == null:
		return false
	for area in attack_area.get_overlapping_areas():
		if area != null and area.name.to_lower().contains("hurtbox"):
			return true
	return false


func _detach_from_hand(player: Node) -> void:
	if player == null:
		return

	var desired_parent := player
	if get_parent() != desired_parent:
		var old_parent := get_parent()
		if old_parent:
			old_parent.remove_child(self)
		player.add_child(self)
	_set_item_physics_enabled(false)
	_set_item_visuals_visible(false)
	right_hand_attachment = null


func _equip_to_right_hand(player: Node) -> void:
	if player == null:
		return

	var attachment := _get_or_create_right_hand_attachment(player)
	if attachment == null:
		push_warning("Could not attach item: right hand bone attachment is missing.")
		return

	if get_parent() == attachment:
		_set_item_physics_enabled(false)
		_set_item_visuals_visible(true)
		return

	var old_parent := get_parent()
	if old_parent != attachment:
		if old_parent:
			old_parent.remove_child(self)
		attachment.add_child(self)

	_set_item_physics_enabled(false)
	_set_item_visuals_visible(true)
	ViewmodelComponent.set_visual_layer_recursive(self, 2)

	position = held_item_position
	rotation = Vector3(
		deg_to_rad(held_item_rotation_degrees.x),
		deg_to_rad(held_item_rotation_degrees.y),
		deg_to_rad(held_item_rotation_degrees.z)
	)
	scale = Vector3.ONE * held_item_scale
	_apply_item_blade_flip()


func _apply_item_blade_flip() -> void:
	if not held_item_flip_blade:
		return

	match held_item_flip_axis:
		0:
			rotate_object_local(Vector3.RIGHT, PI)
		1:
			rotate_object_local(Vector3.UP, PI)
		2:
			rotate_object_local(Vector3.FORWARD, PI)


func _set_item_physics_enabled(enabled: bool) -> void:
	melee_shared.set_item_physics_enabled(self, enabled, BAT_PHYSICS_COLLISION_LAYER, BAT_PHYSICS_COLLISION_MASK, BAT_PHYSICS_MASS, BAT_PHYSICS_LINEAR_DAMP, BAT_PHYSICS_ANGULAR_DAMP)


func _configure_item_physics() -> void:
	mass = BAT_PHYSICS_MASS
	linear_damp = BAT_PHYSICS_LINEAR_DAMP
	angular_damp = BAT_PHYSICS_ANGULAR_DAMP
	can_sleep = true


func _set_item_visuals_visible(visibility: bool) -> void:
	_set_visual_children_visible(self, visibility)


func _set_visual_children_visible(node: Node, visibility: bool) -> void:
	melee_shared.set_visual_children_visible(node, visibility)


func _get_or_create_right_hand_attachment(player: Node) -> BoneAttachment3D:
	if right_hand_attachment and is_instance_valid(right_hand_attachment):
		return right_hand_attachment

	var visual_root := _get_player_visual_root(player)
	var skeleton := _find_skeleton_recursive(visual_root if visual_root else player)
	if skeleton == null:
		return null

	var existing := skeleton.get_node_or_null(BAT_ATTACHMENT_NODE_NAME) as BoneAttachment3D
	if existing:
		right_hand_attachment = existing
		return right_hand_attachment

	var resolved_bone_name := _resolve_right_hand_bone_name(skeleton)
	if resolved_bone_name.is_empty():
		return null

	var attachment := BoneAttachment3D.new()
	attachment.name = BAT_ATTACHMENT_NODE_NAME
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


func _get_player_visual_root(player: Node) -> Node3D:
	if player == null:
		return null
	return player.get("visual_root") as Node3D


func _get_player_animation_player(player: Node) -> AnimationPlayer:
	if player == null:
		return null
	return player.get("animation_player") as AnimationPlayer


func _get_player_camera(player: Node) -> Camera3D:
	if player == null:
		return null
	return player.get("camera") as Camera3D


func _get_player_attack_area(player: Node) -> Area3D:
	if player == null:
		return null
	return player.get("attack_area") as Area3D


func _is_wielding_player_on_floor() -> bool:
	return melee_shared.is_wielding_player_on_floor(self)


func _get_self_animation_player() -> AnimationPlayer:
	var parent := get_parent()
	while parent != null:
		if parent is Node and parent.has_method("get"):
			var animation_player := parent.get("animation_player") as AnimationPlayer
			if animation_player:
				return animation_player
		parent = parent.get_parent()
	return null


func _is_swing_in_windup(player: Node) -> bool:
	if not swing_in_progress:
		return false
	var animation_player := _get_player_animation_player(player)
	if animation_player == null:
		return false
	if animation_player.current_animation != SWING_ANIMATION_NAME:
		return true
	return animation_player.current_animation_position < _swing_frame_to_time(SWING_RELEASE_FRAME)


func _is_knockbackable_npc_target(target: Node, player: Node) -> bool:
	if target == null or target == self or target == player:
		return false
	if target.is_in_group("player"):
		return false
	if not (target is CharacterBody3D):
		return false

	var target_script := target.get_script() as Script
	if target_script == null:
		return false

	return target_script.resource_path.contains("/scripts/npc/")


func _swing_frame_to_time(frame: int) -> float:
	return melee_shared.swing_frame_to_time(frame, SWING_ANIMATION_FPS)


func _reset_swing_state(player: Node) -> void:
	swing_in_progress = false
	swing_animation_finished = true
	swing_force_release = false
	swing_damage_ready = false
	swing_was_released_early = false
	swing_momentum_applied = false
	swing_momentum_applied_dir = Vector3.ZERO
	swing_damaged_targets.clear()
	current_swing_damage = SWING_DAMAGE_INCOMPLETE
	current_swing_knockback = BAT_KNOCKBACK_INCOMPLETE
	if player and player.has_method("set_movement_locked_by"):
		player.call("set_movement_locked_by", self, false)
	var animation_player := _get_player_animation_player(player)
	if animation_player:
		animation_player.speed_scale = 1.0


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
