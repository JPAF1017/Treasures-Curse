extends CharacterBody3D

#variables and constants
const WALK_SPEED = 7.0
const SPRINT_SPEED = 11.0
const CROUCH_SPEED = 3.5
const STAMINA_MAX = 100.0
const STAMINA_WARNING_THRESHOLD = 20.0
const STAMINA_COLOR_NORMAL_INDEX = 18
const STAMINA_COLOR_LOW_INDEX = 17
const HEALTH_MAX = 100.0
const HEALTH_COLOR_NORMAL_INDEX = 23
const STAMINA_PALETTE_PATH = "res://assets/ui/dungeon-pal.png"
const BLOOD_OVERLAY_PATH = "res://assets/ui/BloodOverlay.png"
const DAMAGE_OVERLAY_MAX_ALPHA = 0.7
const DAMAGE_OVERLAY_FADE_TIME = 0.35
const SMOKE_OVERLAY_COLOR := Color(0.75, 0.75, 0.75, 0.55)
const SMOKE_OVERLAY_FADE_SPEED := 3.0
const SMOKE_OVERLAY_TEXTURE_PATH := "res://assets/items assets/smoke.jpeg"
const SMOKE_EFFECT_SCRIPT: Script = preload("res://scripts/items/smoke_effect.gd")
const DAMAGE_TILT_ANGLE_DEG = 20.5
const DAMAGE_TILT_DURATION = 0.35
const JUMP_STAMINA_COST = 20.0
const TIRED_JUMP_HEIGHT_MULTIPLIER = 1.0 / 3.0
const STAMINA_REFILL_DELAY_SECONDS = 5.0
const STAMINA_DRAIN_PER_SECOND = STAMINA_MAX / 7.0
const STAMINA_REFILL_PER_SECOND = STAMINA_MAX / 10.0
const JUMP_VELOCITY = 11
const JUMP_AIR_LOOP_MIN_FRAME = 4
const JUMP_HOLD_FRAME = 16
const JUMP_ANIMATION_FPS = 30.0
const JUMP_AIR_LOOP_SPEED = 0.45
const BUMP_STEP_VELOCITY = 2.2
const BUMP_STEP_COOLDOWN = 0.12
const SENSITIVITY = 0.003
const STUN_SENSITIVITY_MULTIPLIER = 0.08
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5
const POSITION_LOG_INTERVAL = 0.25
const HOTBAR_SLOT_COUNT = 5
const HOTBAR_SELECTED_SCALE = 1.18
const HOTBAR_DEFAULT_SCALE = 1.0
const HOTBAR_ITEM_LABEL_FONT_PATH = "res://assets/ui/dungeon-mode.ttf"
const SHOVEL_ITEM_SCRIPT: Script = preload("res://scripts/items/shovel.gd")
const HEALTH_ITEM_SCRIPT: Script = preload("res://scripts/items/health.gd")
const SMOKE_ITEM_SCRIPT: Script = preload("res://scripts/items/smoke.gd")
const SKULL_KEY_ITEM_SCRIPT: Script = preload("res://scripts/items/skull_key.gd")
const TORCH_ITEM_SCRIPT: Script = preload("res://scripts/items/torch.gd")
const GOLD_ITEM_SCRIPT: Script = preload("res://scripts/items/gold.gd")
const GEM_KEY1_ITEM_SCRIPT: Script = preload("res://scripts/items/gem_key1.gd")
const GEM_KEY2_ITEM_SCRIPT: Script = preload("res://scripts/items/gem_key2.gd")
const GEM_KEY3_ITEM_SCRIPT: Script = preload("res://scripts/items/gem_key3.gd")
const GEM_KEY4_ITEM_SCRIPT: Script = preload("res://scripts/items/gem_key4.gd")
const STEP_SOUND_PATHS := [
	"res://sounds/player/step1.mp3",
	"res://sounds/player/step2.mp3",
	"res://sounds/player/step3.mp3",
	"res://sounds/player/step4.mp3",
	"res://sounds/player/step5.mp3",
]
const CHASE_SOUND_PATHS := [
	"res://sounds/player/chase1.mp3",
]
const CHASE_SHY_SOUND_PATH := "res://sounds/player/chase3.mp3"
const SWING_SOUND_PATH := "res://sounds/player/swing.mp3"
const STEP_ANIM_FPS := 30.0
# Trigger frames for each animation (a step sound fires each time the position crosses one)
const STEP_FRAMES: Dictionary = {
	"walk": [10, 26],
	"walkHold": [10, 26],
	"walkBack": [10, 26],
	"walkBackHold": [10, 26],
	"run": [6, 16],
	"leftStrafe": [10, 26],
	"leftStrafeHold": [10, 26],
	"rightStrafe": [8, 24],
	"rightStrafeHold": [8, 24],
}
@export_range(2.0, 80.0, 0.5) var vision_distance: float = 20.0
@export_range(0.5, 10.0, 0.1) var vision_radius: float = 3.0
@export var debug_position_logs: bool = false
@export var debug_attack_overlap_logs: bool = false
@export var hide_visual_from_player_camera: bool = true
@export_range(-360.0, 360.0, 1.0) var visual_yaw_offset_degrees: float = 180.0
@export var crouch_head_y: float = -0.111
@export_range(1.0, 30.0, 0.5) var crouch_transition_speed: float = 12.0
@export var visual_root_path: NodePath
@export var animation_player_path: NodePath
#------------------------------------------------------
var speed
var t_bob = 0.0
var gravity = 20
var bump_step_timer = 0.0
var position_log_timer = 0.0
var attack_overlap_log_timer = 0.0
var movement_lock_sources: Array[Node] = []
var initial_head_position: Vector3 = Vector3.ZERO
var target_head_y: float = 0.0
var is_crouching: bool = false
var stamina: float = STAMINA_MAX
var stamina_refill_delay_timer: float = 0.0
var health: float = HEALTH_MAX
var previous_health: float = HEALTH_MAX
var is_sprinting: bool = false
var tired_jump_active: bool = false
var jump_phase: int = 0
var jump_air_loop_frame: float = float(JUMP_AIR_LOOP_MIN_FRAME)
var jump_air_loop_forward: bool = true
var stamina_color_normal: Color = Color(1.0, 1.0, 1.0, 1.0)
var stamina_color_low: Color = Color(1.0, 0.3, 0.3, 1.0)
var health_color_normal: Color = Color(1.0, 1.0, 1.0, 1.0)
var stun_timer: float = 0.0

const JUMP_PHASE_NONE = 0
const JUMP_PHASE_ACTIVE = 1
#------------------------------------------------------
@onready var head = $Head
@onready var stand_collision: CollisionShape3D = $Stand
@onready var crouch_collision: CollisionShape3D = $Crouch
@onready var camera = $Head/playerCamera
@onready var vision_collision_shape: CollisionShape3D = $Head/playerCamera/Vision/CollisionShape3D
@onready var attack_area: Area3D = $Attack
@onready var visual_root: Node3D = _resolve_visual_root()
@onready var animation_player: AnimationPlayer = _resolve_animation_player()
@onready var stamina_bar_fill: NinePatchRect = $CanvasLayer/Control/Stamina/StaminaBarContainer
@onready var stamina_label_digit: Label = $CanvasLayer/Control/Stamina/LabelDigit
@onready var health_bar_fill: NinePatchRect = $CanvasLayer/Control/Health/HealthBarContainer
@onready var health_label_digit: Label = $CanvasLayer/Control/Health/LabelDigit
@onready var player_canvas_layer: CanvasLayer = $CanvasLayer
@onready var filter_rect: ColorRect = $CanvasLayer/Filter
@onready var pickup_control: Control = $CanvasLayer/Control/Pickup
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var chase_player: AudioStreamPlayer = $ChasePlayer
@onready var swing_player: AudioStreamPlayer = $SwingPlayer
@onready var hud_control: Control = $CanvasLayer/Control
@onready var loading_control: Control = $CanvasLayer/Loading
@onready var loading_label1: Label = $CanvasLayer/Loading/Label
@onready var loading_label2: Label = $CanvasLayer/Loading/Label2
@onready var loading_label3: Label = $CanvasLayer/Loading/Label3
@onready var loading_label4: Label = $CanvasLayer/Loading/Label4
@onready var warning_control: Control = $CanvasLayer/Warning
@onready var escape_warning_control: Control = $CanvasLayer/EscapeWarning
@onready var key_warning_control: Control = $CanvasLayer/KeyWarning
@onready var key_warning2_control: Control = $CanvasLayer/KeyWarning2
@onready var camera_hint_control: Control = $CanvasLayer/Control/Camera
@onready var sprint_hint_control: Control = $CanvasLayer/Control/Sprint
@onready var item_wheel_control: Control = $CanvasLayer/Control/ItemWheel
@onready var movement_hint_control: Control = $CanvasLayer/Control/Movement
@onready var throw_hint_control: Control = $CanvasLayer/Control/Throw
@onready var use_hint_control: Control = $CanvasLayer/Control/Use
@onready var attack_hint_control: Control = $CanvasLayer/Control/Attack
@onready var grabbed_hint_control: Control = $CanvasLayer/Control/Grabbed

