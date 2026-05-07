extends Control

## Draws a circular arc around the crosshair that fills clockwise from the top
## as a weapon windup progresses (0.0 = empty, 1.0 = full).

var value: float = 0.0 : set = set_value

const RING_RADIUS := 18.0
const RING_WIDTH := 3.0
const RING_COLOR_START := Color(1.0, 1.0, 0.2, 0.9)
const RING_COLOR_END := Color(1.0, 0.3, 0.3, 0.95)
const ARC_POINTS := 64


func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if value <= 0.001:
		return

	var center := size * 0.5
	var angle_start := -PI * 0.5  # start at top
	var angle_end := angle_start + TAU * value
	var color := RING_COLOR_START.lerp(RING_COLOR_END, value)

	var steps := maxi(2, int(ARC_POINTS * value))
	var prev_point := center + Vector2(cos(angle_start), sin(angle_start)) * RING_RADIUS

	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var angle := angle_start + (angle_end - angle_start) * t
		var next_point := center + Vector2(cos(angle), sin(angle)) * RING_RADIUS
		draw_line(prev_point, next_point, color, RING_WIDTH, true)
		prev_point = next_point
