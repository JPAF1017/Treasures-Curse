class_name SkullPuzzleController
extends Node3D

const SKULL_KEY_SCENE_PATH := "res://puzzles/skull_key.tscn"
const GOLD_ITEM_SCRIPT: Script = preload("res://scripts/items/gold.gd")
const EXITING_QUESTION_PATH := "res://menus/exiting_question.tscn"
const ENDING_BAD_PATH := "res://menus/ending_bad.tscn"
const DOOR_OPEN_Y_DEGREES := 60.0
const DOOR_OPEN_DURATION := 1.5
const RAYCAST_DISTANCE := 5.0
const SKULL_PLACE_Y_OFFSET := 1.3
const INTERACT_RANGE := 35.0
const DOOR_OPEN_SOUND_PATH := "res://sounds/Interactions/opening.mp3"

static var player_entered_room: bool = false
static var door_opened_static: bool = false

@onready var key_area_1: Area3D = $Key
@onready var key_area_2: Area3D = $Key2
@onready var hexagon_1: Node3D = $Hexagon
@onready var hexagon_2: Node3D = $Hexagon2
@onready var door: Node3D = $"../Door/Door_01"
@onready var exit_area: Area3D = $"../Door/Exit"

# Placed via E-key interaction (physics disabled, tracked directly)
var _key_1_placed: bool = false
var _key_2_placed: bool = false
# Dropped into area via physics (body signals)
var _key_1_body_count: int = 0
var _key_2_body_count: int = 0

var _door_opened: bool = false
var _player: Node = null
var _place_item_control: Control = null
var _place_item_label: Label = null
var _warning2_control: Control = null
var _warning2_label: Label = null
var _door_area: Area3D = null
var _hovered_area: Area3D = null
var _door_hovered: bool = false
var _warning2_timer: float = 0.0


func _ready() -> void:
	find_child.call_deferred("_find_door_area")
	key_area_1.body_entered.connect(_on_key_1_body_entered)
	key_area_1.body_exited.connect(_on_key_1_body_exited)
	key_area_2.body_entered.connect(_on_key_2_body_entered)
	key_area_2.body_exited.connect(_on_key_2_body_exited)


func _process(delta: float) -> void:
	_find_player_if_needed()
	if _player == null:
		return
	if not SkullPuzzleController.player_entered_room:
		if global_position.distance_to(_player.global_position) <= 30.0:
			SkullPuzzleController.player_entered_room = true

	# Only manage PlaceItem when the player is near this room.
	if global_position.distance_to(_player.global_position) > INTERACT_RANGE:
		if _hovered_area != null or _door_hovered:
			_set_place_item_visible(false)
			_hovered_area = null
			_door_hovered = false
		return

	if _warning2_timer > 0.0:
		_warning2_timer -= delta
		if _warning2_timer <= 0.0:
			_set_warning2_visible(false)

	_update_interact_prompt()

	if Input.is_action_just_pressed("e"):
		if _hovered_area == exit_area:
			_try_exit()
		elif _hovered_area != null:
			if _get_selected_skull_key() != null:
				_try_place_skull(_hovered_area)
			else:
				_show_warning2("I could place something here but what?")
		elif _door_hovered:
			_show_warning2("I think I need to place something on the slabs to open this")


