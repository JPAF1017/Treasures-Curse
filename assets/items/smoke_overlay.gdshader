shader_type canvas_item;

uniform float time_scale = 0.1;
uniform float uv_scale = 3.0;

void fragment() {
	vec2 smoke_uv = fract(UV * uv_scale - TIME * time_scale);
	vec4 c = texture(TEXTURE, smoke_uv);
	COLOR = vec4(c.rgb, COLOR.a);
}