var _game_started: bool = false
var cutscene_active: bool = false
var _map_generated: bool = false
var _loading_label_timer: float = 0.0
const LOADING_LABEL_INTERVAL := 0.5
var _loading_label_index: int = 0
var _warning_timer: float = 0.0
const WARNING_DISPLAY_TIME := 3.0
var _escape_warning_timer: float = 0.0
var _key_warning_timer: float = 0.0
var _key_warning_shown: bool = false
var _key_warning2_timer: float = 0.0
var _key_warning2_shown: bool = false
var _step_sounds: Array = []
var _chase_sounds: Array = []
var _prev_anim_pos: float = -1.0
var _chase_check_timer: float = 0.0
const CHASE_CHECK_INTERVAL := 0.3
const CHASE_FADE_OUT_DURATION := 2.0
var _is_being_chased: bool = false
var _chase_volume_db: float = 0.0
var _chased_by_shy: bool = false
var _shy_chase_sound: AudioStream = null
var _music_resume_position: float = 0.0
var _swing_windup_was_active: bool = false
var _chase_fade_tween: Tween = null
var _net_anim: String = ""
var _net_anim_backwards: bool = false
var _net_held_scene: String = ""
var _prev_net_held_scene: String = ""
var _remote_held_proxy: Node3D = null
var _camera_hint_active: bool = false
var _camera_hint_timer: float = 0.0
const CAMERA_HINT_DURATION := 1.0
var _camera_moved_this_frame: bool = false
var _sprint_hint_shown_once: bool = false
var _sprint_hint_active: bool = false
var _sprint_hint_stamina_consumed: float = 0.0
const SPRINT_HINT_STAMINA_THRESHOLD := 10.0
var _item_wheel_hint_shown_once: bool = false
var _item_wheel_hint_active: bool = false
var _item_wheel_switch_count: int = 0
const ITEM_WHEEL_HINT_SWITCH_THRESHOLD := 4
var _movement_hint_timer: float = 0.0
const MOVEMENT_HINT_DISPLAY_TIME := 10.0
var _throw_hint_dismissed: bool = false
var _throw_hint_timer: float = 0.0
const THROW_HINT_DISPLAY_TIME := 1.0
var _use_hint_dismissed: bool = false
var _attack_hint_dismissed: bool = false
var _grabbed_hint_dismissed: bool = false
var _grabbed_hint_shown: bool = false
const STATUE_SCRIPT_PATH := "res://scripts/npc/statue.gd"
const SHY_SCRIPT_PATH := "res://scripts/npc/shy.gd"
const CHARGER_SCRIPT_PATH := "res://scripts/npc/charger.gd"

const PICKUP_VIS_INTERVAL := 0.1
var _pickup_vis_timer: float = 0.0
var _cached_pickup_candidate: RigidBody3D = null
var _place_item_control: Control = null
var _warning2_control: Control = null

var stamina_bar_initial_scale: Vector2 = Vector2.ONE
var health_bar_initial_scale: Vector2 = Vector2.ONE
var damage_overlay: TextureRect = null
var damage_overlay_tween: Tween = null
var damage_tilt_tween: Tween = null
var smoke_overlay: TextureRect = null
var hotbar_slots: Array[NinePatchRect] = []
var hotbar_slot_base_scales: Array[Vector2] = []
var hotbar_item_icons: Array[TextureRect] = []
var hotbar_item_models: Array[Node3D] = []
var selected_hotbar_slot_index: int = 0
var hotbar_font: FontFile = null

#function on startup
func _ready():
	# In multiplayer, only the authority (local) player gets full HUD/camera/audio setup.
	if not is_multiplayer_authority():
		if camera != null:
			camera.current = false
		if player_canvas_layer != null:
			player_canvas_layer.visible = false
		if footstep_player != null:
			footstep_player.volume_db = -80.0
		if music_player != null:
			music_player.volume_db = -80.0
		if chase_player != null:
			chase_player.volume_db = -80.0
		if swing_player != null:
			swing_player.volume_db = -80.0
		_configure_vision_area()
		if visual_root:
			visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)
			# Do NOT call _configure_player_visual_visibility() here — that would move the
			# remote player's mesh to render layer 2 which the local camera has culled out,
			# making the remote player invisible.  Leave it on layer 1 so everyone can see it.
		# MultiplayerSynchronizer must exist on ALL peers so the non-authority peers
		# receive position/rotation updates. Spawned player2 nodes get it added in
		# _do_spawn() before the MultiplayerSpawner registers them; for the host's
		# embedded player node _ready() creates it here.
		if multiplayer.has_multiplayer_peer() and get_node_or_null("PositionSync") == null:
			_setup_multiplayer_sync()
		return
	# Ensure this player's camera is current (important when spawned at runtime in multiplayer).
	if camera != null:
		camera.current = true
	#detects mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_snap_length = 0.7
	_configure_vision_area()
	# When the host disconnects, send the client back to the start menu.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		multiplayer.server_disconnected.connect(_on_host_disconnected)
	_set_control_mouse_filter_recursive(pickup_control, Control.MOUSE_FILTER_IGNORE)
	initial_head_position = head.position
	target_head_y = initial_head_position.y
	_setup_stamina_ui()
	_setup_health_ui()
	_setup_damage_overlay()
	_setup_smoke_overlay()
	_setup_hotbar_ui()
	_select_hotbar_slot(0)
	# Give player a torch in hotbar slot 1 on startup
	var _torch_scene := preload("res://assets/items/torch.tscn")
	var _torch_instance := _torch_scene.instantiate()
	_torch_instance.name = "PlayerTorch"
	if bool(_torch_instance.call("pick_up_into_hotbar", self, 1)):
		_set_hotbar_item(1, _torch_instance, _torch_instance.call("get_hotbar_icon_texture"))
		_refresh_selected_item_state()
	else:
		push_warning("Failed to add torch to hotbar on startup")
	_update_stamina_ui()
	_update_health_ui()
	_setup_attack_overlap_debug()
	_place_item_control = get_node_or_null("CanvasLayer/Control/PlaceItem") as Control
	_warning2_control = get_node_or_null("CanvasLayer/Warning2") as Control
	for path in STEP_SOUND_PATHS:
		_step_sounds.append(load(path))
	for path in CHASE_SOUND_PATHS:
		_chase_sounds.append(load(path))
	# Use polyphonic stream so each step plays in its own voice and
	# never abruptly cuts the previous one (which causes a click/pop).
	if footstep_player != null:
		var poly := AudioStreamPolyphonic.new()
		poly.polyphony = 4
		footstep_player.stream = poly
		footstep_player.play()
	_shy_chase_sound = load(CHASE_SHY_SOUND_PATH)
	chase_player.finished.connect(_on_chase_sound_finished)
	_chase_volume_db = chase_player.volume_db
	swing_player.stream = load(SWING_SOUND_PATH)	
	# Show loading screen until the player first moves.
	filter_rect.visible = false
	hud_control.visible = false
	loading_control.visible = true
	loading_label1.visible = true
	loading_label2.visible = false
	loading_label3.visible = false
	loading_label4.visible = false
	# Ensure all tutorial hint nodes start hidden.
	if camera_hint_control != null:
		camera_hint_control.visible = false
	if sprint_hint_control != null:
		sprint_hint_control.visible = false
	if item_wheel_control != null:
		item_wheel_control.visible = false
	if throw_hint_control != null:
		throw_hint_control.visible = false
	if use_hint_control != null:
		use_hint_control.visible = false
	if attack_hint_control != null:
		attack_hint_control.visible = false
	if grabbed_hint_control != null:
		grabbed_hint_control.visible = false

	# Connect to dungeon generator's done_generating to show Label4.
	# In multiplayer, player2 spawns AFTER generation is complete so the signal
	# has already fired — detect that and call _on_map_generated() immediately.
	var generator := _find_dungeon_generator(get_tree().root)
	if generator:
		var stage = generator.get("stage")
		# BuildStage.DONE = 5
		if stage != null and int(stage) >= 5:
			_on_map_generated()
		else:
			generator.done_generating.connect(_on_map_generated)
	else:
		_on_map_generated()

	# Initialize player visual rotation.
	if visual_root:
		visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)
		_configure_player_visual_visibility()
	else:
		print("WARNING: Player visual root not found!")

	# Sync position and head rotation to all peers so players can see each other move.
	# Only create if not already added by _do_spawn() (spawned player2 case).
	if multiplayer.has_multiplayer_peer() and get_node_or_null("PositionSync") == null:
		_setup_multiplayer_sync()

func _configure_player_visual_visibility() -> void:
	if visual_root == null or camera == null:
		return

	if hide_visual_from_player_camera:
		# Put player visuals on layer 2 and hide that layer from this camera.
		_set_layer_recursive(visual_root, 2)
		camera.cull_mask = camera.cull_mask & ~2
	else:
		# Keep visuals on default layer so the player model is visible for animation testing.
		_set_layer_recursive(visual_root, 1)
		camera.cull_mask = camera.cull_mask | 1

func _configure_vision_area():
	if vision_collision_shape == null:
		print("WARNING: Vision collision shape not found!")
		return

	var vision_shape = vision_collision_shape.shape as CapsuleShape3D
	if vision_shape == null:
		print("WARNING: Vision shape is not CapsuleShape3D")
		return

	vision_shape.radius = vision_radius
	vision_shape.height = max(vision_distance - (vision_radius * 2.0), 0.1)

	# Rotate the capsule forward and place its center halfway into view distance.
	vision_collision_shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	vision_collision_shape.position = Vector3(0.0, 0.0, -vision_distance * 0.5)

