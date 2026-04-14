class_name NavigationUtils

const PATH_RAYCAST_DISTANCE := 3.5
const SIDE_PROBE_DISTANCE := 2.5
const SENSE_RAY_HEIGHT := 0.8
const BODY_CLEARANCE_WIDTH := 0.7
const WALL_BUFFER_DISTANCE := 0.55
const MIN_CLEARANCE_SCORE := 0.52
const PATH_POINT_REACHED_DISTANCE := 0.55
const MEMORY_NAV_SNAP_DISTANCE := 6.0
const TRAIL_VERTICAL_FOLLOW_DELTA := 2.2

static func has_line_of_sight_to(
	character: CharacterBody3D,
	target_position: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	excluded_bodies: Array = []
) -> bool:
	var from_pos := character.global_position + Vector3(0, SENSE_RAY_HEIGHT, 0)
	return not raycast_blocked(from_pos, target_position, space_state, excluded_bodies)

static func raycast_blocked(
	from_pos: Vector3,
	to_pos: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	excluded_bodies: Array = []
) -> bool:
	return not raycast_hit(from_pos, to_pos, space_state, excluded_bodies).is_empty()

static func raycast_hit(
	from_pos: Vector3,
	to_pos: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	excluded_bodies: Array = []
) -> Dictionary:
	if space_state == null:
		return {}
	
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = excluded_bodies
	query.collision_mask = 1
	return space_state.intersect_ray(query)

static func _get_direction_right(direction: Vector3) -> Vector3:
	var right := Vector3.UP.cross(direction)
	if right.length_squared() <= 0.001:
		return Vector3.RIGHT
	return right.normalized()

static func _measure_clearance(
	from_pos: Vector3,
	to_pos: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	excluded_bodies: Array
) -> float:
	var result := raycast_hit(from_pos, to_pos, space_state, excluded_bodies)
	if result.is_empty():
		return from_pos.distance_to(to_pos)
	if not result.has("position"):
		return 0.0
	var hit_position: Vector3 = result["position"]
	return from_pos.distance_to(hit_position)

static func _evaluate_direction_clearance(
	character: CharacterBody3D,
	direction: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	distance: float
) -> Dictionary:
	if direction.length_squared() <= 0.001:
		return { "clear": false, "score": 0.0 }

	var start := character.global_position + Vector3(0, SENSE_RAY_HEIGHT, 0)
	var dir := direction.normalized()
	var right := _get_direction_right(dir)
	var excluded := [character]

	var offsets := [0.0, BODY_CLEARANCE_WIDTH, -BODY_CLEARANCE_WIDTH, BODY_CLEARANCE_WIDTH * 1.6, -BODY_CLEARANCE_WIDTH * 1.6]
	var weights := [0.30, 0.25, 0.25, 0.10, 0.10]
	var score := 0.0
	var has_hard_collision := false

	for i in offsets.size():
		var side_offset: float = offsets[i]
		var weight: float = weights[i]
		var ray_start := start + right * side_offset
		var ray_end := ray_start + dir * distance
		var free_distance := _measure_clearance(ray_start, ray_end, space_state, excluded)
		if free_distance <= WALL_BUFFER_DISTANCE:
			has_hard_collision = true
		var normalized := clampf((free_distance - WALL_BUFFER_DISTANCE) / maxf(distance - WALL_BUFFER_DISTANCE, 0.001), 0.0, 1.0)
		score += normalized * weight

	# Extra angled probes reduce corner clipping during wall-following.
	for probe_sign in [-1.0, 1.0]:
		var probe_dir := dir.rotated(Vector3.UP, probe_sign * deg_to_rad(22.0))
		var probe_end := start + probe_dir * minf(distance, SIDE_PROBE_DISTANCE)
		var probe_free_distance := _measure_clearance(start, probe_end, space_state, excluded)
		if probe_free_distance <= WALL_BUFFER_DISTANCE:
			has_hard_collision = true
		var probe_normalized := clampf((probe_free_distance - WALL_BUFFER_DISTANCE) / maxf(minf(distance, SIDE_PROBE_DISTANCE) - WALL_BUFFER_DISTANCE, 0.001), 0.0, 1.0)
		score += probe_normalized * 0.10

	var is_clear := not has_hard_collision and score >= MIN_CLEARANCE_SCORE
	return { "clear": is_clear, "score": score }

static func is_direction_clear(
	character: CharacterBody3D,
	direction: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	distance: float = PATH_RAYCAST_DISTANCE
) -> bool:
	return bool(_evaluate_direction_clearance(character, direction, space_state, distance).get("clear", false))

