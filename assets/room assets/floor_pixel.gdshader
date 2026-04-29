// Per-pixel lit floor shader.
// Bypasses the global force_vertex_shading project setting so that
// dynamic point lights (held/dropped torch) correctly illuminate the floor.
shader_type spatial;
render_mode diffuse_lambert;

uniform sampler2D albedo_texture : source_color, filter_nearest;

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
}
