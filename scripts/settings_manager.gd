extends Node

signal psx_filter_changed(enabled: bool)

const SETTINGS_PATH := "user://settings.cfg"

var master_volume: float = 1.0
var vsync_enabled: bool = true
var psx_filter_enabled: bool = true
var exclusive_fullscreen: bool = false
var generation_seed: int = 0  # 0 = random each run


func _ready() -> void:
	_load()
	_apply_volume()
	_apply_vsync()
	_apply_fullscreen()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	_save()


func set_vsync(value: bool) -> void:
	vsync_enabled = value
	_apply_vsync()
	_save()


func set_psx_filter(value: bool) -> void:
	psx_filter_enabled = value
	psx_filter_changed.emit(value)
	_save()


func set_exclusive_fullscreen(value: bool) -> void:
	exclusive_fullscreen = value
	_apply_fullscreen()
	_save()


func set_generation_seed(value: int) -> void:
	generation_seed = value
	_save()


func _apply_volume() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(master_volume))


func _apply_vsync() -> void:
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _apply_fullscreen() -> void:
	var window := get_window()
	if exclusive_fullscreen:
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	else:
		if window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN or window.mode == Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("display", "vsync_enabled", vsync_enabled)
	cfg.set_value("display", "psx_filter_enabled", psx_filter_enabled)
	cfg.set_value("display", "exclusive_fullscreen", exclusive_fullscreen)
	cfg.set_value("display", "generation_seed", generation_seed)
	cfg.save(SETTINGS_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master_volume", 1.0)
	vsync_enabled = cfg.get_value("display", "vsync_enabled", true)
	psx_filter_enabled = cfg.get_value("display", "psx_filter_enabled", true)
	exclusive_fullscreen = cfg.get_value("display", "exclusive_fullscreen", false)
	generation_seed = cfg.get_value("display", "generation_seed", 0)
