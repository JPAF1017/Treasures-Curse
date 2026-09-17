extends RigidBody3D

const TORCH_SCENE_PATH := "res://assets/items/torch.tscn"
const TORCH_ITEM_ICON: Texture2D = preload("res://assets/ui/torch.png")
const TORCH_MODEL_SCENE: PackedScene = preload("res://assets/base assets/ps1psx_wooden_torch.glb")
const TORCH_VIEWMODEL_SCENE: PackedScene = preload("res://assets/items/torch_viewmodel.tscn")
static var melee_shared = preload("res://scripts/items/MeleeItemSharedComponent.gd").new()

const ITEM_DROP_FORWARD_DISTANCE := 1.0
const ITEM_DROP_DOWN_OFFSET := -0.25
const ITEM_DROP_FORWARD_SPEED := 2.0
const ITEM_DROP_UPWARD_SPEED := 0.5
const TORCH_PHYSICS_COLLISION_LAYER := 3
const TORCH_PHYSICS_COLLISION_MASK := 3
const TORCH_PHYSICS_MASS := 0.1
const TORCH_PHYSICS_LINEAR_DAMP := 2.5
const TORCH_PHYSICS_ANGULAR_DAMP := 3.0
const TORCH_ATTACHMENT_NODE_NAME := "RightHandTorchAttachment"

const VIEWMODEL_BOB_FREQ := 2.0
const VIEWMODEL_BOB_AMP_Y := 0.012
const VIEWMODEL_BOB_AMP_X := 0.006

const BASE_FIRE_GRAVITY := Vector3(0.0, 0.9, 0.0)
const BASE_SMOKE_GRAVITY := Vector3(0.0, 1.1, 0.0)

const DRAFT_MOVE_Z_FACTOR := 2.4
const DRAFT_MOVE_X_FACTOR := 2.4
const DRAFT_MOVE_Y_FACTOR := 1.2
const DRAFT_CAM_YAW_FACTOR := 4.0
const DRAFT_CAM_PITCH_FACTOR := 3.5
const DRAFT_ATTACK_SPEED := 24.0
const DRAFT_DECAY_SPEED := 16.0

const TORCH_LIGHT_ENERGY := 12.0
const TORCH_LIGHT_COLOR := Color(0.855485, 0.46624, 0.0)
const TORCH_LIGHT_TWEEN_DURATION := 0.4
const TORCH_LIGHT_RANGE := 200.0
const DEFAULT_LIGHT_ENERGY := 8.0
const DEFAULT_LIGHT_COLOR := Color(1.0, 1.0, 1.0)
const DEFAULT_LIGHT_RANGE := 43.3203
const TORCH_VOLUMETRIC_FOG_ENERGY := 8.0
const DEFAULT_VOLUMETRIC_FOG_ENERGY := 0.5

const MAX_USABLE_TIME := 120.0
var usable_time_left: float = MAX_USABLE_TIME
var is_burning: bool = false

var item_durability_color_start: Color = Color(1.0, 0.3, 0.3, 1.0)
var item_durability_color_end: Color = Color(0.3, 1.0, 0.3, 1.0)
const STAMINA_PALETTE_PATH := "res://assets/ui/dungeon-pal.png"
const ITEM_DURABILITY_COLOR_START_INDEX := 17
const ITEM_DURABILITY_COLOR_END_INDEX := 22

static var equip_key_was_down: bool = false

@export var right_hand_bone_name: String = "mixamorig_RightHand"
@export var held_item_position: Vector3 = Vector3(0.03, 0.07, -0.04)
@export var held_item_rotation_degrees: Vector3 = Vector3(92.0, 300.0, 276.0)
@export_range(0.01, 2.0, 0.01) var held_item_scale: float = 0.2

@export var viewmodel_position: Vector3 = Vector3(-0.44, -0.38, -0.45)
@export var viewmodel_rotation_degrees: Vector3 = Vector3(-10.0, 25.0, -14.0)
@export_range(0.01, 2.0, 0.01) var viewmodel_scale: float = 0.75

