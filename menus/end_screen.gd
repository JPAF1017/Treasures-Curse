extends Control

const START_MENU_PATH := "res://menus/start_menu.tscn"

@onready var quit_button: Button = $Button/Quit
@onready var main_menu_button: Button = $Button/"Main Menu"

@onready var stat_charger: Label = get_node_or_null("Stats/Charger")
@onready var stat_gnome: Label = get_node_or_null("Stats/Gnome")
@onready var stat_fly: Label = get_node_or_null("Stats/Fly")
@onready var stat_shambler: Label = get_node_or_null("Stats/Shambler")
@onready var stat_knight: Label = get_node_or_null("Stats/Knight")
@onready var stat_damage: Label = get_node_or_null("Stats/Damage")
@onready var stat_time: Label = get_node_or_null("Stats/Time")


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	quit_button.pressed.connect(_on_quit_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_populate_stats()


func _populate_stats() -> void:
	if stat_charger:
		stat_charger.text = "Chargers killed: %d" % GameStats.kills_charger
	if stat_gnome:
		stat_gnome.text = "Gnomes killed: %d" % GameStats.kills_gnome
	if stat_fly:
		stat_fly.text = "Flies killed: %d" % GameStats.kills_fly
	if stat_shambler:
		stat_shambler.text = "Shamblers killed: %d" % GameStats.kills_shambler
	if stat_knight:
		stat_knight.text = "Knights killed: %d" % GameStats.kills_knight
	if stat_damage:
		stat_damage.text = "Damage dealt: %d" % int(GameStats.damage_dealt)
	if stat_time:
		stat_time.text = "Time: %s" % GameStats.format_time(GameStats.playtime)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_main_menu_pressed() -> void:
	GameStats.reset()
	get_tree().change_scene_to_file(START_MENU_PATH)
