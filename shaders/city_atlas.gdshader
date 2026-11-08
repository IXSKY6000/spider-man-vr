shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec4 atlas_rect;

void vertex() {
	// Dimensions are encoded as log2 in COLOR to survive 8-bit vertex packing.
	atlas_rect = vec4(UV2, exp2(round(COLOR.rg * 8.0)) / 4096.0);
}

void fragment() {
	vec2 uv = atlas_rect.xy + fract(UV) * atlas_rect.zw;
	vec2 dx = dFdx(UV) * atlas_rect.zw;
	vec2 dy = dFdy(UV) * atlas_rect.zw;
	// Keep the sampling footprint within the 8-pixel wrapped atlas gutter.
	float footprint = max(length(dx), length(dy)) * 4096.0;
	float gradient_scale = min(1.0, 4.0 / max(footprint, 0.001));
	vec4 color = textureGrad(atlas, uv, dx * gradient_scale, dy * gradient_scale);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
}
