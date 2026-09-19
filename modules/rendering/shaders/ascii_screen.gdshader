shader_type canvas_item;

uniform sampler2D fg_texture : filter_nearest, repeat_disable;
uniform sampler2D bg_texture : filter_nearest, repeat_disable;
uniform sampler2D glyph_texture : filter_nearest, repeat_disable;
uniform sampler2D font_atlas : filter_nearest, repeat_disable;

uniform float time_sec;
uniform vec2 wind_dir;
uniform float wind_strength;
uniform float zoom_level;
uniform vec2 cloud_dir;   // normalised cardinal direction set by ClimateSystem (season)

const vec2 GRID_SIZE = vec2(128.0, 128.0);
const vec2 ATLAS_GRID = vec2(16.0, 16.0);
const float SWAY_THRESHOLD = 0.15;
const float WAVE_FREQ = 0.10;
const float WAVE_SPEED = 0.50;

// Cloud overlay constants
const float CLOUD_SCALE     = 10.0;  // lower = bigger cloud blobs (world-space tiles)
const float CLOUD_SPEED     = 0.006; // base cardinal scroll speed (tiles/sec) — always-on
const float CLOUD_WIND_NUDGE = 0.0015; // extra wind-driven contribution (much weaker than base)
const float CLOUD_THRESHOLD = 0.50;  // noise value below which there is no cloud — higher = sparser
const float DAY_LENGTH_SEC = 600.0;  // seconds per full day cycle (tune to taste)
const float MOON_INTENSITY = 0.28;   // moonlight as fraction of sun intensity
const float STAR_THRESHOLD = 0.965;  // ~3.5% of tiles receive a star dot
const float STAR_ALPHA_MAX = 0.55;   // peak star brightness
const float HAZE_MAX_ALPHA = 0.02;   // cloud haze opacity cap (keeps glyphs readable)
const float SHADE_MUL_MIN  = 0.70;   // darkest a cloud shadow can make a tile
const float SUN_LIFT_MAX   = 0.33;   // max additive brightness in full sunlight

