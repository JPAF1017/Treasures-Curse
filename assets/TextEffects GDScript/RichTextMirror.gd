@tool
class_name RichTextMirror
extends RichTextEffect

var bbcode = "mirror"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var offset_correction: float = char_fx.env.get("offset", 0)
	
	var transform = char_fx.transform
	transform.x *= -1;
	char_fx.transform = transform;
	
	char_fx.offset = Vector2(-offset_correction, 0)
	return true
