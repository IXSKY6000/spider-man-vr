shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Deep harbour water. Dielectric Fresnel and sky reflections use Godot's PBR.
// No screen/depth textures: GLES3 and stereo OpenXR compatible.
uniform vec3 water_color : source_color = vec3(0.035, 0.115, 0.135);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.75;
uniform float surface_roughness : hint_range(0.02, 0.5) = 0.13;
uniform float patch_half_size = 96.0;
uniform bool displace_vertices = true;
uniform sampler2D ripple_normal : hint_normal, repeat_enable, filter_linear_mipmap;
varying vec2 water_world_xz;
varying vec2 large_wave_slope;

// Height and analytic gradient. Deep-water dispersion: omega squared = g*k.
vec3 wave(vec2 p, vec2 direction, float wavelength, float amplitude, float phase) {
 float k = 6.2831853 / wavelength;
 float theta = dot(p, direction) * k - sqrt(9.81 * k) * TIME + phase;
 return vec3(amplitude * sin(theta), amplitude * k * cos(theta) * direction);
}

void vertex() {
 water_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
 large_wave_slope = vec2(0.0);
 if (displace_vertices) {
  vec3 swell = wave(water_world_xz, vec2(0.94, 0.342), 19.0, 0.15, 0.0);
  swell += wave(water_world_xz, vec2(-0.38, 0.925), 11.5, 0.075, 1.7);
  swell += wave(water_world_xz, vec2(0.68, -0.733), 7.3, 0.035, 4.1);
  // Flatten at the patch edge to meet the distant tiles without a height seam.
  vec2 a = abs(VERTEX.xz);
  float radius = max(a.x, a.y) / patch_half_size;
  float t = clamp((radius - 0.65) / 0.35, 0.0, 1.0);
  float envelope = 1.0 - t * t * (3.0 - 2.0 * t);
  float derivative = -6.0 * t * (1.0 - t) / (0.35 * patch_half_size);
  vec2 edge_gradient = a.x > a.y ? vec2(sign(VERTEX.x), 0.0) : vec2(0.0, sign(VERTEX.z));
  VERTEX.y += swell.x * envelope * wind_strength;
  large_wave_slope = (swell.yz * envelope + swell.x * derivative * edge_gradient) * wind_strength;
 }
}

void fragment() {
 vec2 p = water_world_xz;
 // Filter subpixel ripples to reduce distant shimmer, including in stereo.
 float footprint = max(length(dFdx(p)), length(dFdy(p)));
 float detail = 1.0 - smoothstep(0.03, 0.32, footprint);
 float medium = 1.0 - smoothstep(0.15, 1.2, footprint);
 vec2 slope = large_wave_slope;
 slope += medium * wave(p, vec2(0.94, 0.342), 2.4, 0.018, 2.3).yz * wind_strength;
 slope += medium * wave(p, vec2(-0.62, 0.785), 1.37, 0.010, 5.4).yz * wind_strength;
 // Cross-flowing seamless fractal normals break up regular wave trains.
 vec2 normal_a = texture(ripple_normal, p * 0.065 + vec2(TIME * 0.007, TIME * 0.003)).rg * 2.0 - 1.0;
 vec2 normal_b = texture(ripple_normal, p * 0.193 + vec2(-TIME * 0.011, TIME * 0.006)).rg * 2.0 - 1.0;
 slope += wind_strength * (normal_a * medium * 0.26 + normal_b * detail * 0.13);
 slope += detail * wave(p, vec2(0.83, -0.558), 0.43, 0.0008, 3.7).yz * wind_strength;
 slope += detail * wave(p, vec2(0.44, 0.898), 0.27, 0.0005, 0.9).yz * wind_strength;
 vec3 normal_world = normalize(vec3(-slope.x, 1.0, -slope.y));
 NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
 ALBEDO = water_color;
 // Water IOR 1.333 gives F0 approximately 0.02. Non-metallic surface.
 METALLIC = 0.0;
 SPECULAR = 0.25;
 ROUGHNESS = mix(0.24, surface_roughness, medium);
}
