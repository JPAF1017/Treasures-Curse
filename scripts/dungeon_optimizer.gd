extends Node

## World-unit horizontal radius (XZ only) within which rooms stay visible.
## 1 voxel = 10 units. Bridge is 5 voxels long = 50 units.
## 4-room buffer = ~120 units covers the player's visible area well.
const ROOM_VISIBLE_HORIZ_DIST := 120.0

const UPDATE_INTERVAL := 0.25  # seconds between culling passes

var _player: Node3D = null
var _rooms: Array = []
var _npcs: Array = []
var _ready_to_update := false
var _update_timer := 0.0


func _ready() -> void:
	var generator := _find_dungeon_generator(get_parent())
	if generator:
		generator.done_generating.connect(_on_dungeon_ready)


func _find_dungeon_generator(node: Node) -> Node:
	for child in node.get_children():
		if child.has_signal("done_generating"):
			return child
		var result := _find_dungeon_generator(child)
		if result:
			return result
	return null


func _on_dungeon_ready() -> void:
	_rooms = get_parent().find_children("*", "DungeonRoom3D", true, false)
	_player = get_tree().get_first_node_in_group("player")
	_ready_to_update = true
	# Immediately run one pass so nothing is frozen/hidden at wrong moment
	_update()


func _process(delta: float) -> void:
	if not _ready_to_update:
		return
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0
	_update()


func _update() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return

	var pp := _player.global_position

	# --- Room visibility ---
	for room_node in _rooms:
		if not is_instance_valid(room_node):
			continue
		var room := room_node as Node3D
		if room == null:
			continue
		var rp: Vector3 = room.global_position
		var horiz_dist := Vector2(pp.x - rp.x, pp.z - rp.z).length()
		room.visible = horiz_dist <= ROOM_VISIBLE_HORIZ_DIST

	# --- NPC freezing ---
	# Rebuild list every pass so newly spawned NPCs are tracked
	var all_bodies := get_parent().find_children("*", "CharacterBody3D", true, false)
	_npcs = all_bodies.filter(func(n: Node) -> bool: return is_instance_valid(n) and not n.is_in_group("player"))

	# Fallback default detection range for NPCs that don't declare one
	const DEFAULT_DETECTION_RANGE := 30.0
	# Max NPCs that can actively target the player at once
	const MAX_TARGETING_NPCS := 4

	var space_state := _player.get_world_3d().direct_space_state
	var player_eye := pp + Vector3(0, 0.8, 0)

	# Count NPCs already targeting
	var targeting_count := 0
	for npc_node in _npcs:
		if is_instance_valid(npc_node) and npc_node.get("target_player") != null and is_instance_valid(npc_node.get("target_player")):
			targeting_count += 1

	for npc_node in _npcs:
		if not is_instance_valid(npc_node):
			continue
		var npc := npc_node as Node3D
		if npc == null:
			continue
		var np: Vector3 = npc.global_position
		var dist := pp.distance_to(np)

		# Check if player is within NPC's detection range (proximity-based, ignores walls)
		var det_range: float = npc_node.get("DETECTION_RANGE") if npc_node.get("DETECTION_RANGE") != null else DEFAULT_DETECTION_RANGE
		var in_detection := dist <= det_range

		# Check if the player has line of sight to the NPC
		var has_los := false
		if not in_detection:
			var npc_eye := np + Vector3(0, 0.8, 0)
			has_los = not NavigationUtils.raycast_blocked(player_eye, npc_eye, space_state, [_player, npc_node])

		# Also enforce targeting cap: non-targeting NPCs beyond cap stay frozen
		var is_targeting := npc_node.get("target_player") != null and is_instance_valid(npc_node.get("target_player"))
		var over_cap := not is_targeting and targeting_count >= MAX_TARGETING_NPCS

		var freeze := (not in_detection and not has_los) or over_cap
		npc.process_mode = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT
