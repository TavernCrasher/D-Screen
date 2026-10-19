shader_type canvas_item;
render_mode blend_add, unshaded;
// DW1 mist (FUN_800b4780, rules/mist_fx.gd): two layers of 320x240 quads of the 256x200
// 4bpp mist texture, added in display space as the PS1 does. Layer 1: CLUT row 0, colour
// 150, B + F/4; layer 2: mirrored, CLUT row2, colour 80, B + F. F = min(31, c5 * colour >> 7)
// per texel, then filtered like the background. Screen space from the screen centre
// (FIELD-29). The quads repeat every 320x240, so the pattern also fills a widescreen view
// (the user's choice; DW1's screen is 320x240).

uniform sampler2D idx_tex : filter_nearest;    // 256x200, value = palette index
uniform sampler2D clut_tex : filter_nearest;   // 16x16, rgb = 5-bit values (0..31)
uniform vec2 view_size;
uniform vec2 rect_pos;                         // this rect (the background's part of the view)
uniform vec2 rect_size;
uniform vec2 l1;                               // layer 1 X0, Y0 (offset space)
uniform float l2x;                             // layer 2 X2
uniform int row2;

vec3 texel_add(ivec2 t, int row, float colour, bool quarter) {
	t = ivec2((t.x % 256 + 256) % 256, (t.y % 200 + 200) % 200);
	int idx = int(texelFetch(idx_tex, t, 0).r * 255.0 + 0.5);
	vec3 c5 = floor(texelFetch(clut_tex, ivec2(idx, row), 0).rgb * 255.0 + 0.5);
	vec3 f = min(vec3(31.0), floor(c5 * colour / 128.0));
	return quarter ? floor(f / 4.0) : f;
}

// One layer at the position p inside its 320x240 quad, bilinear over the texels.
vec3 layer(vec2 p, int row, float colour, bool quarter) {
	vec2 tc = vec2(mod(p.x, 320.0) * 255.0 / 320.0, mod(p.y, 240.0) * 200.0 / 240.0) - 0.5;
	ivec2 i = ivec2(floor(tc));
	vec2 f = fract(tc);
	vec3 a = mix(texel_add(i, row, colour, quarter), texel_add(i + ivec2(1, 0), row, colour, quarter), f.x);
	vec3 b = mix(texel_add(i + ivec2(0, 1), row, colour, quarter), texel_add(i + ivec2(1, 1), row, colour, quarter), f.x);
	return mix(a, b, f.y);
}

void fragment() {
	float s = view_size.y / 240.0;
	vec2 o = (rect_pos + UV * rect_size - view_size / 2.0) / s;
	vec3 add = layer(o - l1, 0, 150.0, true);
	add += layer(vec2(l2x - o.x, o.y - l1.y), row2, 80.0, false);
	COLOR = vec4(add / 31.0, 1.0);
}
