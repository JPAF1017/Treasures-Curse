class_name EnemyDeathLingerComponent
extends RefCounted

static func run_death_linger(
	body: CharacterBody3D,
	animation_player: AnimationPlayer,
	linger_seconds: float,
	monitored_areas: Array[Area3D] = [],
	death_animation_candidates: Array[StringName] = [&"death", &"die"]
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

	var wait_time := maxf(linger_seconds, 0.0)
	if wait_time > 0.0 and body.get_tree() != null:
		await body.get_tree().create_timer(wait_time).timeout

	if is_instance_valid(body):
		body.queue_free()

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
