extends Node3D

# Stored so retries (on dungeon failure) use the same RPC path.
var _generation_seed: int = 0

const CHARGER_SCENE := preload("res://entities/charger.tscn")
const FLY_SCENE     := preload("res://entities/fly.tscn")
const SHAMBLER_SCENE := preload("res://entities/shambler.tscn")
const GNOME_SCENE   := preload("res://entities/gnome.tscn")
const STATUE_SCENE  := preload("res://entities/statue.tscn")
const SHY_SCENE     := preload("res://entities/shy.tscn")
const KNIGHT_SCENE  := preload("res://entities/knight.tscn")

const CHARGER_COUNT  := 5
const FLY_COUNT      := 5
const SHAMBLER_COUNT := 3
const GNOME_GROUPS   := 3  # each group spawns 2 or 3 gnomes in the same room
# Floors (0-based index) where shy spawns (one per floor)
const SHY_FLOORS     := [1, 3]
# Knights: one on the 2nd floor (index 1) and one on the 3rd floor (index 2)

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

# ---- Statue deferred-spawn state (server only) ----
const STATUE_COUNTDOWN_DURATION  := 120.0  # 2 minutes before each spawn
const STATUE_SEEN_DESPAWN_TIME   := 30.0   # 30 seconds after first sighting before despawn
const STATUE_SPAWN_BEHIND_MIN    := 3.0    # min distance directly behind the player
const STATUE_SPAWN_BEHIND_MAX    := 6.0    # max distance directly behind the player
const STATUE_SPAWN_ARC_HALF_DEG  := 90.0  # half-angle of the behind-player arc
const STATUE_SPAWN_ATTEMPTS      := 12     # random candidates per retry
const STATUE_SPAWN_RETRY_SEC     := 0.2    # seconds between hidden-spot retries
const STATUE_DESPAWN_CHECK_SEC   := 0.25   # poll interval while waiting for a no-look window
const STATUE_VIEW_CONE_DEG       := 65.0   # slightly wider than the statue's 60° view cone

var _second_floor_y: float = INF           # Y threshold set after dungeon generation
var _top_floor_y: float = INF              # top floor Y — statue must not spawn here
var _voxel_y: float = 0.0                  # floor step height
var _statue_timer_active: bool = false
var _statue_countdown: float = 0.0
var _spawn_retry_timer: float = 0.0
var _statue_node: Node3D = null            # live statue reference (null = not spawned)
var _statue_seen: bool = false             # has any player spotted the statue?
var _statue_seen_timer: float = 0.0        # 1-min countdown after first sighting
var _despawn_check_timer: float = 0.0      # poll interval while waiting for no-look moment
var _statue_intro_triggered: bool = false  # true once a player has entered the IntroStatue room

# Enemies that must stay inside their intro room.
# Each entry: { "enemy": Node3D, "center": Vector3, "half_xz": float }
var _confined_enemies: Array = []


