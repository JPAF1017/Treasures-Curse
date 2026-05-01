extends Control

const TEST_MAP_PATH := "res://levels/level1.tscn"

@onready var play_button: Button = $Button/MenuButton
@onready var quit_button: Button = $Button/Quit
@onready var multiplayer_button: Button = $Button/Multiplayer
@onready var settings_button: Button = $Button/Settings
@onready var button_container: Control = $Button

var _map_instance: Node = null


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	settings_button.pressed.connect(_on_settings_pressed)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/host_join_menu.tscn")


func _on_settings_pressed() -> void:
	var settings: PackedScene = load("res://menus/settings_menu.tscn")
	add_child(settings.instantiate())


func _on_play_pressed() -> void:
	play_button.disabled = true
	button_container.visible = false
	# Reset puzzle pool state so each run gets a fresh shuffle
	CandlePuzzleRoom.reset_for_generation()
	TableItemSpawn.reset_for_generation()
	var packed: PackedScene = load(TEST_MAP_PATH)
	_map_instance = packed.instantiate()
	var generator := _find_dungeon_generator(_map_instance)
	if generator:
		generator.generate_threaded = true
		generator.done_generating.connect(_on_map_ready)
		if SettingsManager.generation_seed != 0:
			generator.generate_on_ready = false
	get_tree().root.add_child(_map_instance)
	if not generator:
		_on_map_ready()
		return
	if SettingsManager.generation_seed != 0:
		generator.call("generate", SettingsManager.generation_seed)


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

	# Lock the player so WASD doesn't skip the cutscene
	var player := _find_player(_map_instance)
	if player != null and "cutscene_active" in player:
		player.cutscene_active = true

	# Show the cutscene as a top-level overlay (layer 100 puts it above all game UI)
	var cutscene_canvas := CanvasLayer.new()
	cutscene_canvas.layer = 100
	tree.root.add_child(cutscene_canvas)
	var cutscene_packed: PackedScene = load("res://menus/cutscene.tscn")
	cutscene_canvas.add_child(cutscene_packed.instantiate())

	queue_free()


func _find_player(from: Node) -> Node:
	var p := from.find_child("player", true, false)
	if p != null:
		return p
	var players := from.find_children("*", "CharacterBody3D", true, false)
	return players[0] if not players.is_empty() else null


func _move_player_to_start_room() -> void:
	var players := _map_instance.find_children("*", "CharacterBody3D", true, false)
	var start_room := _map_instance.find_child("StartRoom", true, false)
	if players.is_empty() or start_room == null:
		return
	var player: Node3D = players[0]
	# Place the player at the StartRoom's position, slightly above the floor
	player.global_position = start_room.global_position + Vector3(0, 1.0, 0)
