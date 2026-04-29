extends Control

const ENDING_GOOD_PATH := "res://menus/ending_good.tscn"

@onready var _label_incomplete: Label = $Texts/incomplete
@onready var _label_empty: Label = $Texts/empty
@onready var _label_mp_incomplete: Label = $Texts/multiplayerIncomplete
@onready var _btn_incomplete: Button = $Buttons/incomplete
@onready var _btn_empty_yes: Button = $Buttons/emptyYes
@onready var _btn_empty_no: Button = $Buttons/emptyNo


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_btn_incomplete.pressed.connect(_return_to_game)
	_btn_empty_no.pressed.connect(_return_to_game)
	_btn_empty_yes.pressed.connect(_go_good_ending)


## Called by skull_puzzle_controller after adding this node to the tree.
## mode: "incomplete" | "empty" | "multiplayer_incomplete"
func setup(mode: String) -> void:
	match mode:
		"incomplete":
			_label_incomplete.visible = true
			_btn_incomplete.visible = true
		"empty":
			_label_empty.visible = true
			_btn_empty_yes.visible = true
			_btn_empty_no.visible = true
		"multiplayer_incomplete":
			_label_mp_incomplete.visible = true
			_btn_incomplete.visible = true


func _return_to_game() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()


func _go_good_ending() -> void:
	GameStats.stop_timer()
	get_tree().change_scene_to_file(ENDING_GOOD_PATH)
