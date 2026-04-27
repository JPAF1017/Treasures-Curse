extends Node3D

# Stored so retries (on dungeon failure) use the same RPC path.
var _generation_seed: int = 0

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

# ---------- Item spawning configuration ----------
# Scene paths must match the paths used by big_room.gd
const ITEM_SCENES: Dictionary = {
	"health": "res://assets/items/health.tscn",
	"smoke":  "res://assets/items/smoke.tscn",
	"sword":  "res://assets/items/sword.tscn",
	"shovel": "res://assets/items/shovel.tscn",
	"bat":    "res://assets/items/bat.tscn",
	"torch":  "res://assets/items/torch.tscn",
}

# Items big_room.gd previously picked from — now picked by level1_spawner with seeded rng.
const BIG_ROOM_ITEM_PATHS: Array[String] = [
	"res://assets/items/sword.tscn",
	"res://assets/items/shovel.tscn",
	"res://assets/items/bat.tscn",
	"res://assets/items/health.tscn",
	"res://assets/items/smoke.tscn",
]

# Total desired count for each item type (does NOT include big-room or table items,
# which are handled separately below before _spawn_map_items is called).
const ITEM_TARGET_COUNTS: Dictionary = {
	"health": 8,
	"smoke":  12,
	"sword":  7,
	"shovel": 7,
	"bat":    7,
	"torch":  15,
}


# References to the MultiplayerSpawner nodes added in level1.tscn
var _npc_spawner: MultiplayerSpawner = null
var _item_spawner: MultiplayerSpawner = null
# Cached after dungeon generation so late joiners can receive the registry via
# request_map_seed (they miss the initial broadcast).
var _table_registry: Dictionary = {}


func _ready() -> void:
	# Wire up the MultiplayerSpawner nodes so they know which scenes to replicate.
	_npc_spawner = get_node_or_null("NPCSpawner") as MultiplayerSpawner
	_item_spawner = get_node_or_null("ItemSpawner") as MultiplayerSpawner
	if _npc_spawner:
		_npc_spawner.spawn_path = get_path()
		_npc_spawner.spawn_function = _do_spawn_npc
		for s in [CHARGER_SCENE, FLY_SCENE, SHAMBLER_SCENE, GNOME_SCENE, STATUE_SCENE, SHY_SCENE]:
			_npc_spawner.add_spawnable_scene(s.resource_path)
	if _item_spawner:
		_item_spawner.spawn_path = get_path()
		_item_spawner.spawn_function = _do_spawn_item
		for path in ITEM_SCENES.values():
			_item_spawner.add_spawnable_scene(path)

	var generator := _find_dungeon_generator(self)
	if generator:
		generator.done_generating.connect(_on_dungeon_ready.bind(generator))
		generator.generating_failed.connect(_on_dungeon_failed.bind(generator))


## Called via RPC from the server (and locally on the server) so all peers
## start dungeon generation with the exact same seed.
@rpc("authority", "call_local", "reliable")
func remote_generate(seed_int: int) -> void:
	if _generation_seed != 0:
		return  # already started; ignore duplicate RPC (e.g. from request_map_seed + broadcast overlap)
	_generation_seed = seed_int
	# Seed the global RNG so that big_room.gd's randi() calls are deterministic
	# across all peers (they don't have access to the local rng instance).
	seed(seed_int)
	var generator := _find_dungeon_generator(self)
	if generator:
		generator.call("generate", seed_int)


## Called by a client that just loaded the map and needs the generation seed.
## If the server has already started generation the seed is sent back directly via rpc_id.
## If generation hasn't started yet the upcoming rpc("remote_generate") broadcast will reach the client normally.
@rpc("any_peer", "call_remote", "reliable")
func request_map_seed() -> void:
	if not multiplayer.is_server():
		return
	if _generation_seed != 0:
		rpc_id(multiplayer.get_remote_sender_id(), "remote_generate", _generation_seed)
		# Also send the puzzle-table registry so the late joiner's puzzle checks work.
		if not _table_registry.is_empty():
			rpc_id(multiplayer.get_remote_sender_id(), "_apply_table_registry", _table_registry)


