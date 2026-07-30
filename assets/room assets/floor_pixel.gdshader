// Per-pixel lit floor shader — disabled, falls back to project default shading.
shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_nearest;

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
}