static func append_trail_point(
	trail: Array[Vector3],
	position: Vector3,
	max_points: int = 25,
	min_spacing: float = 0.7
) -> void:
	if trail.is_empty():
		trail.append(position)
		return

	if trail[trail.size() - 1].distance_to(position) < min_spacing:
		return

	trail.append(position)
	while trail.size() > max_points:
		trail.remove_at(0)

static func get_trail_follow_target(
	from_position: Vector3,
	trail: Array[Vector3],
	reached_distance: float = 0.8,
	max_vertical_delta: float = TRAIL_VERTICAL_FOLLOW_DELTA
) -> Dictionary:
	while not trail.is_empty():
		var next_point := trail[0]
		if absf(next_point.y - from_position.y) > max_vertical_delta:
			trail.remove_at(0)
			continue
		var to_next := next_point - from_position
		to_next.y = 0.0
		if to_next.length() <= reached_distance:
			trail.remove_at(0)
		else:
			break

	if trail.is_empty():
		return { "has_target": false, "target": from_position }

	return { "has_target": true, "target": trail[0] }

static func prune_trail_for_stairs(
	trail: Array[Vector3],
	reference_y: float,
	max_vertical_delta: float = 1.8,
	max_points: int = 14
) -> void:
	if trail.is_empty():
		return

	for i in range(trail.size() - 1, -1, -1):
		if absf(trail[i].y - reference_y) > max_vertical_delta:
			trail.remove_at(i)

	while trail.size() > max_points:
		trail.remove_at(trail.size() - 1)

static func get_cached_path_target(
	from_position: Vector3,
	path_cache: Array[Vector3],
	reached_distance: float = 0.8
) -> Dictionary:
	while not path_cache.is_empty():
		var next_point := path_cache[0]
		var to_next := next_point - from_position
		to_next.y = 0.0
		if to_next.length() <= reached_distance:
			path_cache.remove_at(0)
		else:
			break

	if path_cache.is_empty():
		return { "has_target": false, "target": from_position }

	return { "has_target": true, "target": path_cache[0] }

static func update_los_trail_state(
	has_line_of_sight: bool,
	los_state_initialized: bool,
	previous_has_line_of_sight: bool,
	trail_memory_timer: float,
	trail_sample_timer: float,
	trail: Array[Vector3],
	last_visible_position: Vector3,
	trail_memory_time: float,
	trail_point_spacing: float,
	trail_max_points: int,
	los_loss_grace_timer: float = 0.0,
	los_loss_grace_duration: float = 0.35,
	stair_height_delta_for_prune: float = 1.8,
	stair_prune_max_points: int = 14,
	clear_on_los_regained: bool = true,
	reverse_on_los_lost: bool = true
) -> Dictionary:
	var transition := ""
	if has_line_of_sight:
		los_loss_grace_timer = los_loss_grace_duration
	var effective_has_line_of_sight := has_line_of_sight or los_loss_grace_timer > 0.0

	if not los_state_initialized:
		previous_has_line_of_sight = effective_has_line_of_sight
		los_state_initialized = true
	elif not previous_has_line_of_sight and effective_has_line_of_sight:
		transition = "LOS_REGAINED"
		if clear_on_los_regained:
			trail.clear()
			trail_sample_timer = 0.0
	elif previous_has_line_of_sight and not effective_has_line_of_sight:
		transition = "LOS_LOST"
		trail_memory_timer = trail_memory_time
		trail_sample_timer = 0.0
		if reverse_on_los_lost and trail.size() > 1:
			trail.reverse()
		if trail.is_empty() or trail[0].distance_to(last_visible_position) > trail_point_spacing:
			trail.insert(0, last_visible_position)
		prune_trail_for_stairs(trail, last_visible_position.y, stair_height_delta_for_prune, min(trail_max_points, stair_prune_max_points))
		while trail.size() > trail_max_points:
			trail.remove_at(trail.size() - 1)

	previous_has_line_of_sight = effective_has_line_of_sight
	return {
		"effective_has_line_of_sight": effective_has_line_of_sight,
		"los_state_initialized": los_state_initialized,
		"previous_has_line_of_sight": previous_has_line_of_sight,
		"los_loss_grace_timer": los_loss_grace_timer,
		"trail_memory_timer": trail_memory_timer,
		"trail_sample_timer": trail_sample_timer,
		"transition": transition,
	}

static func snap_position_to_navigation(
	character: CharacterBody3D,
	position: Vector3,
	max_snap_distance: float = MEMORY_NAV_SNAP_DISTANCE
) -> Vector3:
	if character == null:
		return position
	var world := character.get_world_3d()
	if world == null:
		return position
	var nav_map: RID = world.navigation_map
	if not nav_map.is_valid():
		return position
	var snapped_pos := NavigationServer3D.map_get_closest_point(nav_map, position)
	if snapped_pos == Vector3.INF:
		return position
	if snapped_pos.distance_to(position) > max_snap_distance:
		return position
	return snapped_pos

