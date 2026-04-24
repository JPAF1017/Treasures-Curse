extends Node3D

const CHARGER_SCENE := preload("res://entities/charger.tscn")
const FLY_SCENE     := preload("res://entities/fly.tscn")
const SHAMBLER_SCENE := preload("res://entities/shambler.tscn")
const GNOME_SCENE   := preload("res://entities/gnome.tscn")
const STATUE_SCENE  := preload("res://entities/statue.tscn")
const SHY_SCENE     := preload("res://entities/shy.tscn")

const CHARGER_COUNT  := 5
const FLY_COUNT      := 5
const SHAMBLER_COUNT := 3
const GNOME_GROUPS   := 3  # each group spawns 2 or 3 gnomes in the same room
# Floors (0-based index) where statues and shy spawn (one per floor)
const STATUE_FLOORS  := [1, 3]
const SHY_FLOORS     := [1, 3]


func _ready() -> void:
	var generator := _find_dungeon_generator(self)
	if generator:
		generator.done_generating.connect(_on_dungeon_ready.bind(generator))


func _find_dungeon_generator(node: Node) -> Node:
	for child in node.get_children():
		if child.has_signal("done_generating"):
			return child
		var result := _find_dungeon_generator(child)
		if result:
			return result
	return null


func _on_dungeon_ready(generator: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Collect all placed rooms, skip the StartRoom so enemies don't spawn on the player
	var all_rooms: Array = generator.find_children("*", "DungeonRoom3D", true, false)
	var start_room: Node3D = generator.find_child("StartRoom", true, false) as Node3D
	var start_pos: Vector3 = start_room.global_position if start_room else Vector3.ZERO
	var start_pos_xz := Vector2(start_pos.x, start_pos.z)

	# Voxel scale for converting grid distance to world units (default 10 units per voxel)
	var voxel_xz: float = generator.get("voxel_scale").x
	const MIN_ROOM_DIST_VOXELS := 4
	var min_horiz_dist: float = MIN_ROOM_DIST_VOXELS * voxel_xz

	# Eligible rooms: at least 4 voxels away horizontally, OR directly above/below start (same XZ).
	var rooms: Array = all_rooms.filter(func(r: Node) -> bool:
		if r.name == "StartRoom":
			return false
		var rp := (r as Node3D).global_position
		var rp_xz := Vector2(rp.x, rp.z)
		var horiz_dist := rp_xz.distance_to(start_pos_xz)
		# Allow rooms directly above/below start (within one voxel horizontally)
		if horiz_dist < voxel_xz:
			return true
		return horiz_dist >= min_horiz_dist
	)

	# Shuffle so NPCs are dispersed randomly across eligible rooms.
	rooms.shuffle()

	if rooms.is_empty():
		return

	# Build a list of spawn tasks: [scene, count]
	# count > 1 means a group spawning close together in the same room
	var tasks: Array = []
	for _i in CHARGER_COUNT:
		tasks.append([CHARGER_SCENE, 1])
	for _i in FLY_COUNT:
		tasks.append([FLY_SCENE, 1])
	for _i in SHAMBLER_COUNT:
		tasks.append([SHAMBLER_SCENE, 1])
	for _i in GNOME_GROUPS:
		var group_size: int = 2 if rng.randi() % 2 == 0 else 3
		tasks.append([GNOME_SCENE, group_size])

	# Shuffle tasks so enemy types are interleaved, dispersed across eligible rooms.
	tasks.shuffle()

	# Assign tasks cycling through the shuffled room pool.
	for i in tasks.size():
		var room: Node3D = rooms[i % rooms.size()]
		var scene: PackedScene = tasks[i][0]
		var count: int = tasks[i][1]

		for j in count:
			var enemy: Node3D = scene.instantiate()
			# Small random spread within the room so grouped gnomes don't stack
			var spread := Vector3(
				rng.randf_range(-2.5, 2.5),
				2.0,
				rng.randf_range(-2.5, 2.5)
			)
			add_child(enemy)
			enemy.global_position = room.global_position + spread

	# Spawn statues and shy on specific dungeon floors
	var gen_origin_y: float = (generator as Node3D).global_position.y
	var voxel_y: float = generator.get("voxel_scale").y
	for floor_data: Array in [[STATUE_SCENE, STATUE_FLOORS], [SHY_SCENE, SHY_FLOORS]]:
		var scene: PackedScene = floor_data[0]
		var floors: Array = floor_data[1]
		for floor_idx: int in floors:
			var target_y := gen_origin_y + floor_idx * voxel_y
			var floor_rooms := all_rooms.filter(func(r: Node) -> bool:
				if r.name == "StartRoom":
					return false
				var rp := (r as Node3D).global_position
				if abs(rp.y - target_y) >= voxel_y * 0.5:
					return false
				var horiz_dist := Vector2(rp.x, rp.z).distance_to(start_pos_xz)
				return horiz_dist < voxel_xz or horiz_dist >= min_horiz_dist
			)
			if floor_rooms.is_empty():
				continue
			floor_rooms.shuffle()
			var enemy: Node3D = scene.instantiate()
			var room: Node3D = floor_rooms[0]
			add_child(enemy)
			enemy.global_position = room.global_position + Vector3(rng.randf_range(-2.5, 2.5), 2.0, rng.randf_range(-2.5, 2.5))
