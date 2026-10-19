shader_type spatial;
// The dark outline TS models carry as shell meshes, for DW1's own models (DigimonModel.
// _dw1_style): the mesh pushed out along its normals and drawn back faces only.
render_mode unshaded, cull_front, depth_draw_opaque;

#include "res://shaders/custom_sway.gdshaderinc"

uniform float width = 0.008;
varying float drop;
uniform vec4 colour : source_color = vec4(0.07, 0.05, 0.04, 1.0);

void vertex() {
	drop = UV2.x;
	// UV2.x: how much of the outline to drop (tools/dw1_refine.py: where rigid parts overlap)
	VERTEX += NORMAL * width * (1.0 - UV2.x) + sway_offset(VERTEX, CUSTOM0.x, CUSTOM0.y);
}

void fragment() {
	if (drop > 0.98) {
		discard;    // no shell at all where the outline is dropped (a coincident shell still shows its back faces)
	}
	ALBEDO = colour.rgb;
}
