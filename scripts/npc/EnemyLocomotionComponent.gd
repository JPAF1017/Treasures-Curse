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
	var pushed_bodies: Array[RigidBody3D] = []
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is RigidBody3D:
			var rigid := collider as RigidBody3D
			if rigid.freeze or rigid in pushed_bodies:
				continue
			pushed_bodies.append(rigid)
			if rigid.sleeping:
				rigid.sleeping = false

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

			var mass := maxf(rigid.mass, 0.1)
			var char_speed := Vector3(body.velocity.x, 0.0, body.velocity.z).length()
			var target_speed := clampf(maxf(char_speed, push_force), 1.5, 4.5)
			var current_speed := rigid.linear_velocity.dot(push_dir)
			if current_speed < target_speed:
				var needed_speed := target_speed - maxf(current_speed, 0.0)
				var impulse_magnitude := clampf(needed_speed * mass, 0.01, 2.0)
				rigid.apply_central_impulse(push_dir * impulse_magnitude)
			if rigid.linear_velocity.length_squared() > 36.0:
				rigid.linear_velocity = rigid.linear_velocity.limit_length(6.0)

