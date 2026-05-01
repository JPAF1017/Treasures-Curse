class_name VoiceChat
extends Node

## Proximity voice chat for multiplayer.
## Added dynamically to each player node when a multiplayer session is active.
##
## SENDING (authority peer only):
##   Captures microphone audio via AudioEffectCapture on a dedicated muted bus,
##   encodes it as int16 PCM, and broadcasts it every 20 ms via unreliable RPC.
##
## RECEIVING (all remote peers):
##   Receives PCM bytes and pushes them into an AudioStreamGenerator on an
##   AudioStreamPlayer3D that is a child of the remote player node — so Godot's
##   built-in 3D attenuation provides the proximity effect automatically.
##
## Push-to-talk: hold V to transmit.

const CHUNK_INTERVAL    := 0.02   ## Send one audio chunk every 20 ms
const MAX_VOICE_DIST    := 15.0   ## Distance (units) where voice fully fades out
const UNIT_SIZE         := 3.0    ## Distance (units) for full-volume playback
const MIC_BUS_NAME      := "VoiceCapture"

var _capture_effect: AudioEffectCapture           = null
var _capture_bus_idx: int                         = -1
var _generator_playback: AudioStreamGeneratorPlayback = null
var _send_timer: float                            = 0.0
var _talking: bool                                = false
var _voice_receiver: AudioStreamPlayer3D          = null
var _talk_label: Label3D                          = null


func _ready() -> void:
	_setup_receiver()
	_setup_talk_indicator()
	if get_parent().is_multiplayer_authority():
		_setup_mic_capture()


# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

func _setup_receiver() -> void:
	_voice_receiver = AudioStreamPlayer3D.new()
	_voice_receiver.name = "VoiceReceiver"
	_voice_receiver.max_distance = MAX_VOICE_DIST
	_voice_receiver.unit_size = UNIT_SIZE
	_voice_receiver.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(AudioServer.get_mix_rate())
	gen.buffer_length = 0.5
	_voice_receiver.stream = gen
	add_child(_voice_receiver)
	_voice_receiver.play()
	_generator_playback = _voice_receiver.get_stream_playback() as AudioStreamGeneratorPlayback


func _setup_talk_indicator() -> void:
	_talk_label = Label3D.new()
	_talk_label.name = "TalkIndicator"
	_talk_label.text = "[VOICE]"
	_talk_label.modulate = Color(0.35, 1.0, 0.35)
	_talk_label.font_size = 18
	_talk_label.position = Vector3(0.0, 2.2, 0.0)
	_talk_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_talk_label.visible = false
	add_child(_talk_label)


func _setup_mic_capture() -> void:
	# Avoid duplicate buses if this node is re-added.
	var existing := AudioServer.get_bus_index(MIC_BUS_NAME)
	if existing >= 0:
		_capture_bus_idx = existing
		_capture_effect = AudioServer.get_bus_effect(existing, 0) as AudioEffectCapture
		return

	AudioServer.add_bus()
	_capture_bus_idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_capture_bus_idx, MIC_BUS_NAME)
	# Mute so the speaker does not hear their own mic locally.
	AudioServer.set_bus_mute(_capture_bus_idx, true)

	_capture_effect = AudioEffectCapture.new()
	_capture_effect.buffer_length = 0.5
	AudioServer.add_bus_effect(_capture_bus_idx, _capture_effect)

	var mic_input := AudioStreamPlayer.new()
	mic_input.name = "MicInput"
	mic_input.stream = AudioStreamMicrophone.new()
	mic_input.bus = MIC_BUS_NAME
	mic_input.autoplay = false
	add_child(mic_input)


# ---------------------------------------------------------------------------
# Per-frame logic (authority only)
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not get_parent().is_multiplayer_authority():
		return

	var should_talk := Input.is_physical_key_pressed(KEY_V)

	if should_talk != _talking:
		_talking = should_talk
		var mic := get_node_or_null("MicInput") as AudioStreamPlayer
		if mic:
			if _talking:
				mic.play()
			else:
				mic.stop()
				if _capture_effect:
					_capture_effect.clear_buffer()
		# Notify remote peers so they can show/hide the talking indicator.
		if multiplayer.get_peers().size() > 0:
			rpc("_set_talking_indicator", _talking)

	if not _talking or _capture_effect == null:
		_send_timer = 0.0
		return

	_send_timer += delta
	if _send_timer >= CHUNK_INTERVAL:
		_send_timer -= CHUNK_INTERVAL
		_send_voice_chunk()


func _send_voice_chunk() -> void:
	var available := _capture_effect.get_frames_available()
	if available <= 0:
		return

	# AudioEffectCapture gives stereo Vector2 frames; mix down to mono int16 bytes.
	var frames := _capture_effect.get_buffer(available)
	var bytes := PackedByteArray()
	bytes.resize(available * 2)  # 2 bytes per int16 sample
	for i in available:
		var mono := (frames[i].x + frames[i].y) * 0.5
		bytes.encode_s16(i * 2, clampi(int(mono * 32767.0), -32768, 32767))

	if multiplayer.get_peers().size() > 0:
		rpc("_receive_voice_chunk", bytes)


# ---------------------------------------------------------------------------
# RPCs (executed on remote peers)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_voice_chunk(bytes: PackedByteArray) -> void:
	if _generator_playback == null:
		return
	var sample_count := bytes.size() / 2
	var pcm := PackedVector2Array()
	pcm.resize(sample_count)
	for i in sample_count:
		var f := float(bytes.decode_s16(i * 2)) / 32767.0
		pcm[i] = Vector2(f, f)
	_generator_playback.push_buffer(pcm)


@rpc("authority", "call_remote", "reliable")
func _set_talking_indicator(active: bool) -> void:
	if _talk_label:
		_talk_label.visible = active


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func _exit_tree() -> void:
	# Only clean up the bus if this instance created it (authority peer).
	if _capture_bus_idx < 0:
		return
	var idx := AudioServer.get_bus_index(MIC_BUS_NAME)
	if idx >= 0:
		AudioServer.remove_bus(idx)
	_capture_bus_idx = -1
