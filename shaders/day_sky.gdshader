shader_type sky;
uniform vec3 sun_direction = vec3(-0.214, 0.927, 0.307);
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// Photographic solar centre, measured from the original HDR panorama.
uniform vec2 panorama_sun_uv = vec2(0.5951673720, 0.2339545356);

void sky() {
	vec3 direction = normalize(EYEDIR);
	vec3 sun = normalize(sun_direction);
	float target_elevation = asin(sun.y);
	float source_elevation = (0.5 - panorama_sun_uv.y) * PI;
	float elevation = asin(clamp(direction.y, -1.0, 1.0));
	// Align the photographed sun with the existing bake, preserving the horizon
	// and zenith. Smooth derivatives keep its disc round at the alignment point.
	float weight = elevation < target_elevation
		? smoothstep(0.0, target_elevation, elevation)
		: 1.0 - smoothstep(target_elevation, PI * 0.5, elevation);
	float sampled_elevation = elevation - (target_elevation - source_elevation) * weight;
	float sun_azimuth = atan(sun.x, sun.z) / TAU + 0.5;
	vec2 uv = vec2(atan(direction.x, direction.z) / TAU + 0.5 + panorama_sun_uv.x - sun_azimuth, 0.5 - sampled_elevation / PI);
	COLOR = texture(panorama, uv).rgb;
}
