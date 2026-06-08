@tool
class_name RichTextDegrade
extends RichTextEffect

var bbcode = "degrade"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var start_color: Color = char_fx.env.get("start_color", Color.WHITE)
	var end_color: Color = char_fx.env.get("end_color", Color.BLACK)
	var end: int = char_fx.env.get("end", 10)
	var smoothing: float = float(char_fx.relative_index) / max(float(end), 1.0)
	
	char_fx.color = start_color.lerp(end_color, smoothing)
	return true
