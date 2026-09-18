shader_type canvas_item;

uniform sampler2D fg_texture : filter_nearest, repeat_disable;
uniform sampler2D bg_texture : filter_nearest, repeat_disable;
uniform sampler2D glyph_texture : filter_nearest, repeat_disable;
uniform sampler2D font_atlas : filter_nearest, repeat_disable;

uniform float time_sec;
uniform vec2 wind_dir;
uniform float wind_strength;
uniform float zoom_level;

const vec2 GRID_SIZE = vec2(128.0, 128.0);
const vec2 ATLAS_GRID = vec2(16.0, 16.0);
const float SWAY_THRESHOLD = 0.20;
const float WAVE_FREQ = 0.10;
const float WAVE_SPEED = 0.50;

float sample_rain_intensity(vec2 p) {
	vec2 clamped_p = clamp(p, vec2(0.0), GRID_SIZE - vec2(1.0));
	vec2 uv = (clamped_p + vec2(0.5)) / GRID_SIZE;
	int fl = int(floor(texture(glyph_texture, uv).a * 255.0 + 0.5));
	return float((fl >> 2) & 63) / 63.0;
}

void fragment() {
	// Determine tile and in-cell UV coordinates
	vec2 tile_pos = floor(UV * GRID_SIZE);
	vec2 cell_uv = fract(UV * GRID_SIZE);
	tile_pos = clamp(tile_pos, vec2(0.0), GRID_SIZE - vec2(1.0));
	vec2 tile_uv = (tile_pos + vec2(0.5)) / GRID_SIZE;

	vec4 bg_col = texture(bg_texture, tile_uv);
	vec4 fg_col = texture(fg_texture, tile_uv);
	vec4 glyph_data = texture(glyph_texture, tile_uv);

	float base_glyph = floor(glyph_data.r * 255.0 + 0.5);
	float sway_glyph = floor(glyph_data.g * 255.0 + 0.5);
	float sway_factor = glyph_data.b;
	int flags = int(floor(glyph_data.a * 255.0 + 0.5));

	bool is_burning = (flags & 1) != 0;
	bool is_frozen = (flags & 2) != 0;

	// Bilinear smooth filtering for rain intensity across tile boundaries
	vec2 rain_sample_coord = tile_pos + cell_uv - vec2(0.5);
	vec2 p00 = floor(rain_sample_coord);
	vec2 rf = fract(rain_sample_coord);
	float r00 = sample_rain_intensity(p00);
	float r10 = sample_rain_intensity(p00 + vec2(1.0, 0.0));
	float r01 = sample_rain_intensity(p00 + vec2(0.0, 1.0));
	float r11 = sample_rain_intensity(p00 + vec2(1.0, 1.0));
	float smooth_rain_intensity = mix(mix(r00, r10, rf.x), mix(r01, r11, rf.x), rf.y);

	// Rain representation: slow strobing deep-blue tint overlay per tile
	float rain_strobe = 0.0;
	vec3 target_blue = vec3(0.0);
	if (smooth_rain_intensity > 0.001) {
		// Per-tile phase offset for organic, non-uniform strobing
		float tile_phase = mod(tile_pos.x * 1.618034 + tile_pos.y * 2.414214, 6.2831853);
		// Slow strobing cycle (~1.6 rad/s -> ~3.9s per full pulse)
		rain_strobe = (sin(time_sec * 1.6 + tile_phase) + 1.0) * 0.5;
		rain_strobe = smoothstep(0.1, 0.9, rain_strobe);

		// Color grade based on rain intensity:
		// Light rain: cool slate blue
		// Heavy rain: deep, dark midnight / oceanic storm blue
		vec3 light_blue = vec3(0.10, 0.22, 0.40);
		vec3 deep_blue  = vec3(0.012, 0.045, 0.18);
		target_blue = mix(light_blue, deep_blue, smooth_rain_intensity);

		// Depth of tint scales with intensity and pulses with the slow strobe
		float strobe_factor = mix(0.55, 1.0, rain_strobe);
		float bg_tint_factor = clamp(smooth_rain_intensity * 0.88 * strobe_factor, 0.0, 0.92);
		bg_col.rgb = mix(bg_col.rgb, target_blue, bg_tint_factor);

		// Foreground glyphs softly pulse with cool rain tint
		vec3 fg_rain_tint = mix(vec3(0.62, 0.76, 0.92), vec3(0.35, 0.55, 0.85), smooth_rain_intensity);
		fg_col.rgb = mix(fg_col.rgb, fg_rain_tint, smooth_rain_intensity * (0.25 + 0.25 * rain_strobe));
	}

	// Wind wave animation
	float chosen_glyph = base_glyph;
	if (wind_strength > 0.05 && sway_factor > 0.0) {
		float phase = dot(tile_pos, wind_dir) * WAVE_FREQ;
		float wave = sin(phase - time_sec * wind_strength * WAVE_SPEED) * wind_strength;
		float effective = wave * sway_factor;
		if (effective > SWAY_THRESHOLD) {
			if (sway_glyph > 0.0) {
				chosen_glyph = sway_glyph;
			}
			fg_col.rgb = mix(fg_col.rgb, vec3(1.0), effective * 0.22);
		} else if (effective < -SWAY_THRESHOLD * 0.8) {
			fg_col.rgb = mix(fg_col.rgb, vec3(0.0), abs(effective) * 0.12);
		}
	}

	// Burning / Frozen overlay
	if (is_burning) {
		float b_phase = mod(tile_pos.x * 1.618 + tile_pos.y * 2.414, 6.2831853);
		float flame_pulse = (sin(time_sec * 8.0 + b_phase) + 1.0) * 0.5;
		bg_col.rgb = mix(bg_col.rgb, vec3(0.75, 0.22, 0.02), 0.55 + flame_pulse * 0.45);
		fg_col = vec4(1.0, 0.70 + flame_pulse * 0.30, 0.05, 1.0);
		// Cycle flame chars: ^ (94), * (42), ^ (94), ~ (126)
		int f_idx = int(mod(time_sec * 8.0 + tile_pos.x * 0.7 + tile_pos.y * 0.5, 4.0));
		if (f_idx == 0 || f_idx == 2) {
			chosen_glyph = 94.0;
		} else if (f_idx == 1) {
			chosen_glyph = 42.0;
		} else {
			chosen_glyph = 126.0;
		}
	} else if (is_frozen) {
		bg_col.rgb = mix(bg_col.rgb, vec3(0.70, 0.85, 1.0), 0.50);
		fg_col.rgb = mix(fg_col.rgb, vec3(0.80, 0.90, 1.0), 0.40);
	}

	// Sample font atlas (16 columns x 16 rows)
	float glyph_x = mod(chosen_glyph, ATLAS_GRID.x);
	float glyph_y = floor(chosen_glyph / ATLAS_GRID.x);
	vec2 atlas_uv = (vec2(glyph_x, glyph_y) + cell_uv) / ATLAS_GRID;
	vec4 font_sample = texture(font_atlas, atlas_uv);
	float glyph_mask = font_sample.a;

	vec4 final_color = mix(bg_col, fg_col, glyph_mask);

	// Slow strobing tint overlay on final color (rain particles completely disabled)
	if (smooth_rain_intensity > 0.001 && !is_burning) {
		float overlay_alpha = smooth_rain_intensity * (0.10 + 0.18 * rain_strobe);
		final_color.rgb = mix(final_color.rgb, target_blue, overlay_alpha);
	}

	COLOR = final_color;
}