## Applies the server-computed table-slot→item-scene mapping on every peer so that
## puzzle checks (item_hold_check, candle_puzzle_room) work identically everywhere.
@rpc("authority", "call_local", "reliable")
func _apply_table_registry(registry: Dictionary) -> void:
	_table_registry = registry
	for slot: int in registry:
		TableItemSpawn._registry[slot] = registry[slot]


func _on_dungeon_failed(generator: Node) -> void:
	push_warning("[level1_spawner] Dungeon generation failed on current seed — retrying with a new random seed.")
	if not multiplayer.has_multiplayer_peer():
		# Singleplayer: retry immediately with a new random seed.
		generator.call("generate")
		return
	if multiplayer.is_server():
		# Reset the stored seed so remote_generate's duplicate-guard doesn't block the retry.
		_generation_seed = 0
		_table_registry = {}
		rpc("remote_generate", randi())
	# Clients reset their seed too so they accept the incoming retry broadcast.
	else:
		_generation_seed = 0


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
	# Seed from _generation_seed so NPC/item placement is identical on all peers.
	# In singleplayer _generation_seed is 0, so fall back to randomize().
	if _generation_seed != 0:
		rng.seed = _generation_seed
	else:
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

	# Sort rooms by a deterministic key so find_children order doesn't affect placement.
	all_rooms.sort_custom(func(a: Node, b: Node) -> bool:
		var pa := (a as Node3D).global_position
		var pb := (b as Node3D).global_position
		if pa.x != pb.x: return pa.x < pb.x
		if pa.y != pb.y: return pa.y < pb.y
		return pa.z < pb.z
	)

	# Eligible rooms: at least 4 voxels away horizontally, OR directly above/below start (same XZ).
	# Candle puzzle rooms are excluded so NPCs never spawn in them.
	var rooms: Array = all_rooms.filter(func(r: Node) -> bool:
		if r.name == "StartRoom":
			return false
		if r is CandlePuzzleRoom:
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
	_rng_shuffle(rooms, rng)

	# In multiplayer, only the server spawns NPCs and items.
	# MultiplayerSpawner replicates them automatically to all clients.
	var is_server := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

	if rooms.is_empty() or not is_server:
		# Still need to activate player spawner on clients after generation.
		var player_spawner := get_node_or_null("PlayerSpawner")
		if player_spawner and player_spawner.has_method("activate"):
			player_spawner.call("activate", start_pos + Vector3(0, 1.0, 0))
		return

	# Build a list of spawn tasks: [scene, count]
	# count > 1 means a group spawning close together in the same room
	var tasks: Array = []
	for i in CHARGER_COUNT:
		tasks.append([CHARGER_SCENE, 1])
	for i in FLY_COUNT:
		tasks.append([FLY_SCENE, 1])
	for i in SHAMBLER_COUNT:
		tasks.append([SHAMBLER_SCENE, 1])
	for i in GNOME_GROUPS:
		var group_size: int = 2 if rng.randi() % 2 == 0 else 3
		tasks.append([GNOME_SCENE, group_size])

	# Shuffle tasks so enemy types are interleaved, dispersed across eligible rooms.
	_rng_shuffle(tasks, rng)

	# Assign tasks cycling through the shuffled room pool.
	for i in tasks.size():
		var room: Node3D = rooms[i % rooms.size()]
		var scene: PackedScene = tasks[i][0]
		var count: int = tasks[i][1]

		for j in count:
			var spread := Vector3(
				rng.randf_range(-2.5, 2.5),
				2.0,
				rng.randf_range(-2.5, 2.5)
			)
			var target_pos := room.global_position + spread
			if _npc_spawner:
				_npc_spawner.spawn({"scene": scene.resource_path, "pos": target_pos})
			else:
				var enemy: Node3D = scene.instantiate()
				add_child(enemy)
				enemy.global_position = target_pos

	# Spawn statues and shy on specific dungeon floors
	# (server only — MultiplayerSpawner replicates to clients)
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
				if r is CandlePuzzleRoom:
					return false
				var rp := (r as Node3D).global_position
				if abs(rp.y - target_y) >= voxel_y * 0.5:
					return false
				var horiz_dist := Vector2(rp.x, rp.z).distance_to(start_pos_xz)
				return horiz_dist < voxel_xz or horiz_dist >= min_horiz_dist
			)
			if floor_rooms.is_empty():
				continue
			_rng_shuffle(floor_rooms, rng)
			var room: Node3D = floor_rooms[0]
			var target_pos := room.global_position + Vector3(rng.randf_range(-2.5, 2.5), 2.0, rng.randf_range(-2.5, 2.5))
			if _npc_spawner:
				_npc_spawner.spawn({"scene": scene.resource_path, "pos": target_pos})
			else:
				var enemy: Node3D = scene.instantiate()
				add_child(enemy)
				enemy.global_position = target_pos

	# ---------- Spawn items in big rooms (server only, via ItemSpawner) ----------
	# big_room.gd no longer spawns items directly; we pick them here with the seeded
	# rng and route them through _item_spawner so clients receive the same items.
	var big_room_counts: Dictionary = {}
	for key: String in ITEM_SCENES:
		big_room_counts[key] = 0
	var _br_scene_to_key: Dictionary = {}
	for key: String in ITEM_SCENES:
		_br_scene_to_key[ITEM_SCENES[key]] = key
	for room: Node in all_rooms:
		if not (room is BigRoom):
			continue
		for spawn_name: String in ["Spawn/SpawnItem", "Spawn/SpawnItem2"]:
			var spawn_area := room.get_node_or_null(spawn_name) as Node3D
			if spawn_area == null:
				continue
			var path: String = BIG_ROOM_ITEM_PATHS[rng.randi() % BIG_ROOM_ITEM_PATHS.size()]
			if _item_spawner:
				_item_spawner.spawn({"scene": path, "pos": spawn_area.global_position + Vector3(0, 0.5, 0)})
			if _br_scene_to_key.has(path):
				big_room_counts[_br_scene_to_key[path]] += 1

	# ---------- Spawn puzzle table items (server only, via ItemSpawner) ----------
	# TableItemSpawn no longer self-spawns in _ready(); we assign items with the seeded
	# rng and broadcast the registry so all peers have the same slot→item mapping.
	var table_spawns: Array = generator.find_children("*", "Area3D", true, false).filter(
		func(n: Node) -> bool: return n is TableItemSpawn
	)
	table_spawns.sort_custom(func(a: Node, b: Node) -> bool:
		var pa := (a as Node3D).global_position
		var pb := (b as Node3D).global_position
		if pa.x != pb.x: return pa.x < pb.x
		if pa.y != pb.y: return pa.y < pb.y
		return pa.z < pb.z
	)
	var table_pool: Array = [
		"res://assets/items/sword.tscn", "res://assets/items/bat.tscn",
		"res://assets/items/shovel.tscn", "res://assets/items/health.tscn",
		"res://assets/items/smoke.tscn"
	]
	_rng_shuffle(table_pool, rng)
	var table_reg: Dictionary = {}
	for i in table_spawns.size():
		var ts := table_spawns[i] as TableItemSpawn
		var path: String = table_pool[i % table_pool.size()]
		if ts.table_slot > 0:
			table_reg[ts.table_slot] = path
		var ts_shape := ts.get_node_or_null("CollisionShape3D") as Node3D
		var table_pos := ts_shape.global_position if ts_shape else ts.global_position
		if _item_spawner:
			_item_spawner.spawn({"scene": path, "pos": table_pos + Vector3(0, 0.2, 0), "puzzle_item": true})
	# Apply registry on all peers (call_local runs on server too).
	if multiplayer.has_multiplayer_peer():
		rpc("_apply_table_registry", table_reg)
	else:
		_apply_table_registry(table_reg)

	# ---------- Spawn items across the map (server only) ----------
	var item_rooms: Array = rooms.filter(func(r: Node) -> bool:
		var n := r.name.to_lower()
		return not (n.begins_with("corridor") or n.begins_with("stair"))
	)
	_spawn_map_items(generator, item_rooms, rng, big_room_counts)

	# Notify the multiplayer player spawner so it places a character for each client.
	var player_spawner := get_node_or_null("PlayerSpawner")
	if player_spawner and player_spawner.has_method("activate"):
		player_spawner.call("activate", start_pos + Vector3(0, 1.0, 0))


