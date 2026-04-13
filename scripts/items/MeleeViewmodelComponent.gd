class_name MeleeViewmodelComponent
extends RefCounted

var _model_scene: PackedScene
var _viewmodel_name: String
var _instance: Node3D = null
var _bob_time: float = 0.0

var bob_freq: float = 2.0
var bob_amp_y: float = 0.012
var bob_amp_x: float = 0.006

var shaking: bool = false
var _shake_time: float = 0.0
const SHAKE_SPEED := 45.0
const SHAKE_INTENSITY := 0.006


func _init(model_scene: PackedScene, viewmodel_name: String) -> void:
	_model_scene = model_scene
	_viewmodel_name = viewmodel_name


func show(player: Node, vm_position: Vector3, vm_rotation_degrees: Vector3, vm_scale: float) -> void:
	if _instance and is_instance_valid(_instance):
		_instance.visible = true
		_apply_transform(vm_position, vm_rotation_degrees, vm_scale)
		return

	var camera := _get_player_camera(player)
	if camera == null:
		return

	_instance = _model_scene.instantiate() as Node3D
	_instance.name = _viewmodel_name
	camera.add_child(_instance)
	_apply_transform(vm_position, vm_rotation_degrees, vm_scale)


func _apply_transform(vm_position: Vector3, vm_rotation_degrees: Vector3, vm_scale: float) -> void:
	_instance.position = vm_position
	_instance.rotation = Vector3(
		deg_to_rad(vm_rotation_degrees.x),
		deg_to_rad(vm_rotation_degrees.y),
		deg_to_rad(vm_rotation_degrees.z)
	)
	_instance.scale = Vector3.ONE * vm_scale


func hide() -> void:
	if _instance and is_instance_valid(_instance):
		_instance.queue_free()
		_instance = null
	_bob_time = 0.0


func update_bob(player: Node, delta: float, base_position: Vector3) -> void:
	if _instance == null or not is_instance_valid(_instance):
		return

	var player_body := player as CharacterBody3D
	if player_body == null:
		return

	var speed := player_body.velocity.length()
	var on_floor: bool = player_body.is_on_floor()

	if speed > 0.5 and on_floor:
		_bob_time += delta * speed
	else:
		_bob_time = lerpf(_bob_time, 0.0, delta * 5.0)

	var bob_y := sin(_bob_time * bob_freq) * bob_amp_y
	var bob_x := cos(_bob_time * bob_freq * 0.5) * bob_amp_x
	var offset := Vector3(bob_x, bob_y, 0.0)

	if shaking:
		_shake_time += delta * SHAKE_SPEED
		offset.x += sin(_shake_time * 7.3) * SHAKE_INTENSITY
		offset.y += cos(_shake_time * 11.1) * SHAKE_INTENSITY * 0.7
	else:
		_shake_time = 0.0

	_instance.position = base_position + offset


func is_active() -> bool:
	return _instance != null and is_instance_valid(_instance)


static func set_visual_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		set_visual_layer_recursive(child, layer)


func _get_player_camera(player: Node) -> Camera3D:
	if player == null:
		return null
	return player.get("camera") as Camera3D
