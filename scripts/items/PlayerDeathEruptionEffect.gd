class_name PlayerDeathEruptionEffect
extends RefCounted

## Player Defeat Cursed Death Eruption Visual & Auditory Effect.
## Emits:
## 1. Dark Shadow Miasma: Billowing explosive clouds of dark obsidian and shadowy violet mist.
## 2. Cursed Arcane Runes: Upward erupting fountain of glowing crimson and purple eldritch runes.
## 3. Dissolving Soul Embers: Luminous soul sparks and ethereal cyan embers floating upward.
## 4. Cursed Shockwave Ring: Expanding ground-level ring of dark arcane energy.
## 5. Soul Pillar Wisps: Focused upward vortex of cursed energy escaping into the dungeon air.
## 6. Positional Death Audio: Heavy cursed expiration audio cue.

const SMOKE_TEXTURE_PATH := "res://assets/base assets/smoke_01.png"
const DEATH_SOUND_PATH := "res://sounds/player/death_sound.mp3"

# Particle amounts
const MIASMA_AMOUNT := 48
const MIASMA_LIFETIME := 1.7
const RUNE_AMOUNT := 36
const RUNE_LIFETIME := 1.4
const EMBER_AMOUNT := 55
const EMBER_LIFETIME := 2.0
const SHOCKWAVE_AMOUNT := 24
const SHOCKWAVE_LIFETIME := 0.65
const PILLAR_AMOUNT := 22
const PILLAR_LIFETIME := 1.5

const EFFECT_DURATION := 2.6

static var _rune_texture: Texture2D = null


## Spawns the player's cursed death eruption at the specified world position.
## [param scene_tree] - SceneTree reference (get_tree())
## [param origin] - 3D world position where the player fell
static func spawn(scene_tree: SceneTree, origin: Vector3) -> void:
	if scene_tree == null:
		return

	var root := scene_tree.current_scene
	if root == null:
		return

	var container := Node3D.new()
	container.name = "PlayerDeathEruptionFX"
	root.add_child(container)
	container.global_position = origin

	# 1. Billowing dark cursed shadow miasma
	_spawn_shadow_miasma(container, origin)

	# 2. Erupting cursed arcane runes
	_spawn_curse_runes(container, origin)

	# 3. Floating luminous soul embers
	_spawn_soul_embers(container, origin)

	# 4. Expanding ground shockwave pulse
	_spawn_shockwave_ring(container, origin)

	# 5. Ascending soul pillar wisps
	_spawn_soul_pillar(container, origin)

	# 6. Positional death audio cue
	_play_death_audio(container, origin)

	# Self-cleanup
	_schedule_cleanup(scene_tree, container)


# ── 1. Dark Shadow Miasma ─────────────────────────────────────────────────────

static func _spawn_shadow_miasma(parent: Node3D, origin: Vector3) -> void:
	var miasma := CPUParticles3D.new()
	miasma.name = "ShadowMiasma"
	miasma.emitting = false
	miasma.one_shot = true
	miasma.amount = MIASMA_AMOUNT
	miasma.lifetime = MIASMA_LIFETIME
	miasma.explosiveness = 0.92
	miasma.lifetime_randomness = 0.35

	miasma.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	miasma.emission_sphere_radius = 0.35

	miasma.direction = Vector3(0.0, 0.75, 0.0)
	miasma.spread = 85.0
	miasma.initial_velocity_min = 2.0
	miasma.initial_velocity_max = 4.6
	miasma.damping_min = 1.8
	miasma.damping_max = 3.2
	miasma.gravity = Vector3(0.0, 0.5, 0.0)

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.2, 1.3))
	scale_curve.add_point(Vector2(1.0, 2.2))
	miasma.scale_amount_curve = scale_curve
	miasma.scale_amount_min = 0.8
	miasma.scale_amount_max = 1.6

	# Obsidian black to rich cursed shadow violet fading out
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0.04, 0.01, 0.07, 0.0),
		Color(0.07, 0.02, 0.14, 0.92),
		Color(0.22, 0.06, 0.32, 0.48),
		Color(0.28, 0.08, 0.38, 0.0),
	])
	miasma.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.65, 0.65)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex:
		mat.albedo_texture = tex
	quad.material = mat
	miasma.mesh = quad

	parent.add_child(miasma)
	miasma.global_position = origin
	miasma.restart()
	miasma.emitting = true


# ── 2. Cursed Arcane Runes ───────────────────────────────────────────────────

