@tool
extends DungeonRoom3D

@export var torch_spawn_chance: float = 0.50

func _ready() -> void:
	super._ready()
	randomize_torches()

func randomize_torches() -> void:
	var props := get_node_or_null("Models/Props") as Node
	if props == null:
		return
	for child in props.get_children():
		if child.name.begins_with("Torch"):
			child.visible = randf() < torch_spawn_chance
