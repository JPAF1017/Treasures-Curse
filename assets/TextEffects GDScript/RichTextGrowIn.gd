@tool
class_name RichTextGrowIn
extends RichTextEffect

var bbcode = "grow_in"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var transform = char_fx.transform
	var size: float = 0.0;
	var min_size: float = char_fx.env.get("min_size", 0.0)
	var max_size: float = char_fx.env.get("max_size", 1.0)
	var duration: float = char_fx.env.get("duration", 0.8)
	var end: int = char_fx.env.get("end", 10)
	var start = 0
	
	var position: int = int((fmod(float(char_fx.elapsed_time) / duration, 1.0)) * end + 1.0)
	var time: float = fmod(float(char_fx.elapsed_time) / duration, 2.0) - 1.0
	var smoothing1: float = (char_fx.relative_index - (position - start - end)) / (float(end))
	var smoothing2: float = (char_fx.get_relative_index() - position)/ max(float(end), 1.0)
	
	if time < 0:
		if char_fx.relative_index >= position:
				size = lerp(min_size, max_size, smoothing2) #Normal start to end
		else:
				size = lerp(max_size, min_size, smoothing1) #Normal start to end
	else:
		if char_fx.relative_index >= position:
				size = lerp(max_size, min_size, smoothing2) #Normal end to start
		else:
				size = lerp(min_size, max_size, smoothing1) #Inverted start to end
	
	transform.x *= size # scale width
	transform.y *= size # scale height
	char_fx.transform = transform
	return true
