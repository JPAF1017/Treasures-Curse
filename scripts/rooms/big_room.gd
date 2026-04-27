@tool
class_name BigRoom
extends DungeonRoom3D

# Items in big rooms are now spawned by level1_spawner after dungeon generation,
# using a seeded RNG and the ItemSpawner, so all peers receive the same items.

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
