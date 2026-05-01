extends Control

const START_MENU_PATH := "res://menus/start_menu.tscn"

@onready var continue_button: Button = $Button/Continue
@onready var quit_button: Button = $Button/Quit
@onready var main_menu_button: Button = $Button/"Main Menu"
@onready var settings_button: Button = $Button/Settings


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_continue_pressed()


func _on_continue_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	# Free the level scene and all its resources before loading the menu.
	var current := get_tree().current_scene
	if current:
		get_tree().root.remove_child(current)
		current.queue_free()
	queue_free()
	var start_menu: PackedScene = load(START_MENU_PATH)
	var menu_instance := start_menu.instantiate()
	get_tree().root.add_child(menu_instance)
	get_tree().current_scene = menu_instance


func _on_settings_pressed() -> void:
	var settings: PackedScene = load("res://menus/settings_menu.tscn")
	var instance := settings.instantiate()
	instance.seed_locked = true
	add_child(instance)
