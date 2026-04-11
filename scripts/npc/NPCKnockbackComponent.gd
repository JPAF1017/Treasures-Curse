class_name NPCKnockbackComponent
extends RefCounted

const DEFAULT_KNOCKBACK_DURATION := 0.18
const DEFAULT_UPWARD_RATIO := 0.35

var active_time_left: float = 0.0


func begin_knockback(body: CharacterBody3D, direction: Vector3, strength: float, upward_ratio: float = DEFAULT_UPWARD_RATIO, duration: float = DEFAULT_KNOCKBACK_DURATION) -> void:
	if body == null:
		return
	if strength <= 0.0:
		return
	if direction == Vector3.ZERO:
		return

	active_time_left = maxf(duration, 0.0)

	var launch_direction := direction.normalized()
	var new_velocity := body.velocity
	new_velocity.x += launch_direction.x * strength
	new_velocity.z += launch_direction.z * strength
	new_velocity.y = maxf(new_velocity.y, strength * upward_ratio)
	body.velocity = new_velocity


func update(delta: float) -> bool:
	if active_time_left <= 0.0:
		return false

	active_time_left = maxf(active_time_left - delta, 0.0)
	return active_time_left > 0.0


func is_active() -> bool:
	return active_time_left > 0.0


func clear() -> void:
	active_time_left = 0.0