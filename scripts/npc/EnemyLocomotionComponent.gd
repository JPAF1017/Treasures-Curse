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

static func push_rigid_bodies(body: CharacterBody3D, push_force: float = 2.0) -> void:
	if body == null or not is_instance_valid(body):
		return
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is RigidBody3D:
			var rigid := collider as RigidBody3D
			if rigid.freeze:
				continue
			var normal := collision.get_normal()
			var push_dir := Vector3(-normal.x, 0.0, -normal.z)
			if push_dir.length_squared() > 0.001:
				push_dir = push_dir.normalized()
			else:
				var horiz_vel := Vector3(body.velocity.x, 0.0, body.velocity.z)
				if horiz_vel.length_squared() > 0.001:
					push_dir = horiz_vel.normalized()
				else:
					continue
			
			var mass := rigid.mass if rigid.mass > 0.0 else 0.1
			var impulse_magnitude := clampf(push_force * mass, 0.1, 10.0)
			rigid.apply_central_impulse(push_dir * impulse_magnitude)