static func build_short_path_cache(
	character: CharacterBody3D,
	target_position: Vector3,
	max_points: int = 10
) -> Array[Vector3]:
	var path := _get_navigation_path(character, target_position)
	var cache: Array[Vector3] = []
	if path.size() <= 1:
		return cache

	for i in range(1, path.size()):
		cache.append(path[i])
		if cache.size() >= max_points:
			break

	return cache

static func _get_navigation_path(character: CharacterBody3D, target_position: Vector3) -> PackedVector3Array:
	if character == null:
		return PackedVector3Array()
	var world := character.get_world_3d()
	if world == null:
		return PackedVector3Array()
	var nav_map: RID = world.navigation_map
	if not nav_map.is_valid():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(nav_map, character.global_position, target_position, true)

static func _get_path_follow_direction(character: CharacterBody3D, path: PackedVector3Array) -> Vector3:
	if character == null or path.size() == 0:
		return Vector3.ZERO

	var closest_index := 0
	var closest_distance_sq := INF
	for i in path.size():
		var d2 := character.global_position.distance_squared_to(path[i])
		if d2 < closest_distance_sq:
			closest_distance_sq = d2
			closest_index = i

	for i in range(closest_index, path.size()):
		var to_point := path[i] - character.global_position
		to_point.y = 0.0
		if to_point.length() > PATH_POINT_REACHED_DISTANCE:
			return to_point.normalized()

	return Vector3.ZERO

static func find_path_direction_to_target(
	character: CharacterBody3D,
	target_position: Vector3,
	_space_state: PhysicsDirectSpaceState3D,
	wall_follow_mode: int = 0
) -> Dictionary:
	if character == null:
		return { "direction": Vector3.ZERO, "wall_follow_mode": wall_follow_mode }

	var to_target := target_position - character.global_position
	to_target.y = 0.0
	if to_target.length() <= PATH_POINT_REACHED_DISTANCE:
		return { "direction": Vector3.ZERO, "wall_follow_mode": 0 }

	var path := _get_navigation_path(character, target_position)
	var desired_direction := _get_path_follow_direction(character, path)

	if desired_direction.length_squared() <= 0.001:
		desired_direction = target_position - character.global_position
		desired_direction.y = 0.0
		if desired_direction.length_squared() <= 0.001:
			return { "direction": Vector3.ZERO, "wall_follow_mode": wall_follow_mode }
		desired_direction = desired_direction.normalized()

	return { "direction": desired_direction, "wall_follow_mode": 0 }

static func find_path_direction(
	character: CharacterBody3D,
	target_direction: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	wall_follow_mode: int = 0
) -> Dictionary:
	target_direction.y = 0.0
	if target_direction.length_squared() <= 0.001:
		return { "direction": Vector3.ZERO, "wall_follow_mode": wall_follow_mode }
	
	target_direction = target_direction.normalized()

	var direct_eval := _evaluate_direction_clearance(character, target_direction, space_state, PATH_RAYCAST_DISTANCE)
	if bool(direct_eval.get("clear", false)):
		return { "direction": target_direction, "wall_follow_mode": 0 }

	var angles_to_try := [12.0, -12.0, 20.0, -20.0, 32.0, -32.0, 45.0, -45.0, 60.0, -60.0, 80.0, -80.0, 105.0, -105.0, 130.0, -130.0, 150.0, -150.0]
	var best_direction := Vector3.ZERO
	var best_score := -999.0
	var best_backup_direction := Vector3.ZERO
	var best_backup_score := -999.0
	var new_wall_follow_mode := wall_follow_mode

	for angle_deg in angles_to_try:
		var angle_rad := deg_to_rad(angle_deg)
		var test_direction := target_direction.rotated(Vector3.UP, angle_rad)
		var eval := _evaluate_direction_clearance(character, test_direction, space_state, SIDE_PROBE_DISTANCE)
		var clearance_score := float(eval.get("score", 0.0))
		var score := test_direction.dot(target_direction) * 0.8 + clearance_score * 1.4
		if wall_follow_mode != 0 and signf(angle_deg) == float(wall_follow_mode):
			score += 0.12

		if score > best_backup_score:
			best_backup_score = score
			best_backup_direction = test_direction

		if bool(eval.get("clear", false)) and score > best_score:
			best_score = score
			best_direction = test_direction
			if angle_deg > 0.0:
				new_wall_follow_mode = 1
			elif angle_deg < 0.0:
				new_wall_follow_mode = -1

	if best_direction == Vector3.ZERO and best_backup_direction != Vector3.ZERO:
		best_direction = best_backup_direction

	return { "direction": best_direction, "wall_follow_mode": new_wall_follow_mode }
