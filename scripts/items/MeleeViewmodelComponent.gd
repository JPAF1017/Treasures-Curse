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

var _swing_active: bool = false
var _swing_time: float = 0.0
var _swing_type: int = 0  # cycles through 0, 1, 2
var _swing_counter: int = 0  # tracks which swing to use next

# ── Base rotation (set via _apply_transform, remembered for additive blending) ──
var _base_rotation: Vector3 = Vector3.ZERO

# ── Swing timing ──
const SWING_DURATION := 0.18          # fast forward strike
const SWING_RETURN_DURATION := 0.55   # slower recovery

# ── Swing type definitions ──
# Each swing is defined by a dictionary containing:
#   "pos_start"  – position offset at the beginning of the swing (wind-up)
#   "pos_peak"   – position offset at the peak of the swing (impact)
#   "rot_start"  – rotation offset (degrees) at the beginning of the swing
#   "rot_peak"   – rotation offset (degrees) at the peak of the swing

# Swing 0: Right-to-left horizontal slash
static var swing_0: Dictionary = {
	"pos_start": Vector3(0.15, 0.05, 0.0),
	"pos_peak":  Vector3(-0.25, -0.02, -0.05),
	"rot_start": Vector3(0.0, -25.0, -20.0),
	"rot_peak":  Vector3(-10.0, 35.0, 30.0),
	"twist_angle": 90.0,
}

# Swing 1: Diagonal downward slash (upper-left to lower-right)
static var swing_1: Dictionary = {
	"pos_start": Vector3(-0.15, 0.12, 0.0),
	"pos_peak":  Vector3(0.2, -0.15, -0.05),
	"rot_start": Vector3(15.0, 25.0, 25.0),
	"rot_peak":  Vector3(-30.0, -30.0, -20.0),
	"twist_angle": -45.0,
}

# Swing 2: Overhead downward chop
static var swing_2: Dictionary = {
	"pos_start": Vector3(0.0, 0.15, 0.02),
	"pos_peak":  Vector3(0.0, -0.15, -0.08),
	"rot_start": Vector3(35.0, 0.0, 0.0),
	"rot_peak":  Vector3(-90.0, 0.0, 5.0),
	"twist_angle": 0.0,
}


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
	_base_rotation = Vector3(
		deg_to_rad(vm_rotation_degrees.x),
		deg_to_rad(vm_rotation_degrees.y),
		deg_to_rad(vm_rotation_degrees.z)
	)
	_instance.position = vm_position
	_instance.rotation = _base_rotation
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

	# ── Apply swing animation ──
	var swing_pos_offset := Vector3.ZERO
	var swing_rot_offset := Vector3.ZERO
	var twist_angle := 0.0

	if _swing_active:
		_swing_time += delta
		var forward_time := SWING_DURATION
		var swing_data := _get_swing_data(_swing_type)
		var target_twist := deg_to_rad(swing_data.get("twist_angle", 0.0))

		if _swing_time < forward_time:
			# Forward phase: ease-out for snappy attack feel
			var t := _swing_time / forward_time
			var eased_t := _ease_out_cubic(t)

			swing_pos_offset = swing_data["pos_start"].lerp(swing_data["pos_peak"], eased_t)
			swing_rot_offset = _lerp_v3_deg(swing_data["rot_start"], swing_data["rot_peak"], eased_t)
			twist_angle = lerpf(0.0, target_twist, eased_t)
		else:
			# Return phase: ease-in-out for smooth recovery
			var return_t := clampf((_swing_time - forward_time) / SWING_RETURN_DURATION, 0.0, 1.0)
			var eased_return := _ease_in_out_cubic(return_t)

			swing_pos_offset = swing_data["pos_peak"].lerp(Vector3.ZERO, eased_return)
			swing_rot_offset = _lerp_v3_deg(swing_data["rot_peak"], Vector3.ZERO, eased_return)
			twist_angle = lerpf(target_twist, 0.0, eased_return)

			if return_t >= 1.0:
				_swing_active = false

	_instance.position = base_position + offset + swing_pos_offset
	_instance.rotation = _base_rotation + Vector3(
		deg_to_rad(swing_rot_offset.x),
		deg_to_rad(swing_rot_offset.y),
		deg_to_rad(swing_rot_offset.z)
	)
	if twist_angle != 0.0:
		_instance.rotate_object_local(Vector3.UP, twist_angle)


func start_swing() -> void:
	_swing_active = true
	_swing_time = 0.0
	_swing_type = _swing_counter % 3
	_swing_counter += 1


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


# ── Helpers ──

func _get_swing_data(swing_type: int) -> Dictionary:
	match swing_type:
		0: return swing_0
		1: return swing_1
		2: return swing_2
		_: return swing_0


static func _ease_out_cubic(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv


static func _ease_in_out_cubic(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	else:
		var inv := -2.0 * t + 2.0
		return 1.0 - inv * inv * inv / 2.0


static func _lerp_v3_deg(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(
		lerpf(a.x, b.x, t),
		lerpf(a.y, b.y, t),
		lerpf(a.z, b.z, t)
	)
