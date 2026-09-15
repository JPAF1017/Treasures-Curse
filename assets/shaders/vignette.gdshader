shader_type canvas_item;

uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.0;
uniform float radius : hint_range(0.0, 1.0) = 0.38;
uniform float softness : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float vig = smoothstep(radius, radius + softness, dist);
	COLOR = vec4(vignette_color.rgb, vig * intensity * vignette_color.a);
}
