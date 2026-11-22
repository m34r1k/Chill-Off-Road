shader_type sky;
// Stylized sky: colour gradient, sun glow, drifting clouds, stars and a moon.
// Every uniform here is driven each frame by scripts/atmosphere.gd.

uniform vec3 zenith_color : source_color = vec3(0.22, 0.47, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.82, 0.95);
uniform vec3 ground_color : source_color = vec3(0.3, 0.33, 0.3);
uniform vec3 sun_direction = vec3(0.0, 0.5, -0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.9);
uniform float sun_size = 0.035;
uniform float sun_glow = 0.5;
uniform vec3 moon_direction = vec3(0.0, -0.5, 0.8);
uniform float moon_size = 0.03;
uniform float night = 0.0;

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.35;
uniform vec3 cloud_light_color : source_color = vec3(1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.62, 0.66, 0.76);
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_scale = 0.55;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	const mat2 turn = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * value_noise(p);
		p = turn * p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

// 0 = clear sky, 1 = solid cloud. Coverage lowers the threshold noise must pass;
// the curve keeps the slider's low end for scattered clouds and its top end fully overcast.
float cloud_density(vec2 uv, int octaves) {
	float threshold = mix(0.68, -0.05, pow(cloud_coverage, 1.5));
	return smoothstep(threshold, threshold + 0.16, fbm(uv, octaves)) * smoothstep(0.0, 0.1, cloud_coverage);
}

vec3 stars(vec3 dir) {
	vec3 p = dir * 180.0;
	vec3 cell = floor(p);
	float r = hash13(cell);
	if (r < 0.985) {
		return vec3(0.0);
	}
	float brightness = 1.0 - smoothstep(0.0, 0.35, length(p - (cell + 0.5)));
	return vec3(0.9, 0.93, 1.0) * brightness * (r - 0.985) / 0.015 * 3.0;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;

	// Horizon band blending up into the zenith, and down into the ground colour.
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.45));
	col = mix(col, ground_color, 1.0 - smoothstep(-0.25, 0.0, h));

	// Sun glow, strongest when the sun is low (golden hour).
	float sun_dot = dot(dir, sun_direction);
	float sun_up = smoothstep(-0.15, 0.05, sun_direction.y);
	float low_sun = 1.0 - smoothstep(0.0, 0.5, sun_direction.y);
	col += sun_color * pow(max(sun_dot, 0.0), 8.0) * sun_glow * (0.4 + 0.6 * low_sun) * sun_up;
	col += sun_color * pow(max(sun_dot, 0.0), 120.0) * 0.6 * sun_up;

	// Small sharp details are skipped in the low-res lighting pass.
	if (!AT_CUBEMAP_PASS) {
		if (night > 0.0 && h > 0.0) {
			col += stars(dir) * night * smoothstep(0.0, 0.2, h);
		}
		float moon_dot = dot(dir, moon_direction);
		float moon = smoothstep(cos(moon_size), cos(moon_size * 0.85), moon_dot);
		col = mix(col, vec3(0.92, 0.93, 0.98) * 1.4, moon * night);
		col += vec3(0.5, 0.6, 0.8) * pow(max(moon_dot, 0.0), 200.0) * 0.4 * night;

		float disc = smoothstep(cos(sun_size), cos(sun_size * 0.8), sun_dot);
		col += sun_color * disc * 6.0 * sun_up;
	}

	// Clouds: noise projected onto a flat layer overhead, drifting with the wind.
	if (h > 0.0 && cloud_coverage > 0.001) {
		vec2 uv = dir.xz / (h + 0.15) * cloud_scale + cloud_offset;
		float density = cloud_density(uv, AT_CUBEMAP_PASS ? 3 : 5);
		// Thicker cloud between this point and the sun means this side is in shadow.
		vec2 toward_sun = normalize(sun_direction.xz + vec2(1e-4)) * 0.12;
		float shadow = cloud_density(uv + toward_sun, 3);
		vec3 cloud = mix(cloud_light_color, cloud_shadow_color, clamp(shadow * 1.1, 0.0, 1.0));
		// Glowing edges when looking toward the sun.
		cloud += sun_color * pow(max(sun_dot, 0.0), 12.0) * (1.0 - density) * 0.8 * sun_up;
		// Far-away clouds melt into the horizon haze.
		cloud = mix(cloud, horizon_color, (1.0 - smoothstep(0.0, 0.35, h)) * 0.6);
		density *= smoothstep(0.0, 0.08, h);
		col = mix(col, cloud, density);
	}

	COLOR = col;
}
