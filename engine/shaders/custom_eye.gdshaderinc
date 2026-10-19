// DW1's per-frame texture tiles on a custom model (EyeDriver, tools/custom_eye_atlas.py): the texels of
// a channel in the model texture (up to 8 rects in all) are swapped for the state's crop from a small
// atlas (one row per state: the eyes' open, battle, half, closed; or a channel's tiles in order, as
// Tinmon's brow flash and tread phases). Each rect follows one channel slot (eye_rect_slot: 0 the
// eyes, 1-3 the other channels) and that slot's row (eye_cells); row 0 is the model texture as it is.
// The atlas's alpha is 1 - the lid (lids aren't glossy).
uniform sampler2D eye_atlas : source_color, filter_linear_mipmap;
uniform ivec4 eye_cells = ivec4(0);     // the row each slot shows
uniform int eye_count = 0;
uniform vec4 eye_rects[8];              // u0, v0, u1, v1 in the model texture
uniform vec4 eye_slots[8];              // x, y, w, h of each rect's row-0 crop in the atlas
uniform int eye_rect_slot[8];           // the channel slot of each rect
uniform float eye_step = 0.0;           // atlas v between rows
uniform float eye_lid_roughness = 0.6;
uniform int eye_part_slot = -1;         // the slot whose tile picks the built parts shown (-1: none)

// Built parts shown by a texture-swap channel (tools/dw1_refine.py alpha_solid "swap_sets": Giromon's two
// chain-tooth sets, one per DW1 strip tile): UV2.y is the part's tile in the channel's list (1 the disc
// tile, 0 always shown); a part whose tile isn't the slot's current row is collapsed in the vertex
// stage, so it casts no shadow either.
bool eye_part_hidden(vec2 uv2) {
	if (eye_part_slot < 0 || uv2.y < 0.5) {
		return false;
	}
	return int(uv2.y + 0.5) - 1 != eye_cells[clamp(eye_part_slot, 0, 3)];
}

bool eye_override(vec2 uv, out vec4 col) {
	col = vec4(0.0);
	for (int i = 0; i < eye_count; i++) {
		vec4 r = eye_rects[i];
		if (uv.x >= r.x && uv.x < r.z && uv.y >= r.y && uv.y < r.w) {
			int cell = eye_cells[clamp(eye_rect_slot[i], 0, 3)];
			if (cell == 0) {
				continue;
			}
			vec4 s = eye_slots[i];
			vec2 k = s.zw / (r.zw - r.xy);
			vec2 a = s.xy + (uv - r.xy) * k + vec2(0.0, eye_step * float(cell));
			col = textureGrad(eye_atlas, a, dFdx(uv) * k, dFdy(uv) * k);
			return true;
		}
	}
	return false;
}
