class_name MeleeItemSharedComponent
extends RefCounted

const DEFAULT_PICKUP_DISTANCE := 3.5
const DEFAULT_EQUIP_ACTION: StringName = &"e"


func get_pickup_max_distance() -> float:
	return DEFAULT_PICKUP_DISTANCE


func get_equip_action_name() -> StringName:
	return DEFAULT_EQUIP_ACTION


func read_equip_input(action_name: StringName, previous_key_down: bool, fallback_key: Key = KEY_E) -> Dictionary:
	if not action_name.is_empty() and InputMap.has_action(action_name):
		return {
			"just_pressed": Input.is_action_just_pressed(action_name),
			"is_down": previous_key_down,
		}

	var is_down := Input.is_physical_key_pressed(fallback_key)
	return {
		"just_pressed": is_down and not previous_key_down,
		"is_down": is_down,
	}


func is_item_node(node: Node, scene_path: String, base_name: String) -> bool:
	if node == null:
		return false

	if node.scene_file_path == scene_path:
		return true

	var lower_name := node.name.to_lower()
	var item_name := base_name.to_lower()
	return lower_name == item_name or lower_name.ends_with(item_name)


func find_item_rigidbody_from_node(node: Node, scene_path: String, base_name: String) -> RigidBody3D:
	var current: Node = node
	while current != null:
		if current is RigidBody3D:
			var body := current as RigidBody3D
			if is_item_node(body, scene_path, base_name):
				return body
		if current is Node3D and is_item_node(current, scene_path, base_name):
			for child in current.get_children():
				if child is RigidBody3D and is_item_node(child, scene_path, base_name):
					return child as RigidBody3D
		current = current.get_parent()
	return null


func set_item_physics_enabled(
	body: RigidBody3D,
	enabled: bool,
	collision_layer_when_enabled: int,
	collision_mask_when_enabled: int,
	mass_value: float,
	linear_damp_value: float,
	angular_damp_value: float,
	collision_shape_node_name: String = "CollisionShape3D"
) -> void:
	body.freeze = not enabled
	body.sleeping = not enabled
	body.can_sleep = true
	body.continuous_cd = enabled
	body.mass = mass_value
	body.linear_damp = linear_damp_value
	body.angular_damp = angular_damp_value
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.collision_layer = 0 if not enabled else collision_layer_when_enabled
	body.collision_mask = 0 if not enabled else collision_mask_when_enabled
	var item_collision := body.get_node_or_null(collision_shape_node_name) as CollisionShape3D
	if item_collision:
		item_collision.disabled = not enabled


func set_visual_children_visible(node: Node, visibility: bool) -> void:
	if node is VisualInstance3D:
		node.visible = visibility
	for child in node.get_children():
		set_visual_children_visible(child, visibility)


func is_wielding_player_on_floor(item_node: Node) -> bool:
	var current := item_node.get_parent()
	while current != null:
		if current is CharacterBody3D:
			return current.is_on_floor()
		current = current.get_parent()
	return false


func is_hurtbox_area(node: Node) -> bool:
	if not (node is Area3D):
		return false

	var area := node as Area3D
	if area.is_in_group("hurtbox"):
		return true

	return area.name.to_lower().contains("hurtbox")


func find_damage_target_from_hurtbox(overlap_node: Node, item_node: Node, player: Node) -> Node:
	if not is_hurtbox_area(overlap_node):
		return null

	var current: Node = overlap_node
	while current != null:
		if current == item_node or current == player:
			return null
		if current.has_method("apply_damage"):
			return current
		current = current.get_parent()

	return null


func collect_hurtbox_damage_targets(attack_area: Area3D, item_node: Node, player: Node, already_hit_targets: Dictionary = {}) -> Array[Node]:
	var targets: Array[Node] = []
	if attack_area == null:
		return targets

	for area in attack_area.get_overlapping_areas():
		var target := find_damage_target_from_hurtbox(area, item_node, player)
		if target == null:
			continue

		var target_id := target.get_instance_id()
		if already_hit_targets.has(target_id):
			continue
		if targets.has(target):
			continue

		targets.append(target)

	return targets


func swing_frame_to_time(frame: int, animation_fps: float) -> float:
	if animation_fps <= 0.0:
		return 0.0
	return max(frame - 1, 0) / animation_fps


func play_sound_at_pos(scene_tree: SceneTree, path: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if scene_tree == null:
		return
	var root := scene_tree.current_scene
	if root == null:
		return
	var audio_player := AudioStreamPlayer3D.new()
	root.add_child(audio_player)
	audio_player.stream = load(path)
	audio_player.global_position = pos
	audio_player.volume_db = volume_db
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()


func check_and_apply_environment_hit(item_node: Node, player: Node, reach: float = 3.0) -> bool:
	if player == null:
		return false
	var camera: Camera3D = player.get("camera") as Camera3D
	if camera == null:
		return false

	var space_state: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	if space_state == null:
		return false

	var origin: Vector3 = camera.global_position
	var target_pos: Vector3 = origin - camera.global_transform.basis.z * reach

	var query := PhysicsRayQueryParameters3D.create(origin, target_pos)
	query.exclude = [player]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1

	var result := space_state.intersect_ray(query)
	if result.has("position"):
		var hit_collider = result.get("collider")
		if hit_collider != null and not hit_collider.has_method("apply_damage") and not hit_collider.is_in_group("player"):
			var hit_pos: Vector3 = result["position"]
			var hit_normal: Vector3 = result["normal"]
			SparksEffect.spawn(player.get_tree(), hit_pos, hit_normal)
			play_sound_at_pos(player.get_tree(), "res://sounds/Interactions/hit_solid.mp3", hit_pos)
			return true
	return false