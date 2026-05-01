extends Control

const MUSIC_PATH := "res://sounds/menu/good.mp3"
const ESCAPE_MENU_PATH := "res://menus/escape_menu.tscn"
const SLIDE_DURATION := 18.0
const FADE_DURATION := 1.5

@onready var _image1: Sprite2D = $"Images/1"
@onready var _image2: Sprite2D = $"Images/2"
@onready var _image3: Sprite2D = $"Images/3"
@onready var _image4: Sprite2D = $"Images/4"
@onready var _label1: Label = $Texts/Label1
@onready var _label2: Label = $Texts/Label2
@onready var _label3: Label = $Texts/Label3
@onready var _label4: Label = $Texts/Label4

var _music_player: AudioStreamPlayer = null
var _current_slide: int = 0
var _slide_timer: float = 0.0
var _fading_in: bool = false
var _fading_out: bool = false
var _fade_timer: float = 0.0
var _done: bool = false
var _images: Array = []
var _labels: Array = []


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_images = [_image1, _image2, _image3, _image4]
	_labels = [_label1, _label2, _label3, _label4]

	for i in 4:
		_images[i].visible = (i == 0)
		_labels[i].visible = (i == 0)
		_images[i].modulate.a = 1.0
		_labels[i].modulate.a = 1.0

	_image1.modulate.a = 0.0
	_label1.modulate.a = 0.0
	_fading_in = true
	_fade_timer = 0.0
	_slide_timer = SLIDE_DURATION

	_music_player = AudioStreamPlayer.new()
	_music_player.stream = load(MUSIC_PATH)
	_music_player.volume_db = -5.0
	add_child(_music_player)
	_music_player.play()


func _process(delta: float) -> void:
	if _done:
		return

	if _fading_in:
		_fade_timer += delta
		var t := minf(_fade_timer / FADE_DURATION, 1.0)
		_images[_current_slide].modulate.a = t
		_labels[_current_slide].modulate.a = t
		if t >= 1.0:
			_fading_in = false
			_fade_timer = 0.0
		return

	if _fading_out:
		_fade_timer += delta
		var t := 1.0 - minf(_fade_timer / FADE_DURATION, 1.0)
		_images[_current_slide].modulate.a = t
		_labels[_current_slide].modulate.a = t
		if t <= 0.0:
			_fading_out = false
			_finish()
		return

	_slide_timer -= delta
	if _slide_timer <= 0.0:
		_advance_slide()


func _advance_slide() -> void:
	if _current_slide >= 3:
		_fading_out = true
		_fade_timer = 0.0
	else:
		_show_slide(_current_slide + 1)


func _show_slide(index: int) -> void:
	for i in 4:
		_images[i].visible = (i == index)
		_labels[i].visible = (i == index)
		_images[i].modulate.a = 1.0
		_labels[i].modulate.a = 1.0
	_current_slide = index
	_slide_timer = SLIDE_DURATION


func _input(event: InputEvent) -> void:
	if _done:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	get_viewport().set_input_as_handled()
	if _fading_in:
		_fading_in = false
		_fade_timer = 0.0
		_images[_current_slide].modulate.a = 1.0
		_labels[_current_slide].modulate.a = 1.0
	elif _fading_out:
		_fading_out = false
		_finish()
	else:
		_advance_slide()


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_music_player):
		_music_player.stop()
	get_tree().change_scene_to_file(ESCAPE_MENU_PATH)
