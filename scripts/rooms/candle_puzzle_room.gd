@tool
class_name CandlePuzzleRoom
extends DungeonRoom3D

const _PUZZLE_TABLE_PATHS: Array[String] = [
	"res://puzzles/candle_puzzle_table1.tscn",
	"res://puzzles/candle_puzzle_table2.tscn",
	"res://puzzles/candle_puzzle_table3.tscn",
	"res://puzzles/candle_puzzle_table4.tscn",
]

# Shared across all instances so no two rooms pick the same table.
static var _shared_pool: Array[String] = []
static var _pool_idx: int = 0
static var puzzle_door_opened: bool = false

static func reset_for_generation() -> void:
	_shared_pool.clear()
	_pool_idx = 0
	puzzle_door_opened = false

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_randomize_tables()

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

var _satisfied_count: int = 0
var _door_opened: bool = false

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
	if door == null:
		return
	var tween := create_tween()
	tween.tween_property(door, "rotation:y", door.rotation.y + PI / 2.0, 1.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
