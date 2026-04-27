extends RigidBody3D

const SKULL_KEY_SCENE_PATH := "res://puzzles/skull_key.tscn"
const SKULL_KEY_ITEM_ICON: Texture2D = preload("res://assets/ui/skull.png")
const SKULL_KEY_MODEL_SCENE: PackedScene = preload("res://assets/items assets/skull.glb")
static var melee_shared = preload("res://scripts/items/MeleeItemSharedComponent.gd").new()

const ITEM_DROP_FORWARD_DISTANCE := 1.0
const ITEM_DROP_DOWN_OFFSET := -0.25
const ITEM_DROP_FORWARD_SPEED := 2.0
const ITEM_DROP_UPWARD_SPEED := 0.5
const SKULL_KEY_PHYSICS_COLLISION_LAYER := 3
const SKULL_KEY_PHYSICS_COLLISION_MASK := 3
const SKULL_KEY_PHYSICS_MASS := 0.1
const SKULL_KEY_PHYSICS_LINEAR_DAMP := 0.2
const SKULL_KEY_PHYSICS_ANGULAR_DAMP := 0.4
const SKULL_KEY_ATTACHMENT_NODE_NAME := "RightHandSkullKeyAttachment"

const VIEWMODEL_BOB_FREQ := 2.0
const VIEWMODEL_BOB_AMP_Y := 0.012
const VIEWMODEL_BOB_AMP_X := 0.006

static var equip_key_was_down: bool = false

@export var right_hand_bone_name: String = "mixamorig_RightHand"
@export var held_item_position: Vector3 = Vector3(0.03, 0.07, -0.04)
@export var held_item_rotation_degrees: Vector3 = Vector3(92.0, 300.0, 276.0)
@export_range(0.01, 2.0, 0.01) var held_item_scale: float = 0.2

@export var viewmodel_position: Vector3 = Vector3(-0.25, -0.18, -0.35)
@export var viewmodel_rotation_degrees: Vector3 = Vector3(0.0, 15.0, 0.0)
@export_range(0.01, 2.0, 0.01) var viewmodel_scale: float = 0.06

var inventory_slot_index: int = -1
var right_hand_attachment: BoneAttachment3D = null
var viewmodel_instance: Node3D = null
var viewmodel_bob_time: float = 0.0


func _ready() -> void:
	_configure_item_physics()


static func get_pickup_max_distance() -> float:
	return melee_shared.get_pickup_max_distance()


static func get_equip_action_name() -> StringName:
	return melee_shared.get_equip_action_name()


static func get_scene_path() -> String:
	return SKULL_KEY_SCENE_PATH


static func get_item_icon() -> Texture2D:
	return SKULL_KEY_ITEM_ICON


static func is_skull_key_node(node: Node) -> bool:
	return melee_shared.is_item_node(node, SKULL_KEY_SCENE_PATH, "skull_key")


static func find_skull_key_rigidbody_from_node(node: Node) -> RigidBody3D:
	return melee_shared.find_item_rigidbody_from_node(node, SKULL_KEY_SCENE_PATH, "skull_key")


static func is_equip_input_just_pressed() -> bool:
	var equip_input: Dictionary = melee_shared.read_equip_input(get_equip_action_name(), equip_key_was_down)
	equip_key_was_down = bool(equip_input.get("is_down", equip_key_was_down))
	return bool(equip_input.get("just_pressed", false))


func get_hotbar_icon_texture() -> Texture2D:
	return SKULL_KEY_ITEM_ICON


func get_hotbar_icon_modulate(alpha: float) -> Color:
	return Color(1.0, 1.0, 1.0, alpha)


func can_start_primary_action() -> bool:
	return false


func begin_primary_action(_player: Node) -> bool:
	return false


func release_primary_action(_player: Node) -> void:
	pass


func is_equipped_in_hand() -> bool:
	if inventory_slot_index < 0:
		return false
	var parent := get_parent()
	return parent != null and parent == right_hand_attachment


func update_primary_action(player: Node, delta: float) -> bool:
	_update_viewmodel_bob(player, delta)
	return false


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

	_hide_viewmodel()

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
	var camera := player.get("camera") as Camera3D
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
	_set_visual_layer_recursive(self, 1)
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
		_show_viewmodel(player)
	else:
		_detach_from_hand(player)
		_hide_viewmodel()


