shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec3 sun_direction;
uniform float depth_min;
uniform float depth_span;
varying highp vec4 atlas_rect;
varying highp float light_depth;

void vertex() {
	highp vec3 bytes = round(COLOR.rgb * 255.0);
	highp float packed = dot(bytes, vec3(1.0, 256.0, 65536.0));
	highp vec2 origin = vec2(mod(packed, 512.0), mod(floor(packed / 512.0), 512.0)) * (8.0 / 4096.0);
	highp vec2 size = exp2(vec2(5.0) + vec2(mod(floor(packed / 262144.0), 4.0), mod(floor(packed / 1048576.0), 4.0))) / 4096.0;
	atlas_rect = vec4(origin, size);
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	light_depth = (dot(world_position, sun_direction) - depth_min) / depth_span;
}

void fragment() {
	vec2 half_pixel = vec2(0.5) / (atlas_rect.zw * 4096.0);
	vec2 local_uv = clamp(fract(UV), half_pixel, vec2(1.0) - half_pixel);
	if (texture(atlas, atlas_rect.xy + local_uv * atlas_rect.zw).a < 0.45) { discard; }
	highp float depth = floor(clamp(light_depth, 0.000001, 0.999999) * 16777215.0 + 0.5);
	vec3 bytes = vec3(mod(depth, 256.0), mod(floor(depth / 256.0), 256.0), floor(depth / 65536.0)) / 255.0;
	// Compatibility converts ALBEDO from sRGB before its final sRGB output.
	// Those conversions cancel for an unshaded material, preserving data bytes.
	ALBEDO = bytes;
}