#camera function
func _unhandled_input(event):
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		var sens := SENSITIVITY * STUN_SENSITIVITY_MULTIPLIER if stun_timer > 0.0 else SENSITIVITY
		head.rotate_y(-event.relative.x * sens)
		camera.rotate_x(-event.relative.y * sens)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(90))
		_sync_visual_rotation_to_head()
		if _camera_hint_active:
			_camera_moved_this_frame = true
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if stamina <= 0.0:
					return
				var selected_item := _get_selected_primary_item()
				if selected_item != null and (_is_gem_key_item_model(selected_item) or (selected_item.get_meta("puzzle_item", false) and not CandlePuzzleRoom.puzzle_door_opened)):
					if warning_control != null:
						warning_control.visible = true
						_warning_timer = WARNING_DISPLAY_TIME
					return
				if selected_item == null or not bool(selected_item.call("begin_primary_action", self)):
					return
				if not _use_hint_dismissed and not selected_item.get_meta("puzzle_item", false) and (_is_health_item_model(selected_item) or _is_smoke_item_model(selected_item)):
					_use_hint_dismissed = true
					if use_hint_control != null:
						use_hint_control.visible = false
				if not _attack_hint_dismissed and not selected_item.get_meta("puzzle_item", false) and (selected_item is Sword or selected_item is Bat or _is_shovel_item_model(selected_item)):
					_attack_hint_dismissed = true
					if attack_hint_control != null:
						attack_hint_control.visible = false
			else:
				var selected_item := _get_selected_primary_item()
				if selected_item:
					selected_item.call("release_primary_action", self)
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_select_hotbar_slot((selected_hotbar_slot_index - 1 + HOTBAR_SLOT_COUNT) % HOTBAR_SLOT_COUNT)
				_on_item_wheel_slot_switched()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_select_hotbar_slot((selected_hotbar_slot_index + 1) % HOTBAR_SLOT_COUNT)
				_on_item_wheel_slot_switched()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			var had_item := _get_selected_hotbar_item() != null
			_drop_selected_hotbar_item()
			if had_item and not _throw_hint_dismissed:
				_throw_hint_dismissed = true
				if throw_hint_control != null:
					throw_hint_control.visible = false
			return

		var slot_index := _hotbar_index_from_keycode(event.keycode)
		if slot_index != -1:
			_select_hotbar_slot(slot_index)
			_on_item_wheel_slot_switched()

#movement function
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer():
		# Guard against calling is_multiplayer_authority() while the peer is still
		# connecting — that state causes a "multiplayer instance isn't active" spam.
		var peer := multiplayer.multiplayer_peer
		if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		if not is_multiplayer_authority():
			# Keep remote player's visual model facing the synced head direction.
			if visual_root:
				visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)
			# Apply the synced animation state from the authority peer.
			if animation_player and not _net_anim.is_empty():
				if _net_anim_backwards:
					if animation_player.current_animation != _net_anim or animation_player.speed_scale > 0.0:
						animation_player.play_backwards(_net_anim)
				else:
					if animation_player.current_animation != _net_anim or animation_player.speed_scale < 0.0:
						animation_player.play(_net_anim)
			# Update the held-item visual proxy when the equipped scene changes.
			if _net_held_scene != _prev_net_held_scene:
				_prev_net_held_scene = _net_held_scene
				_update_remote_held_proxy()
			return
	bump_step_timer = max(bump_step_timer - delta, 0.0)
	position_log_timer = max(position_log_timer - delta, 0.0)
	attack_overlap_log_timer = max(attack_overlap_log_timer - delta, 0.0)
	stun_timer = max(stun_timer - delta, 0.0)
	_pickup_vis_timer = max(_pickup_vis_timer - delta, 0.0)
	if movement_hint_control != null and movement_hint_control.visible:
		_movement_hint_timer -= delta
		if _movement_hint_timer <= 0.0:
			movement_hint_control.visible = false
	if throw_hint_control != null and throw_hint_control.visible and not _throw_hint_dismissed:
		_throw_hint_timer -= delta
		if _throw_hint_timer <= 0.0:
			throw_hint_control.visible = false
			_throw_hint_dismissed = true
	if _camera_hint_active:
		var cam_moved := _camera_moved_this_frame
		_camera_moved_this_frame = false
		if cam_moved:
			_camera_hint_timer += delta
			if _camera_hint_timer >= CAMERA_HINT_DURATION:
				_camera_hint_active = false
				if camera_hint_control != null:
					camera_hint_control.visible = false
				if not _item_wheel_hint_shown_once:
					_item_wheel_hint_shown_once = true
					_item_wheel_hint_active = true
					if item_wheel_control != null:
						item_wheel_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
						item_wheel_control.visible = true
	if _warning_timer > 0.0:
		_warning_timer -= delta
		if _warning_timer <= 0.0 and warning_control != null:
			warning_control.visible = false
	if _escape_warning_timer > 0.0:
		_escape_warning_timer -= delta
		if _escape_warning_timer <= 0.0 and escape_warning_control != null:
			escape_warning_control.visible = false
	if _key_warning_timer > 0.0:
		_key_warning_timer -= delta
		if _key_warning_timer <= 0.0 and key_warning_control != null:
			key_warning_control.visible = false
	if _key_warning2_timer > 0.0:
		_key_warning2_timer -= delta
		if _key_warning2_timer <= 0.0 and key_warning2_control != null:
			key_warning2_control.visible = false
	_update_smoke_overlay(delta)

	# Freeze all NPCs and show loading until the player first moves.
	if not _game_started:
		if not _map_generated:
			_loading_label_timer += delta
			if _loading_label_timer >= LOADING_LABEL_INTERVAL:
				_loading_label_timer = 0.0
				_loading_label_index = (_loading_label_index + 1) % 3
				loading_label1.visible = _loading_label_index == 0
				loading_label2.visible = _loading_label_index == 1
				loading_label3.visible = _loading_label_index == 2
		var move_input := Input.get_vector("a", "d", "w", "s")
		var jump_input := Input.is_action_just_pressed("ui_accept")
		if not cutscene_active and (move_input != Vector2.ZERO or jump_input):
			_game_started = true
			filter_rect.visible = true
			hud_control.visible = true
			loading_control.visible = false
			if camera_hint_control != null:
				camera_hint_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
				camera_hint_control.visible = true
				_camera_hint_active = true
			music_player.play()
			# Unfreeze all NPCs by restoring inherited process mode.
			for npc in _get_all_npcs():
				npc.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			# Keep NPCs frozen while waiting.
			for npc in _get_all_npcs():
				npc.process_mode = Node.PROCESS_MODE_DISABLED
			return
	var is_movement_locked := _is_movement_locked() or stun_timer > 0.0
	var input_dir := Vector2.ZERO
	if not is_movement_locked:
		input_dir = Input.get_vector("a", "d", "w", "s")
		if input_dir != Vector2.ZERO:
			GameStats.start_timer()

	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_crouch_state(Input.is_action_pressed("Ctrl"))
	_update_head_height(delta)
#------------------------------------------------------
#jump input
	var jump_pressed := not is_movement_locked and Input.is_action_just_pressed("ui_accept")
	if jump_pressed and is_on_floor():
		if stamina >= JUMP_STAMINA_COST:
			stamina = max(stamina - JUMP_STAMINA_COST, 0.0)
			if stamina <= 0.0:
				stamina_refill_delay_timer = STAMINA_REFILL_DELAY_SECONDS
			tired_jump_active = false
			jump_phase = JUMP_PHASE_ACTIVE
			velocity.y = JUMP_VELOCITY
			jump_air_loop_frame = float(JUMP_AIR_LOOP_MIN_FRAME)
			jump_air_loop_forward = true
			if animation_player and animation_player.has_animation("jump"):
				animation_player.play("jump")
				animation_player.seek(0.0, true)
		else:
			# Tired jump: reduced jump height and no jump animation.
			if stamina > 0.0:
				stamina = 0.0
				stamina_refill_delay_timer = STAMINA_REFILL_DELAY_SECONDS
			tired_jump_active = true
			jump_phase = JUMP_PHASE_NONE
			velocity.y = JUMP_VELOCITY * TIRED_JUMP_HEIGHT_MULTIPLIER
#------------------------------------------------------
#sprint input
	# Sprint is only valid while moving forward (including forward diagonals) and not crouching.
	var sprint_input := not is_movement_locked and Input.is_action_pressed("shift")
	var can_sprint := input_dir.y < 0.0 and not is_crouching
	is_sprinting = false
	if tired_jump_active:
		speed = CROUCH_SPEED
	elif is_crouching:
		speed = CROUCH_SPEED
	elif sprint_input and can_sprint and stamina > 0.0:
		is_sprinting = true
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	if is_sprinting:
		var drain: float = STAMINA_DRAIN_PER_SECOND * delta
		stamina = max(stamina - drain, 0.0)
		if stamina <= 0.0:
			stamina_refill_delay_timer = STAMINA_REFILL_DELAY_SECONDS
			is_sprinting = false
			speed = WALK_SPEED
		if _sprint_hint_active:
			_sprint_hint_stamina_consumed += drain
			if _sprint_hint_stamina_consumed >= SPRINT_HINT_STAMINA_THRESHOLD:
				_sprint_hint_active = false
				if sprint_hint_control != null:
					sprint_hint_control.visible = false

	if stamina_refill_delay_timer > 0.0:
		stamina_refill_delay_timer = max(stamina_refill_delay_timer - delta, 0.0)
	elif not is_sprinting:
		stamina = min(stamina + STAMINA_REFILL_PER_SECOND * delta, STAMINA_MAX)
	_update_pickup_prompt_visibility()
	_refresh_selected_item_state()
	_update_hotbar_windup_indicator()
	_update_stamina_ui()
