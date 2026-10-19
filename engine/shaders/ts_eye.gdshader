shader_type spatial;
// Time Stranger eyeball material (*_f01/_f02), rebuilt from DSTS_Unified's node graph:
// base texture on UV; eyelid atlas ("iris", OverlayColorSampler3) and pupil atlas
// (OverlayNormalSampler) on UV2 (= TS uv3) shifted by expression/gaze offsets.
// The atlases are 4x4 cells of 0.25: rows open, closed, happy, angry (EyeDriver picks them
// from DW1's per-frame eye tiles). TS has no half-lidded row: half_lid lays the closed row's
// upper lid over the top of the open eye, down to a lid line.

uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform sampler2D lid_tex : source_color, filter_linear_mipmap;
uniform sampler2D pupil_tex : source_color, filter_linear_mipmap;
uniform vec2 expression_offset = vec2(0.0);  // picks the eyelid row (open/closed/happy/angry)
uniform vec2 gaze_offset = vec2(0.0);        // moves the pupil
uniform float half_lid = 0.0;                // 1: DW1's half-lidded eye
uniform float half_cut = 0.5;                // where the lid stops, in the cell (0 top, 1 bottom)

void fragment() {
	vec4 base = texture(base_tex, UV);
	vec4 lid = texture(lid_tex, UV2 + expression_offset);
	vec4 pupil = texture(pupil_tex, UV2 + expression_offset + gaze_offset);
	if (half_lid > 0.0) {
		vec4 closed = texture(lid_tex, UV2 + vec2(0.0, 0.25));
		float v = fract(UV2.y * 4.0);
		float w = fwidth(v) * 1.5 + 0.004;
		float hole = 1.0 - lid.a;          // where the open eye shows
		float cover = (1.0 - smoothstep(half_cut - w, half_cut + w, v)) * closed.a * half_lid;
		lid = vec4(mix(lid.rgb, closed.rgb, cover), max(lid.a, cover));
		pupil.a *= 1.0 - cover;
		// the lid's edge: a dark line along the cut, across the eye only
		float edge = (1.0 - smoothstep(0.0, 0.035 + w, abs(v - half_cut))) * closed.a * half_lid * hole;
		lid = vec4(mix(lid.rgb, vec3(0.08, 0.06, 0.07), edge * 0.9), max(lid.a, edge));
	}
	vec3 overlay = mix(pupil.rgb, lid.rgb, lid.a);
	float a = max(pupil.a, lid.a);
	ALBEDO = mix(base.rgb, overlay, a);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