var inventory_slot_index: int = -1
var right_hand_attachment: BoneAttachment3D = null
var viewmodel_instance: Node3D = null
const TORCH_SOUND_PATH := "res://sounds/torch/torch.mp3"

var viewmodel_bob_time: float = 0.0
var _current_fire_gravity: Vector3 = BASE_FIRE_GRAVITY
var _current_smoke_gravity: Vector3 = BASE_SMOKE_GRAVITY
var _carried_omni: OmniLight3D = null
var _held_sound: AudioStreamPlayer = null
var _torch_lit_state: bool = false

var _current_player: Node = null
var _current_camera: Camera3D = null
var _prev_camera_basis := Basis.IDENTITY
var _has_prev_camera_transform := false
var _current_tilt_rad := Vector3.ZERO

@onready var _fire_particle: Node3D = $fire_particle
@onready var _dropped_light: OmniLight3D = get_node_or_null("OmniLight3D")


func _ready() -> void:
	add_to_group("torch_items")
	_configure_item_physics()
	if _fire_particle:
		_fire_particle.visible = is_burning
	if _dropped_light:
		_dropped_light.visible = is_burning and inventory_slot_index < 0
		if _dropped_light.visible:
			_dropped_light.top_level = true
			_dropped_light.global_position = global_position + Vector3(0.0, DROPPED_LIGHT_HEIGHT_OFFSET, 0.0)
			_dropped_light.omni_range = 16.0
	_setup_item_durability_palette_colors()

func _setup_item_durability_palette_colors() -> void:
	var palette_texture := load(STAMINA_PALETTE_PATH) as Texture2D
	if palette_texture == null:
		return
	var palette_image := palette_texture.get_image()
	if palette_image == null or palette_image.is_empty():
		return
	item_durability_color_start = _get_palette_color(palette_image, ITEM_DURABILITY_COLOR_START_INDEX, item_durability_color_start)
	item_durability_color_end = _get_palette_color(palette_image, ITEM_DURABILITY_COLOR_END_INDEX, item_durability_color_end)

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

const DROPPED_LIGHT_HEIGHT_OFFSET := 1.2

func _exit_tree() -> void:
	_hide_viewmodel()


func _process(delta: float) -> void:
	if is_burning:
		if is_infinite_torch():
			usable_time_left = MAX_USABLE_TIME
		else:
			usable_time_left -= delta
			if usable_time_left <= 0.0:
				_delete_torch()
				return

	if viewmodel_instance and is_instance_valid(viewmodel_instance) and viewmodel_instance.visible:
		_update_viewmodel_dynamics(delta)


func _physics_process(_delta: float) -> void:
	# Keep the dropped light at a fixed world-space height above the torch
	# so it illuminates the floor regardless of how the torch tumbled.
	if _dropped_light and _dropped_light.visible and _dropped_light.top_level:
		_dropped_light.global_position = global_position + Vector3(0.0, DROPPED_LIGHT_HEIGHT_OFFSET, 0.0)


func _delete_torch() -> void:
	_hide_viewmodel()
	if right_hand_attachment and is_instance_valid(right_hand_attachment) and get_parent() == right_hand_attachment:
		right_hand_attachment.remove_child(self)

	if inventory_slot_index >= 0:
		var parent := get_parent()
		var player: Node = null
		while parent:
			if parent.has_method("_set_hotbar_item"):
				player = parent
				break
			parent = parent.get_parent()
		if player == null and right_hand_attachment:
			parent = right_hand_attachment
			while parent:
				if parent.has_method("_set_hotbar_item"):
					player = parent
					break
				parent = parent.get_parent()
		if player:
			_apply_torch_light(player, false)
			player.call("_set_hotbar_item", inventory_slot_index, null, null)
			if player.has_method("_refresh_selected_item_state"):
				player.call("_refresh_selected_item_state")
			if player.has_method("_update_pickup_prompt_visibility"):
				player.call("_update_pickup_prompt_visibility")
	
	if _carried_omni and is_instance_valid(_carried_omni):
		_carried_omni.queue_free()
	
	queue_free()


