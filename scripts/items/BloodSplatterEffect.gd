class_name BloodSplatterEffect
extends RefCounted

## Blood splatter visual effect using simple sphere meshes.
## Spawns small dark-red spheres that burst outward from the target's position
## on hit, then fall with gravity and fade out.

# ── Configuration ──────────────────────────────────────────────────────────────
const PARTICLE_COUNT_MIN := 30
const PARTICLE_COUNT_MAX := 45
const PARTICLE_RADIUS_MIN := 0.03
const PARTICLE_RADIUS_MAX := 0.08
const BURST_SPEED_MIN := 1.5
const BURST_SPEED_MAX := 4.5
const UPWARD_BIAS := 1.5
const GRAVITY := 9.8
const LIFETIME := 0.6
const FADE_START_RATIO := 0.4  # start fading at 40% of lifetime

# Dark blood-red colour palette (randomised per particle for variety).
const BLOOD_COLORS: Array[Color] = [
	Color(0.45, 0.02, 0.02, 1.0),  # deep crimson
	Color(0.55, 0.04, 0.04, 1.0),  # dark red
	Color(0.35, 0.0, 0.0, 1.0),    # near-black red
	Color(0.5, 0.06, 0.02, 1.0),   # brownish red
]


## Spawn a burst of blood-sphere particles at the given world position.
## Call this from the weapon's _apply_attack_damage after confirming a hit.
## [param scene_tree] – the SceneTree (get_tree())
## [param world_position] – the 3D impact point (usually the NPC's global_position + offset)
## [param hit_direction] – normalised direction FROM the attacker TO the target (used to bias the burst)
static func spawn(scene_tree: SceneTree, world_position: Vector3, hit_direction: Vector3 = Vector3.ZERO) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var count := randi_range(PARTICLE_COUNT_MIN, PARTICLE_COUNT_MAX)
	for i in count:
		_spawn_single_particle(root, scene_tree, world_position, hit_direction)


# ── Internal helpers ───────────────────────────────────────────────────────────

static func _spawn_single_particle(root: Node, scene_tree: SceneTree, origin: Vector3, hit_dir: Vector3) -> void:
	# Create MeshInstance3D with a tiny SphereMesh
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "BloodParticle"

	var sphere := SphereMesh.new()
	var radius := randf_range(PARTICLE_RADIUS_MIN, PARTICLE_RADIUS_MAX)
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	mesh_instance.mesh = sphere

	# Assign a simple unshaded material with a random blood colour
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLOOD_COLORS[randi() % BLOOD_COLORS.size()]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = mat

	# Offset origin slightly upward to roughly centre-mass height
	var spawn_pos := origin + Vector3(0.0, randf_range(0.6, 1.2), 0.0)
	mesh_instance.global_position = spawn_pos if root.is_inside_tree() else spawn_pos
	root.add_child(mesh_instance)
	mesh_instance.global_position = spawn_pos

	# Calculate an initial velocity: random burst + bias towards hit direction
	var random_dir := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(0.2, 1.0),  # bias upward
		randf_range(-1.0, 1.0)
	).normalized()

	if hit_dir.length_squared() > 0.001:
		random_dir = (random_dir + hit_dir.normalized() * 0.6).normalized()

	random_dir.y += UPWARD_BIAS * randf_range(0.3, 1.0)
	var speed := randf_range(BURST_SPEED_MIN, BURST_SPEED_MAX)
	var velocity := random_dir * speed

	# Animate the particle with physics-like motion via a coroutine
	_animate_particle(scene_tree, mesh_instance, mat, velocity)


static func _animate_particle(scene_tree: SceneTree, particle: MeshInstance3D, mat: StandardMaterial3D, velocity: Vector3) -> void:
	var elapsed := 0.0
	var pos := particle.global_position
	var vel := velocity
	var base_alpha := mat.albedo_color.a

	while elapsed < LIFETIME:
		if not is_instance_valid(particle):
			return

		var dt := scene_tree.root.get_process_delta_time()
		if dt <= 0.0:
			dt = 0.016  # fallback ~60fps

		# Physics step
		vel.y -= GRAVITY * dt
		pos += vel * dt
		particle.global_position = pos

		# Fade out
		elapsed += dt
		var life_ratio := elapsed / LIFETIME
		if life_ratio > FADE_START_RATIO:
			var fade_progress := (life_ratio - FADE_START_RATIO) / (1.0 - FADE_START_RATIO)
			var col := mat.albedo_color
			col.a = base_alpha * (1.0 - fade_progress)
			mat.albedo_color = col

		# Scale down slightly as it fades
		var scale_factor := lerpf(1.0, 0.3, life_ratio)
		particle.scale = Vector3.ONE * scale_factor

		await scene_tree.process_frame

	# Clean up
	if is_instance_valid(particle):
		particle.queue_free()
