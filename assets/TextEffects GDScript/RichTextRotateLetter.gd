@tool
class_name RichTextRotateLetter
extends RichTextEffect

var bbcode = "rotate_letter"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var transform = char_fx.transform
	var angle: float = char_fx.env.get("duration", 0.2) #in radians
	var duration: float = char_fx.env.get("duration", 2)
	var delay: float = char_fx.env.get("delay",0)
	delay += 1
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
		
	transform = transform.rotated_local(angle)
	if char_fx.relative_index == position:
		char_fx.transform = transform
	return true
