shader_type canvas_item;

global uniform vec2 resolution;
global uniform float color_depth;

uniform sampler2D screen_texture: hint_screen_texture, filter_nearest;

void fragment() {
	// disabled
	COLOR = texture(screen_texture, SCREEN_UV);
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
