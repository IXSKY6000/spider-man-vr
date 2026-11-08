shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D shadow_0 : filter_nearest, repeat_disable;
uniform sampler2D shadow_1 : filter_nearest, repeat_disable;
uniform sampler2D shadow_2 : filter_nearest, repeat_disable;
uniform sampler2D shadow_3 : filter_nearest, repeat_disable;
uniform vec3 sun_direction;
uniform vec3 shadow_right;
uniform vec3 shadow_up;
uniform vec2 shadow_minimum;
uniform float shadow_span;
uniform float depth_min;
uniform float depth_span;
uniform float shadow_resolution = 4096.0;
uniform float shadow_grid = 2.0;
uniform float lighting_exposure = 1.0;
uniform float fade_distance = 900.0;
uniform float fade_width = 140.0;
varying highp vec4 atlas_rect;
varying highp vec3 world_position;
varying vec3 world_normal;
varying float view_distance;

void vertex() {
 highp vec3 bytes = round(COLOR.rgb * 255.0);
 highp float packed = dot(bytes, vec3(1.0, 256.0, 65536.0));
 highp vec2 origin = vec2(mod(packed, 512.0), mod(floor(packed / 512.0), 512.0)) * (8.0 / 4096.0);
 highp vec2 size = exp2(vec2(5.0) + vec2(mod(floor(packed / 262144.0), 4.0), mod(floor(packed / 1048576.0), 4.0))) / 4096.0;
 atlas_rect = vec4(origin, size);
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
 view_distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float stored_depth(vec2 global_uv) {
 vec2 scaled = clamp(global_uv, vec2(0.0000001), vec2(0.9999999)) * shadow_grid;
 vec2 local = fract(scaled);
 local.y = 1.0 - local.y;
 vec3 encoded;
 if (shadow_grid < 1.5) { encoded = texture(shadow_0, local).rgb; }
 else if (scaled.y < 1.0) {
  if (scaled.x < 1.0) { encoded = texture(shadow_0, local).rgb; }
  else { encoded = texture(shadow_1, local).rgb; }
 } else {
  if (scaled.x < 1.0) { encoded = texture(shadow_2, local).rgb; }
  else { encoded = texture(shadow_3, local).rgb; }
 }
 return dot(round(encoded * 255.0), vec3(1.0, 256.0, 65536.0)) / 16777215.0;
}

float sunlight(vec3 normal) {
 vec2 uv = (vec2(dot(world_position, shadow_right), dot(world_position, shadow_up)) - shadow_minimum) / shadow_span;
 if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 1.0; }
 highp float receiver = (dot(world_position, sun_direction) - depth_min) / depth_span;
 // Compare on the receiver plane, preserving contacts on sloped ground/walls.
 vec3 face_normal = normalize(cross(dFdx(world_position), dFdy(world_position)));
 float plane_dot = dot(face_normal, sun_direction);
 plane_dot = (plane_dot < 0.0 ? -1.0 : 1.0) * max(abs(plane_dot), 0.05);
 vec2 plane_gradient = -vec2(dot(face_normal, shadow_right), dot(face_normal, shadow_up)) / plane_dot;
 float bias = 0.06 / depth_span;
 vec2 texel = vec2(1.0 / (shadow_resolution * shadow_grid));
 vec2 pixel = uv / texel - 0.5;
 vec2 fraction = fract(pixel);
 vec2 first = (floor(pixel) + 0.5) * texel;
 float visibility = 0.0;
 for (int y = 0; y < 2; y++) {
  for (int x = 0; x < 2; x++) {
   vec2 sample_uv = first + vec2(float(x), float(y)) * texel;
   float correction = clamp(dot((sample_uv - uv) * shadow_span, plane_gradient), -1.5, 1.5) / depth_span;
   float caster = stored_depth(sample_uv);
   vec2 weight = mix(1.0 - fraction, fraction, vec2(float(x), float(y)));
   visibility += step(caster - bias, receiver + correction) * weight.x * weight.y;
  }
 }
 return visibility;
}

vec3 to_linear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), greaterThan(c, vec3(0.04045))); }
vec3 to_srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, greaterThan(c, vec3(0.0031308))); }

void fragment() {
 vec2 dx = dFdx(UV) * atlas_rect.zw;
 vec2 dy = dFdy(UV) * atlas_rect.zw;
 float major_length = max(length(dx), length(dy)) * 4096.0;
 float minor_length = min(length(dx), length(dy)) * 4096.0;
 float mip = clamp(log2(max(minor_length, 1.0)), 0.0, 2.0);
 vec2 major_axis = length(dx) > length(dy) ? dx : dy;
 major_axis *= min(1.0, 4.0 * exp2(mip) / max(major_length, 0.001));
 vec2 inset = vec2(0.5) / (atlas_rect.zw * 4096.0);
 vec4 color = vec4(0.0);
 // Bound each anisotropic tap to its own repeated tile. Hardware anisotropy
 // can otherwise sample neighbouring images in the shared atlas.
 for (int i = 0; i < 4; i++) {
  vec2 local = fract(UV + (float(i) * 0.25 - 0.375) * major_axis / atlas_rect.zw);
  vec2 uv = atlas_rect.xy + clamp(local, inset, vec2(1.0) - inset) * atlas_rect.zw;
  color += textureLod(atlas, uv, mip) * 0.25;
 }
 if (color.a < 0.45) { discard; }
 vec3 normal = normalize(world_normal);
 vec3 ambient = mix(vec3(0.15, 0.14, 0.13), vec3(0.26, 0.31, 0.39), normal.y * 0.5 + 0.5);
 float direct = max(dot(normal, sun_direction), 0.0) * sunlight(normal);
 vec3 base = OUTPUT_IS_SRGB ? to_linear(color.rgb) : color.rgb;
 vec3 radiance = base * (ambient + vec3(1.05, 0.99, 0.87) * direct) * lighting_exposure;
 ALBEDO = OUTPUT_IS_SRGB ? to_srgb(radiance) : radiance;
 ALPHA = 1.0 - smoothstep(fade_distance - fade_width, fade_distance, view_distance);
 ALPHA_HASH_SCALE = 1.0;
}
