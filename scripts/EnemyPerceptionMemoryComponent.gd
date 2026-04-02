class_name EnemyPerceptionMemoryComponent
extends RefCounted

static func update_los_trail_state(
	has_line_of_sight: bool,
	state: Dictionary,
	trail: Array[Vector3],
	last_visible_position: Vector3,
	config: Dictionary
) -> Dictionary:
	return NavigationUtils.update_los_trail_state(
		has_line_of_sight,
		bool(state.get("los_state_initialized", false)),
		bool(state.get("previous_has_line_of_sight", false)),
		float(state.get("trail_memory_timer", 0.0)),
		float(state.get("trail_sample_timer", 0.0)),
		trail,
		last_visible_position,
		float(config.get("trail_memory_time", 5.0)),
		float(config.get("trail_point_spacing", 0.7)),
		int(config.get("trail_max_points", 28)),
		float(state.get("los_loss_grace_timer", 0.0)),
		float(config.get("los_loss_grace_time", 0.35)),
		float(config.get("stair_vertical_delta", 1.8)),
		int(config.get("stair_trail_max_points", 14))
	)