// ---------------------------------------------------------------------------
// Cloud noise helpers — 2-octave FBM using a fast value-noise hash
// ---------------------------------------------------------------------------
vec2 _cloud_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float _cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f); // smoothstep blend
	float a = dot(_cloud_hash(i),              f);
	float b = dot(_cloud_hash(i + vec2(1,0)),  f - vec2(1,0));
	float c = dot(_cloud_hash(i + vec2(0,1)),  f - vec2(0,1));
	float d = dot(_cloud_hash(i + vec2(1,1)),  f - vec2(1,1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}

float sample_cloud(vec2 world_tile_uv) {
	// Two-octave FBM: large base shape + finer detail
	float n = _cloud_noise(world_tile_uv)                 * 0.65
	        + _cloud_noise(world_tile_uv * 2.1 + vec2(5.2, 1.3)) * 0.35;
	// Remap so only the denser portions form visible cloud
	return smoothstep(CLOUD_THRESHOLD, CLOUD_THRESHOLD + 0.35, n);
}

// ---------------------------------------------------------------------------
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

	// ---------------------------------------------------------------------------
	// HD-2D Lighting: Full Day/Night Cycle + Cloud Shadows
	// ---------------------------------------------------------------------------

	// --- Day position and sun altitude ---
	// day_t : 0=midnight, 0.25=sunrise, 0.5=noon, 0.75=sunset
	// sun_alt: -1=midnight, 0=horizon, +1=noon
	float day_t   = mod(time_sec, DAY_LENGTH_SEC) / DAY_LENGTH_SEC;
	float sun_alt = sin((day_t - 0.25) * 6.2831853);
	float sun_above   = max(0.0, sun_alt);                          // 0 at night
	float night_amt   = smoothstep(0.0, -0.25, sun_alt);            // 1 at full night
	float golden_amt  = 1.0 - smoothstep(0.0, 0.40, abs(sun_alt)); // 1 at horizon
	float is_dawn     = golden_amt * step(day_t, 0.5);              // dawn side only
	float is_dusk     = golden_amt * step(0.5, day_t);              // dusk side only
	float dawn_close  = 1.0 - smoothstep(0.0, 0.08, sun_alt);      // tight to horizon

	// Moon travels opposite the sun
	float moon_alt   = sin((day_t + 0.25) * 6.2831853);
	float moon_above = max(0.0, moon_alt);

	// --- Sun color keyframes (blended across phases) ---
	vec3 sun_noon    = vec3(1.00, 0.96, 0.82); // warm white — midday
	vec3 sun_golden  = vec3(1.00, 0.78, 0.42); // golden — late morning / early afternoon
	vec3 sun_sunrise = vec3(1.00, 0.62, 0.28); // amber orange — sunrise
	vec3 sun_dawn_c  = vec3(0.92, 0.50, 0.68); // rose / magenta — pre-sunrise
	vec3 sun_dusk_c  = vec3(1.00, 0.48, 0.18); // blood orange — sunset
	vec3 sun_eve     = vec3(0.50, 0.28, 0.62); // purple — evening
	vec3 moon_col    = vec3(0.60, 0.70, 0.95); // cool blue-white moonlight

	vec3 sky_day   = vec3(0.52, 0.63, 0.82); // blue sky ambient
	vec3 sky_gold  = vec3(0.65, 0.50, 0.42); // warm grey horizon ambient
	vec3 sky_night = vec3(0.04, 0.06, 0.18); // deep navy night ambient

	// Build sun color by layering phase transitions
	vec3 sun_col = mix(sun_noon, sun_golden,  golden_amt);
	sun_col = mix(sun_col, sun_sunrise, is_dawn * 0.60);
	sun_col = mix(sun_col, sun_dawn_c,  is_dawn * dawn_close * 0.80);
	sun_col = mix(sun_col, sun_dusk_c,  is_dusk * 0.85);
	sun_col = mix(sun_col, sun_eve,     smoothstep(0.0, -0.20, sun_alt));
	sun_col = mix(sun_col, moon_col * MOON_INTENSITY, night_amt);

	vec3 sky_col = mix(sky_day, sky_night, night_amt);
	sky_col = mix(sky_col, sky_gold, golden_amt * (1.0 - night_amt));

	// --- Soft cloud density: 3-scale FBM for smooth penumbra at cloud edges ---
	// Cardinal cloud scroll: constant base speed along cloud_dir (season-driven),
	// plus a mild wind nudge — completely independent of wind_strength magnitude.
	vec2 cloud_scroll = cloud_dir * CLOUD_SPEED * time_sec
	                  + wind_dir  * wind_strength * CLOUD_WIND_NUDGE * time_sec;
	vec2 cloud_uv     = (UV * GRID_SIZE / CLOUD_SCALE) + cloud_scroll;
	float cn0 = sample_cloud(cloud_uv);
	float cn1 = sample_cloud(cloud_uv * 0.72 + vec2(1.7,  0.9));
	float cn2 = sample_cloud(cloud_uv * 1.55 - vec2(0.6,  1.3));
	float cloud_density  = cn0 * 0.55 + cn1 * 0.28 + cn2 * 0.17;
	// Clouds only cast meaningful shadow when the sun is up
	float effective_light = mix(1.0, 1.0 - cloud_density, sun_above * 0.85);

	if (!is_burning) {
		// --- Shadow / sunlight tile mix ---
		float shade_mul = mix(SHADE_MUL_MIN, 1.0, effective_light);
		float sun_lift  = SUN_LIFT_MAX * sun_above * effective_light;
		vec3  sky_fill  = sky_col * 0.10 * cloud_density * sun_above;

		vec3 in_shadow = final_color.rgb * shade_mul + sky_fill;
		vec3 in_sun    = final_color.rgb * sun_col * (1.0 + sun_lift);
		final_color.rgb = mix(in_shadow, in_sun, effective_light);

		// --- Penumbra / crepuscular glow at cloud-shadow boundaries ---
		float edge       = effective_light * (1.0 - effective_light) * 4.0;
		float golden_bst = 1.0 + golden_amt * 0.5; // wider glow at dawn/dusk
		final_color.rgb += sun_col * edge * 0.12 * golden_bst * sun_above;

		// --- Moonlight (additive, cloud-attenuated) ---
		float moon_factor = mix(1.0, 1.0 - cloud_density, moon_above * 0.5);
		float moon_lift   = 0.12 * night_amt * moon_above * moon_factor;
		final_color.rgb  += final_color.rgb * moon_col * moon_lift;

		// --- Stars (procedural per-tile, dark tiles only, night only) ---
		float star_h   = fract(sin(dot(tile_pos, vec2(127.1, 311.7))) * 43758.5453);
		float bg_lum   = dot(bg_col.rgb, vec3(0.299, 0.587, 0.114));
		float star_vis = night_amt * smoothstep(0.25, 0.0, bg_lum);
		float twinkle  = 0.7 + 0.3 * sin(time_sec * 3.14159 + star_h * 62.8318);
		float star_alpha = step(STAR_THRESHOLD, star_h) * star_vis * twinkle * STAR_ALPHA_MAX;
		final_color.rgb += vec3(0.85, 0.90, 1.00) * star_alpha;

		// --- Global exposure envelope (dark at night, full at noon) ---
		float exposure  = mix(0.28, 1.0, smoothstep(-0.20, 0.25, sun_alt));
		// Moonlit nights get a slightly brighter floor
		exposure = max(exposure, moon_above * 0.18 * night_amt);
		final_color.rgb *= exposure;

		// --- Mild Reinhard tonemap: compresses sun highlights, preserves midtones ---
		// At input=1.0 output is exactly 1.0; values >1.0 are soft-clipped
		final_color.rgb = final_color.rgb / (final_color.rgb + vec3(0.75)) * vec3(1.75);

		// --- Residual cloud haze (very subtle, day only) ---
		float haze_alpha = cloud_density * wind_strength * HAZE_MAX_ALPHA * sun_above;
		vec3  haze_col   = mix(vec3(0.88, 0.92, 1.0), vec3(0.50, 0.55, 0.75), cloud_density);
		final_color.rgb  = mix(final_color.rgb, haze_col, haze_alpha);
	}

	COLOR = final_color;
}
