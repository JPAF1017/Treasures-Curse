extends Node3D

## Radius within which only one torch sound plays.
const DEDUP_RADIUS := 8.0

@onready var torch_sound: AudioStreamPlayer3D = $TorchSound

# Tracks which fire_particle nodes are currently the active sound emitter.
static var _sound_emitters: Array[Node3D] = []

func _ready() -> void:
	# Purge any freed nodes from the list.
	_sound_emitters = _sound_emitters.filter(func(n: Node3D) -> bool: return is_instance_valid(n))

	# If another emitter is already within range, stay silent.
	for emitter in _sound_emitters:
		if emitter.global_position.distance_to(global_position) <= DEDUP_RADIUS:
			torch_sound.stop()
			return

	# No nearby emitter — register self and play.
	_sound_emitters.append(self)

func _exit_tree() -> void:
	_sound_emitters.erase(self)
