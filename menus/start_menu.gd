extends Control

const TEST_MAP_PATH := "res://levels/level1.tscn"

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var play_button: Button = $Button/MenuButton

var _map_instance: Node = null


func _ready() -> void:
	video_player.finished.connect(_on_video_finished)
	play_button.pressed.connect(_on_play_pressed)


func _on_video_finished() -> void:
	video_player.play()


func _on_play_pressed() -> void:
	play_button.disabled = true
	# Reset puzzle pool state so each run gets a fresh shuffle
	CandlePuzzleRoom.reset_for_generation()
	TableItemSpawn.reset_for_generation()
	var packed: PackedScene = load(TEST_MAP_PATH)
	_map_instance = packed.instantiate()
	var generator := _find_dungeon_generator(_map_instance)
	if generator:
		generator.generate_threaded = true
		generator.done_generating.connect(_on_map_ready)
	get_tree().root.add_child(_map_instance)
	if not generator:
		_on_map_ready()


func _find_dungeon_generator(node: Node) -> Node:
	for child in node.get_children():
		if child.has_signal("done_generating"):
			return child
		var result := _find_dungeon_generator(child)
		if result:
			return result
	return null


func _on_map_ready() -> void:
	_move_player_to_start_room()
	var tree := get_tree()
	tree.root.remove_child(self)
	tree.current_scene = _map_instance
	queue_free()


func _move_player_to_start_room() -> void:
	var players := _map_instance.find_children("*", "CharacterBody3D", true, false)
	var start_room := _map_instance.find_child("StartRoom", true, false)
	if players.is_empty() or start_room == null:
		return
	var player: Node3D = players[0]
	# Place the player at the StartRoom's position, slightly above the floor
	player.global_position = start_room.global_position + Vector3(0, 1.0, 0)
