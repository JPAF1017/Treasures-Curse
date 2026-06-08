@tool
class_name RichTextJumpingLetter
extends RichTextEffect

var bbcode = "jumping_letter"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var power: float = char_fx.env.get("power", 10)
	var duration: float = char_fx.env.get("duration", 2)
	var delay: float = char_fx.env.get("delay",0)
	delay += 1
	var variating: bool = char_fx.env.get("variating", true)
	var rotating: bool = char_fx.env.get("rotating", true)
	var end: int = char_fx.env.get("end", 10)
	var position: int = 0
	
	if rotating:
		position = int(fmod(float(char_fx.elapsed_time) / duration, delay) * end + 1.0)
	else:
		var time: float = fmod(float(char_fx.elapsed_time) / duration, 2.0) - 1.0
		var place: float = 1 - abs(time * 2 - 1)
		var value: float = place * 2 - 1
		position = (int)(value * (end + 1))
		
	if variating:
		power *= abs(cos(char_fx.elapsed_time * 1.0))
	
	if char_fx.relative_index == position:
		char_fx.offset = Vector2(0, -power)
	return true
