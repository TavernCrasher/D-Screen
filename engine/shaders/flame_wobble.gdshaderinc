// The flicker of a custom model's flame tongues (custom_fire.gdshader and its outline
// dw1_outline_flame.gdshader share it, so the outline stays on the moving tips). The mesh carries
// per-vertex COLOR_0 from tools/hy3d_rig.py --flame-mask: r = flame mask (0 core, 1 tongue),
// g = tip weight (0 root, 1 tip), b = the tongue's phase, a = emission weight. Model space, after
// skinning, so DW1's bob and squash still apply; the tongues stream back (-z) like a comet.

uniform float wobble_amount = 0.025;    // metres at a tip (~4% of DemiMeramon's body width)
uniform float wobble_speed = 3.0;       // flickers per second
uniform float stretch_amount = 0.03;    // tips lengthen and shorten backwards by up to this much

vec3 flame_wobble(vec3 v, vec4 c) {
	float tip = c.r * c.g * c.g;        // roots stay put, tips move most
	float ph = c.b * 6.2832;
	// a wave travelling from root to tip, two frequencies so it never repeats exactly
	float t = TIME * wobble_speed * 6.2832;
	float w1 = sin(t + ph - c.g * 3.0);
	float w2 = sin(t * 1.73 + ph * 2.0 - c.g * 5.0);
	v.x += (w1 * 0.7 + w2 * 0.3) * wobble_amount * tip;
	v.y += (w2 * 0.6 + w1 * 0.2) * wobble_amount * 0.6 * tip;
	v.z -= (0.5 + 0.5 * sin(t * 0.8 + ph * 3.0)) * stretch_amount * tip;
	return v;
}
