class_name TableItemSpawn
extends Area3D

const _ITEM_PATHS: Array[String] = [
	"res://assets/items/sword.tscn",
	"res://assets/items/bat.tscn",
	"res://assets/items/shovel.tscn",
	"res://assets/items/health.tscn",
	"res://assets/items/smoke.tscn",
]

# Total table slots across all puzzle rooms in one dungeon generation.
const _SLOTS_PER_GENERATION: int = 4

static var _shared_pool: Array[String] = []
static var _picks_this_gen: int = 0
# Maps table_slot (int) → spawned item scene path (String).
static var _registry: Dictionary = {}

# Set in each table tscn Spawn node: 1, 2, 3, or 4.
@export var table_slot: int = 0

static func reset_for_generation() -> void:
	_shared_pool.clear()
	_picks_this_gen = 0
	_registry.clear()

static func get_item_for_slot(slot: int) -> String:
	return _registry.get(slot, "")

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var root := get_tree().root
	_spawn_item.bind(root).call_deferred()

func _spawn_item(root: Node) -> void:
	# If this node was removed from the tree (replaced by candle_puzzle_room),
	# don't spawn — the replacement instance will spawn its own item.
	if not is_inside_tree():
		return
	# Capture position here (deferred) so all parent transforms are finalised.
	var shape := get_node_or_null("CollisionShape3D") as Node3D
	var spawn_pos := shape.global_position if shape else global_position
	if _picks_this_gen >= _SLOTS_PER_GENERATION or _shared_pool.is_empty():
		_shared_pool = _ITEM_PATHS.duplicate()
		_shared_pool.shuffle()
		_picks_this_gen = 0
		_registry.clear()
	var path: String = _shared_pool[_picks_this_gen]
	_picks_this_gen += 1
	if table_slot > 0:
		_registry[table_slot] = path
	var item := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(item)
	item.global_position = spawn_pos
	# Freeze RigidBody items so CSG table collision has time to generate,
	# preventing them from falling through the table on spawn.
	if item is RigidBody3D:
		(item as RigidBody3D).freeze = true
		_unfreeze_item.bind(item).call_deferred()

func _unfreeze_item(item: RigidBody3D) -> void:
	if is_instance_valid(item):
		item.freeze = false
