extends Object

## Static utility component: suppresses NPC aggro while inside an active smoke sphere.
## Call suppress_aggro_if_in_smoke(self) in _physics_process after detection updates
## but before movement decisions. Returns true when smoke suppression is active.

const SmokeEffect = preload("res://scripts/items/smoke_effect.gd")

## Returns true if the NPC is inside any active smoke sphere.
static func is_inside_smoke(npc: Node3D) -> bool:
	for effect in SmokeEffect.active_effects:
		if not is_instance_valid(effect):
			continue
		if npc.global_position.distance_to(effect.global_position) < effect.get_world_radius():
			return true
	return false

## Clears aggro/target state so the NPC wanders. Returns true if suppression applied.
## Handles the common target fields used across all non-juggernaut NPCs generically.
static func suppress_aggro_if_in_smoke(npc: Node3D) -> bool:
	if not is_inside_smoke(npc):
		return false

	# Clear primary target reference (name varies by NPC)
	if "target_player" in npc:
		npc.target_player = null
	if "player" in npc and npc.get("player") is CharacterBody3D:
		npc.player = null

	# Reset LOS and trail memory so re-detection is clean on exit
	if "los_lost_timer" in npc:
		npc.los_lost_timer = 0.0
	if "los_state_initialized" in npc:
		npc.los_state_initialized = false
	if "last_visible_player_position" in npc:
		npc.last_visible_player_position = Vector3.ZERO
	if "last_known_player_position" in npc:
		npc.last_known_player_position = Vector3.ZERO
	if "memorized_target_trail" in npc:
		var trail = npc.get("memorized_target_trail")
		if trail is Array:
			trail.clear()

	# Gnome-specific: chase/grab state flags
	if "is_player_in_detect" in npc:
		npc.is_player_in_detect = false
	if "is_player_in_chase" in npc:
		npc.is_player_in_chase = false
	if "chase_memory_timer" in npc:
		npc.chase_memory_timer = 0.0
	if "attack_range_player" in npc:
		npc.attack_range_player = null
	if "grabbed_player" in npc and npc.get("grabbed_player") != null:
		if npc.has_method("_lock_grabbed_player"):
			npc._lock_grabbed_player(false)
		npc.grabbed_player = null

	# Charger-specific: cancel any active lunge/charge/backup
	if "is_backing_up" in npc:
		npc.is_backing_up = false
	if "is_charging" in npc:
		npc.is_charging = false
	if "is_lunging" in npc:
		npc.is_lunging = false
	if "is_decelerating" in npc:
		npc.is_decelerating = false

	return true