static func get_pickup_max_distance() -> float:
	return melee_shared.get_pickup_max_distance()


static func get_equip_action_name() -> StringName:
	return melee_shared.get_equip_action_name()


static func get_scene_path() -> String:
	return TORCH_SCENE_PATH


static func get_item_icon() -> Texture2D:
	return TORCH_ITEM_ICON


static func is_torch_node(node: Node) -> bool:
	return melee_shared.is_item_node(node, TORCH_SCENE_PATH, "torch")


static func find_torch_rigidbody_from_node(node: Node) -> RigidBody3D:
	return melee_shared.find_item_rigidbody_from_node(node, TORCH_SCENE_PATH, "torch")


static func is_equip_input_just_pressed() -> bool:
	var equip_input: Dictionary = melee_shared.read_equip_input(get_equip_action_name(), equip_key_was_down)
	equip_key_was_down = bool(equip_input.get("is_down", equip_key_was_down))
	return bool(equip_input.get("just_pressed", false))


func get_hotbar_icon_texture() -> Texture2D:
	return TORCH_ITEM_ICON


func get_hotbar_icon_modulate(alpha: float) -> Color:
	return Color(1.0, 1.0, 1.0, alpha)


func get_hotbar_durability_percent() -> float:
	if is_infinite_torch():
		return 1.0
	return clampf(usable_time_left / MAX_USABLE_TIME, 0.0, 1.0)


func can_start_primary_action() -> bool:
	return false


func begin_primary_action(_player: Node) -> bool:
	return false


func release_primary_action(_player: Node) -> void:
	pass


func update_primary_action(_player: Node, _delta: float) -> bool:
	return false


func get_holding_player() -> Node:
	if _current_player and is_instance_valid(_current_player):
		return _current_player
	var p := get_parent()
	while p:
		if p.is_in_group("player"):
			return p
		p = p.get_parent()
	return null


func is_held_by_player() -> bool:
	return inventory_slot_index >= 0 and get_holding_player() != null


const LEVEL1_SPAWNER_SCRIPT := preload("res://scripts/level1_spawner.gd")

func is_player_in_infinite_torch_zone() -> bool:
	var player := get_holding_player()
	if player == null:
		return false
	var player_pos: Vector3 = player.global_position
	if LEVEL1_SPAWNER_SCRIPT != null:
		return LEVEL1_SPAWNER_SCRIPT.is_in_first_two_layers(player_pos)
	return player_pos.y < -15.0


func is_infinite_torch() -> bool:
	if SettingsManager.unlimited_torch:
		return true
	return is_held_by_player() and is_player_in_infinite_torch_zone()


func is_equipped_in_hand() -> bool:
	if inventory_slot_index < 0:
		return false
	var parent := get_parent()
	return parent != null and parent == right_hand_attachment


func pick_up_into_hotbar(player: Node, slot_index: int) -> bool:
	if player == null:
		return false
	if inventory_slot_index != -1:
		return false
	if slot_index < 0:
		return false

	inventory_slot_index = slot_index
	_current_player = player
	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	player.add_child(self)
	_set_item_physics_enabled(false)
	_set_item_visuals_visible(false)
	if _dropped_light:
		_dropped_light.top_level = false
		_dropped_light.position = Vector3(0.0, 0.417, 0.008)
		_dropped_light.omni_range = 12.0
		_dropped_light.visible = false
	is_burning = false
	return true


