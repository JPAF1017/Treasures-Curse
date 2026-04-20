shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D smoke_texture : source_color;

uniform vec4 color : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform float time_scale = 0.04;
uniform float smoke_sharpness = 0.45;
uniform float inner_fade = 0.25;
uniform float outer_fade = 0.78;
uniform float opacity = 0.7;

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float dist = length(centered_uv);

	// Fade: invisible at center, peak in middle ring, fade at edge
	float ring_fade = smoothstep(inner_fade, inner_fade + 0.25, dist)
		* smoothstep(1.0, outer_fade, dist);

	// Two scrolling layers at different speeds/directions for depth
	vec2 uv1 = UV + vec2(TIME * time_scale, TIME * time_scale * 0.6);
	vec2 uv2 = UV - vec2(TIME * time_scale * 0.5, TIME * time_scale * 0.8);
	float smoke1 = texture(smoke_texture, uv1).r;
	float smoke2 = texture(smoke_texture, uv2).r;
	float smoke_val = smoothstep(0.0, smoke_sharpness, (smoke1 + smoke2) * 0.5);

	ALBEDO = color.rgb;
	ALPHA = smoke_val * ring_fade * opacity;
}
