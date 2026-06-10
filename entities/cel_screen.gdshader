shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

uniform int color_steps : hint_range(2, 8) = 4;
uniform vec4 shadow_tint : source_color = vec4(0.08, 0.04, 0.18, 1.0);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.35;
uniform float outline_strength : hint_range(0.0, 1.0) = 0.5;
uniform float outline_thickness : hint_range(0.5, 3.0) = 1.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

float posterize(float v, float steps) {
	return floor(v * steps + 0.5) / steps;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 color = texture(SCREEN_TEXTURE, uv);

	// --- Posterize (cel quantize) ---
	float s = float(color_steps);
	color.r = posterize(color.r, s);
	color.g = posterize(color.g, s);
	color.b = posterize(color.b, s);

	// --- Shadow tint on dark pixels ---
	float luminance = luma(color.rgb);
	float shadow_factor = 1.0 - smoothstep(0.0, 0.5, luminance);
	color.rgb = mix(color.rgb, shadow_tint.rgb, shadow_factor * shadow_tint_strength);

	// --- Sobel outline on luminance ---
	if (outline_strength > 0.0) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_thickness;
		float tl = luma(texture(SCREEN_TEXTURE, uv + vec2(-px.x,  px.y)).rgb);
		float tm = luma(texture(SCREEN_TEXTURE, uv + vec2( 0.0,   px.y)).rgb);
		float tr = luma(texture(SCREEN_TEXTURE, uv + vec2( px.x,  px.y)).rgb);
		float ml = luma(texture(SCREEN_TEXTURE, uv + vec2(-px.x,  0.0 )).rgb);
		float mr = luma(texture(SCREEN_TEXTURE, uv + vec2( px.x,  0.0 )).rgb);
		float bl = luma(texture(SCREEN_TEXTURE, uv + vec2(-px.x, -px.y)).rgb);
		float bm = luma(texture(SCREEN_TEXTURE, uv + vec2( 0.0,  -px.y)).rgb);
		float br = luma(texture(SCREEN_TEXTURE, uv + vec2( px.x, -px.y)).rgb);

		float gx = -tl - 2.0*ml - bl + tr + 2.0*mr + br;
		float gy = -tl - 2.0*tm - tr + bl + 2.0*bm + br;
		float edge = clamp(sqrt(gx*gx + gy*gy) * 3.0, 0.0, 1.0) * outline_strength;
		color.rgb = mix(color.rgb, outline_color.rgb, edge);
	}

	COLOR = color;
}
