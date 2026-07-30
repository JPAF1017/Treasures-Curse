class_name VoiceChat
extends Node3D

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

const CHUNK_INTERVAL       := 0.02    ## Send audio chunks every 20 ms
const MAX_VOICE_DIST       := 40.0    ## Distance where voice fully fades out
const UNIT_SIZE            := 10.0    ## Distance for full-volume playback
const VOICE_VOLUME_DB      := 6.0     ## Extra gain on received voice
const MIC_BUS_NAME         := "VoiceCapture"
const MAX_BYTES_PER_PACKET := 1150    ## Audio bytes per RPC (header adds 4 → total ≤1154, under MTU)
const MIC_GAIN             := 2.5     ## Amplify captured mic signal before sending (raise if quiet)

var _capture_effect: AudioEffectCapture               = null
var _capture_bus_idx: int                             = -1
var _generator_playback: AudioStreamGeneratorPlayback = null
var _current_generator_rate: int                      = 0
var _send_timer: float                                = 0.0
var _voice_receiver: AudioStreamPlayer3D              = null
var _talk_label: Label3D                              = null


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
	_voice_receiver.volume_db = VOICE_VOLUME_DB
	_voice_receiver.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_apply_generator(AudioServer.get_mix_rate())
	add_child(_voice_receiver)
	_voice_receiver.play()
	# get_stream_playback() can return null on the same frame as play(); fetch
	# lazily in _receive_voice_chunk so it is always valid when needed.
	_generator_playback = _voice_receiver.get_stream_playback() as AudioStreamGeneratorPlayback


func _apply_generator(rate: int) -> void:
	## Create (or recreate) the AudioStreamGenerator at the given sample rate.
	## Called on init and whenever the sender's rate differs from ours.
	_current_generator_rate = rate
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(rate)
	gen.buffer_length = 0.8  # Larger buffer absorbs network jitter
	_voice_receiver.stream = gen


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
	mic_input.autoplay = true
	add_child(mic_input)


# ---------------------------------------------------------------------------
# Per-frame logic (authority only)
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not get_parent().is_multiplayer_authority():
		return
	if _capture_effect == null:
		return

	_send_timer += delta
	if _send_timer >= CHUNK_INTERVAL:
		_send_timer -= CHUNK_INTERVAL
		_send_voice_chunk()


func _send_voice_chunk() -> void:
	# Drain the full capture buffer so the receiver stays in sync with real-time.
	var available := _capture_effect.get_frames_available()
	if available <= 0:
		return

	# Mix stereo Vector2 frames down to mono int16 bytes.
	var frames := _capture_effect.get_buffer(available)
	var audio_bytes := PackedByteArray()
	audio_bytes.resize(available * 2)
	for i in available:
		var mono := (frames[i].x + frames[i].y) * 0.5 * MIC_GAIN
		audio_bytes.encode_s16(i * 2, clampi(int(mono * 32767.0), -32768, 32767))

	if not (multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0):
		return

	# Prepend our mix_rate (4 bytes) so the receiver can detect & fix mismatches.
	# Split into MTU-safe packets.
	var rate_header := PackedByteArray()
	rate_header.resize(4)
	rate_header.encode_u32(0, AudioServer.get_mix_rate())

	var offset := 0
	while offset < audio_bytes.size():
		var chunk_size := mini(audio_bytes.size() - offset, MAX_BYTES_PER_PACKET)
		rpc("_receive_voice_chunk", rate_header + audio_bytes.slice(offset, offset + chunk_size))
		offset += chunk_size


# ---------------------------------------------------------------------------
# RPCs (executed on remote peers)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_voice_chunk(packet: PackedByteArray) -> void:
	if packet.size() < 4:
		return
	# Read sender's mix_rate from header; rebuild generator if it differs from ours.
	var sender_rate := packet.decode_u32(0)
	if sender_rate != _current_generator_rate:
		_apply_generator(sender_rate)
		_voice_receiver.play()
		_generator_playback = null
	# Lazily acquire the playback handle.
	if _generator_playback == null and _voice_receiver != null:
		_generator_playback = _voice_receiver.get_stream_playback() as AudioStreamGeneratorPlayback
	if _generator_playback == null:
		return
	var bytes := packet.slice(4)
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
