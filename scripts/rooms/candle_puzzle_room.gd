@tool
class_name CandlePuzzleRoom
extends DungeonRoom3D

const _PUZZLE_TABLE_PATHS: Array[String] = [
	"res://puzzles/candle_puzzle_table1.tscn",
	"res://puzzles/candle_puzzle_table2.tscn",
	"res://puzzles/candle_puzzle_table3.tscn",
	"res://puzzles/candle_puzzle_table4.tscn",
]

const RAYCAST_DISTANCE := 5.0
const ITEM_PLACE_Y_OFFSET := 1.5
const WARNING2_DISPLAY_TIME := 3.0

# Maps table item scene path → expected item script path (mirrors item_hold_check.gd)
const _SCENE_TO_SCRIPT: Dictionary = {
	"res://assets/items/Gem_key1.tscn": "res://scripts/items/gem_key1.gd",
	"res://assets/items/Gem_key2.tscn": "res://scripts/items/gem_key2.gd",
	"res://assets/items/Gem_key3.tscn": "res://scripts/items/gem_key3.gd",
	"res://assets/items/Gem_key4.tscn": "res://scripts/items/gem_key4.gd",
}

# Shared across all instances so no two rooms pick the same table.
static var _shared_pool: Array[String] = []
static var _pool_idx: int = 0
static var puzzle_door_opened: bool = false

static func reset_for_generation() -> void:
	_shared_pool.clear()
	_pool_idx = 0
	puzzle_door_opened = false

# Runtime placement state
var _hold_areas: Array[Area3D] = []        # index 0–3 → ItemHold1–4 Area3D
var _slot_occupied: Array[bool] = [false, false, false, false]
var _slot_correct: Array[bool] = [false, false, false, false]  # true if placed item was correct
var _placed_items: Array[Node3D] = [null, null, null, null]  # items placed at each hold
var _satisfied_count: int = 0
var _door_opened: bool = false

# Player / UI references (found at runtime)
var _player: Node = null
var _place_item_control: Control = null
var _warning2_control: Control = null

# Interaction state
var _hovered_hold_index: int = -1
var _warning2_timer: float = 0.0


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_randomize_tables()
	_find_hold_areas.call_deferred()


func _find_hold_areas() -> void:
	_hold_areas.clear()
	for i in range(1, 5):
		var hold_node := find_child("ItemHold%d" % i, true, false) as Node3D
		if hold_node == null:
			continue
		var area := hold_node.get_node_or_null("Area3D") as Area3D
		if area != null:
			_hold_areas.append(area)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_find_player_if_needed()
	if _player == null:
		return

	# Countdown Warning2 timer
	if _warning2_timer > 0.0:
		_warning2_timer -= delta
		if _warning2_timer <= 0.0:
			_set_warning2_visible(false)

	_update_place_prompt()

	if _hovered_hold_index >= 0 and Input.is_action_just_pressed("e"):
		_try_place_item(_hovered_hold_index)

	# Detect if the player picked up a placed item from the table (only before door opens)
	if not _door_opened:
		for i in _placed_items.size():
			var placed := _placed_items[i]
			if placed == null or not is_instance_valid(placed):
				_slot_occupied[i] = false
				_placed_items[i] = null
				continue
			if _slot_occupied[i] and int(placed.get("inventory_slot_index")) >= 0:
				# Item was picked back up — free the slot
				if _slot_correct[i]:
					_satisfied_count = max(_satisfied_count - 1, 0)
					_slot_correct[i] = false
				placed.scale = Vector3.ONE
				_slot_occupied[i] = false
				_placed_items[i] = null


func _find_player_if_needed() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0]
	_place_item_control = _player.get_node_or_null("CanvasLayer/Control/PlaceItem") as Control
	_warning2_control = _player.get_node_or_null("CanvasLayer/Warning2") as Control


func _get_player_camera() -> Camera3D:
	if _player == null:
		return null
	return _player.get("camera") as Camera3D


func _get_selected_item() -> Node:
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
	return item


func _update_place_prompt() -> void:
	if _hold_areas.is_empty() or _door_opened:
		_set_place_item_visible(false)
		_hovered_hold_index = -1
		return

	var camera := _get_player_camera()
	if camera == null or _get_selected_item() == null:
		_set_place_item_visible(false)
		_hovered_hold_index = -1
		return

	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * RAYCAST_DISTANCE)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [_player]
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	var found_idx := -1
	if not result.is_empty():
		var collider: Object = result.get("collider")
		for i in _hold_areas.size():
			if collider == _hold_areas[i] and not _slot_occupied[i]:
				found_idx = i
				break

	_hovered_hold_index = found_idx
	# Show PlaceItem only when aimed at a free slot and Warning2 is not active
	if found_idx >= 0 and _warning2_timer <= 0.0:
		_set_place_item_visible(true)
	else:
		_set_place_item_visible(false)


func _set_place_item_visible(visible_state: bool) -> void:
	if _place_item_control != null and is_instance_valid(_place_item_control):
		_place_item_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place_item_control.visible = visible_state


func _set_warning2_visible(visible_state: bool) -> void:
	if _warning2_control != null and is_instance_valid(_warning2_control):
		_warning2_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_warning2_control.visible = visible_state


