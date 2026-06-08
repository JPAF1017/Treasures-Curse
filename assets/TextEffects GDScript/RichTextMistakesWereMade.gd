@tool
class_name RichTextMistakesWereMade
extends RichTextEffect

var bbcode = "mistakes_were_made"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var offset_correction: float = char_fx.env.get("offset", 0)
	var rotation_now: float = abs(cos(char_fx.elapsed_time))
	
	var transform = char_fx.transform
	transform.y *= rotation_now # scale height
	transform.origin = Vector2(transform.origin.x, abs(transform.origin.y * rotation_now));
	char_fx.transform = transform
	
	char_fx.offset = Vector2(0,(offset_correction - (1 + rotation_now)* offset_correction /2) - rotation_now)
	return true
