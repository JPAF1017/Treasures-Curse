class_name TableItemSpawn
extends Area3D

# Maps table_slot (int) → spawned item scene path (String).
# Populated by level1_spawner._apply_table_registry() after dungeon generation
# so that all peers (server and clients) have the same mapping.
static var registry: Dictionary = {}

# Set in each table tscn Spawn node: 1, 2, 3, or 4.
@export var table_slot: int = 0

## Called before every dungeon generation to reset stale state.
static func reset_for_generation() -> void:
	registry.clear()

static func get_item_for_slot(floor_y: float, slot: int) -> String:
	var key := "%d|%d" % [roundi(floor_y), slot]
	return registry.get(key, "")
