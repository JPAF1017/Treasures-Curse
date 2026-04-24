extends Node3D

const SKULL_KEY_SCENE_PATH := "res://puzzles/skull_key.tscn"
const DOOR_OPEN_Y_DEGREES := 60.0
const DOOR_OPEN_DURATION := 1.5
const RAYCAST_DISTANCE := 5.0
const SKULL_PLACE_Y_OFFSET := 1.3

@onready var key_area_1: Area3D = $Key
@onready var key_area_2: Area3D = $Key2
@onready var hexagon_1: Node3D = $Hexagon
@onready var hexagon_2: Node3D = $Hexagon2
@onready var door: Node3D = $"../Door/Door_01"

# Placed via E-key interaction (physics disabled, tracked directly)
var _key_1_placed: bool = false
var _key_2_placed: bool = false
# Dropped into area via physics (body signals)
var _key_1_body_count: int = 0
var _key_2_body_count: int = 0

var _door_opened: bool = false
var _player: Node = null
var _interact_control: Control = null
var _hovered_area: Area3D = null


func _ready() -> void:
	key_area_1.body_entered.connect(_on_key_1_body_entered)
	key_area_1.body_exited.connect(_on_key_1_body_exited)
	key_area_2.body_entered.connect(_on_key_2_body_entered)
	key_area_2.body_exited.connect(_on_key_2_body_exited)


func _process(_delta: float) -> void:
	_find_player_if_needed()
	if _player == null:
		return
	_update_interact_prompt()
	if _hovered_area != null and Input.is_action_just_pressed("e"):
		_try_place_skull(_hovered_area)


func _find_player_if_needed() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0]
	_interact_control = _player.get_node_or_null("CanvasLayer/Control/Interact") as Control


func _get_player_camera() -> Camera3D:
	if _player == null:
		return null
	return _player.get("camera") as Camera3D


func _get_selected_skull_key() -> Node:
	if _player == null:
		return null
	var models = _player.get("hotbar_item_models")
	if models == null:
		return null
	var idx: int = int(_player.get("selected_hotbar_slot_index"))
	if idx < 0 or idx >= models.size():
		return null
	var item: Node = models[idx]
	if item == null or not is_instance_valid(item):
		return null
	if item.scene_file_path == SKULL_KEY_SCENE_PATH:
		return item
	return null


func _update_interact_prompt() -> void:
	var camera := _get_player_camera()
	if camera == null or _get_selected_skull_key() == null:
		_set_interact_visible(false)
		_hovered_area = null
		return

	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * RAYCAST_DISTANCE)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [_player]
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	var aimed: Area3D = null
	if not result.is_empty():
		var collider: Object = result.get("collider")
		if collider == key_area_1 and not _key_1_placed and _key_1_body_count == 0:
			aimed = key_area_1
		elif collider == key_area_2 and not _key_2_placed and _key_2_body_count == 0:
			aimed = key_area_2

	_hovered_area = aimed
	_set_interact_visible(aimed != null)


func _set_interact_visible(visible_state: bool) -> void:
	if _interact_control and is_instance_valid(_interact_control):
		_interact_control.visible = visible_state


func _try_place_skull(area: Area3D) -> void:
	var skull := _get_selected_skull_key()
	if skull == null:
		return

	var slot_index: int = int(skull.get("inventory_slot_index"))

	# Hide viewmodel and clear hand attachment
	if skull.has_method("_hide_viewmodel"):
		skull.call("_hide_viewmodel")
	skull.set("right_hand_attachment", null)
	skull.set("inventory_slot_index", -1)

	# Clear from player hotbar
	if _player.has_method("_set_hotbar_item"):
		_player.call("_set_hotbar_item", slot_index, null, null)
	if _player.has_method("_refresh_selected_item_state"):
		_player.call("_refresh_selected_item_state")
	if _player.has_method("_update_pickup_prompt_visibility"):
		_player.call("_update_pickup_prompt_visibility")

	# Reparent to scene root
	var world_root := get_tree().current_scene
	var old_parent := skull.get_parent()
	if old_parent:
		old_parent.remove_child(skull)
	world_root.add_child(skull)

	# Determine target hexagon
	var target_hex: Node3D = hexagon_1 if area == key_area_1 else hexagon_2

	# Place skull above hexagon
	skull.global_position = target_hex.global_position + Vector3(0.0, SKULL_PLACE_Y_OFFSET, 0.0)
	skull.rotation = Vector3.ZERO
	skull.scale = Vector3.ONE * 1.5

	# Keep physics disabled but make it visible
	if skull.has_method("_set_item_physics_enabled"):
		skull.call("_set_item_physics_enabled", false)
	if skull.has_method("_set_item_visuals_visible"):
		skull.call("_set_item_visuals_visible", true)
	if skull.has_method("_set_visual_layer_recursive"):
		skull.call("_set_visual_layer_recursive", skull, 1)

	# Mark slot filled and check puzzle
	if area == key_area_1:
		_key_1_placed = true
	else:
		_key_2_placed = true

	_set_interact_visible(false)
	_hovered_area = null
	_check_puzzle()


func _is_skull_key(body: Node) -> bool:
	return body is RigidBody3D and body.scene_file_path == SKULL_KEY_SCENE_PATH


func _on_key_1_body_entered(body: Node) -> void:
	if _is_skull_key(body):
		_key_1_body_count += 1
		_check_puzzle()


func _on_key_1_body_exited(body: Node) -> void:
	if _is_skull_key(body):
		_key_1_body_count = maxi(_key_1_body_count - 1, 0)


func _on_key_2_body_entered(body: Node) -> void:
	if _is_skull_key(body):
		_key_2_body_count += 1
		_check_puzzle()


func _on_key_2_body_exited(body: Node) -> void:
	if _is_skull_key(body):
		_key_2_body_count = maxi(_key_2_body_count - 1, 0)


func _check_puzzle() -> void:
	if _door_opened:
		return
	var slot1_filled := _key_1_placed or _key_1_body_count > 0
	var slot2_filled := _key_2_placed or _key_2_body_count > 0
	if not slot1_filled or not slot2_filled:
		return
	_door_opened = true
	_open_door()


func _open_door() -> void:
	var tween := create_tween()
	tween.tween_property(door, "rotation:y", deg_to_rad(DOOR_OPEN_Y_DEGREES), DOOR_OPEN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
