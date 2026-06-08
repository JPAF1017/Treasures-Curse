@tool
class_name RichTextUpsideDown
extends RichTextEffect

var bbcode = "upside_down"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var offset_correction: float = char_fx.env.get("offset", 0)
	
	var transform = char_fx.transform
	transform.y *= -1;
	char_fx.transform = transform;
	
	char_fx.offset = Vector2(0, offset_correction)
	return true
