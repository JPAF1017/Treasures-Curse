extends Node

# Kill counts per enemy type
var kills_charger: int = 0
var kills_gnome: int = 0
var kills_fly: int = 0
var kills_shambler: int = 0
var kills_knight: int = 0

# Damage dealt by the player to enemies
var damage_dealt: float = 0.0

# Playtime in seconds — starts on first player movement
var playtime: float = 0.0
var _timer_running: bool = false
var _timer_stopped: bool = false


func reset() -> void:
	kills_charger = 0
	kills_gnome = 0
	kills_fly = 0
	kills_shambler = 0
	kills_knight = 0
	damage_dealt = 0.0
	playtime = 0.0
	_timer_running = false
	_timer_stopped = false


func start_timer() -> void:
	if not _timer_stopped:
		_timer_running = true


func stop_timer() -> void:
	_timer_running = false
	_timer_stopped = true


func record_kill(enemy_type: String) -> void:
	match enemy_type:
		"charger":  kills_charger += 1
		"gnome":    kills_gnome += 1
		"fly":      kills_fly += 1
		"shambler": kills_shambler += 1
		"knight":   kills_knight += 1


func record_damage(amount: float) -> void:
	if amount > 0.0:
		damage_dealt += amount


func _process(delta: float) -> void:
	if _timer_running:
		playtime += delta


func format_time(seconds: float) -> String:
	var total := int(seconds)
	var m := total / 60
	var s := total % 60
	return "%d:%02d" % [m, s]
