extends Control

const CORRIDOR_SCENE_PATH := "res://assets/rooms/corridor.tscn"

var seed_locked: bool = false

@onready var volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $Panel/MarginContainer/VBoxContainer/VolumeRow/VolumeValue
@onready var vsync_check: CheckBox = $Panel/MarginContainer/VBoxContainer/VSyncRow/VSyncCheck
@onready var fullscreen_check: CheckBox = $Panel/MarginContainer/VBoxContainer/FullscreenRow/FullscreenCheck
@onready var aspect_option: OptionButton = $Panel/MarginContainer/VBoxContainer/AspectRow/AspectOption
@onready var seed_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SeedRow/SeedInput
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/BackRow/Back
@onready var unstuck_row: HBoxContainer = $Panel/MarginContainer/VBoxContainer/UnstuckRow
@onready var unstuck_button: Button = $Panel/MarginContainer/VBoxContainer/UnstuckRow/Unstuck
@onready var panel: Panel = $Panel


func _ready() -> void:
	volume_slider.value = SettingsManager.master_volume
	volume_value_label.text = "%d%%" % int(SettingsManager.master_volume * 100)
	vsync_check.button_pressed = SettingsManager.vsync_enabled
	fullscreen_check.button_pressed = SettingsManager.exclusive_fullscreen
	aspect_option.select(SettingsManager.aspect_ratio)
	if SettingsManager.generation_seed != 0:
		seed_input.text = str(SettingsManager.generation_seed)
	if seed_locked:
		seed_input.editable = false
		seed_input.placeholder_text = "Locked in-game"
		unstuck_row.visible = true
		panel.offset_top -= 40.0
		panel.offset_bottom += 40.0

	volume_slider.value_changed.connect(_on_volume_changed)
	vsync_check.toggled.connect(_on_vsync_toggled)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	aspect_option.item_selected.connect(_on_aspect_selected)
	seed_input.text_changed.connect(_on_seed_changed)
	back_button.pressed.connect(_on_back_pressed)
	unstuck_button.pressed.connect(_on_unstuck_pressed)


func _on_volume_changed(value: float) -> void:
	volume_value_label.text = "%d%%" % int(value * 100)
	SettingsManager.set_master_volume(value)


func _on_vsync_toggled(pressed: bool) -> void:
	SettingsManager.set_vsync(pressed)


func _on_fullscreen_toggled(pressed: bool) -> void:
	SettingsManager.set_exclusive_fullscreen(pressed)


func _on_aspect_selected(index: int) -> void:
	SettingsManager.set_aspect_ratio(index)


func _on_seed_changed(new_text: String) -> void:
	if new_text.is_empty():
		SettingsManager.set_generation_seed(0)
	elif new_text.is_valid_int():
		SettingsManager.set_generation_seed(new_text.to_int())


func _on_back_pressed() -> void:
	queue_free()


func _on_unstuck_pressed() -> void:
	var player := _find_local_player()
	if player == null:
		return

	var nearest := _find_nearest_corridor(player.global_position)
	if nearest != null:
		player.global_position = Vector3(nearest.global_position.x, player.global_position.y, nearest.global_position.z)
		if player.has_method("_is_movement_locked"):
			for src in player.movement_lock_sources.duplicate():
				if src != null and is_instance_valid(src) and src.has_method("_interrupt_grab"):
					src.call("_interrupt_grab", false)
		player.velocity = Vector3.ZERO

	var pause_menu := get_parent()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()
	else:
		queue_free()


func _find_local_player() -> CharacterBody3D:
	for p in get_tree().get_nodes_in_group("player"):
		if p is CharacterBody3D:
			if not multiplayer.has_multiplayer_peer() or p.is_multiplayer_authority():
				return p as CharacterBody3D
	return null


func _find_nearest_corridor(from_pos: Vector3) -> Node3D:
	var corridors: Array[Node3D] = []
	_collect_corridors(get_tree().root, corridors)
	if corridors.is_empty():
		return null
	var nearest: Node3D = corridors[0]
	var from_xz := Vector2(from_pos.x, from_pos.z)
	var nearest_dist := from_xz.distance_squared_to(Vector2(nearest.global_position.x, nearest.global_position.z))
	for c in corridors:
		var d := from_xz.distance_squared_to(Vector2(c.global_position.x, c.global_position.z))
		if d < nearest_dist:
			nearest_dist = d
			nearest = c
	return nearest


func _collect_corridors(node: Node, result: Array[Node3D]) -> void:
	if node is Node3D and (node as Node3D).scene_file_path == CORRIDOR_SCENE_PATH:
		result.append(node as Node3D)
	for child in node.get_children():
		_collect_corridors(child, result)
