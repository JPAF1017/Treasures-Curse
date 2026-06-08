@tool
class_name RichTextRotatingDegrade
extends RichTextEffect

var bbcode = "rotating_degrade"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	
	var start_color: Color = char_fx.env.get("start_color", Color.WHITE)
	var end_color: Color = char_fx.env.get("end_color", Color.BLACK)
	var duration: float = char_fx.env.get("duration", 2)
	var end: int = char_fx.env.get("end", 10)
	var start = 0
	
	var position: int = int((fmod(float(char_fx.elapsed_time) / duration, 1.0)) * end + 1.0)
	var time: float = fmod(float(char_fx.elapsed_time) / duration, 2.0) - 1.0
	var smoothing1: float = (char_fx.relative_index - (position - start - end)) / (float(end) * 1.0)
	var smoothing2: float = (char_fx.get_relative_index() - position)/ max(float(end), 1.0)
	
	if time < 0:
		if char_fx.relative_index >= position:
				char_fx.color = start_color.lerp(end_color, smoothing2) #Normal start to end
		else:
				char_fx.color = end_color.lerp(start_color, smoothing1)  #Normal start to end
	else:
		if char_fx.relative_index >= position:
				char_fx.color = end_color.lerp(start_color, smoothing2) #Normal end to start
		else:
				char_fx.color = start_color.lerp(end_color, smoothing1) #Inverted start to end
	
	return true