func drop_from_hotbar(player: Node) -> bool:
	if player == null:
		return false
	if inventory_slot_index < 0:
		return false

	_hide_viewmodel()
	_apply_torch_light(player, false)
	_detach_from_hand(player)

	var world_root: Node = null
	if player.has_method("get_tree"):
		var tree := player.get_tree()
		if tree:
			world_root = tree.current_scene
	if world_root == null:
		world_root = player.get_parent()
	if world_root == null:
		world_root = player

	var drop_origin := global_position
	var camera := _get_player_camera(player)
	if camera:
		drop_origin = camera.global_position + (-camera.global_transform.basis.z * ITEM_DROP_FORWARD_DISTANCE) + Vector3(0.0, ITEM_DROP_DOWN_OFFSET, 0.0)

	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	if world_root:
		world_root.add_child(self, true)
	else:
		player.add_child(self)

	global_position = drop_origin
	_set_visual_layer_recursive(self, 1)
	_set_item_visuals_visible(true)
	if _fire_particle:
		_fire_particle.visible = true
	if _dropped_light:
		_dropped_light.top_level = true
		_dropped_light.global_position = global_position + Vector3(0.0, DROPPED_LIGHT_HEIGHT_OFFSET, 0.0)
		_dropped_light.omni_range = 16.0
		_dropped_light.visible = true
	_set_item_physics_enabled(true)
	var player_node := player as Node3D
	var forward := Vector3.FORWARD
	if player_node:
		forward = -player_node.global_transform.basis.z
	if camera:
		forward = -camera.global_transform.basis.z
	linear_velocity = (forward * ITEM_DROP_FORWARD_SPEED) + (Vector3.UP * ITEM_DROP_UPWARD_SPEED)
	inventory_slot_index = -1
	right_hand_attachment = null
	return true


func refresh_inventory_state(player: Node, selected_slot_index: int, _is_sprinting: bool) -> void:
	if player == null or inventory_slot_index < 0:
		return

	if inventory_slot_index == selected_slot_index:
		_equip_to_right_hand(player)
		_set_item_visuals_visible(true)
		_show_viewmodel(player)
		_apply_torch_light(player, true)
		is_burning = true
	else:
		_detach_from_hand(player)
		var is_selected_torch := _has_selected_torch(player, selected_slot_index)
		var is_primary := _is_primary_passive_torch(player)
		var keep_visible: bool = selected_slot_index >= 0 and (not is_selected_torch) and is_primary
		if keep_visible:
			_show_viewmodel(player)
			_apply_torch_light(player, true)
			is_burning = true
		else:
			_hide_viewmodel()
			_apply_torch_light(player, false)
			is_burning = false


func _has_selected_torch(player: Node, selected_slot_index: int) -> bool:
	if player == null:
		return false
	var models = player.get("hotbar_item_models")
	if models is Array and selected_slot_index >= 0 and selected_slot_index < models.size():
		var sel = models[selected_slot_index]
		if sel != null and is_instance_valid(sel) and sel.get_script() == get_script():
			return true
	return false


func _is_single_player_active(player: Node) -> bool:
	if player == null:
		return true
	var tree := player.get_tree() if player.has_method("get_tree") else null
	if tree == null:
		return true
	var active_count := 0
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and not p.get("is_dead") and not p.get("_is_spectating"):
			active_count += 1
	return active_count <= 1


func _is_primary_passive_torch(player: Node) -> bool:
	if player == null:
		return true
	var models = player.get("hotbar_item_models")
	if models is Array:
		for model in models:
			if model != null and is_instance_valid(model) and model.get_script() == get_script():
				return model == self
	return true


func _configure_item_physics() -> void:
	melee_shared.configure_item_physics(self, TORCH_PHYSICS_MASS, TORCH_PHYSICS_LINEAR_DAMP, TORCH_PHYSICS_ANGULAR_DAMP)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	melee_shared.limit_body_velocity_and_recover(state)


func _set_item_physics_enabled(enabled: bool) -> void:
	melee_shared.set_item_physics_enabled(self, enabled, TORCH_PHYSICS_COLLISION_LAYER, TORCH_PHYSICS_COLLISION_MASK, TORCH_PHYSICS_MASS, TORCH_PHYSICS_LINEAR_DAMP, TORCH_PHYSICS_ANGULAR_DAMP)


func _set_item_visuals_visible(visibility: bool) -> void:
	melee_shared.set_visual_children_visible(self, visibility)


func _set_visual_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D and not node is Light3D:
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_visual_layer_recursive(child, layer)


func _equip_to_right_hand(player: Node) -> void:
	if player == null:
		return

	var attachment := _get_or_create_right_hand_attachment(player)
	if attachment == null:
		push_warning("Could not attach torch item: right hand bone attachment is missing.")
		return

	if get_parent() == attachment:
		_set_item_physics_enabled(false)
		_set_item_visuals_visible(true)
		if _fire_particle:
			_fire_particle.visible = true
		if _dropped_light:
			_dropped_light.visible = false
		return

	var old_parent := get_parent()
	if old_parent != attachment:
		if old_parent:
			old_parent.remove_child(self)
		attachment.add_child(self)

	_set_item_physics_enabled(false)
	_set_item_visuals_visible(true)
	_set_visual_layer_recursive(self, 2)
	if _fire_particle:
		_fire_particle.visible = true
	if _dropped_light:
		_dropped_light.visible = false

	position = held_item_position
	rotation = Vector3(
		deg_to_rad(held_item_rotation_degrees.x),
		deg_to_rad(held_item_rotation_degrees.y),
		deg_to_rad(held_item_rotation_degrees.z)
	)
	scale = Vector3.ONE * held_item_scale


func _detach_from_hand(player: Node) -> void:
	if player == null:
		return

	var desired_parent := player
	if get_parent() != desired_parent:
		var old_parent := get_parent()
		if old_parent:
			old_parent.remove_child(self)
		player.add_child(self)
	_set_item_physics_enabled(false)
	_set_item_visuals_visible(false)
	if _fire_particle:
		_fire_particle.visible = false
	right_hand_attachment = null


func _get_or_create_right_hand_attachment(player: Node) -> BoneAttachment3D:
	if right_hand_attachment and is_instance_valid(right_hand_attachment):
		return right_hand_attachment

	var visual_root := _get_player_visual_root(player)
	var skeleton := _find_skeleton_recursive(visual_root if visual_root else player)
	if skeleton == null:
		return null

	var existing := skeleton.get_node_or_null(TORCH_ATTACHMENT_NODE_NAME) as BoneAttachment3D
	if existing:
		right_hand_attachment = existing
		return right_hand_attachment

	var resolved_bone_name := _resolve_right_hand_bone_name(skeleton)
	if resolved_bone_name.is_empty():
		return null

	var attachment := BoneAttachment3D.new()
	attachment.name = TORCH_ATTACHMENT_NODE_NAME
	attachment.bone_name = resolved_bone_name
	skeleton.add_child(attachment)
	right_hand_attachment = attachment
	return right_hand_attachment


func _resolve_right_hand_bone_name(skeleton: Skeleton3D) -> String:
	if skeleton == null:
		return ""

	if not right_hand_bone_name.is_empty() and skeleton.find_bone(right_hand_bone_name) != -1:
		return right_hand_bone_name

	var fallback_bone := ""
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		var lower_name := bone_name.to_lower()
		if lower_name.contains("right") and lower_name.contains("hand"):
			return bone_name
		if fallback_bone.is_empty() and lower_name.contains("hand"):
			fallback_bone = bone_name

	return fallback_bone


