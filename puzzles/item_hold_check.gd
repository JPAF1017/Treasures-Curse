extends Area3D

@export var table_slot: int = 1

const _SCENE_TO_SCRIPT: Dictionary = {
	"res://assets/items/Gem_key1.tscn": "res://scripts/items/gem_key1.gd",
	"res://assets/items/Gem_key2.tscn": "res://scripts/items/gem_key2.gd",
	"res://assets/items/Gem_key3.tscn": "res://scripts/items/gem_key3.gd",
	"res://assets/items/Gem_key4.tscn": "res://scripts/items/gem_key4.gd",
}

var _satisfied: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if _satisfied:
		return
	if _check_item(body):
		_satisfied = true
		var room := _find_room()
		if room and room.has_method("on_item_hold_satisfied"):
			room.call("on_item_hold_satisfied")

func _on_body_exited(body: Node3D) -> void:
	if _satisfied and _check_item(body):
		_satisfied = false
		var room := _find_room()
		if room and room.has_method("on_item_hold_unsatisfied"):
			room.call("on_item_hold_unsatisfied")

# Walk up the tree to find the puzzle room rather than relying on owner,
# which can be null for programmatically added nodes.
func _find_room() -> Node:
	var n := get_parent()
	while n != null:
		if n.has_method("on_item_hold_satisfied"):
			return n
		n = n.get_parent()
	return null

func _check_item(body: Node) -> bool:
	var scr = body.get_script()
	if scr == null:
		return false
	var expected_scene: String = TableItemSpawn.get_item_for_slot(table_slot)
	if expected_scene.is_empty():
		return false
	var expected_script: String = _SCENE_TO_SCRIPT.get(expected_scene, "")
	return scr.resource_path == expected_script
