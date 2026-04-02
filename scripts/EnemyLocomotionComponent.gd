class_name EnemyLocomotionComponent
extends RefCounted

static func apply_gravity(body: CharacterBody3D, gravity: float, delta: float) -> void:
	if body.is_on_floor():
		body.velocity.y = 0.0
	else:
		body.velocity.y -= gravity * delta

static func try_bump_step(
	body: CharacterBody3D,
	bump_step_timer: float,
	bump_step_velocity: float,
	bump_step_cooldown: float,
	horizontal_speed_threshold: float = 0.2
) -> float:
	var horizontal_speed := Vector2(body.velocity.x, body.velocity.z).length()
	if horizontal_speed > horizontal_speed_threshold and body.is_on_floor() and body.is_on_wall() and body.velocity.y <= 0.0 and bump_step_timer <= 0.0:
		body.velocity.y = bump_step_velocity
		return bump_step_cooldown

	return bump_step_timer