extends Control

const SOUND_PATHS: Array[String] = [
	"res://sounds/cutscene/cutscene1.mp3",
	"res://sounds/cutscene/cutscene2.mp3",
	"res://sounds/cutscene/cutscene3.mp3",
	"res://sounds/cutscene/cutscene4.mp3",
]
const MUSIC_PATH := "res://sounds/menu/cutscene.mp3"
const FADE_DURATION := 1.5

@onready var _image1: Sprite2D = $"Images/1"
@onready var _image2: Sprite2D = $"Images/2"
@onready var _image3: Sprite2D = $"Images/3"
@onready var _image4: Sprite2D = $"Images/4"
@onready var _label1: Label = $Texts/Label1
@onready var _label2: Label = $Texts/Label2
@onready var _label3: Label = $Texts/Label3
@onready var _label4: Label = $Texts/Label4

var _audio_player: AudioStreamPlayer = null
var _music_player: AudioStreamPlayer = null
var _current_slide: int = 0
var _fading_in: bool = false
var _fading_out: bool = false
var _fade_timer: float = 0.0
var _done: bool = false
var _images: Array = []
var _labels: Array = []
var _paused_streams_3d: Array = []
var _paused_streams_2d: Array = []


func _ready() -> void:
	# This node must keep running while the game tree is paused.
	process_mode = PROCESS_MODE_ALWAYS

	_images = [_image1, _image2, _image3, _image4]
	_labels = [_label1, _label2, _label3, _label4]

	# Show only the first slide
	for i in 4:
		_images[i].visible = (i == 0)
		_labels[i].visible = (i == 0)
		_images[i].modulate.a = 1.0
		_labels[i].modulate.a = 1.0

	# Fade in first slide
	_image1.modulate.a = 0.0
	_label1.modulate.a = 0.0
	_fading_in = true
	_fade_timer = 0.0

	# Start background music — loops for the whole cutscene
	_music_player = AudioStreamPlayer.new()
	_music_player.process_mode = PROCESS_MODE_ALWAYS
	var music_stream := load(MUSIC_PATH) as AudioStream
	if music_stream is AudioStreamMP3:
		(music_stream as AudioStreamMP3).loop = true
	_music_player.stream = music_stream
	_music_player.volume_db = -10.0
	add_child(_music_player)
	_music_player.play()

	# Start per-slide audio — must also run while paused
	_audio_player = AudioStreamPlayer.new()
	_audio_player.process_mode = PROCESS_MODE_ALWAYS
	_audio_player.volume_db = -5.0
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)
	_play_slide_audio(0)

	# Hide player loading screen so it doesn't show through the cutscene
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("hide_loading_screen"):
			p.hide_loading_screen()

	# Pause all currently-playing 3D audio streams (torch fire sounds etc.).
	# The audio server keeps mixing even when the scene tree is paused, so we
	# must set stream_paused manually. NPCs are already frozen by player.gd.
	for node in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if node.playing and not node.stream_paused:
			node.stream_paused = true
			_paused_streams_3d.append(node)
	for node in get_tree().root.find_children("*", "AudioStreamPlayer2D", true, false):
		if node.playing and not node.stream_paused:
			node.stream_paused = true
			_paused_streams_2d.append(node)


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


func _play_slide_audio(index: int) -> void:
	_audio_player.stream = load(SOUND_PATHS[index])
	_audio_player.play()


func _on_audio_finished() -> void:
	_advance_slide()


func _advance_slide() -> void:
	if _current_slide >= 3:
		# Last slide: fade out to end
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
	_play_slide_audio(index)


func _input(event: InputEvent) -> void:
	if _done:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			skip = true
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			skip = true
	if not skip:
		return
	get_viewport().set_input_as_handled()
	if _fading_in:
		# Complete fade in instantly and begin the slide countdown
		_fading_in = false
		_fade_timer = 0.0
		_images[_current_slide].modulate.a = 1.0
		_labels[_current_slide].modulate.a = 1.0
	elif _fading_out:
		# Skip the rest of the fade and finish immediately
		_fading_out = false
		_finish()
	else:
		_audio_player.stop()
		_advance_slide()


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_music_player):
		_music_player.stop()
	if is_instance_valid(_audio_player):
		_audio_player.stop()
	# Restore all audio streams that were paused at cutscene start
	for node in _paused_streams_3d:
		if is_instance_valid(node):
			node.stream_paused = false
	for node in _paused_streams_2d:
		if is_instance_valid(node):
			node.stream_paused = false
	# Notify all local players to start the game
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("start_from_cutscene"):
			p.start_from_cutscene()
	# Clean up: remove the CanvasLayer wrapper we were placed in
	if get_parent() is CanvasLayer:
		get_parent().queue_free()
	else:
		queue_free()