static func _spawn_curse_runes(parent: Node3D, origin: Vector3) -> void:
	var runes := CPUParticles3D.new()
	runes.name = "CurseRunes"
	runes.emitting = false
	runes.one_shot = true
	runes.amount = RUNE_AMOUNT
	runes.lifetime = RUNE_LIFETIME
	runes.explosiveness = 0.86
	runes.lifetime_randomness = 0.3

	runes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	runes.emission_sphere_radius = 0.3

	runes.direction = Vector3(0.0, 1.0, 0.0)
	runes.spread = 65.0
	runes.initial_velocity_min = 2.4
	runes.initial_velocity_max = 5.0
	runes.gravity = Vector3(0.0, -0.8, 0.0)
	runes.damping_min = 1.4
	runes.damping_max = 2.6

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(0.18, 1.25))
	scale_curve.add_point(Vector2(0.7, 0.95))
	scale_curve.add_point(Vector2(1.0, 0.0))
	runes.scale_amount_curve = scale_curve
	runes.scale_amount_min = 0.65
	runes.scale_amount_max = 1.3

	# Deep blood crimson into radiant cursed violet
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.2, 0.3, 0.0),
		Color(1.0, 0.15, 0.4, 1.0),
		Color(0.75, 0.18, 0.95, 0.85),
		Color(0.4, 0.05, 0.6, 0.0),
	])
	runes.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.38, 0.38)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_rune_texture()
	quad.material = mat
	runes.mesh = quad

	parent.add_child(runes)
	runes.global_position = origin
	runes.restart()
	runes.emitting = true


# ── 3. Dissolving Soul Embers ─────────────────────────────────────────────────

static func _spawn_soul_embers(parent: Node3D, origin: Vector3) -> void:
	var embers := CPUParticles3D.new()
	embers.name = "SoulEmbers"
	embers.emitting = false
	embers.one_shot = true
	embers.amount = EMBER_AMOUNT
	embers.lifetime = EMBER_LIFETIME
	embers.explosiveness = 0.8
	embers.lifetime_randomness = 0.4

	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.35

	embers.direction = Vector3(0.0, 1.0, 0.0)
	embers.spread = 75.0
	embers.initial_velocity_min = 1.6
	embers.initial_velocity_max = 4.2
	embers.gravity = Vector3(0.0, 1.6, 0.0)
	embers.damping_min = 1.2
	embers.damping_max = 2.4

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.2, 1.15))
	scale_curve.add_point(Vector2(0.7, 0.7))
	scale_curve.add_point(Vector2(1.0, 0.0))
	embers.scale_amount_curve = scale_curve
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.1

	# Brilliant core into soul cyan and ethereal magenta
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(0.9, 0.4, 1.0, 1.0),
		Color(0.5, 0.85, 1.0, 0.8),
		Color(0.35, 0.2, 0.7, 0.0),
	])
	embers.color_ramp = grad

	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	sphere.radial_segments = 4
	sphere.rings = 2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat
	embers.mesh = sphere

	parent.add_child(embers)
	embers.global_position = origin
	embers.restart()
	embers.emitting = true


# ── 4. Cursed Shockwave Ring ─────────────────────────────────────────────────

static func _spawn_shockwave_ring(parent: Node3D, origin: Vector3) -> void:
	var ring := CPUParticles3D.new()
	ring.name = "CursedShockwave"
	ring.emitting = false
	ring.one_shot = true
	ring.amount = SHOCKWAVE_AMOUNT
	ring.lifetime = SHOCKWAVE_LIFETIME
	ring.explosiveness = 0.94

	ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	ring.emission_ring_axis = Vector3.UP
	ring.emission_ring_radius = 0.25
	ring.emission_ring_inner_radius = 0.05
	ring.emission_ring_height = 0.05

	ring.direction = Vector3.UP
	ring.flatness = 0.96
	ring.initial_velocity_min = 2.8
	ring.initial_velocity_max = 4.8
	ring.damping_min = 2.5
	ring.damping_max = 4.0
	ring.gravity = Vector3.ZERO

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.35, 1.35))
	scale_curve.add_point(Vector2(1.0, 0.1))
	ring.scale_amount_curve = scale_curve
	ring.scale_amount_min = 0.6
	ring.scale_amount_max = 1.3

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.25, 0.8, 0.0),
		Color(0.8, 0.15, 0.9, 0.85),
		Color(0.45, 0.08, 0.6, 0.4),
		Color(0.2, 0.04, 0.3, 0.0),
	])
	ring.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex:
		mat.albedo_texture = tex
	quad.material = mat
	ring.mesh = quad

	parent.add_child(ring)
	ring.global_position = origin
	ring.restart()
	ring.emitting = true


