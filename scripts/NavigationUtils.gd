class_name NavigationUtils

const PATH_RAYCAST_DISTANCE := 3.5
const SIDE_PROBE_DISTANCE := 2.5
const SENSE_RAY_HEIGHT := 0.8

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
	if space_state == null:
		return false
	
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = excluded_bodies
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)
	return not result.is_empty()

static func is_direction_clear(
	character: CharacterBody3D,
	direction: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	distance: float = PATH_RAYCAST_DISTANCE
) -> bool:
	if direction.length_squared() <= 0.001:
		return false
	var start := character.global_position + Vector3(0, SENSE_RAY_HEIGHT, 0)
	var end := start + direction.normalized() * distance
	return not raycast_blocked(start, end, space_state, [character])

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

	if is_direction_clear(character, target_direction, space_state):
		return { "direction": target_direction, "wall_follow_mode": 0 }

	var angles_to_try := [20.0, -20.0, 35.0, -35.0, 50.0, -50.0, 70.0, -70.0, 90.0, -90.0, 120.0, -120.0, 145.0, -145.0]
	var best_direction := Vector3.ZERO
	var best_score := -999.0
	var new_wall_follow_mode := wall_follow_mode

	for angle_deg in angles_to_try:
		var angle_rad := deg_to_rad(angle_deg)
		var test_direction := target_direction.rotated(Vector3.UP, angle_rad)
		if is_direction_clear(character, test_direction, space_state, SIDE_PROBE_DISTANCE):
			var score := test_direction.dot(target_direction)
			if wall_follow_mode != 0 and signf(angle_deg) == float(wall_follow_mode):
				score += 0.2
			if score > best_score:
				best_score = score
				best_direction = test_direction
				if angle_deg > 0.0:
					new_wall_follow_mode = 1
				elif angle_deg < 0.0:
					new_wall_follow_mode = -1

	return { "direction": best_direction, "wall_follow_mode": new_wall_follow_mode }
