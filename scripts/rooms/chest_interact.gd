extends Node3D

const RAYCAST_DISTANCE := 5.0
const LID_OPEN_DEGREES := -90.0
const LID_OPEN_DURATION := 1.0

@onready var chest_area: Area3D = $Chest/Area3D
@onready var chest_lid: Node3D = $Chest/Cube_085

var _player: Node = null
var _interact_control: Control = null
var _is_opened: bool = false
var _is_hovered: bool = false


func _process(_delta: float) -> void:
	_find_player_if_needed()
	if _player == null:
		return
	_update_interact_prompt()
	if _is_hovered and not _is_opened \
			and Input.is_action_just_pressed("e"):
		_open_chest()


func _find_player_if_needed() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0]
	_interact_control = _player.get_node_or_null(
		"CanvasLayer/Control/Interact"
	) as Control


func _get_player_camera() -> Camera3D:
	if _player == null:
		return null
	return _player.get("camera") as Camera3D


func _update_interact_prompt() -> void:
	if _is_opened:
		_set_interact_visible(false)
		_is_hovered = false
		return

	var cam := _get_player_camera()
	if cam == null:
		_set_interact_visible(false)
		_is_hovered = false
		return

	var origin := cam.global_position
	var forward := -cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + forward * RAYCAST_DISTANCE
	)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [_player]
	var result := get_world_3d().direct_space_state.intersect_ray(
		query
	)

	var aimed := false
	if not result.is_empty():
		var collider: Object = result.get("collider")
		if collider == chest_area:
			aimed = true

	_is_hovered = aimed
	_set_interact_visible(aimed)


func _set_interact_visible(visible_state: bool) -> void:
	if _interact_control and is_instance_valid(_interact_control):
		_interact_control.visible = visible_state


func _open_chest() -> void:
	_is_opened = true
	_set_interact_visible(false)
	_is_hovered = false

	if chest_lid == null:
		return

	var tween := create_tween()
	tween.tween_property(
		chest_lid, "rotation:x",
		deg_to_rad(LID_OPEN_DEGREES), LID_OPEN_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