func _ready() -> void:
	# Wire up the MultiplayerSpawner nodes so they know which scenes to replicate.
	_npc_spawner = get_node_or_null("NPCSpawner") as MultiplayerSpawner
	_item_spawner = get_node_or_null("ItemSpawner") as MultiplayerSpawner
	if _npc_spawner:
		_npc_spawner.spawn_path = get_path()
		_npc_spawner.spawn_function = _do_spawn_npc
		for s in [CHARGER_SCENE, FLY_SCENE, SHAMBLER_SCENE, GNOME_SCENE, STATUE_SCENE, SHY_SCENE, KNIGHT_SCENE]:
			_npc_spawner.add_spawnable_scene(s.resource_path)
	if _item_spawner:
		_item_spawner.spawn_path = get_path()
		_item_spawner.spawn_function = _do_spawn_item
		for path in ITEM_SCENES.values():
			_item_spawner.add_spawnable_scene(path)
		for path: String in [
			"res://assets/items/Gem_key1.tscn",
			"res://assets/items/Gem_key2.tscn",
			"res://assets/items/Gem_key3.tscn",
			"res://assets/items/Gem_key4.tscn",
		]:
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
	for key: String in registry:
		TableItemSpawn._registry[key] = registry[key]


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
	var voxel_y: float = generator.get("voxel_scale").y
	const MIN_ROOM_DIST_VOXELS := 4
	var min_horiz_dist: float = MIN_ROOM_DIST_VOXELS * voxel_xz

	# Store floor geometry for the deferred statue spawn (available on all peers).
	_second_floor_y = start_pos.y + voxel_y * 0.5
	_voxel_y = voxel_y

	# Remove all procedurally placed non-corridor rooms on the bottom floor.
	# Pre-placed rooms and corridors are kept; only random filler rooms are removed.
	const PREPLACED_NAMES := ["StartRoom", "IntroArena", "TreasureRoom", "Stair", "Bridge", "Gauntlet"]
	for child in generator.get_children():
		if not (child is DungeonRoom3D):
			continue
		var rp := (child as Node3D).global_position
		if abs(rp.y - start_pos.y) < voxel_y:
			if child.name in PREPLACED_NAMES:
				continue
			# Keep corridors so rooms stay connected
			if child.name.begins_with("Corridor"):
				continue
			# Keep pre-placed dead end rooms
			if child.name.begins_with("DeadEnd"):
				continue
			child.queue_free()

	# Refresh all_rooms after removals.
	all_rooms = generator.find_children("*", "DungeonRoom3D", true, false)
	# Spawn gauntlet enemies below each room's chandelier and open each
	# room's Door node when all enemies in that room have been killed.
	var _gauntlet_node := generator.find_child("Gauntlet", true, false)
	if is_instance_valid(_gauntlet_node):
		var _g := _gauntlet_node as Node

		# Spawn an NPC and return the live node reference.
		var _spawn_npc := func(scene: PackedScene, pos: Vector3) -> Node3D:
			if _npc_spawner:
				return _npc_spawner.spawn({"scene": scene.resource_path, "pos": pos}) as Node3D
			var _n: Node3D = scene.instantiate()
			add_child(_n)
			_n.global_position = pos
			return _n

		# When all enemies in the list have left the tree, queue_free the door.
		var _watch_room := func(enemies: Array, door: Node3D) -> void:
			if enemies.is_empty() or not is_instance_valid(door):
				return
			var _alive := [enemies.size()]
			for _e: Node3D in enemies:
				if is_instance_valid(_e):
					(_e as Node).tree_exiting.connect(func() -> void:
						_alive[0] -= 1
						if _alive[0] <= 0 and is_instance_valid(door):
							door.queue_free()
					)

		# -- Room1: 1 knight --
		var _r1: Array = []
		var _chan1 := _g.get_node_or_null("Models/Room1/Props/chandelier") as Node3D
		var _flr1  := _g.get_node_or_null("Models/Room1/Floor") as Node3D
		if _chan1 and _flr1:
			var _fy1 := _flr1.global_position.y + 1.0
			var _n1 := _spawn_npc.call(KNIGHT_SCENE, Vector3(_chan1.global_position.x, _fy1, _chan1.global_position.z)) as Node3D
			if _n1: _r1.append(_n1)
		_watch_room.call(_r1, _g.get_node_or_null("Models/Room1/Door") as Node3D)

		# -- Room2: 1 knight + 2 chargers --
		var _r2: Array = []
		var _chan2 := _g.get_node_or_null("Models/Room2/Props/chandelier") as Node3D
		var _flr2  := _g.get_node_or_null("Models/Room2/Floor") as Node3D
		if _chan2 and _flr2:
			var _cx2 := _chan2.global_position.x
			var _fy2 := _flr2.global_position.y + 1.0
			var _cz2 := _chan2.global_position.z
			for _entry in [[KNIGHT_SCENE, Vector3(_cx2, _fy2, _cz2)],
					[CHARGER_SCENE, Vector3(_cx2 - 2.0, _fy2, _cz2)],
					[CHARGER_SCENE, Vector3(_cx2 + 2.0, _fy2, _cz2)]]:
				var _n2 := _spawn_npc.call(_entry[0], _entry[1]) as Node3D
				if _n2: _r2.append(_n2)
		_watch_room.call(_r2, _g.get_node_or_null("Models/Room2/Door") as Node3D)

		# -- Room3: 2 knights --
		var _r3: Array = []
		var _chan3 := _g.get_node_or_null("Models/Room3/Props/chandelier") as Node3D
		var _flr3  := _g.get_node_or_null("Models/Room3/Floor") as Node3D
		if _chan3 and _flr3:
			var _cx3 := _chan3.global_position.x
			var _fy3 := _flr3.global_position.y + 1.0
			var _cz3 := _chan3.global_position.z
			for _offset: float in [-1.5, 1.5]:
				var _n3 := _spawn_npc.call(KNIGHT_SCENE, Vector3(_cx3 + _offset, _fy3, _cz3)) as Node3D
				if _n3: _r3.append(_n3)
		_watch_room.call(_r3, _g.get_node_or_null("Models/Room3/Door") as Node3D)

	# Sort rooms by a deterministic key so find_children order doesn't affect placement.
	all_rooms.sort_custom(func(a: Node, b: Node) -> bool:
		var pa := (a as Node3D).global_position
		var pb := (b as Node3D).global_position
		if pa.x != pb.x: return pa.x < pb.x
		if pa.y != pb.y: return pa.y < pb.y
		return pa.z < pb.z
	)

	# Compute top floor Y — statue will never be allowed to spawn at this level.
	var _max_room_y := -INF
	for _rr in all_rooms:
		var _ry := (_rr as Node3D).global_position.y
		if _ry > _max_room_y:
			_max_room_y = _ry
	_top_floor_y = _max_room_y

	# Eligible rooms: above the bottom floor, at least 4 voxels away horizontally from start
	# (or directly above/below it). Candle puzzle rooms are always excluded.
	var rooms: Array = all_rooms.filter(func(r: Node) -> bool:
		if r.name == "StartRoom" or r.name == "IntroArena" or r.name == "SkullPuzzle":
			return false
		if r is CandlePuzzleRoom:
			return false
		var rp := (r as Node3D).global_position
		# Exclude rooms on the bottom two floors
		if abs(rp.y - start_pos.y) < voxel_y * 2.0:
			return false
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
		var ps := get_node_or_null("PlayerSpawner")
		if ps and ps.has_method("activate"):
			ps.call("activate", start_pos + Vector3(0, 1.0, 0))
		return

	# Build a list of spawn tasks: [scene, count]
	# count > 1 means a group spawning close together in the same room
	# NOTE: chargers are spawned exclusively in IntroArena below, not here.
	var tasks: Array = []
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
	for floor_data: Array in [[SHY_SCENE, SHY_FLOORS]]:
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
		# Skip big rooms on the bottom two floors or in the IntroArena
		if (room as Node3D).name == "IntroArena":
			continue
		if abs((room as Node3D).global_position.y - start_pos.y) < voxel_y * 2.0:
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
	# Also include TableItemSpawn nodes in pre-placed rooms that live outside the generator.
	var _scene_root := generator.get_parent()
	if _scene_root:
		var _preplaced_ts := _scene_root.find_children("*", "Area3D", true, false).filter(
			func(n: Node) -> bool:
				return n is TableItemSpawn and not generator.is_ancestor_of(n)
		)
		_preplaced_ts.sort_custom(func(a: Node, b: Node) -> bool:
			var pa := (a as Node3D).global_position
			var pb := (b as Node3D).global_position
			if pa.x != pb.x: return pa.x < pb.x
			if pa.y != pb.y: return pa.y < pb.y
			return pa.z < pb.z
		)
		print("[Puzzle] Pre-placed TableItemSpawn nodes found: ", _preplaced_ts.size())
		for _pts in _preplaced_ts:
			print("[Puzzle]   pre-placed ts: ", _pts.name, " slot=", (_pts as TableItemSpawn).table_slot, " pos=", (_pts as Node3D).global_position)
		table_spawns.append_array(_preplaced_ts)
	print("[Puzzle] Total TableItemSpawn nodes (generator + pre-placed): ", table_spawns.size())
	var table_pool: Array = [
		"res://assets/items/Gem_key1.tscn",
		"res://assets/items/Gem_key2.tscn",
		"res://assets/items/Gem_key3.tscn",
		"res://assets/items/Gem_key4.tscn",
	]
	_rng_shuffle(table_pool, rng)
	var table_reg: Dictionary = {}
	for i in table_spawns.size():
		var ts := table_spawns[i] as TableItemSpawn
		var path: String = table_pool[i % table_pool.size()]
		if ts.table_slot > 0:
			# Walk up to the CandlePuzzleRoom so the key matches what _check_slot_correct uses.
			var _room_ancestor: Node = (ts as Node3D).get_parent()
			while _room_ancestor != null and not (_room_ancestor is CandlePuzzleRoom):
				_room_ancestor = _room_ancestor.get_parent()
			var _floor_y_key: float = (_room_ancestor as Node3D).global_position.y if _room_ancestor is CandlePuzzleRoom else (ts as Node3D).global_position.y
			var _floor_key := "%d|%d" % [roundi(_floor_y_key), ts.table_slot]
			print("[Puzzle] registry key=", _floor_key, " → ", path)
			table_reg[_floor_key] = path
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
	# Pool includes upper-floor rooms AND corridors for wider distribution.
	# Stair rooms and puzzle rooms are excluded; bottom two floors already filtered above.
	var spawn_pool: Array = all_rooms.filter(func(r: Node) -> bool:
		var rp := (r as Node3D).global_position
		if abs(rp.y - start_pos.y) < voxel_y * 2.0:
			return false
		if r is CandlePuzzleRoom:
			return false
		var n := r.name.to_lower()
		if n.begins_with("stair"):
			return false
		return true
	)
	_spawn_map_items(generator, spawn_pool, rng, big_room_counts)

	# Spawn 1 charger and 1 sword inside the IntroArena.
	# The charger cannot be baked into intro_arena.tscn because charger._ready() sets
	# top_level = true, which would leave it at world origin after SimpleDungeons moves the room.
	var intro_arena := generator.find_child("IntroArena", true, false) as Node3D
	if intro_arena:
		var arena_pos := intro_arena.global_position
		var charger_ref: Node3D = null
		if _npc_spawner:
			charger_ref = _npc_spawner.spawn({"scene": CHARGER_SCENE.resource_path, "pos": arena_pos + Vector3(0, 1.0, 0)})
		else:
			charger_ref = CHARGER_SCENE.instantiate()
			add_child(charger_ref)
			charger_ref.global_position = arena_pos + Vector3(0, 1.0, 0)
		# When the charger dies, rotate Door_02 by 60° on Y to open the exit.
		# Also spawn a health potion at the arena center if any player took damage.
		if charger_ref and charger_ref.has_signal("died"):
			var door := intro_arena.get_node_or_null("Models/Walls/Back/Door_02") as Node3D
			if door:
				charger_ref.died.connect(func() -> void:
					var tw := door.create_tween()
					tw.tween_property(door, "rotation_degrees:y", 60.0, 1.2) \
						.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
					var players := get_tree().get_nodes_in_group("player")
					var someone_hurt := players.any(func(p: Node) -> bool:
						return p.get(&"health") != null and (p.get(&"health") as float) < 100.0
					)
					if someone_hurt:
						var potion_pos := arena_pos + Vector3(0, 0.5, 0)
						if _item_spawner:
							_item_spawner.spawn({"scene": ITEM_SCENES["health"], "pos": potion_pos})
						else:
							var potion: Node3D = load(ITEM_SCENES["health"]).instantiate()
							add_child(potion)
							potion.global_position = potion_pos
				)
		var sword_pos := arena_pos + Vector3(0, 0.5, 0)
		if _item_spawner:
			_item_spawner.spawn({"scene": ITEM_SCENES["sword"], "pos": sword_pos})
		else:
			var sword: Node3D = load(ITEM_SCENES["sword"]).instantiate()
			add_child(sword)
			sword.global_position = sword_pos

	# Helper: spawn one NPC in an intro room, open its back door when it dies,
	# and confine it to the room bounds.
	var _spawn_intro_room := func(room_name: String, scene: PackedScene) -> void:
		var intro_room := generator.find_child(room_name, true, false) as Node3D
		if not intro_room:
			return
		var room_pos := intro_room.global_position
		var npc_ref: Node3D = null
		if _npc_spawner:
			npc_ref = _npc_spawner.spawn({"scene": scene.resource_path, "pos": room_pos + Vector3(0, 1.0, 0)})
		else:
			npc_ref = scene.instantiate()
			add_child(npc_ref)
			npc_ref.global_position = room_pos + Vector3(0, 1.0, 0)
		if npc_ref:
			_confined_enemies.append({"enemy": npc_ref, "center": room_pos, "half_xz": 13.0})
			if npc_ref.has_signal("died"):
				var door := intro_room.get_node_or_null("Models/Walls/Back/Door_02") as Node3D
				if door:
					npc_ref.died.connect(func() -> void:
						var tw := door.create_tween()
						tw.tween_property(door, "rotation_degrees:y", 60.0, 1.2) \
							.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
					)

	_spawn_intro_room.call("IntroFly",      FLY_SCENE)

	# IntroGnomes: spawn 3 gnomes; door opens only when all 3 are dead.
	var intro_gnomes := generator.find_child("IntroGnomes", true, false) as Node3D
	if intro_gnomes:
		var gnomes_pos := intro_gnomes.global_position
		var gnome_door := intro_gnomes.get_node_or_null("Models/Walls/Back/Door_02") as Node3D
		var alive_gnomes := [3]
		var offsets := [Vector3(-2.5, 1.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(2.5, 1.0, 0.0)]
		for offset: Vector3 in offsets:
			var gnome_ref: Node3D = null
			if _npc_spawner:
				gnome_ref = _npc_spawner.spawn({"scene": GNOME_SCENE.resource_path, "pos": gnomes_pos + offset})
			else:
				gnome_ref = GNOME_SCENE.instantiate()
				add_child(gnome_ref)
				gnome_ref.global_position = gnomes_pos + offset
			if gnome_ref and gnome_ref.has_signal("died") and gnome_door:
				_confined_enemies.append({"enemy": gnome_ref, "center": gnomes_pos, "half_xz": 13.0})
				gnome_ref.died.connect(func() -> void:
					alive_gnomes[0] -= 1
					if alive_gnomes[0] <= 0:
						var tw := gnome_door.create_tween()
						tw.tween_property(gnome_door, "rotation_degrees:y", 60.0, 1.2) \
							.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				)

	_spawn_intro_room.call("IntroKnight",   KNIGHT_SCENE)
	_spawn_intro_room.call("IntroShambler", SHAMBLER_SCENE)

	# IntroShy: spawn 1 shy; door opens the first time the player looks at it.
	# The shy is not killed — the sight event alone unlocks the exit.
	var intro_shy := generator.find_child("IntroShy", true, false) as Node3D
	if intro_shy:
		var shy_pos := intro_shy.global_position
		var shy_door := intro_shy.get_node_or_null("Models/Walls/Back/Door_02") as Node3D
		var shy_ref: Node3D = null
		if _npc_spawner:
			shy_ref = _npc_spawner.spawn({"scene": SHY_SCENE.resource_path, "pos": shy_pos + Vector3(0, 1.0, 0)})
		else:
			shy_ref = SHY_SCENE.instantiate()
			add_child(shy_ref)
			shy_ref.global_position = shy_pos + Vector3(0, 1.0, 0)
		if shy_ref and shy_door:
			_confined_enemies.append({"enemy": shy_ref, "center": shy_pos, "half_xz": 13.0})
			# Wait until _ready() has run so the Seen area node is resolved.
			shy_ref.ready.connect(func() -> void:
				var seen_area := shy_ref.get_node_or_null("Seen") as Area3D
				if seen_area == null:
					return
				var _door_opened := [false]
				seen_area.area_entered.connect(func(area: Area3D) -> void:
					if _door_opened[0] or not area.is_in_group("player_vision"):
						return
					_door_opened[0] = true
					var tw := shy_door.create_tween()
					tw.tween_property(shy_door, "rotation_degrees:y", 60.0, 1.2) \
						.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				)
			, CONNECT_ONE_SHOT)

	# Notify the multiplayer player spawner so it places a character for each client.
	var player_spawner := get_node_or_null("PlayerSpawner")
	if player_spawner and player_spawner.has_method("activate"):
		player_spawner.call("activate", start_pos + Vector3(0, 1.0, 0))

	# Move the host's embedded player to the start room.
	# (PlayerSpawner only handles extra multiplayer clients; the host player
	# is a static node in the scene and always needs to be relocated here.)
	# Connect the IntroStatue room's RoomTitle area so the statue spawns immediately
	# when a player first walks in, starting the despawn/respawn cycle.
	var intro_statue_room := generator.find_child("IntroStatue", true, false) as Node3D
	if intro_statue_room:
		var room_title := intro_statue_room.get_node_or_null("RoomTitle") as Area3D
		if room_title:
			room_title.body_entered.connect(_on_intro_statue_body_entered)
		else:
			push_warning("[StatueSpawn] Could not find RoomTitle in IntroStatue room.")
	else:
		push_warning("[StatueSpawn] Could not find IntroStatue room — statue trigger disabled.")

	var host_player := get_node_or_null("player") as Node3D
	if host_player:
		host_player.global_position = start_pos + Vector3(0, 1.0, 0)


## Fills in the ITEM_TARGET_COUNTS quota beyond what was already placed in big rooms.
## pre_spawned: dict of {key → count} tracking items already spawned in big rooms.
func _spawn_map_items(
	_generator: Node, rooms: Array, rng: RandomNumberGenerator, pre_spawned: Dictionary
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

		# Corridors are narrow (1 voxel wide) so use a tighter spread.
		var is_corridor := room.name.to_lower().begins_with("corridor")
		var max_spread: float = 1.5 if is_corridor else 3.5
		var spread := Vector3(
			rng.randf_range(-max_spread, max_spread),
			0.5,
			rng.randf_range(-max_spread, max_spread)
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
	# Mark so player.gd knows the MultiplayerSpawner will auto-despawn it on reparent.
	node.set_meta("spawner_managed", true)
	return node


# ---------------------------------------------------------------------------
# Deferred statue spawn — triggered when any player reaches the 2nd floor.
# Server-only logic; MultiplayerSpawner replicates the statue to all clients.
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _second_floor_y == INF:
		return
	var is_server := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if not is_server:
		return

	# --- Confine intro-room enemies inside their room bounds ---
	for entry in _confined_enemies:
		var enemy: Node3D = entry["enemy"]
		if not is_instance_valid(enemy):
			continue
		var center: Vector3 = entry["center"]
		var half: float = entry["half_xz"]
		var pos := enemy.global_position
		var dx := pos.x - center.x
		var dz := pos.z - center.z
		if abs(dx) > half or abs(dz) > half:
			enemy.global_position = Vector3(
				center.x + clampf(dx, -half, half),
				pos.y,
				center.z + clampf(dz, -half, half)
			)

	# --- Active-statue lifecycle: sighting detection → 1-min → despawn ---
	if _statue_node != null and is_instance_valid(_statue_node):
		if not _statue_seen:
			if _is_statue_seen_by_any_player():
				_statue_seen = true
				_statue_seen_timer = STATUE_SEEN_DESPAWN_TIME
				print("[StatueSpawn] Statue spotted — 1-min despawn countdown started.")
		else:
			_statue_seen_timer -= delta
			if _statue_seen_timer <= 0.0:
				_despawn_check_timer -= delta
				if _despawn_check_timer <= 0.0:
					_despawn_check_timer = STATUE_DESPAWN_CHECK_SEC
					if not _is_statue_seen_by_any_player():
						_despawn_statue()
		return

	# --- No active statue: retry spawning once the intro room trigger has fired ---
	if _statue_timer_active:
		_statue_countdown -= delta
		if _statue_countdown <= 0.0:
			_spawn_retry_timer -= delta
			if _spawn_retry_timer <= 0.0:
				_spawn_retry_timer = STATUE_SPAWN_RETRY_SEC
				_try_spawn_statue()


## Picks a target player and attempts to spawn the statue in a spot hidden from all players.
func _try_spawn_statue() -> void:
	var players: Array = get_tree().get_nodes_in_group("player").filter(
		func(p: Node) -> bool: return is_instance_valid(p)
	)
	if players.is_empty():
		return

	# Singleplayer: only one player. Multiplayer: pick a random target.
	var target: Node3D = players[randi() % players.size()]
	var spawn_pos := _find_hidden_spawn_near(target.global_position, target)
	if spawn_pos == Vector3.ZERO:
		return  # every angle is visible — retry on next interval

	_statue_seen = false
	_statue_seen_timer = 0.0
	_despawn_check_timer = 0.0
	print("[StatueSpawn] Spawning statue at ", spawn_pos)
	if _npc_spawner:
		_statue_node = _npc_spawner.spawn({"scene": STATUE_SCENE.resource_path, "pos": spawn_pos})
	else:
		_statue_node = STATUE_SCENE.instantiate()
		add_child(_statue_node)
		_statue_node.global_position = spawn_pos


## Returns a world position directly behind `target` (±STATUE_SPAWN_ARC_HALF_DEG) that is
## not visible to any player and not on the top floor. Returns Vector3.ZERO on failure.
func _find_hidden_spawn_near(center: Vector3, target: Node3D = null) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var players: Array = get_tree().get_nodes_in_group("player")

	# Determine the player's backward direction (+Z in local space = behind them).
	var backward := Vector3(0.0, 0.0, 1.0)  # fallback: world +Z
	if target != null:
		var head := target.get_node_or_null("Head") as Node3D
		if head:
			backward = head.global_transform.basis.z.normalized()
		else:
			backward = target.global_transform.basis.z.normalized()

	# Each call picks random angles within the behind-player arc so successive
	# retries (every 0.2 s) explore different candidate positions.
	var distances: Array = [STATUE_SPAWN_BEHIND_MIN,
			lerpf(STATUE_SPAWN_BEHIND_MIN, STATUE_SPAWN_BEHIND_MAX, 0.5),
			STATUE_SPAWN_BEHIND_MAX]
	for i in STATUE_SPAWN_ATTEMPTS:
		var angle_offset := randf_range(-STATUE_SPAWN_ARC_HALF_DEG, STATUE_SPAWN_ARC_HALF_DEG)
		var dir := backward.rotated(Vector3.UP, deg_to_rad(angle_offset))
		for dist in distances:
			var candidate := center + Vector3(dir.x * dist, 0.0, dir.z * dist)
			# Reject candidates inside or behind a wall.
			var wall_query := PhysicsRayQueryParameters3D.create(
				center + Vector3(0, 1.0, 0),
				candidate + Vector3(0, 1.0, 0)
			)
			if not space_state.intersect_ray(wall_query).is_empty():
				continue
			if not _is_position_visible_to_any_player(candidate, players, space_state):
				return candidate
	return Vector3.ZERO


## Fires when any body enters the IntroStatue room's RoomTitle Area3D (server only).
## Immediately kicks off the statue spawn instead of waiting for the 2nd-floor countdown.
func _on_intro_statue_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if _statue_intro_triggered or _statue_node != null:
		return
	_statue_intro_triggered = true
	# Set countdown to 0 so _process begins spawning retries on the very next frame.
	_statue_timer_active = true
	_statue_countdown = 0.0
	_spawn_retry_timer = 0.0
	print("[StatueSpawn] Player entered IntroStatue room — statue spawn triggered.")


## Despawns the active statue and resets the spawn cycle to its 3-min countdown.
func _despawn_statue() -> void:
	print("[StatueSpawn] Despawning statue — respawning in 3 minutes.")
	_statue_node.queue_free()
	_statue_node = null
	_statue_seen = false
	_statue_seen_timer = 0.0
	_despawn_check_timer = 0.0
	# Begin the next 3-min countdown immediately.
	_statue_timer_active = true
	_statue_countdown = STATUE_COUNTDOWN_DURATION
	_spawn_retry_timer = 0.0


## Returns true if any player currently has unobstructed line of sight to the statue.
func _is_statue_seen_by_any_player() -> bool:
	if _statue_node == null or not is_instance_valid(_statue_node):
		return false
	# Check at chest height so partial occlusion by the floor doesn't give false negatives.
	var check_pos := _statue_node.global_position + Vector3(0, 1.2, 0)
	var space_state := get_world_3d().direct_space_state
	for player in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(player):
			continue
		var cam := (player as Node3D).get_node_or_null("Head/playerCamera") as Camera3D
		var view_origin: Vector3
		var view_forward: Vector3
		if cam != null:
			view_origin = cam.global_position
			view_forward = -cam.global_transform.basis.z.normalized()
		else:
			var head := (player as Node3D).get_node_or_null("Head") as Node3D
			if head != null:
				view_origin = head.global_position
				view_forward = -head.global_transform.basis.z.normalized()
			else:
				view_origin = (player as Node3D).global_position + Vector3(0, 1.7, 0)
				view_forward = -(player as Node3D).global_transform.basis.z.normalized()
		var dir_to_statue := (check_pos - view_origin).normalized()
		var dot := view_forward.dot(dir_to_statue)
		var angle := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
		if angle <= STATUE_VIEW_CONE_DEG:
			var query := PhysicsRayQueryParameters3D.create(view_origin, check_pos)
			query.exclude = [player, _statue_node]
			var result := space_state.intersect_ray(query)
			if result.is_empty():
				return true
	return false


## Returns true if `pos` is within the view cone AND line of sight of any player.
func _is_position_visible_to_any_player(
	pos: Vector3, players: Array, space_state: PhysicsDirectSpaceState3D
) -> bool:
	for player in players:
		if not is_instance_valid(player):
			continue
		# Prefer the actual camera node; fall back to head, then player body.
		var cam := (player as Node3D).get_node_or_null("Head/playerCamera") as Camera3D
		var view_origin: Vector3
		var view_forward: Vector3
		if cam != null:
			view_origin = cam.global_position
			view_forward = -cam.global_transform.basis.z.normalized()
		else:
			var head := (player as Node3D).get_node_or_null("Head") as Node3D
			if head != null:
				view_origin = head.global_position
				view_forward = -head.global_transform.basis.z.normalized()
			else:
				view_origin = (player as Node3D).global_position + Vector3(0, 1.7, 0)
				view_forward = -(player as Node3D).global_transform.basis.z.normalized()
		var dir_to_pos := (pos - view_origin).normalized()
		var dot := view_forward.dot(dir_to_pos)
		var angle := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
		if angle <= STATUE_VIEW_CONE_DEG:
			# Within view cone — check for an unobstructed line of sight.
			var query := PhysicsRayQueryParameters3D.create(view_origin, pos)
			query.exclude = [player]
			var result := space_state.intersect_ray(query)
			if result.is_empty():
				return true  # player has clear line of sight to this position
	return false
