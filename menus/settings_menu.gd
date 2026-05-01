extends Control

var seed_locked: bool = false

@onready var volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $Panel/MarginContainer/VBoxContainer/VolumeRow/VolumeValue
@onready var vsync_check: CheckBox = $Panel/MarginContainer/VBoxContainer/VSyncRow/VSyncCheck
@onready var psx_check: CheckBox = $Panel/MarginContainer/VBoxContainer/PSXRow/PSXCheck
@onready var fullscreen_check: CheckBox = $Panel/MarginContainer/VBoxContainer/FullscreenRow/FullscreenCheck
@onready var seed_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SeedRow/SeedInput
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/BackRow/Back


func _ready() -> void:
	volume_slider.value = SettingsManager.master_volume
	volume_value_label.text = "%d%%" % int(SettingsManager.master_volume * 100)
	vsync_check.button_pressed = SettingsManager.vsync_enabled
	psx_check.button_pressed = SettingsManager.psx_filter_enabled
	fullscreen_check.button_pressed = SettingsManager.exclusive_fullscreen
	if SettingsManager.generation_seed != 0:
		seed_input.text = str(SettingsManager.generation_seed)
	if seed_locked:
		seed_input.editable = false
		seed_input.placeholder_text = "Locked in-game"

	volume_slider.value_changed.connect(_on_volume_changed)
	vsync_check.toggled.connect(_on_vsync_toggled)
	psx_check.toggled.connect(_on_psx_toggled)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	seed_input.text_changed.connect(_on_seed_changed)
	back_button.pressed.connect(_on_back_pressed)


func _on_volume_changed(value: float) -> void:
	volume_value_label.text = "%d%%" % int(value * 100)
	SettingsManager.set_master_volume(value)


func _on_vsync_toggled(pressed: bool) -> void:
	SettingsManager.set_vsync(pressed)


func _on_psx_toggled(pressed: bool) -> void:
	SettingsManager.set_psx_filter(pressed)


func _on_fullscreen_toggled(pressed: bool) -> void:
	SettingsManager.set_exclusive_fullscreen(pressed)


func _on_seed_changed(new_text: String) -> void:
	if new_text.is_empty():
		SettingsManager.set_generation_seed(0)
	elif new_text.is_valid_int():
		SettingsManager.set_generation_seed(new_text.to_int())


func _on_back_pressed() -> void:
	queue_free()
