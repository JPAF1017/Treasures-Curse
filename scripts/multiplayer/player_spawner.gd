class_name PlayerSpawner
extends Node

## Manages spawning of additional player characters in multiplayer.
## One player is always embedded in level1.tscn for the host (peer 1).
## This spawner creates one CharacterBody3D per connecting client and
## assigns multiplayer authority so each player controls only their own character.

const PLAYER_SCENE := preload("res://entities/player2.tscn")

# Side offset applied between each extra player so they don't overlap on spawn.
const SPAWN_SIDE_OFFSET := Vector3(2.5, 0.0, 0.0)

var _spawner: MultiplayerSpawner = null
var _start_position := Vector3.ZERO
var _activated := false


func _enter_tree() -> void:
	# Create the MultiplayerSpawner early (before _ready) so it is in the tree
	# on both server and client before any spawn() calls happen.
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "MultiplayerSpawner"
	_spawner.spawn_function = _do_spawn
	add_child(_spawner)


func _ready() -> void:
	# spawn_path must point to a valid node so MultiplayerSpawner knows where to
	# parent spawned nodes. Set it here (not in _enter_tree) so get_path() is valid.
	_spawner.spawn_path = get_path()
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Call this on the server after dungeon generation is complete.
## start_pos should be the start room's world position (including vertical offset).
func activate(start_pos: Vector3) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_start_position = start_pos
	_activated = true
	# Spawn one player for every already-connected client (skip server peer, which
	# uses the player node that is embedded directly in level1.tscn).
	var index := 1
	for peer_id in multiplayer.get_peers():
		_spawn_for_peer(peer_id, index)
		index += 1


func _on_peer_connected(id: int) -> void:
	if not _activated:
		return
	var index := _count_spawned_players() + 1
	_spawn_for_peer(id, index)


func _on_peer_disconnected(id: int) -> void:
	for child in get_children():
		if child is not MultiplayerSpawner and child.name == str(id):
			child.queue_free()
			return


func _count_spawned_players() -> int:
	var n := 0
	for child in get_children():
		if child is not MultiplayerSpawner:
			n += 1
	return n


func _spawn_for_peer(peer_id: int, index: int) -> void:
	var pos := _start_position + SPAWN_SIDE_OFFSET * float(index)
	_spawner.spawn({"id": peer_id, "pos": pos})


func _do_spawn(data: Dictionary) -> Node:
	var player: Node3D = PLAYER_SCENE.instantiate() as Node3D
	player.name = str(data["id"])
	player.set_multiplayer_authority(data["id"])
	player.position = data["pos"]
	# Add the MultiplayerSynchronizer BEFORE returning so the MultiplayerSpawner
	# registers it as part of the spawn — adding it later in _ready() causes
	# "has no network ID" errors.
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PositionSync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath("Head:rotation"))
	sync.replication_config = config
	player.add_child(sync)
	# Authority must be set on the sync AFTER add_child (so it has a path)
	# but BEFORE returning to the MultiplayerSpawner (still inside the spawn function).
	# This is the correct window — equivalent to _enter_tree of the spawner.
	sync.set_multiplayer_authority(data["id"])
	# On the client that owns this player, mark the camera current now so
	# it is active the moment the node enters the scene tree.
	if multiplayer.get_unique_id() == data["id"]:
		var cameras := player.find_children("*", "Camera3D", true, false)
		if cameras.size() > 0:
			(cameras[0] as Camera3D).current = true
	return player