func _find_player_if_needed() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0]
	_place_item_control = _player.get_node_or_null("CanvasLayer/Control/PlaceItem") as Control
	_place_item_label = _player.get_node_or_null("CanvasLayer/Control/PlaceItem/Label") as Label
	_warning2_control = _player.get_node_or_null("CanvasLayer/Warning2") as Control
	_warning2_label = _player.get_node_or_null("CanvasLayer/Warning2/Label") as Label


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
	_door_hovered = false
	var camera := _get_player_camera()
	if camera == null:
		_set_place_item_visible(false)
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
		elif collider == exit_area:
			aimed = exit_area
		elif not _door_opened and collider == _door_area:
			_door_hovered = true

	var has_skull := _get_selected_skull_key() != null

	if aimed == exit_area:
		_hovered_area = aimed
		_set_place_item_label("interact")
		_set_place_item_visible(true)
	elif aimed != null and has_skull:
		_hovered_area = aimed
		_set_place_item_label("place item")
		_set_place_item_visible(true)
	elif aimed != null and not has_skull:
		_hovered_area = aimed
		_set_place_item_label("interact")
		_set_place_item_visible(true)
	elif _door_hovered:
		_hovered_area = null
		_set_place_item_label("interact")
		_set_place_item_visible(true)
	else:
		_hovered_area = null
		_set_place_item_visible(false)


func _set_place_item_label(txt: String) -> void:
	if _place_item_label != null and is_instance_valid(_place_item_label):
		_place_item_label.text = txt


func _set_place_item_visible(visible_state: bool) -> void:
	if _place_item_control != null and is_instance_valid(_place_item_control):
		_place_item_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place_item_control.visible = visible_state


func _set_warning2_visible(visible_state: bool) -> void:
	if _warning2_control != null and is_instance_valid(_warning2_control):
		_warning2_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_warning2_control.visible = visible_state


func _show_warning2(msg: String) -> void:
	if _warning2_label != null and is_instance_valid(_warning2_label):
		_warning2_label.text = msg
	_set_warning2_visible(true)
	_warning2_timer = 3.0


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

	_set_place_item_visible(false)
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
	SkullPuzzleController.door_opened_static = true
	_play_door_sound(door.global_position if door != null else global_position)
	var tween := create_tween()
	tween.tween_property(door, "rotation:y", deg_to_rad(DOOR_OPEN_Y_DEGREES), DOOR_OPEN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_door_sound(pos: Vector3) -> void:
	var sound_player := AudioStreamPlayer3D.new()
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(sound_player)
		sound_player.stream = load(DOOR_OPEN_SOUND_PATH)
		sound_player.volume_db = linear_to_db(0.7)
		sound_player.global_position = pos
		sound_player.finished.connect(sound_player.queue_free)
		sound_player.play()


func _count_gold_for_player(player: Node) -> int:
	var models = player.get("hotbar_item_models")
	if models == null:
		return 0
	var count := 0
	for item in models:
		if item != null and is_instance_valid(item) and item.get_script() == GOLD_ITEM_SCRIPT:
			count += 1
	return count


func _count_items_for_player(player: Node) -> int:
	var models = player.get("hotbar_item_models")
	if models == null:
		return 0
	var count := 0
	for item in models:
		if item != null and is_instance_valid(item):
			count += 1
	return count


func _try_exit() -> void:
	if not (multiplayer.get_multiplayer_peer() is OfflineMultiplayerPeer):
		_handle_multiplayer_exit()
	else:
		_handle_solo_exit()


func _handle_solo_exit() -> void:
	if _player == null:
		return
	var gold := _count_gold_for_player(_player)
	if gold == 0:
		_show_exit_question("empty")
	elif gold >= 1:
		GameStats.stop_timer()
		get_tree().change_scene_to_file(ENDING_BAD_PATH)
	else:
		_show_exit_question("incomplete")


func _handle_multiplayer_exit() -> void:
	var all_players := get_tree().get_nodes_in_group("player")
	var any_has_gold := false
	for p in all_players:
		if _count_gold_for_player(p) >= 1:
			any_has_gold = true
	if not any_has_gold:
		_show_exit_question("empty")
	else:
		GameStats.stop_timer()
		get_tree().change_scene_to_file(ENDING_BAD_PATH)


func _show_exit_question(mode: String) -> void:
	var packed := load(EXITING_QUESTION_PATH) as PackedScene
	var node := packed.instantiate()
	get_tree().current_scene.add_child(node)
	node.setup(mode)
