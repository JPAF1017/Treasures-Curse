extends Node3D

## Dissolve range: -1.0 = fully hidden, 1.0 = fully visible
const DISSOLVE_IN_SPEED := 1
const DISSOLVE_OUT_SPEED := 1.2
const DISSOLVE_MIN := -1.0
const DISSOLVE_MAX := 1.0
const LINGER_DURATION := 10.0

static var active_effects: Array = []

var _inner_material: ShaderMaterial = null
var _outer_material: ShaderMaterial = null
var _dissolve: float = DISSOLVE_MIN
var _state: int = 0  # 0=idle, 1=expanding, 2=lingering, 3=collapsing
var _linger_timer: float = 0.0


func _ready() -> void:
	var inner := get_node_or_null("InnerSphere") as MeshInstance3D
	if inner:
		_inner_material = inner.material_override as ShaderMaterial
	var outer := get_node_or_null("OuterSphere") as MeshInstance3D
	if outer:
		_outer_material = outer.material_override as ShaderMaterial
	_set_dissolve(DISSOLVE_MIN)
	visible = false


func _process(delta: float) -> void:
	match _state:
		1:  # Expanding
			_dissolve = minf(_dissolve + DISSOLVE_IN_SPEED * delta, DISSOLVE_MAX)
			_set_dissolve(_dissolve)
			if _dissolve >= DISSOLVE_MAX:
				_state = 2
				_linger_timer = LINGER_DURATION
		2:  # Lingering
			_linger_timer -= delta
			if _linger_timer <= 0.0:
				_state = 3
		3:  # Collapsing
			_dissolve = maxf(_dissolve - DISSOLVE_OUT_SPEED * delta, DISSOLVE_MIN)
			_set_dissolve(_dissolve)
			if _dissolve <= DISSOLVE_MIN:
				_state = 0
				visible = false
				queue_free()


func activate() -> void:
	_dissolve = DISSOLVE_MIN
	_set_dissolve(_dissolve)
	visible = true
	_state = 1
	if not active_effects.has(self):
		active_effects.append(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		active_effects.erase(self)


func get_world_radius() -> float:
	return scale.x  # sphere mesh radius=1, so world radius = scale.x


func _set_dissolve(value: float) -> void:
	if _inner_material:
		_inner_material.set_shader_parameter("dissolve", value)
	if _outer_material:
		_outer_material.set_shader_parameter("dissolve", value)
