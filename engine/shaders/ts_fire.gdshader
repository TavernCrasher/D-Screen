shader_type spatial;
// Time Stranger's moving fire (data/ts_fire.json, tools/ts_fire.py): a tiling flame normal map
// (chr_f01n) scrolls over the second UV set and bends the lookup of the fire texture, so the
// flames flow and flicker; the fire glows in TS's emissive tint. Flame cards (the "eff" mesh,
// a fire sprite) cut out by the sprite's alpha, so their outline licks as the lookup bends.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D distort_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform vec2 scroll = vec2(0.05, -0.75);     // UV2 units per second (ScrollSpeedSet2U)
uniform float distort = 0.02;                // how far the scrolling normal bends the lookup
uniform vec3 emission_tint = vec3(1.0);      // EmissiveIntensity
uniform float emission_strength = 1.0;       // EmissiveSampler, scaled to the old look
uniform bool card = false;
uniform float roughness = 0.5;

void fragment() {
	vec2 n = texture(distort_tex, UV2 + TIME * scroll).xy * 2.0 - 1.0;
	// a second, slower layer crossing the first breaks up the repetition
	n += (texture(distort_tex, UV2 * 0.7 + TIME * scroll * vec2(-0.6, 0.55)).xy * 2.0 - 1.0) * 0.5;
	vec2 uv = UV + n * distort;
	vec4 a = texture(albedo_tex, uv);
	ALBEDO = a.rgb;
	if (card) {
		ALPHA = a.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	EMISSION = texture(emission_tex, uv).rgb * emission_tint * emission_strength;
	ROUGHNESS = roughness;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
