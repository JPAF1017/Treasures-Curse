extends Control

const START_MENU_PATH := "res://menus/start_menu.tscn"

@onready var quit_button: Button = $Button/Quit
@onready var main_menu_button: Button = $Button/"Main Menu"


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	quit_button.pressed.connect(_on_quit_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(START_MENU_PATH)