# ── 5. Soul Pillar Wisps ──────────────────────────────────────────────────────

static func _spawn_soul_pillar(parent: Node3D, origin: Vector3) -> void:
	var pillar := CPUParticles3D.new()
	pillar.name = "SoulPillar"
	pillar.emitting = false
	pillar.one_shot = true
	pillar.amount = PILLAR_AMOUNT
	pillar.lifetime = PILLAR_LIFETIME
	pillar.explosiveness = 0.65

	pillar.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pillar.emission_sphere_radius = 0.15

	pillar.direction = Vector3.UP
	pillar.spread = 15.0
	pillar.initial_velocity_min = 3.2
	pillar.initial_velocity_max = 5.8
	pillar.gravity = Vector3(0.0, 1.2, 0.0)
	pillar.damping_min = 0.8
	pillar.damping_max = 1.8

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.6))
	pillar.scale_amount_curve = scale_curve
	pillar.scale_amount_min = 0.5
	pillar.scale_amount_max = 1.0

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(0.2, 0.05, 0.3, 0.0),
		Color(0.45, 0.1, 0.55, 0.5),
		Color(0.25, 0.05, 0.35, 0.3),
		Color(0.1, 0.02, 0.15, 0.0),
	])
	pillar.color_ramp = grad

	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.7)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex: Texture2D = load(SMOKE_TEXTURE_PATH)
	if tex:
		mat.albedo_texture = tex
	quad.material = mat
	pillar.mesh = quad

	parent.add_child(pillar)
	pillar.global_position = origin
	pillar.restart()
	pillar.emitting = true


# ── 6. Positional Death Audio ─────────────────────────────────────────────────

static func _play_death_audio(parent: Node3D, origin: Vector3) -> void:
	var stream: AudioStream = load(DEATH_SOUND_PATH)
	if stream == null:
		return

	var audio := AudioStreamPlayer3D.new()
	audio.name = "DeathAudio"
	audio.stream = stream
	audio.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	audio.unit_size = 5.0
	audio.max_distance = 35.0
	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE

	parent.add_child(audio)
	audio.global_position = origin
	audio.play()


# ── Procedural Arcane Rune Texture ────────────────────────────────────────────

static func _get_rune_texture() -> Texture2D:
	if _rune_texture != null:
		return _rune_texture

	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (float(size) - 1.0) * 0.5

	for y in range(size):
		for x in range(size):
			var nx := (float(x) - center) / center
			var ny := (float(y) - center) / center
			var dist := sqrt(nx * nx + ny * ny)

			# Central core glow
			var core := clampf(1.0 - dist * 2.8, 0.0, 1.0)
			core = core * core

			# Outer rune circle (radius ~0.76)
			var outer_circle := clampf(1.0 - absf(dist - 0.76) * 14.0, 0.0, 1.0)

			# Inner rune circle (radius ~0.42)
			var inner_circle := clampf(1.0 - absf(dist - 0.42) * 16.0, 0.0, 1.0)

			# 8-spoke arcane radial runes
			var angle := atan2(ny, nx)
			if angle < 0.0:
				angle += TAU
			var spoke_dist := absf(fposmod(angle + PI / 8.0, PI / 4.0) - PI / 8.0)
			var spoke_mask := clampf(1.0 - spoke_dist * 18.0, 0.0, 1.0)
			var spoke := spoke_mask * clampf(1.0 - absf(dist - 0.59) * 4.5, 0.0, 1.0)

			# Cardinal 4-point flares extending outside the outer circle
			var flare_h := clampf(1.0 - absf(nx), 0.0, 1.0) * clampf(1.0 - absf(ny) * 9.0, 0.0, 1.0)
			var flare_v := clampf(1.0 - absf(ny), 0.0, 1.0) * clampf(1.0 - absf(nx) * 9.0, 0.0, 1.0)
			var flares := (flare_h + flare_v) * 0.75

			var alpha := clampf(core + outer_circle * 0.9 + inner_circle * 0.85 + spoke * 0.9 + flares, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_rune_texture = ImageTexture.create_from_image(img)
	return _rune_texture


# ── Cleanup ───────────────────────────────────────────────────────────────────

static func _schedule_cleanup(scene_tree: SceneTree, container: Node3D) -> void:
	if scene_tree == null or container == null:
		return

	scene_tree.create_timer(EFFECT_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(container):
			container.queue_free()
	)