func _try_place_item(hold_index: int) -> void:
	var item := _get_selected_item()
	if item == null:
		return

	# Non-puzzle item: reject with Warning2
	if not item.get_meta("puzzle_item", false):
		_set_place_item_visible(false)
		_set_warning2_visible(true)
		_warning2_timer = WARNING2_DISPLAY_TIME
		return

	# Use drop_from_hotbar so every item type handles its own viewmodel/hand cleanup.
	# This reparents the item to the scene root, re-enables physics, and adds throw
	# velocity — we then immediately freeze and reposition it.
	var area := _hold_areas[hold_index]
	var target_pos := area.global_position + Vector3(0.0, ITEM_PLACE_Y_OFFSET, 0.0)

	if _player.has_method("_drop_selected_hotbar_item"):
		_player.call("_drop_selected_hotbar_item")
		# Freeze in place WITHOUT zeroing collision layer, so the player can still
		# aim at the item and pick it back up to retry.
		if item is RigidBody3D:
			var rb := item as RigidBody3D
			rb.freeze = true
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
		item.global_position = target_pos
		item.rotation = Vector3.ZERO
		if item.has_method("_set_item_visuals_visible"):
			item.call("_set_item_visuals_visible", true)
		if item.has_method("_set_visual_layer_recursive"):
			item.call("_set_visual_layer_recursive", item, 1)
		# Per-item scale adjustments
		var item_script := item.get_script() as Script
		var script_path := item_script.resource_path if item_script != null else ""
		match script_path:
			"res://scripts/items/gem_key1.gd", "res://scripts/items/gem_key2.gd", \
			"res://scripts/items/gem_key3.gd", "res://scripts/items/gem_key4.gd":
				item.scale = Vector3(1.5, 1.5, 1.5)

	# Mark slot occupied, track placed item, clear prompt
	_slot_occupied[hold_index] = true
	_placed_items[hold_index] = item
	_set_place_item_visible(false)
	_hovered_hold_index = -1

	# Manually check correctness (physics is off so item_hold_check won't fire)
	_check_slot_correct(hold_index, item)


func _check_slot_correct(hold_index: int, item: Node) -> void:
	# table_slot is 1-indexed; ItemHold1 → slot 1, etc.
	var table_slot: int = hold_index + 1
	var expected_scene: String = TableItemSpawn.get_item_for_slot(table_slot)
	if expected_scene.is_empty():
		return
	var expected_script: String = _SCENE_TO_SCRIPT.get(expected_scene, "")
	if expected_script.is_empty():
		return
	var item_script: Script = item.get_script() as Script
	if item_script != null and item_script.resource_path == expected_script:
		_slot_correct[hold_index] = true
		on_item_hold_satisfied()


func on_item_hold_satisfied() -> void:
	_satisfied_count += 1
	if not _door_opened and _satisfied_count >= 4:
		_door_opened = true
		_open_door()


func on_item_hold_unsatisfied() -> void:
	_satisfied_count = max(_satisfied_count - 1, 0)


func _open_door() -> void:
	CandlePuzzleRoom.puzzle_door_opened = true
	var door := get_node_or_null("Models/WallsLR/Door_01") as Node3D
	if door != null:
		var tween := create_tween()
		tween.tween_property(door, "rotation:y", door.rotation.y + PI / 2.0, 1.0) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	# Keep gem keys frozen in place as decorative trophies.
	# Disable their collision so they cannot be picked up from the hold.
	for placed_item in _placed_items:
		if placed_item == null or not is_instance_valid(placed_item):
			continue
		if placed_item is RigidBody3D:
			var rb := placed_item as RigidBody3D
			rb.collision_layer = 0
			rb.collision_mask = 0


func _randomize_tables() -> void:
	var table_nodes: Array[Node3D] = _find_table_nodes(self)
	if table_nodes.is_empty():
		return
	# Reshuffle when the pool is exhausted (new generation).
	if _pool_idx >= _shared_pool.size():
		_shared_pool = _PUZZLE_TABLE_PATHS.duplicate()
		_shared_pool.shuffle()
		_pool_idx = 0
	for table_node: Node3D in table_nodes:
		if _pool_idx >= _shared_pool.size():
			# Safety: reshuffle if somehow more slots than tables.
			_shared_pool.shuffle()
			_pool_idx = 0
		_replace_table_node(table_node, _shared_pool[_pool_idx])
		_pool_idx += 1


func _replace_table_node(old_node: Node3D, scene_path: String) -> void:
	var parent: Node = old_node.get_parent()
	var saved_transform: Transform3D = old_node.transform
	var saved_name: StringName = old_node.name
	var saved_index: int = old_node.get_index()
	var packed: PackedScene = load(scene_path)
	var new_node: Node3D = packed.instantiate()
	new_node.name = saved_name
	new_node.transform = saved_transform
	parent.remove_child(old_node)
	old_node.queue_free()
	parent.add_child(new_node)
	parent.move_child(new_node, saved_index)


func _find_table_nodes(node: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in node.get_children():
		if child is Node3D and String(child.name).begins_with("wall_table"):
			result.append(child as Node3D)
		else:
			result.append_array(_find_table_nodes(child))
	return result