#------------------------------------------------------
#wasd direction input and other physics
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Animation handling
	if animation_player:
		var swing_anim_active := _update_selected_item_action(delta)
		_update_swing_sound(swing_anim_active)
		var jump_anim_active := _update_jump_animation_phase(delta)
		var is_walking_forward := input_dir.y < 0.0
		var is_walking_backward := input_dir.y > 0.0
		var is_strafing_left := input_dir.x < 0.0
		var is_strafing_right := input_dir.x > 0.0
		var wants_run := is_sprinting
		var grounded_animation_state := is_on_floor() or tired_jump_active
		var _sel_item := _get_selected_hotbar_item()
		var _hold_item := _is_health_item_model(_sel_item) or _is_gold_item_model(_sel_item)
		if swing_anim_active:
			pass
		elif jump_anim_active:
			pass
		elif grounded_animation_state:
			if is_crouching:
				if is_walking_forward and animation_player.has_animation("crouchWalk"):
					var _anim := "crouchWalkHold" if _hold_item and animation_player.has_animation("crouchWalkHold") else "crouchWalk"
					if animation_player.current_animation != _anim or animation_player.speed_scale < 0.0:
						animation_player.play(_anim)
				elif is_walking_backward and animation_player.has_animation("crouchWalk"):
					var _anim := "crouchWalkBackHold" if _hold_item and animation_player.has_animation("crouchWalkBackHold") else "crouchWalk"
					if _hold_item and animation_player.has_animation("crouchWalkBackHold"):
						if animation_player.current_animation != _anim:
							animation_player.play(_anim)
					else:
						if animation_player.current_animation != _anim or animation_player.speed_scale > 0.0:
							animation_player.play_backwards(_anim)
				elif is_strafing_right and animation_player.has_animation("crouchStrafeRight"):
					var _anim := "crouchStrafeRightHold" if _hold_item and animation_player.has_animation("crouchStrafeRightHold") else "crouchStrafeRight"
					if animation_player.current_animation != _anim:
						animation_player.play(_anim)
				elif is_strafing_left and animation_player.has_animation("crouchStrafeLeft"):
					var _anim := "crouchStrafeLeftHold" if _hold_item and animation_player.has_animation("crouchStrafeLeftHold") else "crouchStrafeLeft"
					if animation_player.current_animation != _anim:
						animation_player.play(_anim)
				else:
					var _anim := "crouchIdleHold" if _hold_item and animation_player.has_animation("crouchIdleHold") else "crouchIdle"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
			elif animation_player.has_animation("walk"):
				if is_walking_forward:
					if wants_run and animation_player.has_animation("run"):
						if animation_player.current_animation != "run":
							animation_player.play("run")
					else:
						var _anim := "walkHold" if _hold_item and animation_player.has_animation("walkHold") else "walk"
						if animation_player.current_animation != _anim or animation_player.speed_scale < 0.0:
							animation_player.play(_anim)
				elif is_walking_backward:
					var _anim := "walkBackHold" if _hold_item and animation_player.has_animation("walkBackHold") else "walk"
					if _hold_item and animation_player.has_animation("walkBackHold"):
						if animation_player.current_animation != _anim:
							animation_player.play(_anim)
					else:
						if animation_player.current_animation != _anim or animation_player.speed_scale > 0.0:
							animation_player.play_backwards(_anim)
				elif is_strafing_left:
					var _anim := "leftStrafeHold" if _hold_item and animation_player.has_animation("leftStrafeHold") else "leftStrafe"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
				elif is_strafing_right:
					var _anim := "rightStrafeHold" if _hold_item and animation_player.has_animation("rightStrafeHold") else "rightStrafe"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
				else:
					var _anim := "idleHold" if _hold_item and animation_player.has_animation("idleHold") else "idle"
					if animation_player.has_animation(_anim) and animation_player.current_animation != _anim:
						animation_player.play(_anim)
		elif animation_player.has_animation("jump") and jump_phase != JUMP_PHASE_NONE:
			if animation_player.current_animation != "jump":
				animation_player.play("jump")
		elif animation_player.has_animation("idle") and animation_player.current_animation != "idle":
			# Fallback when no jump animation exists.
			animation_player.play("idle")
		# Broadcast the current animation state so remote peers can mirror it.
		_net_anim = animation_player.current_animation
		_net_anim_backwards = animation_player.speed_scale < 0.0
	
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 2.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 2.0)
#------------------------------------------------------
#headbob during movement
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)
#------------------------------------------------------
#fov changing
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	_sync_visual_rotation_to_head()

	# Step up tiny bumps while moving so movement stays smooth on uneven floors.
	# Only step up against static geometry, not against NPCs or other characters.
	if input_dir != Vector2.ZERO and is_on_floor() and is_on_wall() and velocity.y <= 0.0 and bump_step_timer <= 0.0:
		if not _is_wall_collision_with_character():
			velocity.y = BUMP_STEP_VELOCITY
			bump_step_timer = BUMP_STEP_COOLDOWN
	
	move_and_slide()
	if tired_jump_active and is_on_floor():
		tired_jump_active = false
	_try_auto_equip_item()
	_log_player_position()
	_log_attack_overlap_snapshot()
	_update_footsteps()
	_update_chase_sound(delta)

func _setup_attack_overlap_debug() -> void:
	if attack_area == null:
		return

	if not attack_area.area_entered.is_connected(_on_attack_area_entered):
		attack_area.area_entered.connect(_on_attack_area_entered)
	if not attack_area.area_exited.is_connected(_on_attack_area_exited):
		attack_area.area_exited.connect(_on_attack_area_exited)
	if not attack_area.body_entered.is_connected(_on_attack_body_entered):
		attack_area.body_entered.connect(_on_attack_body_entered)
	if not attack_area.body_exited.is_connected(_on_attack_body_exited):
		attack_area.body_exited.connect(_on_attack_body_exited)

	print("[AttackDebug] attack area ready monitoring=%s monitorable=%s layer=%d mask=%d" % [
		str(attack_area.monitoring),
		str(attack_area.monitorable),
		attack_area.collision_layer,
		attack_area.collision_mask,
	])

