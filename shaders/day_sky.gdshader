shader_type sky;
uniform vec3 sun_direction = vec3(-0.214, 0.927, 0.307);

void sky() {
	vec3 direction = normalize(EYEDIR);
	float elevation = max(direction.y, 0.0);
	vec3 horizon = vec3(0.48, 0.65, 0.82);
	vec3 zenith = vec3(0.07, 0.27, 0.60);
	vec3 atmosphere = mix(horizon, zenith, pow(elevation, 0.45));
	if (direction.y < 0.0) {
		atmosphere = mix(vec3(0.10, 0.12, 0.14), horizon, exp(direction.y * 18.0));
	}
	float separation = acos(clamp(dot(direction, normalize(sun_direction)), -1.0, 1.0));
	float disc = 1.0 - smoothstep(0.0042, 0.0049, separation);
	float halo = exp(-pow(separation / 0.025, 2.0));
	COLOR = atmosphere + vec3(1.0, 0.94, 0.80) * (disc * 8.0 + halo * 0.18);
}
