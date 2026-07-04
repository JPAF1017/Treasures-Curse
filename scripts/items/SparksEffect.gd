class_name SparksEffect
extends RefCounted

## Environmental sparks visual effect using simple sphere meshes.
## Spawns small bright yellow/orange/white spheres that burst outward from a hit surface,
## deflected along the surface normal, then fall with gravity and fade out.

# ── Configuration ──────────────────────────────────────────────────────────────
const PARTICLE_COUNT_MIN := 8
const PARTICLE_COUNT_MAX := 16
const PARTICLE_RADIUS_MIN := 0.03
const PARTICLE_RADIUS_MAX := 0.08
const BURST_SPEED_MIN := 1.5
const BURST_SPEED_MAX := 5.0
const GRAVITY := 12.0 # sparks fall slightly faster
const LIFETIME := 0.4 # shorter lifetime than blood
const FADE_START_RATIO := 0.2

# Bright spark colors
const SPARK_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0, 1.0),  # white-hot
	Color(1.0, 0.9, 0.2, 1.0),  # bright yellow
	Color(1.0, 0.6, 0.05, 1.0), # intense orange
	Color(1.0, 0.35, 0.0, 1.0), # reddish orange
]


## Spawn a burst of sparks at the given world position, directing them outwards from the surface normal.
static func spawn(scene_tree: SceneTree, world_position: Vector3, surface_normal: Vector3 = Vector3.UP) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var count := randi_range(PARTICLE_COUNT_MIN, PARTICLE_COUNT_MAX)
	for i in count:
		_spawn_single_particle(root, scene_tree, world_position, surface_normal)


# ── Internal helpers ───────────────────────────────────────────────────────────

static func _spawn_single_particle(root: Node, scene_tree: SceneTree, origin: Vector3, normal: Vector3) -> void:
	# Create MeshInstance3D with a tiny SphereMesh
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SparkParticle"

	var sphere := SphereMesh.new()
	var radius := randf_range(PARTICLE_RADIUS_MIN, PARTICLE_RADIUS_MAX)
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 4
	sphere.rings = 2
	mesh_instance.mesh = sphere

	# Assign an unshaded material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SPARK_COLORS[randi() % SPARK_COLORS.size()]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = mat

	root.add_child(mesh_instance)
	mesh_instance.global_position = origin

	# Calculate initial velocity: burst directed outwards from the normal
	# Create a random tangent direction vector
	var random_offset := Vector3(
		randf_range(-0.8, 0.8),
		randf_range(-0.8, 0.8),
		randf_range(-0.8, 0.8)
	)
	
	# Combine normal direction with some random spread
	var direction := (normal + random_offset).normalized()
	
	var speed := randf_range(BURST_SPEED_MIN, BURST_SPEED_MAX)
	var velocity := direction * speed

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
			dt = 0.016

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

		# Scale down
		var scale_factor := lerpf(1.0, 0.1, life_ratio)
		particle.scale = Vector3.ONE * scale_factor

		await scene_tree.process_frame

	if is_instance_valid(particle):
		particle.queue_free()
