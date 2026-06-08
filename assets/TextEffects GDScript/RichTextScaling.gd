@tool
class_name RichTextScaling
extends RichTextEffect

var bbcode = "scaling"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var transform = char_fx.transform
	var min_size: float = char_fx.env.get("min_size", 0.0)
	var max_size: float = char_fx.env.get("max_size", 1.0)
	var end: int = char_fx.env.get("end", 10)
	var size: float = 0.0;
	
	var smoothing: float = char_fx.relative_index/ max(float(end), 1)
	size = lerp(min_size, max_size, smoothing)
	
	transform.x *= size # scale width
	transform.y *= size # scale height
	char_fx.transform = transform
	return true