## Fills in the ITEM_TARGET_COUNTS quota beyond what was already placed in big rooms.
## pre_spawned: dict of {key → count} tracking items already spawned in big rooms.
func _spawn_map_items(
	generator: Node, rooms: Array, rng: RandomNumberGenerator, pre_spawned: Dictionary
) -> void:
	# Build a flat list of item spawn tasks: each entry is a scene path string.
	# pre_spawned accounts for items already placed in big rooms so we don't exceed targets.
	var item_tasks: Array[String] = []
	for key: String in ITEM_TARGET_COUNTS:
		var target: int = ITEM_TARGET_COUNTS[key]
		var already: int = pre_spawned.get(key, 0)
		var remaining: int = maxi(target - already, 0)
		for i in remaining:
			item_tasks.append(ITEM_SCENES[key])

	_rng_shuffle(item_tasks, rng)

	if item_tasks.is_empty() or rooms.is_empty():
		return

	# Track items placed per room so we spread across the whole map.
	# Items are placed in rooms with the fewest items first; the cap rises
	# automatically when all rooms are equally loaded.
	var room_item_counts: Dictionary = {}
	for room in rooms:
		room_item_counts[room] = 0

	for scene_path: String in item_tasks:
		# Find the current minimum load among all rooms.
		var min_count: int = room_item_counts.values().min()
		# Pick randomly from rooms that are at the minimum (least loaded).
		var candidates: Array = rooms.filter(func(r: Node) -> bool:
			return room_item_counts.get(r, 0) == min_count
		)
		var room: Node3D = candidates[rng.randi() % candidates.size()]

		var spread := Vector3(
			rng.randf_range(-3.0, 3.0),
			2.0,
			rng.randf_range(-3.0, 3.0)
		)
		var target_pos := room.global_position + spread
		if _item_spawner:
			_item_spawner.spawn({"scene": scene_path, "pos": target_pos})
		else:
			var packed: PackedScene = load(scene_path)
			if packed == null:
				push_error("[level1_spawner] Failed to load item: " + scene_path)
				continue
			var item: Node3D = packed.instantiate()
			add_child(item)
			item.global_position = target_pos
		room_item_counts[room] += 1


## Fisher-Yates shuffle using the provided RandomNumberGenerator so results are
## deterministic across all peers when the same seed is used.
func _rng_shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp


## Spawn function called by NPCSpawner on all peers.
func _do_spawn_npc(data: Dictionary) -> Node:
	var packed := load(data["scene"]) as PackedScene
	var node: Node3D = packed.instantiate() as Node3D
	node.position = data["pos"]
	return node


## Spawn function called by ItemSpawner on all peers.
func _do_spawn_item(data: Dictionary) -> Node:
	var packed := load(data["scene"]) as PackedScene
	var node: Node3D = packed.instantiate() as Node3D
	node.position = data["pos"]
	if data.get("puzzle_item", false):
		node.set_meta("puzzle_item", true)
		# Freeze briefly so CSG table collision has time to generate before physics.
		if node is RigidBody3D:
			(node as RigidBody3D).freeze = true
			node.call_deferred("set", "freeze", false)
	return node
