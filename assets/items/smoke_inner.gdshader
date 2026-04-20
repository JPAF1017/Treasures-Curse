shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D smoke_texture : source_color;

uniform vec4 outer_color : source_color = vec4(0.11, 0.09, 0.2, 1.0);
uniform vec4 inner_color : source_color = vec4(0.24, 0.2, 0.37, 1.0);
uniform float time_scale = 0.2;
uniform float smoke_sharpness = 0.765;
uniform float dissolve : hint_range(-1.0, 1.0) = -1.0;
uniform float edge_pulse = 0.07;
uniform bool apply_inside = true;
uniform float uv_scale = 3.0;

float fresnel(float amount, vec3 normal, vec3 view)
{
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

float saturatef(float a){
	return clamp(a, 0.0, 1.0);
}

void vertex(){
	vec2 smoke_uv = UV * uv_scale - TIME * time_scale;
	vec4 smoke_color = texture(smoke_texture, smoke_uv);
	VERTEX += NORMAL * smoke_color.r * edge_pulse * sin(UV.y * PI);
}

void fragment(){
	if (!apply_inside){
		float frontiplier = FRONT_FACING ? 1.0 : -1.0;
		NORMAL *= frontiplier;
	}

	float fres = fresnel(2.0, NORMAL, VIEW) * 5.0;
	fres = saturatef(fres);
	fres = 1.0 - fres;

	float outer_fres = fresnel(5.0, NORMAL, VIEW) * 2.0;
	outer_fres = saturatef(outer_fres);

	vec2 smoke_uv = UV * uv_scale - TIME * time_scale;
	vec4 smoke_color = texture(smoke_texture, smoke_uv);
	float smoke_buffer = smoothstep(0.0, smoke_sharpness, smoke_color.r);

	float overlay = mix(fres, 0.5, smoke_buffer);
	overlay = mix(outer_fres, 1.0, overlay);

	ALPHA = smoothstep(-dissolve, 1.0, smoke_color.r);
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	vec3 final_color = mix(outer_color.rgb, inner_color.rgb, overlay);
	ALBEDO = final_color;
}
