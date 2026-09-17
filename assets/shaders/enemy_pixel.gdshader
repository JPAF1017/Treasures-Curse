shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Direct color sampling preserves original vibrant colors without sRGB^2.2 crushing
uniform sampler2D albedo_texture : filter_nearest;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float brightness : hint_range(0.5, 4.0) = 1.35;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;
uniform float saturation : hint_range(0.0, 3.0) = 1.25;
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.2;
uniform float highlight_knee : hint_range(0.3, 1.0) = 0.58;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 col = tex.rgb * albedo_tint.rgb;

	// Lift shadow crushing while preserving highlight headroom
	if (shadow_lift > 0.0) {
		col = pow(col, vec3(1.0 / (1.0 + shadow_lift)));
	}

	// Vibrance / Saturation
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);

	// Contrast
	col = (col - vec3(0.5)) * contrast + vec3(0.5);

	// Brightness
	col *= brightness;

	// Soft shoulder highlight preservation: prevents clipping so all texture details remain visible
	if (highlight_knee < 1.0) {
		vec3 knee = vec3(highlight_knee);
		vec3 span = vec3(1.0) - knee;
		vec3 over = max(col - knee, vec3(0.0));
		vec3 compressed = knee + span * (vec3(1.0) - exp(-over / max(span, vec3(0.001))));
		col = mix(col, compressed, step(knee, col));
	}

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
