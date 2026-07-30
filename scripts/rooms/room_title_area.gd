class_name RoomTitleArea
extends Area3D

static var player_in_dog_room: bool = false
static var player_in_fly_room: bool = false
static var player_in_gnome_room: bool = false
static var player_in_knight_room: bool = false
static var player_in_shambler_room: bool = false
static var player_in_shy_room: bool = false
static var player_in_statue_room: bool = false

static func reset_for_generation() -> void:
	player_in_dog_room = false
	player_in_fly_room = false
	player_in_gnome_room = false
	player_in_knight_room = false
	player_in_shambler_room = false
	player_in_shy_room = false
	player_in_statue_room = false

@export var title_text: String = ""
@export var tracked_enemy_group: String = ""

var _player: Node = null
var _room_title_control: Control = null
var _room_title_rtl: RichTextLabel = null
var _room_title_tween: Tween = null
var _title_disabled: bool = false
var _enemies_connected: bool = false
var _enemy_total: int = 0
var _enemy_death_count: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if _title_disabled or tracked_enemy_group.is_empty() or _enemies_connected:
		return
	var enemies := get_tree().get_nodes_in_group(tracked_enemy_group)
	if enemies.is_empty():
		return
	_enemies_connected = true
	set_process(false)
	_enemy_total = enemies.size()
	for enemy in enemies:
		if enemy.has_signal("died"):
			enemy.died.connect(_on_tracked_enemy_died)


func _on_tracked_enemy_died() -> void:
	_enemy_death_count += 1
	if _enemy_death_count >= _enemy_total:
		_title_disabled = true
		if title_text == "Rotten Dog":
			RoomTitleArea.player_in_dog_room = false
		elif title_text == "Carrionfly":
			RoomTitleArea.player_in_fly_room = false
		elif title_text == "Clingers":
			RoomTitleArea.player_in_gnome_room = false
		elif title_text == "The Rusted":
			RoomTitleArea.player_in_knight_room = false
		elif title_text == "The Flayed":
			RoomTitleArea.player_in_shambler_room = false
		elif title_text == "The Mourning":
			RoomTitleArea.player_in_shy_room = false
		elif title_text == "The Patient One":
			RoomTitleArea.player_in_statue_room = false
		_hide_title()


func _hide_title() -> void:
	if _room_title_tween != null:
		_room_title_tween.kill()
		_room_title_tween = null
	if _room_title_control != null and is_instance_valid(_room_title_control):
		_room_title_control.visible = false
	if _room_title_rtl != null and is_instance_valid(_room_title_rtl):
		_room_title_rtl.text = ""


func _find_player_ui() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0]
	_room_title_control = _player.get_node_or_null("CanvasLayer/RoomTitle") as Control
	if _room_title_control != null:
		_room_title_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_title_rtl = _player.get_node_or_null("CanvasLayer/RoomTitle/Label") as RichTextLabel
	if _room_title_rtl != null and _room_title_rtl.custom_effects.is_empty():
		_room_title_rtl.custom_effects = [RichTextRotatingDegrade.new()]


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if _title_disabled:
		return
	if title_text == "Rotten Dog":
		RoomTitleArea.player_in_dog_room = true
	elif title_text == "Carrionfly":
		RoomTitleArea.player_in_fly_room = true
	elif title_text == "Clingers":
		RoomTitleArea.player_in_gnome_room = true
	elif title_text == "The Rusted":
		RoomTitleArea.player_in_knight_room = true
	elif title_text == "The Flayed":
		RoomTitleArea.player_in_shambler_room = true
	elif title_text == "The Mourning":
		RoomTitleArea.player_in_shy_room = true
	elif title_text == "The Patient One":
		RoomTitleArea.player_in_statue_room = true
	_find_player_ui()
	if _room_title_rtl != null and is_instance_valid(_room_title_rtl):
		_room_title_rtl.text = "[rotating_degrade duration=1.5 end=%d start_color=#ffffff end_color=#8888ff]%s[/rotating_degrade]" \
			% [title_text.length(), title_text]
	if _room_title_control != null and is_instance_valid(_room_title_control):
		if _room_title_tween != null:
			_room_title_tween.kill()
		var vh := _room_title_control.get_viewport_rect().size.y
		_room_title_control.offset_top = vh * 0.5 - 100.0
		_room_title_control.offset_bottom = vh * 0.5 - 10.0
		_room_title_control.visible = true
		_room_title_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_room_title_tween.tween_interval(0.5)
		_room_title_tween.tween_property(_room_title_control, "offset_top", 30.0, 0.5)
		_room_title_tween.parallel().tween_property(_room_title_control, "offset_bottom", 120.0, 0.5)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if title_text == "Rotten Dog":
		RoomTitleArea.player_in_dog_room = false
	elif title_text == "Carrionfly":
		RoomTitleArea.player_in_fly_room = false
	elif title_text == "Clingers":
		RoomTitleArea.player_in_gnome_room = false
	elif title_text == "The Rusted":
		RoomTitleArea.player_in_knight_room = false
	elif title_text == "The Flayed":
		RoomTitleArea.player_in_shambler_room = false
	elif title_text == "The Mourning":
		RoomTitleArea.player_in_shy_room = false
	elif title_text == "The Patient One":
		RoomTitleArea.player_in_statue_room = false
	_hide_title()
