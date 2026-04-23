extends Node

## World-unit horizontal radius (XZ only) within which rooms stay visible.
## 1 voxel = 10 units. Bridge is 5 voxels long = 50 units.
## 4-room buffer = ~120 units covers the player's visible area well.
const ROOM_VISIBLE_HORIZ_DIST := 120.0

## World-unit horizontal radius (XZ only) within which NPCs are active.
## "3 rooms horizontally" = 3 * avg ~2 voxels * 10 units ≈ 60 units.
## NPCs directly above/below the player are outside horizontal range and stay frozen.
const NPC_ACTIVE_HORIZ_DIST := 60.0

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
	for room in _rooms:
		if not is_instance_valid(room):
			continue
		var rp := room.global_position
		var horiz_dist := Vector2(pp.x - rp.x, pp.z - rp.z).length()
		room.visible = horiz_dist <= ROOM_VISIBLE_HORIZ_DIST

	# --- NPC freezing ---
	# Rebuild list if empty or stale (enemies can be killed)
	_npcs = _npcs.filter(func(n: Node) -> bool: return is_instance_valid(n))
	if _npcs.is_empty():
		var all_bodies := get_parent().find_children("*", "CharacterBody3D", true, false)
		_npcs = all_bodies.filter(func(n: Node) -> bool: return not n.is_in_group("player"))

	for npc in _npcs:
		if not is_instance_valid(npc):
			continue
		var np := npc.global_position
		# Horizontal (XZ) distance only — being on a floor above/below doesn't count
		var horiz_dist := Vector2(pp.x - np.x, pp.z - np.z).length()
		var freeze := horiz_dist > NPC_ACTIVE_HORIZ_DIST
		npc.process_mode = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT
