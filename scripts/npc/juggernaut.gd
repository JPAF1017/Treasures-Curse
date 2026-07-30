extends CharacterBody3D

const GRAVITY = 20.0
const _STYLIZED_SHADER: Shader = preload("res://entities/stylized.gdshader")
var _original_materials: Dictionary = {}

var animation_player: AnimationPlayer = null

func _ready() -> void:
	top_level = true
	_collect_original_materials(self)
	if SettingsManager.shader_enabled:
		_apply_stylized_shader(self)
	SettingsManager.shader_changed.connect(_on_shader_changed)
	animation_player = _find_animation_player(self)

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	_play_idle_animation()
	move_and_slide()

func _play_idle_animation() -> void:
	if not animation_player:
		return
	
	if animation_player.has_animation("idle"):
		if animation_player.current_animation != "idle" or not animation_player.is_playing():
			animation_player.speed_scale = 1.0
			animation_player.play("idle")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null


func _collect_original_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mats: Array = []
		for i in mi.get_surface_override_material_count():
			mats.append(mi.get_active_material(i))
		_original_materials[mi] = mats
	for child in node.get_children():
		_collect_original_materials(child)


func _apply_stylized_shader(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var orig_mats: Array = _original_materials.get(mi, [])
		for i in mi.get_surface_override_material_count():
			var sm := ShaderMaterial.new()
			sm.shader = _STYLIZED_SHADER
			sm.set_shader_parameter("albedo_affect", 1.0)
			if i < orig_mats.size():
				var orig = orig_mats[i]
				if orig is StandardMaterial3D:
					var albedo_tex := (orig as StandardMaterial3D).albedo_texture
					if albedo_tex != null:
						sm.set_shader_parameter("albedo_texture", albedo_tex)
					sm.set_shader_parameter("albedo_color", (orig as StandardMaterial3D).albedo_color)
			mi.set_surface_override_material(i, sm)
	for child in node.get_children():
		_apply_stylized_shader(child)


func _restore_original_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, null)
	for child in node.get_children():
		_restore_original_materials(child)


func _on_shader_changed(enabled: bool) -> void:
	_restore_original_materials(self)
	if enabled:
		_apply_stylized_shader(self)