func _on_attack_area_entered(area: Area3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if area == null:
		return
	print("[AttackDebug] area entered: %s parent=%s" % [area.name, area.get_parent().name if area.get_parent() else &"<none>"])

func _on_attack_area_exited(area: Area3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if area == null:
		return
	print("[AttackDebug] area exited: %s parent=%s" % [area.name, area.get_parent().name if area.get_parent() else &"<none>"])

func _on_attack_body_entered(body: Node3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if body == null:
		return
	print("[AttackDebug] body entered: %s" % body.name)

func _on_attack_body_exited(body: Node3D) -> void:
	if not debug_attack_overlap_logs:
		return
	if body == null:
		return
	print("[AttackDebug] body exited: %s" % body.name)

func _log_attack_overlap_snapshot() -> void:
	if not debug_attack_overlap_logs:
		return
	if attack_area == null:
		return
	if attack_overlap_log_timer > 0.0:
		return

	attack_overlap_log_timer = 0.25
	var overlapping_areas := attack_area.get_overlapping_areas()
	var overlapping_bodies := attack_area.get_overlapping_bodies()
	var knight_hurtbox_overlap := false

	for area in overlapping_areas:
		if area == null:
			continue
		var parent := area.get_parent()
		if area.name.to_lower().contains("hurtbox") or (parent and parent.name.to_lower().contains("knight")):
			knight_hurtbox_overlap = true
			break

	print("[AttackDebug] snapshot areas=%d bodies=%d knight_hurtbox_overlap=%s" % [
		overlapping_areas.size(),
		overlapping_bodies.size(),
		str(knight_hurtbox_overlap),
	])

func set_movement_locked_by(locker: Node, locked: bool) -> void:
	if locker == null:
		return

	if locked:
		if not movement_lock_sources.has(locker):
			movement_lock_sources.append(locker)
		if not _grabbed_hint_dismissed and locker.is_in_group("gnome"):
			_grabbed_hint_shown = true
			if grabbed_hint_control != null:
				grabbed_hint_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grabbed_hint_control.visible = true
	else:
		movement_lock_sources.erase(locker)
		if _grabbed_hint_shown and not _grabbed_hint_dismissed and locker.is_in_group("gnome"):
			_grabbed_hint_dismissed = true
			if grabbed_hint_control != null:
				grabbed_hint_control.visible = false

func _is_movement_locked() -> bool:
	return movement_lock_sources.size() > 0

func is_movement_locked_by_other(locker: Node) -> bool:
	for source in movement_lock_sources:
		if source != locker:
			return true
	return false

func _is_wall_collision_with_character() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() is CharacterBody3D:
			var normal := collision.get_normal()
			if absf(normal.y) < 0.5:
				return true
	return false

#function for head bob
func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

func _format_vec3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _update_crouch_state(wants_crouch: bool) -> void:
	if wants_crouch and not is_crouching:
		_enter_crouch()
	elif not wants_crouch and is_crouching:
		_exit_crouch()

func _enter_crouch() -> void:
	if crouch_collision:
		crouch_collision.disabled = false
	if stand_collision:
		stand_collision.disabled = true
	target_head_y = crouch_head_y
	is_crouching = true

func _exit_crouch() -> void:
	if stand_collision:
		stand_collision.disabled = false
	if crouch_collision:
		crouch_collision.disabled = true
	target_head_y = initial_head_position.y
	is_crouching = false

func _update_head_height(delta: float) -> void:
	if head == null:
		return

	head.position.y = lerp(head.position.y, target_head_y, delta * crouch_transition_speed)
	if abs(head.position.y - target_head_y) < 0.001:
		head.position.y = target_head_y

func _setup_stamina_ui() -> void:
	_setup_stamina_palette_colors()

	if stamina_bar_fill == null:
		return

	stamina_bar_initial_scale = stamina_bar_fill.scale
	stamina_bar_fill.pivot_offset = Vector2(0.0, stamina_bar_fill.size.y * 0.5)

func _setup_health_ui() -> void:
	_setup_health_palette_colors()

	if health_bar_fill == null:
		return

	health_bar_initial_scale = health_bar_fill.scale
	health_bar_fill.pivot_offset = Vector2(0.0, health_bar_fill.size.y * 0.5)

func _update_stamina_ui() -> void:
	var stamina_points: int = int(round(clampf(stamina, 0.0, STAMINA_MAX)))
	var active_color: Color = stamina_color_normal if stamina_points >= int(STAMINA_WARNING_THRESHOLD) else stamina_color_low

	if stamina_label_digit != null:
		stamina_label_digit.text = str(stamina_points)
		stamina_label_digit.modulate = active_color

	if stamina_bar_fill == null:
		return

	var stamina_ratio: float = clampf(stamina / STAMINA_MAX, 0.0, 1.0)
	stamina_bar_fill.scale = Vector2(stamina_bar_initial_scale.x * stamina_ratio, stamina_bar_initial_scale.y)
	stamina_bar_fill.modulate = active_color

func _update_health_ui() -> void:
	if health < previous_health - 0.001:
		_show_damage_overlay()

	var health_points: int = int(round(clampf(health, 0.0, HEALTH_MAX)))

	if health_label_digit != null:
		health_label_digit.text = str(health_points)
		health_label_digit.modulate = health_color_normal

	if health_bar_fill == null:
		return

	var health_ratio: float = clampf(health / HEALTH_MAX, 0.0, 1.0)
	health_bar_fill.scale = Vector2(health_bar_initial_scale.x * health_ratio, health_bar_initial_scale.y)
	health_bar_fill.modulate = health_color_normal
	previous_health = health

func _setup_smoke_overlay() -> void:
	var smoke_canvas := CanvasLayer.new()
	smoke_canvas.name = "SmokeOverlayLayer"
	smoke_canvas.layer = 0
	add_child(smoke_canvas)
	smoke_overlay = TextureRect.new()
	smoke_overlay.name = "SmokeOverlay"
	var smoke_tex := load(SMOKE_OVERLAY_TEXTURE_PATH) as Texture2D
	if smoke_tex:
		smoke_overlay.texture = smoke_tex
	smoke_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	smoke_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	smoke_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	smoke_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	smoke_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = load("res://assets/items/smoke_overlay.gdshader") as Shader
	smoke_overlay.material = smoke_mat
	smoke_canvas.add_child(smoke_overlay)


func _update_smoke_overlay(delta: float) -> void:
	if smoke_overlay == null:
		return
	var inside := false
	for effect in SMOKE_EFFECT_SCRIPT.active_effects:
		if not is_instance_valid(effect):
			continue
		var dist := global_position.distance_to(effect.global_position)
		if dist < effect.get_world_radius():
			inside = true
			break
	var target_alpha := SMOKE_OVERLAY_COLOR.a if inside else 0.0
	var current_alpha := smoke_overlay.modulate.a
	smoke_overlay.modulate.a = move_toward(current_alpha, target_alpha, SMOKE_OVERLAY_FADE_SPEED * delta)


func _setup_damage_overlay() -> void:
	previous_health = health
	if player_canvas_layer == null:
		return

	var blood_texture := load(BLOOD_OVERLAY_PATH) as Texture2D
	if blood_texture == null:
		push_warning("Blood overlay texture not found at: %s" % BLOOD_OVERLAY_PATH)
		return

	damage_overlay = TextureRect.new()
	damage_overlay.name = "DamageOverlay"
	damage_overlay.texture = blood_texture
	damage_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_overlay.z_index = 100
	player_canvas_layer.add_child(damage_overlay)

func _show_damage_overlay() -> void:
	if damage_overlay == null:
		return

	if damage_overlay_tween:
		damage_overlay_tween.kill()

	var color := damage_overlay.modulate
	color.a = DAMAGE_OVERLAY_MAX_ALPHA
	damage_overlay.modulate = color

	damage_overlay_tween = create_tween()
	damage_overlay_tween.tween_property(damage_overlay, "modulate:a", 0.0, DAMAGE_OVERLAY_FADE_TIME)

func _setup_hotbar_ui() -> void:
	hotbar_font = load(HOTBAR_ITEM_LABEL_FONT_PATH) as FontFile
	hotbar_slots = [
		$CanvasLayer/Control/Hotbar/Slot1,
		$CanvasLayer/Control/Hotbar/Slot2,
		$CanvasLayer/Control/Hotbar/Slot3,
		$CanvasLayer/Control/Hotbar/Slot4,
		$CanvasLayer/Control/Hotbar/Slot5,
	]
	hotbar_slot_base_scales.clear()
	hotbar_item_icons.clear()
	hotbar_item_models = []

	for slot in hotbar_slots:
		slot.pivot_offset = slot.size * 0.5
		hotbar_slot_base_scales.append(slot.scale)
		hotbar_item_models.append(null)
		var item_icon := slot.get_node_or_null("ItemIcon") as TextureRect
		if item_icon == null:
			item_icon = TextureRect.new()
			item_icon.name = "ItemIcon"
			item_icon.anchor_left = 0.0
			item_icon.anchor_top = 0.0
			item_icon.anchor_right = 1.0
			item_icon.anchor_bottom = 1.0
			item_icon.offset_left = 4.0
			item_icon.offset_top = 4.0
			item_icon.offset_right = -4.0
			item_icon.offset_bottom = -4.0
			item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(item_icon)
		item_icon.texture = null
		item_icon.visible = false
		hotbar_item_icons.append(item_icon)

func _select_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_slots.size():
		return

	selected_hotbar_slot_index = slot_index
	for i in hotbar_slots.size():
		var slot := hotbar_slots[i]
		var base_scale := hotbar_slot_base_scales[i] if i < hotbar_slot_base_scales.size() else Vector2.ONE
		slot.scale = base_scale * (HOTBAR_SELECTED_SCALE if i == selected_hotbar_slot_index else HOTBAR_DEFAULT_SCALE)

	_refresh_selected_item_state()
	_update_hotbar_windup_indicator()
	if not _throw_hint_dismissed:
		var item := hotbar_item_models[selected_hotbar_slot_index] if selected_hotbar_slot_index < hotbar_item_models.size() else null
		var has_item := item != null and is_instance_valid(item)
		var kw2_active := key_warning2_control != null and key_warning2_control.visible
		if throw_hint_control != null:
			if has_item and not kw2_active and not throw_hint_control.visible:
				throw_hint_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
				throw_hint_control.visible = true
				_throw_hint_timer = THROW_HINT_DISPLAY_TIME
			elif (not has_item or kw2_active) and throw_hint_control.visible:
				throw_hint_control.visible = false
	if not _use_hint_dismissed:
		var item := hotbar_item_models[selected_hotbar_slot_index] if selected_hotbar_slot_index < hotbar_item_models.size() else null
		var throw_active := throw_hint_control != null and throw_hint_control.visible
		var kw2_active := key_warning2_control != null and key_warning2_control.visible
		var has_usable: bool = not throw_active and not kw2_active and item != null and is_instance_valid(item) and not item.get_meta("puzzle_item", false) and (_is_health_item_model(item) or _is_smoke_item_model(item))
		if use_hint_control != null:
			if has_usable and not use_hint_control.visible:
				use_hint_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
				use_hint_control.visible = true
			elif not has_usable and use_hint_control.visible:
				use_hint_control.visible = false
	if not _attack_hint_dismissed:
		var item := hotbar_item_models[selected_hotbar_slot_index] if selected_hotbar_slot_index < hotbar_item_models.size() else null
		var throw_active := throw_hint_control != null and throw_hint_control.visible
		var kw2_active := key_warning2_control != null and key_warning2_control.visible
		var has_weapon: bool = not throw_active and not kw2_active and item != null and is_instance_valid(item) and not item.get_meta("puzzle_item", false) and (item is Sword or item is Bat or _is_shovel_item_model(item))
		if attack_hint_control != null:
			if has_weapon and not attack_hint_control.visible:
				attack_hint_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
				attack_hint_control.visible = true
			elif not has_weapon and attack_hint_control.visible:
				attack_hint_control.visible = false

func _hotbar_index_from_keycode(keycode: int) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		_:
			return -1

func _set_hotbar_item(slot_index: int, item_model: Node3D, item_icon_texture: Texture2D) -> void:
	if slot_index < 0 or slot_index >= hotbar_item_models.size():
		return

	hotbar_item_models[slot_index] = item_model
	var item_icon := hotbar_item_icons[slot_index] if slot_index < hotbar_item_icons.size() else null
	if item_icon:
		item_icon.texture = item_icon_texture
		item_icon.visible = item_icon_texture != null

func _find_first_empty_hotbar_slot() -> int:
	for i in hotbar_item_models.size():
		var item_model := hotbar_item_models[i]
		if item_model == null or not is_instance_valid(item_model):
			return i
	return -1

func _get_selected_hotbar_item() -> Node3D:
	if selected_hotbar_slot_index < 0 or selected_hotbar_slot_index >= hotbar_item_models.size():
		return null

	var selected_item := hotbar_item_models[selected_hotbar_slot_index]
	if selected_item == null or not is_instance_valid(selected_item):
		return null

	return selected_item

func _is_primary_item_model(item_model: Node) -> bool:
	return item_model is Sword or item_model is Bat or _is_shovel_item_model(item_model) or _is_health_item_model(item_model) or _is_smoke_item_model(item_model) or _is_skull_key_item_model(item_model) or _is_torch_item_model(item_model) or _is_gold_item_model(item_model) or _is_gem_key_item_model(item_model)

func _is_shovel_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == SHOVEL_ITEM_SCRIPT

func _is_health_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == HEALTH_ITEM_SCRIPT

func _is_smoke_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == SMOKE_ITEM_SCRIPT

func _is_skull_key_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == SKULL_KEY_ITEM_SCRIPT

func _is_torch_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == TORCH_ITEM_SCRIPT

func _is_gold_item_model(item_model: Node) -> bool:
	return item_model != null and item_model.get_script() == GOLD_ITEM_SCRIPT

func _is_gem_key_item_model(item_model: Node) -> bool:
	if item_model == null:
		return false
	var s: Variant = item_model.get_script()
	return s == GEM_KEY1_ITEM_SCRIPT or s == GEM_KEY2_ITEM_SCRIPT or s == GEM_KEY3_ITEM_SCRIPT or s == GEM_KEY4_ITEM_SCRIPT

func _get_selected_primary_item() -> Node:
	var selected_item := _get_selected_hotbar_item()
	if _is_primary_item_model(selected_item):
		return selected_item
	return null

func _has_item_in_hotbar(item: Node) -> bool:
	if item == null:
		return false

	for hotbar_item in hotbar_item_models:
		if hotbar_item == item and is_instance_valid(hotbar_item):
			return true
	return false

func _refresh_selected_item_state() -> void:
	for item_model in hotbar_item_models:
		if _is_primary_item_model(item_model) and is_instance_valid(item_model):
			item_model.call("refresh_inventory_state", self, selected_hotbar_slot_index, is_sprinting)
	# Broadcast the currently held item scene path so remote peers can show a visual proxy.
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		var held := _get_selected_hotbar_item()
		_net_held_scene = held.scene_file_path if held != null and is_instance_valid(held) else ""

func _update_selected_item_action(delta: float) -> bool:
	var selected_item := _get_selected_primary_item()
	if selected_item == null:
		return false

	return bool(selected_item.call("update_primary_action", self, delta))

func _can_trigger_swing_from_selected_slot() -> bool:
	var selected_item := _get_selected_primary_item()
	return selected_item != null and bool(selected_item.call("can_start_primary_action"))

func _get_item_display_name_from_model(item_node: Node) -> String:
	if item_node == null:
		return "Item"

	var raw_name := item_node.name
	if raw_name.is_empty():
		return "Item"

	var words := raw_name.replace("-", " ").replace("_", " ").split(" ", false)
	if words.is_empty():
		return raw_name

	for i in words.size():
		words[i] = words[i].capitalize()

	return " ".join(words)

func _drop_selected_hotbar_item() -> void:
	var selected_item := _get_selected_hotbar_item()
	if selected_item == null:
		return

	if _is_primary_item_model(selected_item):
		var scene_path := selected_item.scene_file_path
		# Capture burning state BEFORE drop_from_hotbar resets it.
		var was_burning: bool = bool(selected_item.get("is_burning")) if selected_item.get("is_burning") != null else false
		# Capture name BEFORE reparenting so we know the world-scene name the remote must use.
		var drop_item_name: String = selected_item.name
		if bool(selected_item.call("drop_from_hotbar", self)):
			_set_hotbar_item(selected_hotbar_slot_index, null, null)
			_refresh_selected_item_state()
			_pickup_vis_timer = 0.0
			_update_pickup_prompt_visibility()
			if multiplayer.has_multiplayer_peer() and not scene_path.is_empty():
				var drop_pos := (selected_item as Node3D).global_position
				var drop_vel := Vector3.ZERO
				if selected_item is RigidBody3D:
					drop_vel = selected_item.linear_velocity
				var is_puzzle_item: bool = selected_item.get_meta("puzzle_item", false)
				rpc("_sync_item_dropped", scene_path, drop_pos, drop_vel, is_puzzle_item, was_burning, drop_item_name)
	else:
		push_warning("Drop not implemented for selected item model: %s" % selected_item.name)


func _pickup_item_into_hotbar(item_body: Node3D) -> void:
	if item_body == null:
		return

	if item_body is Sword or item_body is Bat or _is_shovel_item_model(item_body) or _is_health_item_model(item_body) or _is_smoke_item_model(item_body) or _is_skull_key_item_model(item_body) or _is_torch_item_model(item_body) or _is_gold_item_model(item_body) or _is_gem_key_item_model(item_body):
		if _has_item_in_hotbar(item_body):
			return

		var slot_index := _find_first_empty_hotbar_slot()
		if slot_index == -1:
			push_warning("Hotbar is full. Cannot pick up item.")
			return

		var item_world_path := str(item_body.get_path())
		# If the item was spawned by the MultiplayerSpawner it will auto-despawn on
		# all peers when reparented away from the spawner's spawn_path — sending
		# _sync_item_removed as well causes a double-free that breaks the spawner's
		# net_id tracking for future spawns. Only send the RPC for loose items that
		# the spawner doesn't know about (e.g. previously dropped items).
		var is_spawner_managed: bool = item_body.get_meta("spawner_managed", false)
		if is_spawner_managed:
			item_body.remove_meta("spawner_managed")
		if bool(item_body.call("pick_up_into_hotbar", self, slot_index)):
			if multiplayer.has_multiplayer_peer() and not is_spawner_managed:
				rpc("_sync_item_removed", item_world_path)
			_set_hotbar_item(slot_index, item_body, item_body.call("get_hotbar_icon_texture"))
			_refresh_selected_item_state()
			_pickup_vis_timer = 0.0
			_update_pickup_prompt_visibility()
			if not _key_warning_shown and _is_gold_item_model(item_body):
				_key_warning_shown = true
				if key_warning_control != null:
					key_warning_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
					key_warning_control.visible = true
					_key_warning_timer = WARNING_DISPLAY_TIME
			if not _key_warning2_shown and item_body.get_meta("puzzle_item", false):
				_key_warning2_shown = true
				if key_warning2_control != null:
					key_warning2_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
					key_warning2_control.visible = true
					_key_warning2_timer = WARNING_DISPLAY_TIME
	else:
		push_warning("Pickup not implemented for item model: %s" % item_body.name)

func _try_auto_equip_item() -> void:
	if _find_first_empty_hotbar_slot() == -1:
		return
	if not (Sword.is_equip_input_just_pressed() or bool(SHOVEL_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(HEALTH_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(SMOKE_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(SKULL_KEY_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(TORCH_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(GOLD_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(GEM_KEY1_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(GEM_KEY2_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(GEM_KEY3_ITEM_SCRIPT.call("is_equip_input_just_pressed")) or bool(GEM_KEY4_ITEM_SCRIPT.call("is_equip_input_just_pressed"))):
		return

	var item_body := _get_pickup_candidate()
	if item_body == null:
		return

	_pickup_item_into_hotbar(item_body)

func _set_visual_children_visible(node: Node, visibility: bool) -> void:
	if node is VisualInstance3D:
		node.visible = visibility
	for child in node.get_children():
		_set_visual_children_visible(child, visibility)

func _get_pickup_candidate() -> RigidBody3D:
	if camera == null:
		return null

	var origin: Vector3 = camera.global_transform.origin
	var pickup_distance: float = maxf(Sword.get_pickup_max_distance(), maxf(Bat.get_pickup_max_distance(), maxf(float(SHOVEL_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(HEALTH_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(SMOKE_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(SKULL_KEY_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(TORCH_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(GOLD_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(GEM_KEY1_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(GEM_KEY2_ITEM_SCRIPT.call("get_pickup_max_distance")), maxf(float(GEM_KEY3_ITEM_SCRIPT.call("get_pickup_max_distance")), float(GEM_KEY4_ITEM_SCRIPT.call("get_pickup_max_distance")))))))))))))
	var end: Vector3 = origin + (-camera.global_transform.basis.z * pickup_distance)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider := result.get("collider") as Node
	if collider == null:
		return null

	var bat_candidate := Bat.find_bat_rigidbody_from_node(collider)
	if bat_candidate:
		return bat_candidate

	var sword_candidate := Sword.find_sword_rigidbody_from_node(collider)
	if sword_candidate:
		return sword_candidate

	var shovel_candidate := SHOVEL_ITEM_SCRIPT.call("find_shovel_rigidbody_from_node", collider) as RigidBody3D
	if shovel_candidate:
		return shovel_candidate

	var smoke_candidate := SMOKE_ITEM_SCRIPT.call("find_smoke_rigidbody_from_node", collider) as RigidBody3D
	if smoke_candidate:
		return smoke_candidate

	var skull_key_candidate := SKULL_KEY_ITEM_SCRIPT.call("find_skull_key_rigidbody_from_node", collider) as RigidBody3D
	if skull_key_candidate:
		return skull_key_candidate

	var torch_candidate := TORCH_ITEM_SCRIPT.call("find_torch_rigidbody_from_node", collider) as RigidBody3D
	if torch_candidate:
		return torch_candidate

	var health_candidate := HEALTH_ITEM_SCRIPT.call("find_health_rigidbody_from_node", collider) as RigidBody3D
	if health_candidate:
		return health_candidate

	var gem_key_candidate := _get_pickup_gem_key_candidate(collider)
	if gem_key_candidate:
		return gem_key_candidate

	return GOLD_ITEM_SCRIPT.call("find_gold_rigidbody_from_node", collider) as RigidBody3D

func _get_pickup_gem_key_candidate(collider: Node) -> RigidBody3D:
	var c1 := GEM_KEY1_ITEM_SCRIPT.call("find_gem_key1_rigidbody_from_node", collider) as RigidBody3D
	if c1:
		return c1
	var c2 := GEM_KEY2_ITEM_SCRIPT.call("find_gem_key2_rigidbody_from_node", collider) as RigidBody3D
	if c2:
		return c2
	var c3 := GEM_KEY3_ITEM_SCRIPT.call("find_gem_key3_rigidbody_from_node", collider) as RigidBody3D
	if c3:
		return c3
	return GEM_KEY4_ITEM_SCRIPT.call("find_gem_key4_rigidbody_from_node", collider) as RigidBody3D

func _update_pickup_prompt_visibility() -> void:
	if pickup_control == null:
		return

	var throw_active := throw_hint_control != null and throw_hint_control.visible
	var place_active := _place_item_control != null and _place_item_control.visible
	var warning2_active := _warning2_control != null and _warning2_control.visible
	var key_warning2_active := key_warning2_control != null and key_warning2_control.visible
	if _pickup_vis_timer <= 0.0:
		_cached_pickup_candidate = _get_pickup_candidate()
		_pickup_vis_timer = PICKUP_VIS_INTERVAL
	pickup_control.visible = not throw_active and not place_active and not warning2_active and not key_warning2_active and _find_first_empty_hotbar_slot() != -1 and _cached_pickup_candidate != null

func _has_any_primary_item_in_hotbar() -> bool:
	for item_model in hotbar_item_models:
		if _is_primary_item_model(item_model) and is_instance_valid(item_model):
			return true
	return false

## Removes the world item at the given absolute path on all peers when the authority
## player picks it up.
@rpc("any_peer", "call_remote", "reliable")
func _sync_item_removed(item_path: String) -> void:
	var item := get_node_or_null(NodePath(item_path))
	if item != null:
		item.queue_free()


## Called when the host closes the connection. Returns this client to the start menu.
func _on_host_disconnected() -> void:
	# Disconnect immediately so a second signal fire can't re-enter.
	if multiplayer.server_disconnected.is_connected(_on_host_disconnected):
		multiplayer.server_disconnected.disconnect(_on_host_disconnected)
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	# Defer the scene change so it happens after the current signal/frame unwinds.
	get_tree().call_deferred("change_scene_to_file", "res://menus/start_menu.tscn")


## Spawns a dropped item on all peers so they see it appear in the world.
@rpc("any_peer", "call_remote", "reliable")
func _sync_item_dropped(scene_path: String, drop_pos: Vector3, drop_vel: Vector3, is_puzzle_item: bool = false, is_lit: bool = false, item_name: String = "") -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var item := packed.instantiate() as Node3D
	# Set the name BEFORE add_child so the node path matches what the dropper captured
	# for _sync_item_removed. Without this, a name like "PlayerTorch" stays local while
	# the remote gets the default scene name ("Torch"), breaking the removal lookup.
	if not item_name.is_empty():
		item.name = item_name
	get_tree().current_scene.add_child(item, true)
	item.global_position = drop_pos
	if item is RigidBody3D:
		item.linear_velocity = drop_vel
	if is_puzzle_item:
		item.set_meta("puzzle_item", true)
	if is_lit:
		item.set("is_burning", true)
		var fire_particle := item.get_node_or_null("fire_particle")
		if fire_particle:
			fire_particle.visible = true
		var dropped_light := item.get_node_or_null("OmniLight3D")
		if dropped_light:
			dropped_light.visible = true


@rpc("any_peer", "call_local", "reliable")
func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_update_health_ui()
	_apply_damage_camera_tilt()
	if health <= 0.0:
		get_tree().change_scene_to_file("res://menus/death_menu.tscn")

func show_escape_warning() -> void:
	if escape_warning_control == null:
		return
	escape_warning_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	escape_warning_control.visible = true
	_escape_warning_timer = WARNING_DISPLAY_TIME

func _get_all_npcs() -> Array:
	var all_bodies := get_tree().root.find_children("*", "CharacterBody3D", true, false)
	return all_bodies.filter(func(n: Node) -> bool:
		return is_instance_valid(n) and not n.is_in_group("player")
	)

func _find_dungeon_generator(node: Node) -> Node:
	for child in node.get_children():
		if child.has_signal("done_generating"):
			return child
		var result := _find_dungeon_generator(child)
		if result:
			return result
	return null

const PAUSE_MENU_SCENE_PATH := "res://menus/pause_menu.tscn"

func _open_pause_menu() -> void:
	if not _game_started:
		return
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if player_canvas_layer:
		player_canvas_layer.visible = false
	var pause_scene: PackedScene = load(PAUSE_MENU_SCENE_PATH)
	var pause_menu := pause_scene.instantiate()
	pause_menu.tree_exiting.connect(_on_pause_menu_closed)
	get_tree().root.add_child(pause_menu)

func _on_pause_menu_closed() -> void:
	if player_canvas_layer:
		player_canvas_layer.visible = true

func _on_map_generated() -> void:
	_map_generated = true
	loading_label1.visible = false
	loading_label2.visible = false
	loading_label3.visible = false
	loading_label4.visible = true


func hide_loading_screen() -> void:
	loading_control.visible = false


func start_from_cutscene() -> void:
	if _game_started:
		return
	cutscene_active = false
	_game_started = true
	filter_rect.visible = true
	hud_control.visible = true
	loading_control.visible = false
	if movement_hint_control != null:
		movement_hint_control.visible = true
		_movement_hint_timer = MOVEMENT_HINT_DISPLAY_TIME
	if camera_hint_control != null:
		camera_hint_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		camera_hint_control.visible = true
		_camera_hint_active = true
	music_player.play()
	for npc in _get_all_npcs():
		npc.process_mode = Node.PROCESS_MODE_INHERIT

func _on_item_wheel_slot_switched() -> void:
	if not _item_wheel_hint_active:
		return
	_item_wheel_switch_count += 1
	if _item_wheel_switch_count >= ITEM_WHEEL_HINT_SWITCH_THRESHOLD:
		_item_wheel_hint_active = false
		if item_wheel_control != null:
			item_wheel_control.visible = false

func _update_footsteps() -> void:
	if animation_player == null or not is_on_floor():
		_prev_anim_pos = -1.0
		return
	var anim_name := animation_player.current_animation
	if not STEP_FRAMES.has(anim_name):
		_prev_anim_pos = -1.0
		return
	var cur_pos := animation_player.current_animation_position
	if _prev_anim_pos < 0.0:
		_prev_anim_pos = cur_pos
		return
	var cur_frame := cur_pos * STEP_ANIM_FPS
	var prev_frame := _prev_anim_pos * STEP_ANIM_FPS
	for f: int in STEP_FRAMES[anim_name]:
		# Forward crossing
		if prev_frame < f and f <= cur_frame:
			_play_random_step()
			break
		# Backward crossing (walk_backwards via play_backwards)
		if cur_frame < f and f <= prev_frame:
			_play_random_step()
			break
	_prev_anim_pos = cur_pos

func _play_random_step() -> void:
	if _step_sounds.is_empty() or footstep_player == null:
		return
	var playback := footstep_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if playback == null:
		return
	var stream: AudioStream = _step_sounds[randi() % _step_sounds.size()]
	playback.play_stream(stream, 0.0, footstep_player.volume_db)

func _update_swing_sound(swing_active: bool) -> void:
	var item := _get_selected_primary_item()
	var in_windup := swing_active and item != null and item.has_method("is_swing_windup_active") and bool(item.call("is_swing_windup_active"))
	if _swing_windup_was_active and not in_windup and swing_active:
		# Windup just ended → release phase started → play swing sound.
		if swing_player != null and swing_player.stream != null:
			swing_player.play()
	if not swing_active:
		_swing_windup_was_active = false
	else:
		_swing_windup_was_active = in_windup

func _update_chase_sound(delta: float) -> void:
	if not _game_started:
		return
	_chase_check_timer -= delta
	if _chase_check_timer > 0.0:
		return
	_chase_check_timer = CHASE_CHECK_INTERVAL
	var chaser_count := 0
	var chased_by_shy := false
	for npc in _get_all_npcs():
		if not is_instance_valid(npc):
			continue
		var scr: Script = npc.get_script() as Script
		if scr != null and scr.resource_path == STATUE_SCRIPT_PATH:
			continue
		var tp = npc.get("target_player")
		if tp == null and scr != null and scr.resource_path == CHARGER_SCRIPT_PATH:
			var charger_player = npc.get("player")
			if charger_player != null and (npc.get("is_player_in_range") or npc.get("los_lost_timer") > 0.0):
				tp = charger_player
		if tp != null and is_instance_valid(tp) and tp == self:
			chaser_count += 1
			if scr != null and scr.resource_path == SHY_SCRIPT_PATH:
				chased_by_shy = true
	var chased := chaser_count >= 3
	if chaser_count >= 1 and not _sprint_hint_shown_once:
		_sprint_hint_shown_once = true
		_sprint_hint_active = true
		if sprint_hint_control != null:
			sprint_hint_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sprint_hint_control.visible = true
	if chased and not _is_being_chased:
		_is_being_chased = true
		_chased_by_shy = chased_by_shy
		# Cancel any fade-out in progress and restore volume.
		if _chase_fade_tween:
			_chase_fade_tween.kill()
			_chase_fade_tween = null
		chase_player.volume_db = _chase_volume_db
		# Pause background music and remember where it was.
		if music_player.playing:
			_music_resume_position = music_player.get_playback_position()
			music_player.stop()
		# Chase music disabled.
		#if _chased_by_shy and _shy_chase_sound != null:
		#	chase_player.stream = _shy_chase_sound
		#	chase_player.play()
		#elif not _chase_sounds.is_empty():
		#	chase_player.stream = _chase_sounds[randi() % _chase_sounds.size()]
		#	chase_player.play()
	elif not chased and _is_being_chased:
		_is_being_chased = false
		# Fade the chase music out, then resume the background music.
		if _chase_fade_tween:
			_chase_fade_tween.kill()
		_chase_fade_tween = create_tween()
		_chase_fade_tween.tween_property(chase_player, "volume_db", -80.0, CHASE_FADE_OUT_DURATION)
		_chase_fade_tween.tween_callback(_on_chase_fade_finished)

func _on_chase_sound_finished() -> void:
	pass # Chase music disabled.

func _on_chase_fade_finished() -> void:
	chase_player.stop()
	chase_player.volume_db = _chase_volume_db
	# Resume background music from where it was paused.
	if _game_started and music_player != null:
		music_player.play(_music_resume_position)

func _apply_damage_camera_tilt() -> void:
	if camera == null:
		return
	if damage_tilt_tween:
		damage_tilt_tween.kill()
	var direction := 1.0 if randf() < 0.5 else -1.0
	camera.rotation.z = deg_to_rad(DAMAGE_TILT_ANGLE_DEG * direction)
	damage_tilt_tween = create_tween()
	damage_tilt_tween.tween_property(camera, "rotation:z", 0.0, DAMAGE_TILT_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

@rpc("any_peer", "call_local", "reliable")
func apply_stun_state(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)

@rpc("any_peer", "call_local", "reliable")
func apply_knockback(direction: Vector3, strength: float) -> void:
	var knock_dir := direction
	knock_dir.y = 0.0
	if knock_dir.length_squared() > 0.001:
		knock_dir = knock_dir.normalized()
	velocity.x += knock_dir.x * strength
	velocity.z += knock_dir.z * strength
	velocity.y = maxf(velocity.y, strength * 0.3)

func _setup_stamina_palette_colors() -> void:
	var palette_texture := load(STAMINA_PALETTE_PATH) as Texture2D
	if palette_texture == null:
		push_warning("Stamina palette texture not found at: %s" % STAMINA_PALETTE_PATH)
		return

	var palette_image := palette_texture.get_image()
	if palette_image == null or palette_image.is_empty():
		push_warning("Stamina palette image is empty: %s" % STAMINA_PALETTE_PATH)
		return

	stamina_color_normal = _get_palette_color(palette_image, STAMINA_COLOR_NORMAL_INDEX, stamina_color_normal)
	stamina_color_low = _get_palette_color(palette_image, STAMINA_COLOR_LOW_INDEX, stamina_color_low)

func _setup_health_palette_colors() -> void:
	var palette_texture := load(STAMINA_PALETTE_PATH) as Texture2D
	if palette_texture == null:
		push_warning("Health palette texture not found at: %s" % STAMINA_PALETTE_PATH)
		return

	var palette_image := palette_texture.get_image()
	if palette_image == null or palette_image.is_empty():
		push_warning("Health palette image is empty: %s" % STAMINA_PALETTE_PATH)
		return

	health_color_normal = _get_palette_color(palette_image, HEALTH_COLOR_NORMAL_INDEX, health_color_normal)

func _update_hotbar_windup_indicator() -> void:
	for i in hotbar_item_icons.size():
		var item_icon := hotbar_item_icons[i]
		if item_icon == null:
			continue

		var alpha := 1.0 if i == selected_hotbar_slot_index else 0.85
		var icon_color := Color(1.0, 1.0, 1.0, alpha)

		if i == selected_hotbar_slot_index:
			var selected_item := _get_selected_primary_item()
			if selected_item != null:
				icon_color = selected_item.call("get_hotbar_icon_modulate", alpha)

		item_icon.modulate = icon_color

func _get_palette_color(palette_image: Image, one_based_index: int, fallback: Color) -> Color:
	if one_based_index <= 0:
		return fallback

	var width := palette_image.get_width()
	var height := palette_image.get_height()
	if width <= 0 or height <= 0:
		return fallback

	var max_colors := width * height
	if one_based_index > max_colors:
		return fallback

	var linear_index := one_based_index - 1
	var pixel_x := linear_index % width
	var pixel_y := int(float(linear_index) / float(width))
	return palette_image.get_pixel(pixel_x, pixel_y)

func _set_control_mouse_filter_recursive(node: Control, mouse_filter: Control.MouseFilter) -> void:
	if node == null:
		return

	node.mouse_filter = mouse_filter
	for child in node.get_children():
		if child is Control:
			_set_control_mouse_filter_recursive(child as Control, mouse_filter)

func _log_player_position() -> void:
	if not debug_position_logs:
		return
	if position_log_timer > 0.0:
		return
	position_log_timer = POSITION_LOG_INTERVAL
	print("[PlayerPos] player=%s velocity=%s on_floor=%s" % [
		_format_vec3(global_position),
		_format_vec3(velocity),
		str(is_on_floor()),
	])

# Debug function to check collision state
func _input(event):
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		_open_pause_menu()
		return
	
	if event.is_action_pressed("space"):  # Space key - print debug info
		print("=== PLAYER DEBUG INFO ===")
		print("Position: ", global_position)
		print("Velocity: ", velocity)
		print("Is on floor: ", is_on_floor())
		print("Floor normal: ", get_floor_normal())
		print("Wall normal: ", get_wall_normal())
		print("Slide collision count: ", get_slide_collision_count())
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			print("Collision ", i, ": ", collision.get_collider(), " at ", collision.get_position())

# Helper function to set visual layer for all mesh instances recursively
func _set_layer_recursive(node: Node, layer: int):
	if node is VisualInstance3D:
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_layer_recursive(child, layer)

## Creates a local-only visual proxy for the item currently held by a remote player.
## Called whenever the synced _net_held_scene value changes on a non-authority peer.
func _update_remote_held_proxy() -> void:
	# Clean up previous proxy (also frees any torch lights it may have added).
	if _remote_held_proxy != null and is_instance_valid(_remote_held_proxy):
		if _remote_held_proxy.has_method("refresh_inventory_state"):
			_remote_held_proxy.call("refresh_inventory_state", self, -1, false)
		_remote_held_proxy.queue_free()
	_remote_held_proxy = null
	if _net_held_scene.is_empty():
		return
	var packed := load(_net_held_scene) as PackedScene
	if packed == null:
		return
	var proxy := packed.instantiate() as Node3D
	if proxy.has_method("pick_up_into_hotbar") and bool(proxy.call("pick_up_into_hotbar", self, 0)):
		if proxy.has_method("refresh_inventory_state"):
			# Snapshot the remote camera's children so we can identify and remove
			# any first-person viewmodel nodes added during equip. Those nodes are
			# 3D world-space objects that would be rendered by every player's camera.
			var remote_cam := camera as Camera3D
			var cam_children_before: Array = remote_cam.get_children().duplicate() if remote_cam else []
			proxy.call("refresh_inventory_state", self, 0, false)
			# Free any viewmodel nodes that refresh_inventory_state added to the camera.
			if remote_cam:
				for child in remote_cam.get_children():
					if not cam_children_before.has(child):
						child.queue_free()
		# _equip_to_right_hand sets meshes to layer 2 (hidden from local camera).
		# Override back to layer 1 so the local player can see the remote player's item.
		_set_layer_recursive(proxy, 1)
		_remote_held_proxy = proxy
	else:
		proxy.queue_free()

## Creates a MultiplayerSynchronizer so all peers can see this player's position
## and head rotation, regardless of who has authority over this node.
func _setup_multiplayer_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PositionSync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath("Head:rotation"))
	config.add_property(NodePath(".:_net_anim"))
	config.add_property(NodePath(".:_net_anim_backwards"))
	config.add_property(NodePath(".:_net_held_scene"))
	sync.replication_config = config
	add_child(sync)
	# The authority must match the player node's authority so only the owning
	# peer broadcasts their own data. Without this it defaults to server (1)
	# which causes the server to overwrite player2's position and head rotation.
	sync.set_multiplayer_authority(get_multiplayer_authority())


func _resolve_visual_root() -> Node3D:
	if not visual_root_path.is_empty():
		var configured_visual_root := get_node_or_null(visual_root_path) as Node3D
		if configured_visual_root:
			return configured_visual_root

	for child in get_children():
		if child is Node3D and child != head and _has_visual_descendant(child):
			return child as Node3D

	return null

func _resolve_animation_player() -> AnimationPlayer:
	if not animation_player_path.is_empty():
		var configured_animation_player := get_node_or_null(animation_player_path) as AnimationPlayer
		if configured_animation_player:
			return configured_animation_player

	if visual_root:
		return _find_animation_player_recursive(visual_root)

	return null

func _sync_visual_rotation_to_head() -> void:
	if visual_root:
		visual_root.rotation.y = head.rotation.y + deg_to_rad(visual_yaw_offset_degrees)

func _has_visual_descendant(node: Node) -> bool:
	if node is VisualInstance3D:
		return true
	for child in node.get_children():
		if _has_visual_descendant(child):
			return true
	return false

func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player_recursive(child)
		if found:
			return found
	return null

func _update_jump_animation_phase(delta: float) -> bool:
	if animation_player == null:
		jump_phase = JUMP_PHASE_NONE
		return false
	if not animation_player.has_animation("jump"):
		jump_phase = JUMP_PHASE_NONE
		return false

	if jump_phase == JUMP_PHASE_NONE:
		return false

	# End jump phase immediately on landing so attacks aren't blocked
	if is_on_floor() and velocity.y <= 0.0:
		jump_phase = JUMP_PHASE_NONE
		jump_air_loop_frame = float(JUMP_AIR_LOOP_MIN_FRAME)
		jump_air_loop_forward = true
		return false

	if animation_player.current_animation != "jump":
		animation_player.play("jump")
	animation_player.speed_scale = 1.0

	var jump_animation := animation_player.get_animation("jump")
	if jump_animation == null:
		jump_phase = JUMP_PHASE_NONE
		return false

	var min_loop_frame := float(JUMP_AIR_LOOP_MIN_FRAME)
	var hold_frame := float(JUMP_HOLD_FRAME)
	var frame_step := JUMP_ANIMATION_FPS * delta * JUMP_AIR_LOOP_SPEED
	if not is_on_floor():
		if jump_air_loop_forward:
			jump_air_loop_frame += frame_step
			if jump_air_loop_frame >= hold_frame:
				jump_air_loop_frame = hold_frame
				jump_air_loop_forward = false
		else:
			jump_air_loop_frame -= frame_step
			if jump_air_loop_frame <= min_loop_frame:
				jump_air_loop_frame = min_loop_frame
				jump_air_loop_forward = true

		var loop_time := (jump_air_loop_frame - 1.0) / JUMP_ANIMATION_FPS
		animation_player.seek(loop_time, true)
	else:
		var hold_time := (hold_frame - 1.0) / JUMP_ANIMATION_FPS
		if animation_player.current_animation_position < hold_time:
			animation_player.seek(hold_time, true)

	if animation_player.current_animation_position >= jump_animation.length - 0.02:
		jump_phase = JUMP_PHASE_NONE
		jump_air_loop_frame = float(JUMP_AIR_LOOP_MIN_FRAME)
		jump_air_loop_forward = true
		return false

	return true
