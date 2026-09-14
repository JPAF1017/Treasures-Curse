class_name NPCKnockbackComponent
extends RefCounted

const KnockbackShockwaveEffectScript = preload("res://scripts/items/KnockbackShockwaveEffect.gd")

const DEFAULT_KNOCKBACK_DURATION := 0.18
const DEFAULT_UPWARD_RATIO := 0.35
const HEAVY_KNOCKBACK_THRESHOLD := 15.0

var active_time_left: float = 0.0


func begin_knockback(body: CharacterBody3D, direction: Vector3, strength: float, upward_ratio: float = DEFAULT_UPWARD_RATIO, duration: float = DEFAULT_KNOCKBACK_DURATION) -> void:
	if body == null:
		return
	if strength <= 0.0:
		return
	if direction == Vector3.ZERO:
		return

	active_time_left = maxf(duration, 0.0)

	var launch_direction := direction.normalized()
	var new_velocity := body.velocity
	new_velocity.x += launch_direction.x * strength
	new_velocity.z += launch_direction.z * strength
	new_velocity.y = maxf(new_velocity.y, strength * upward_ratio)
	body.velocity = new_velocity

	# Spawn heavy knockback shockwave distortion ring on high-impact strikes
	if strength >= HEAVY_KNOCKBACK_THRESHOLD and body.get_tree() != null:
		var contact_point := body.global_position - (launch_direction * 0.35) + Vector3(0.0, 0.7, 0.0)
		var scale_mult := clampf(strength / 45.0, 0.8, 1.8)
		KnockbackShockwaveEffectScript.spawn(body.get_tree(), contact_point, launch_direction, scale_mult)


static func spawn_shockwave(scene_tree: SceneTree, contact_point: Vector3, direction: Vector3 = Vector3.UP, scale_mult: float = 1.0) -> void:
	KnockbackShockwaveEffectScript.spawn(scene_tree, contact_point, direction, scale_mult)


func update(delta: float) -> bool:
	if active_time_left <= 0.0:
		return false

	active_time_left = maxf(active_time_left - delta, 0.0)
	return active_time_left > 0.0


func is_active() -> bool:
	return active_time_left > 0.0


func clear() -> void:
	active_time_left = 0.0