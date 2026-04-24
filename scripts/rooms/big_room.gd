@tool
class_name BigRoom
extends DungeonRoom3D

const _ITEM_PATHS: Array[String] = [
	"res://assets/items/sword.tscn",
	"res://assets/items/shovel.tscn",
	"res://assets/items/bat.tscn",
	"res://assets/items/health.tscn",
	"res://assets/items/smoke.tscn",
]

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_spawn_random_item($Spawn/SpawnItem)
	_spawn_random_item($Spawn/SpawnItem2)

func _spawn_random_item(spawn_area: Area3D) -> void:
	if spawn_area == null:
		push_warning("BigRoom: spawn_area is null")
		return
	var path: String = _ITEM_PATHS[randi() % _ITEM_PATHS.size()]
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("BigRoom: failed to load item scene: " + path)
		return
	var item: Node3D = packed.instantiate()
	# Add as a child of the spawn area so it moves with the room during generation
	spawn_area.add_child(item)
	# Use local position instead of global, with a +2.0 Y offset so it drops onto the floor
	item.position = Vector3(0.0, 2.0, 0.0)
