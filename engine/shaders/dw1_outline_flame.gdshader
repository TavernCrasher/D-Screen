shader_type spatial;
// dw1_outline.gdshader for custom fire models: the same dark shell, moved with the flame tongues
// (flame_wobble.gdshaderinc) so the outline stays on the flickering tips, and tapered along them.
render_mode unshaded, cull_front, depth_draw_opaque;

#include "res://shaders/flame_wobble.gdshaderinc"

uniform float width = 0.008;
varying float drop;
uniform vec4 colour : source_color = vec4(0.07, 0.05, 0.04, 1.0);

void vertex() {
	drop = UV2.x;
	// thinner towards the tips (COLOR.g), or the line swamps the narrow flame points
	VERTEX = flame_wobble(VERTEX, COLOR) + NORMAL * width * (1.0 - 0.5 * COLOR.r * COLOR.g)
		* (1.0 - UV2.x);    // UV2.x: outline dropped where rigid parts overlap (tools/dw1_refine.py)
}

void fragment() {
	if (drop > 0.98) {
		discard;    // no shell at all where the outline is dropped (a coincident shell still shows its back faces)
	}
	ALBEDO = colour.rgb;
}