func _configure_item_physics() -> void:
	mass = SKULL_KEY_PHYSICS_MASS
	linear_damp = SKULL_KEY_PHYSICS_LINEAR_DAMP
	angular_damp = SKULL_KEY_PHYSICS_ANGULAR_DAMP
	can_sleep = true


func _set_item_physics_enabled(enabled: bool) -> void:
	melee_shared.set_item_physics_enabled(self, enabled, SKULL_KEY_PHYSICS_COLLISION_LAYER, SKULL_KEY_PHYSICS_COLLISION_MASK, SKULL_KEY_PHYSICS_MASS, SKULL_KEY_PHYSICS_LINEAR_DAMP, SKULL_KEY_PHYSICS_ANGULAR_DAMP)


func _set_item_visuals_visible(visibility: bool) -> void:
	melee_shared.set_visual_children_visible(self, visibility)


func _set_visual_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_visual_layer_recursive(child, layer)


func _equip_to_right_hand(player: Node) -> void:
	if player == null:
		return

	var attachment := _get_or_create_right_hand_attachment(player)
	if attachment == null:
		push_warning("Could not attach skull key: right hand bone attachment is missing.")
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
	_set_visual_layer_recursive(self, 2)

	position = held_item_position
	rotation = Vector3(
		deg_to_rad(held_item_rotation_degrees.x),
		deg_to_rad(held_item_rotation_degrees.y),
		deg_to_rad(held_item_rotation_degrees.z)
	)
	scale = Vector3.ONE * held_item_scale


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


func _get_or_create_right_hand_attachment(player: Node) -> BoneAttachment3D:
	if right_hand_attachment and is_instance_valid(right_hand_attachment):
		return right_hand_attachment

	var visual_root := _get_player_visual_root(player)
	var skeleton := _find_skeleton_recursive(visual_root if visual_root else player)
	if skeleton == null:
		return null

	var existing := skeleton.get_node_or_null(SKULL_KEY_ATTACHMENT_NODE_NAME) as BoneAttachment3D
	if existing:
		right_hand_attachment = existing
		return right_hand_attachment

	var resolved_bone_name := _resolve_right_hand_bone_name(skeleton)
	if resolved_bone_name.is_empty():
		return null

	var attachment := BoneAttachment3D.new()
	attachment.name = SKULL_KEY_ATTACHMENT_NODE_NAME
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


func _get_player_camera(player: Node) -> Camera3D:
	if player == null:
		return null
	return player.get("camera") as Camera3D


func _show_viewmodel(player: Node) -> void:
	if viewmodel_instance and is_instance_valid(viewmodel_instance):
		viewmodel_instance.visible = true
		return

	var camera := _get_player_camera(player)
	if camera == null:
		return

	viewmodel_instance = SKULL_KEY_MODEL_SCENE.instantiate() as Node3D
	viewmodel_instance.name = "SkullKeyViewmodel"
	camera.add_child(viewmodel_instance)

	viewmodel_instance.position = viewmodel_position
	viewmodel_instance.rotation = Vector3(
		deg_to_rad(viewmodel_rotation_degrees.x),
		deg_to_rad(viewmodel_rotation_degrees.y),
		deg_to_rad(viewmodel_rotation_degrees.z)
	)
	viewmodel_instance.scale = Vector3.ONE * viewmodel_scale


func _hide_viewmodel() -> void:
	if viewmodel_instance and is_instance_valid(viewmodel_instance):
		viewmodel_instance.queue_free()
		viewmodel_instance = null
	viewmodel_bob_time = 0.0


func _update_viewmodel_bob(player: Node, delta: float) -> void:
	if viewmodel_instance == null or not is_instance_valid(viewmodel_instance):
		return

	var player_body := player as CharacterBody3D
	if player_body == null:
		return

	var speed := player_body.velocity.length()
	var on_floor: bool = player_body.is_on_floor()

	if speed > 0.5 and on_floor:
		viewmodel_bob_time += delta * speed
	else:
		viewmodel_bob_time = lerpf(viewmodel_bob_time, 0.0, delta * 5.0)

	var bob_y := sin(viewmodel_bob_time * VIEWMODEL_BOB_FREQ) * VIEWMODEL_BOB_AMP_Y
	var bob_x := cos(viewmodel_bob_time * VIEWMODEL_BOB_FREQ * 0.5) * VIEWMODEL_BOB_AMP_X
	viewmodel_instance.position = viewmodel_position + Vector3(bob_x, bob_y, 0.0)
