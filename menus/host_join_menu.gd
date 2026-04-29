extends Control

const PORT := 7777
const MAX_CLIENTS := 3
const GAME_SCENE_PATH := "res://levels/level1.tscn"

@onready var host_button: Button = $Buttons/Host
@onready var join_button: Button = $Buttons/Join
@onready var back_button: Button = $Buttons/Back
@onready var connect_panel: Control = $ConnectPanel
@onready var ip_input: LineEdit = $ConnectPanel/IPInput
@onready var connect_button: Button = $ConnectPanel/Connect
@onready var cancel_join_button: Button = $ConnectPanel/CancelJoin
@onready var status_label: Label = $StatusLabel

var _map_instance: Node = null


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	connect_button.pressed.connect(_on_connect_pressed)
	cancel_join_button.pressed.connect(_on_cancel_join_pressed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	connect_panel.visible = false


func _on_host_pressed() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		_show_status("Failed to start server: " + error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	_show_status("Hosting on port %d. Waiting for players..." % PORT)
	host_button.visible = false
	join_button.visible = false
	back_button.visible = false
	# Brief window for clients to connect before loading
	await get_tree().create_timer(1.5).timeout
	_start_game()


func _on_join_pressed() -> void:
	host_button.visible = false
	join_button.visible = false
	back_button.visible = false
	connect_panel.visible = true
	ip_input.grab_focus()


func _on_connect_pressed() -> void:
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_show_status("Failed to connect: " + error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	_show_status("Connecting to %s:%d..." % [ip, PORT])
	connect_button.disabled = true
	cancel_join_button.disabled = true


func _on_cancel_join_pressed() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	connect_panel.visible = false
	host_button.visible = true
	join_button.visible = true
	back_button.visible = true
	connect_button.disabled = false
	cancel_join_button.disabled = false
	_show_status("")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/start_menu.tscn")


func _on_peer_connected(id: int) -> void:
	_show_status("Player %d connected." % id)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_show_status("Connection failed. Check the IP address and try again.")
	connect_button.disabled = false
	cancel_join_button.disabled = false


func _on_connected_to_server() -> void:
	_show_status("Connected! Loading game...")
	_start_game()


func _start_game() -> void:
	CandlePuzzleRoom.reset_for_generation()
	TableItemSpawn.reset_for_generation()
	var packed: PackedScene = load(GAME_SCENE_PATH)
	_map_instance = packed.instantiate()
	var generator := _find_dungeon_generator(_map_instance)
	if generator:
		generator.generate_threaded = true
		generator.generate_on_ready = false  # seed is controlled by server RPC
		generator.done_generating.connect(_on_map_ready)
	get_tree().root.add_child(_map_instance)
	if not generator:
		_on_map_ready()
		return
	# Only the server picks the seed and broadcasts it so all peers run identical generation.
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		var seed_int := randi()
		# Wait one physics frame to ensure clients have added the scene before the RPC arrives.
		await get_tree().physics_frame
		if is_instance_valid(_map_instance):
			_map_instance.rpc("remote_generate", seed_int)
	else:
		# Client: ask the server for the seed in case it already generated before we connected.
		# If generation hasn't started yet the server ignores this and the normal broadcast handles us.
		await get_tree().physics_frame
		if is_instance_valid(_map_instance):
			_map_instance.rpc_id(1, "request_map_seed")


func _find_dungeon_generator(node: Node) -> Node:
	for child in node.get_children():
		if child.has_signal("done_generating"):
			return child
		var result := _find_dungeon_generator(child)
		if result:
			return result
	return null


func _on_map_ready() -> void:
	_move_player_to_start_room()
	var tree := get_tree()
	tree.root.remove_child(self)
	tree.current_scene = _map_instance

	# Lock the local player so WASD doesn't skip the cutscene
	var embedded_player := _map_instance.get_node_or_null("player")
	if embedded_player != null and "cutscene_active" in embedded_player:
		embedded_player.cutscene_active = true

	# Show the cutscene as a top-level overlay (layer 100 puts it above all game UI)
	var cutscene_canvas := CanvasLayer.new()
	cutscene_canvas.layer = 100
	tree.root.add_child(cutscene_canvas)
	var cutscene_packed: PackedScene = load("res://menus/cutscene.tscn")
	cutscene_canvas.add_child(cutscene_packed.instantiate())

	queue_free()


func _move_player_to_start_room() -> void:
	var start_room := _map_instance.find_child("StartRoom", true, false)
	if start_room == null:
		return
	var start_pos: Vector3 = (start_room as Node3D).global_position + Vector3(0, 1.0, 0)
	# In multiplayer, only the server moves the embedded host player.
	# Clients receive their own spawned player from PlayerSpawner.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var embedded_player := _map_instance.get_node_or_null("player") as Node3D
	if embedded_player != null:
		embedded_player.global_position = start_pos


func _show_status(msg: String) -> void:
	if status_label != null:
		status_label.text = msg
