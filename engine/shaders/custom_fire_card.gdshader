shader_type spatial;
// DW1-style flame cards on a custom model (Flarerizamon's back crest and foot rings,
// tools/hy3d_rig.py --cards): two-sided quads cut out by a flame tile (tools/flame_tile.py, the
// frames side by side, root at the bottom). DW1 flickers its cards by pasting one of three flame
// bands every 0.1 s in the order 3,1,2,3,2,1 (FUN_800c1824); the frames step the same way, and
// TS's flame map bends the lookup a little so the tips lick between steps.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D noise_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float frames = 3.0;
uniform float step_time = 0.1;          // DW1: a band every 0.1 s
uniform float distort = 0.12;           // how far the tips sway, in tile widths
uniform vec2 flow = vec2(0.0, -0.75);
uniform vec3 emission_tint = vec3(1.0, 0.47, 0.11);
uniform float emission_strength = 1.0;
uniform float glow = 0.8;
uniform float roughness = 0.6;

int band(float t) {
	int i = int(mod(floor(t / step_time), 6.0));
	// DW1's order 3,1,2,3,2,1 as frame indices
	return i == 0 ? 2 : (i == 1 ? 0 : (i == 2 ? 1 : (i == 3 ? 2 : (i == 4 ? 1 : 0))));
}

void fragment() {
	float fw = 1.0 / frames;
	vec2 uv = UV;
	vec2 n = texture(noise_tex, vec2(UV.x * 3.0 / fw, UV.y) * 0.5 + TIME * flow).xy * 2.0 - 1.0;
	uv.x += n.x * distort * fw * (1.0 - UV.y);          // v 0 = the tip: it sways most
	uv.x = clamp(uv.x, 0.002, fw - 0.002) + float(band(TIME)) * fw;
	vec4 a = texture(albedo_tex, uv);
	ALBEDO = a.rgb;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = roughness;
	EMISSION = a.rgb * emission_tint * emission_strength * glow;
}
