class_name EnemyDeathLingerComponent
extends RefCounted

const EnemyDissolutionEffectScript = preload("res://scripts/items/EnemyDissolutionEffect.gd")

static func run_death_linger(
	body: CharacterBody3D,
	animation_player: AnimationPlayer,
	linger_seconds: float,
	monitored_areas: Array[Area3D] = [],
	death_animation_candidates: Array[StringName] = [&"death", &"die"],
	custom_center_offset: Vector3 = Vector3.ZERO,
	custom_scale_multiplier: float = 1.0
) -> void:
	if body == null or not is_instance_valid(body):
		return

	for area in monitored_areas:
		if area:
			area.monitoring = false

	_disable_collisions_recursive(body)
	_play_death_animation(animation_player, death_animation_candidates)
	body.set_process(false)
	body.set_physics_process(false)

	# Calculate enemy center and scale for dissolution FX
	var center_offset := custom_center_offset
	var scale_mult := custom_scale_multiplier
	if center_offset == Vector3.ZERO:
		center_offset = _estimate_center_offset(body)
	if is_equal_approx(scale_mult, 1.0):
		scale_mult = _estimate_scale_multiplier(body)

	var origin: Vector3 = body.global_position + (body.global_transform.basis * center_offset)

	# 1. Trigger initial defeat burst: dark cursed shadow miasma & soul embers
	if body.get_tree() != null:
		EnemyDissolutionEffectScript.spawn(body.get_tree(), origin, scale_mult)

	# 2. Attach dissolution wisps and mesh fadeout over linger duration
	var wait_time := maxf(linger_seconds, 0.0)
	if wait_time > 0.0:
		EnemyDissolutionEffectScript.attach_dissolution_linger(body, center_offset, wait_time)
		if body.get_tree() != null:
			await body.get_tree().create_timer(wait_time).timeout

	if is_instance_valid(body):
		# Final soft soul dissipation puff upon complete dissolution
		if body.get_tree() != null:
			EnemyDissolutionEffectScript.spawn(body.get_tree(), body.global_position + center_offset, scale_mult * 0.6)
		body.queue_free()

static func _estimate_center_offset(body: CharacterBody3D) -> Vector3:
	var col_shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape and col_shape.position != Vector3.ZERO:
		return col_shape.position
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).position != Vector3.ZERO:
			return (child as CollisionShape3D).position
	return Vector3(0.0, 0.8, 0.0)

static func _estimate_scale_multiplier(body: CharacterBody3D) -> float:
	var col_shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape == null:
		for child in body.get_children():
			if child is CollisionShape3D:
				col_shape = child as CollisionShape3D
				break
	if col_shape and col_shape.shape:
		if col_shape.shape is BoxShape3D:
			return clampf((col_shape.shape as BoxShape3D).size.y * 0.5, 0.6, 2.5)
		elif col_shape.shape is CapsuleShape3D:
			return clampf((col_shape.shape as CapsuleShape3D).height * 0.5, 0.6, 2.5)
		elif col_shape.shape is SphereShape3D:
			return clampf((col_shape.shape as SphereShape3D).radius * 1.5, 0.6, 2.5)
	return 1.0

static func _play_death_animation(animation_player: AnimationPlayer, candidates: Array[StringName]) -> void:
	if animation_player == null:
		return

	for animation_name in candidates:
		if animation_player.has_animation(animation_name):
			animation_player.speed_scale = 1.0
			animation_player.play(animation_name)
			return

static func _disable_collisions_recursive(node: Node) -> void:
	if node is PhysicsBody3D:
		(node as PhysicsBody3D).collision_layer = 0
		(node as PhysicsBody3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true

	for child in node.get_children():
		_disable_collisions_recursive(child)
