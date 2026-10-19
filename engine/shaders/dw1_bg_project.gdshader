shader_type spatial;
render_mode unshaded, cull_disabled;
// Projects a DW1 pre-rendered map background onto the ground through the map's original
// fixed camera (MapSetup viewpoint/reference/view distance), see tools/dw1_camera.py.

// The pictures are sampled as stored (sRGB, DW1's display values): the palette fade and the far
// layer are worked out there, as on the PS1, then converted for the renderer.
uniform sampler2D bg : filter_linear;
uniform sampler2D bg_b : filter_linear;   // the palette being faded to
uniform int fade_d = 0;                   // the fade's divisor, 0 = none
uniform sampler2D far_a : filter_linear;  // far map objects (anchor y 10000): drawn over
uniform sampler2D far_b : filter_linear;
uniform sampler2D far_add_a : filter_linear;   // far additive objects: added
uniform sampler2D far_add_b : filter_linear;
uniform bool has_far = false;
// DW1's palette fade (FUN_800d7210) on the 5-bit values: c1 - (c1 - c2) / d, truncated toward
// zero; d = 0 shows c1. The pictures hold c * 255 / 31, so the 5-bit values come back exactly.
vec3 blend5(vec3 a, vec3 b, int d) {
	if (d <= 0) {
		return a;
	}
	ivec3 ia = ivec3(round(a * 31.0));
	ivec3 ib = ivec3(round(b * 31.0));
	ivec3 df = ia - ib;
	ivec3 q = ivec3(sign(vec3(df))) * (abs(df) / d);
	return vec3(ia - q) / 31.0;
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
uniform vec3 vp;            // camera position, DW1 units
uniform vec3 axis_r;        // camera right   (DW1 space: x right, y down, z forward)
uniform vec3 axis_d;        // camera down
uniform vec3 axis_f;        // camera forward
uniform float h;            // projection distance (pixels)
uniform vec2 center;        // background image centre (pixels)
uniform vec2 size;          // background image size (pixels)
uniform float unit = 0.005; // metres per DW1 unit

varying vec3 dw;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dw = vec3(w.x, -w.y, -w.z) / unit;          // Godot -> DW1 coordinates
}

void fragment() {
	vec3 q = dw - vp;
	float zc = dot(q, axis_f);
	vec2 px = vec2(h * dot(q, axis_r) / zc, h * dot(q, axis_d) / zc) + center;
	vec2 uv = px / size;
	if (zc <= 0.0 || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		ALBEDO = vec3(0.0);
	} else {
		vec3 col = blend5(texture(bg, uv).rgb, texture(bg_b, uv).rgb, fade_d);
		if (has_far) {
			vec4 fa = texture(far_a, uv);            // premultiplied: no dark fringes
			fa.rgb = blend5(fa.rgb, texture(far_b, uv).rgb, fade_d);
			col = col * (1.0 - fa.a) + fa.rgb;
			vec4 ad = texture(far_add_a, uv);
			ad.rgb = blend5(ad.rgb, texture(far_add_b, uv).rgb, fade_d);
			col = min(col + ad.rgb * ad.a, vec3(1.0));
		}
		ALBEDO = to_linear(col);
	}
	// DW1's background tiles sit at the back of the ordering table (OT 0xFFF): they never hide a
	// sprite or a model. The ground keeps the farthest depth (reverse Z: 0), so overlays anchored
	// behind it (waterfalls, signs) still draw over it.
	DEPTH = 0.0;
}