func _find_skeleton_recursive(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton_recursive(child)
		if found:
			return found
	return null


func _get_player_visual_root(player: Node) -> Node3D:
	if player == null:
		return null
	return player.get("visual_root") as Node3D


func _get_player_camera(player: Node) -> Camera3D:
	if player == null:
		return null
	return player.get("camera") as Camera3D


func _show_viewmodel(player: Node) -> void:
	if viewmodel_instance and is_instance_valid(viewmodel_instance):
		viewmodel_instance.visible = true
		_current_player = player
		if _current_camera == null or not is_instance_valid(_current_camera):
			_current_camera = _get_player_camera(player)
		return

	var camera := _get_player_camera(player)
	if camera == null:
		return

	viewmodel_instance = TORCH_VIEWMODEL_SCENE.instantiate() as Node3D
	viewmodel_instance.name = "TorchViewmodel"
	camera.add_child(viewmodel_instance)

	var vm_sound := viewmodel_instance.find_child("TorchSound", true, false)
	if vm_sound:
		vm_sound.queue_free()

	viewmodel_instance.position = viewmodel_position
	viewmodel_instance.rotation = Vector3(
		deg_to_rad(viewmodel_rotation_degrees.x),
		deg_to_rad(viewmodel_rotation_degrees.y),
		deg_to_rad(viewmodel_rotation_degrees.z)
	)
	viewmodel_instance.scale = Vector3.ONE * viewmodel_scale

	# Align fire particle basis with camera so the flame rises vertically upwards from the camera
	var fire_p := viewmodel_instance.get_node_or_null("fire_particle") as Node3D
	if fire_p:
		fire_p.position = Vector3(-0.02, 0.42, 0.0)
		fire_p.transform.basis = viewmodel_instance.transform.basis.inverse()
		var fire_gpu := fire_p.get_node_or_null("Fire") as GPUParticles3D
		if fire_gpu and fire_gpu.process_material is ParticleProcessMaterial:
			fire_gpu.process_material = fire_gpu.process_material.duplicate()
		var smoke_gpu := fire_p.get_node_or_null("Smoke") as GPUParticles3D
		if smoke_gpu and smoke_gpu.process_material is ParticleProcessMaterial:
			smoke_gpu.process_material = smoke_gpu.process_material.duplicate()

	_current_player = player
	_current_camera = camera
	_has_prev_camera_transform = false
	_current_tilt_rad = Vector3.ZERO
	_current_fire_gravity = BASE_FIRE_GRAVITY
	_current_smoke_gravity = BASE_SMOKE_GRAVITY


func _apply_torch_light(player: Node, torch_on: bool) -> void:
	if torch_on == _torch_lit_state and (not torch_on or (_carried_omni != null and is_instance_valid(_carried_omni))):
		return
	_torch_lit_state = torch_on
	var camera := _get_player_camera(player)
	if camera == null:
		return
	var spotlight := camera.get_node_or_null("SpotLight3D") as SpotLight3D
	if spotlight:
		var target_energy := TORCH_LIGHT_ENERGY if torch_on else DEFAULT_LIGHT_ENERGY
		var target_color := TORCH_LIGHT_COLOR if torch_on else DEFAULT_LIGHT_COLOR
		var target_range := TORCH_LIGHT_RANGE if torch_on else DEFAULT_LIGHT_RANGE
		var target_fog_energy := TORCH_VOLUMETRIC_FOG_ENERGY if torch_on else DEFAULT_VOLUMETRIC_FOG_ENERGY
		var tween := spotlight.create_tween()
		tween.set_parallel(true)
		tween.tween_property(spotlight, "light_energy", target_energy, TORCH_LIGHT_TWEEN_DURATION)
		tween.tween_property(spotlight, "light_color", target_color, TORCH_LIGHT_TWEEN_DURATION)
		tween.tween_property(spotlight, "spot_range", target_range, TORCH_LIGHT_TWEEN_DURATION)
		tween.tween_property(spotlight, "light_volumetric_fog_energy", target_fog_energy, TORCH_LIGHT_TWEEN_DURATION)

	if torch_on:
		if _carried_omni == null or not is_instance_valid(_carried_omni):
			_carried_omni = OmniLight3D.new()
			_carried_omni.name = "TorchCarriedOmni"
			_carried_omni.light_color = Color(0.855485, 0.46624, 0.0)
			_carried_omni.light_energy = 6.0
			_carried_omni.omni_range = 28.0
			_carried_omni.shadow_enabled = false
			_carried_omni.light_volumetric_fog_energy = 0.0
			_carried_omni.light_bake_mode = Light3D.BAKE_DISABLED
			camera.add_child(_carried_omni)
		_carried_omni.visible = true
		# Start the held-torch looping sound (2D so it's always audible regardless of position)
		if _held_sound == null or not is_instance_valid(_held_sound):
			_held_sound = AudioStreamPlayer.new()
			_held_sound.stream = load(TORCH_SOUND_PATH)
			_held_sound.volume_db = -10.0
			add_child(_held_sound)
		if not _held_sound.playing:
			_held_sound.play()
	else:
		if _carried_omni and is_instance_valid(_carried_omni):
			_carried_omni.queue_free()
			_carried_omni = null
		# Stop held-torch sound when unequipped
		if _held_sound and is_instance_valid(_held_sound):
			_held_sound.stop()


func _hide_viewmodel() -> void:
	if viewmodel_instance and is_instance_valid(viewmodel_instance):
		viewmodel_instance.queue_free()
		viewmodel_instance = null
	viewmodel_bob_time = 0.0
	_current_player = null
	_current_camera = null
	_has_prev_camera_transform = false
	_current_tilt_rad = Vector3.ZERO
	_current_fire_gravity = BASE_FIRE_GRAVITY
	_current_smoke_gravity = BASE_SMOKE_GRAVITY


func _update_viewmodel_dynamics(delta: float) -> void:
	_update_viewmodel_bob(_current_player, delta)
	_update_fire_movement_draft(_current_player, delta)


func _update_viewmodel_bob(player: Node, delta: float) -> void:
	if viewmodel_instance == null or not is_instance_valid(viewmodel_instance):
		return

	var target_player := player if player else _current_player
	var player_body := target_player as CharacterBody3D
	if player_body == null:
		return

	var speed := player_body.velocity.length()
	var on_floor: bool = player_body.is_on_floor()

	if speed > 0.5 and on_floor:
		viewmodel_bob_time += delta * speed
	else:
		viewmodel_bob_time = lerpf(viewmodel_bob_time, 0.0, delta * 5.0)

	var bob_y := sin(viewmodel_bob_time * VIEWMODEL_BOB_FREQ) * VIEWMODEL_BOB_AMP_Y
	var bob_x := cos(viewmodel_bob_time * VIEWMODEL_BOB_FREQ * 0.5) * VIEWMODEL_BOB_AMP_X
	viewmodel_instance.position = viewmodel_position + Vector3(bob_x, bob_y, 0.0)


func _update_fire_movement_draft(player: Node, delta: float) -> void:
	if viewmodel_instance == null or not is_instance_valid(viewmodel_instance):
		return
	if delta <= 0.0:
		return

	var fire_p := viewmodel_instance.get_node_or_null("fire_particle") as Node3D
	if fire_p == null:
		return

	var fire_gpu := fire_p.get_node_or_null("Fire") as GPUParticles3D
	var smoke_gpu := fire_p.get_node_or_null("Smoke") as GPUParticles3D
	if fire_gpu == null and smoke_gpu == null:
		return

	var camera := _current_camera
	if camera == null or not is_instance_valid(camera):
		camera = _get_player_camera(player if player else _current_player)
		_current_camera = camera
	if camera == null:
		return

	# 1. Linear player movement in camera space
	var target_player := player if player else _current_player
	var player_body := target_player as CharacterBody3D
	var world_vel := player_body.velocity if player_body else Vector3.ZERO
	var cam_space_vel := camera.global_transform.basis.inverse() * world_vel

	# 2. Camera angular velocity (mouse-look / head rotation)
	var curr_cam_basis := camera.global_transform.basis
	var yaw_speed := 0.0
	var pitch_speed := 0.0

	if _has_prev_camera_transform:
		var rel_basis := curr_cam_basis.inverse() * _prev_camera_basis
		var prev_fwd := -rel_basis.z
		# Angular difference between current forward (0,0,-1) and previous forward
		var yaw_delta := -atan2(prev_fwd.x, -prev_fwd.z)
		var pitch_delta := -atan2(prev_fwd.y, -prev_fwd.z)
		yaw_speed = clampf(yaw_delta / delta, -25.0, 25.0)
		pitch_speed = clampf(pitch_delta / delta, -25.0, 25.0)
	else:
		_has_prev_camera_transform = true

	_prev_camera_basis = curr_cam_basis

	# 3. Calculate target tilt angles in radians:
	# - Walking forward (cam_space_vel.z < 0) pushes flame backward (+X)
	# - Looking UP (pitch_speed > 0) tilts flame downward/backward (+X)
	# - Looking DOWN (pitch_speed < 0) tilts flame forward (-X)
	# - Strafing right (cam_space_vel.x > 0) or turning right (yaw_speed > 0) tilts flame left (+Z in Euler)
	# - Strafing left (cam_space_vel.x < 0) or turning left (yaw_speed < 0) tilts flame right (-Z in Euler)
	var target_tilt_x := deg_to_rad(-cam_space_vel.z * DRAFT_MOVE_Z_FACTOR + pitch_speed * DRAFT_CAM_PITCH_FACTOR)
	var target_tilt_z := deg_to_rad(cam_space_vel.x * DRAFT_MOVE_X_FACTOR + yaw_speed * DRAFT_CAM_YAW_FACTOR)

	# Jumping / vertical movement tilt
	target_tilt_x -= deg_to_rad(cam_space_vel.y * DRAFT_MOVE_Y_FACTOR)

	# Clamp to prevent unnatural inversion
	target_tilt_x = clampf(target_tilt_x, deg_to_rad(-22.0), deg_to_rad(36.0))
	target_tilt_z = clampf(target_tilt_z, deg_to_rad(-32.0), deg_to_rad(32.0))

	# Responsive smoothing: fast attack when accelerating/turning, smooth snapback
	var is_active := (absf(target_tilt_x) > 0.001 or absf(target_tilt_z) > 0.001)
	var smooth_rate := DRAFT_ATTACK_SPEED if is_active else DRAFT_DECAY_SPEED
	_current_tilt_rad.x = lerpf(_current_tilt_rad.x, target_tilt_x, clampf(delta * smooth_rate, 0.0, 1.0))
	_current_tilt_rad.z = lerpf(_current_tilt_rad.z, target_tilt_z, clampf(delta * smooth_rate, 0.0, 1.0))

	# 4. Apply flame tilt directly to fire_particle basis
	# Basis counter-rotation keeps fire upright in camera view;
	# multiplying by r_draft tilts it instantaneously according to draft
	var r_draft := Basis.from_euler(Vector3(_current_tilt_rad.x, 0.0, _current_tilt_rad.z))
	fire_p.transform.basis = viewmodel_instance.transform.basis.inverse() * r_draft

	# 5. Dynamic gravity adjustment for the trailing smoke and flame curvature
	var wind_drag := Vector3(-_current_tilt_rad.z * 0.7, 0.0, _current_tilt_rad.x * 0.8)
	var target_fire_gravity := BASE_FIRE_GRAVITY + wind_drag
	var target_smoke_gravity := BASE_SMOKE_GRAVITY + (wind_drag * 1.3)

	_current_fire_gravity = _current_fire_gravity.lerp(target_fire_gravity, clampf(delta * 18.0, 0.0, 1.0))
	_current_smoke_gravity = _current_smoke_gravity.lerp(target_smoke_gravity, clampf(delta * 18.0, 0.0, 1.0))

	if fire_gpu and fire_gpu.process_material is ParticleProcessMaterial:
		(fire_gpu.process_material as ParticleProcessMaterial).gravity = _current_fire_gravity

	if smoke_gpu and smoke_gpu.process_material is ParticleProcessMaterial:
		(smoke_gpu.process_material as ParticleProcessMaterial).gravity = _current_smoke_gravity
