shader_type spatial;
// A custom model's plain material (albedo texture, roughness, metallic, emission: what hy3d_rig.py
// writes) with DW1's texture tiles (custom_eye.gdshaderinc). DigimonModel swaps it in for the
// StandardMaterial3D the glTF import makes, keeping its outline pass. A material whose emission
// texture is its albedo (Tinmon's brow lamp) glows in the swapped colour.
// Metal (DigimonModel.CUSTOM_REFLECT, per material) reflects a soft procedural room: light above, a
// darker floor below, a key-light lobe, picked per pixel by the world-space reflection vector, so
// the highlights slide over the panels as the model turns, as on real metal (the maps have no sky
// to reflect, and painted sheen streaks read as scratches: the user's note on Tinmon's key).
#include "res://shaders/custom_eye.gdshaderinc"
#include "res://shaders/custom_sway.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness = 0.5;
uniform float metallic = 0.0;
uniform vec3 emission = vec3(0.0);
uniform float emission_albedo = 0.0;    // emission = the (swapped) albedo times this
uniform float reflect_strength = 0.0;
uniform float reflect_tint = 0.5;       // how much the reflection takes the surface's colour (metal)
uniform vec3 reflect_above : source_color = vec3(0.95, 0.94, 0.92);
uniform vec3 reflect_below : source_color = vec3(0.1, 0.1, 0.11);
uniform vec3 reflect_key = vec3(-0.45, 0.8, 0.4);      // the key light's direction (world)
uniform float reflect_key_gain = 1.2;
uniform float reflect_diffuse = 0.7;    // metal trades this much of its diffuse for the reflection
uniform vec2 reflect_horizon = vec2(-0.04, 0.14);   // the room's floor-to-wall blend (reflection y)
// Painted decals kept out of the metal (Giromon's eyes and teeth on its painted steel casing, tools/hy3d_mine_paint.py
// "matte_roles"): the texture's alpha is 1 - matte / 2 (never 0: the import treats 0 as clear); matte texels lose the metallic and the reflection and take
// matte_roughness. The swapped tiles' crops carry the same alpha (tools/custom_eye_atlas.py --channels).
uniform bool alpha_matte = false;
uniform float matte_roughness = 0.2;

void vertex() {
	if (eye_part_hidden(UV2)) {
		VERTEX = vec3(0.0);     // a built part of a swap tile not shown (Giromon's other chain set)
	}
	VERTEX += sway_offset(VERTEX, CUSTOM0.x, CUSTOM0.y);
}

void fragment() {
	vec4 tx = texture(albedo_tex, UV);
	vec3 c = tx.rgb;
	float r = roughness;
	float matte = alpha_matte ? clamp(2.0 * (1.0 - tx.a), 0.0, 1.0) : 0.0;
	vec4 e;
	if (eye_override(UV, e)) {
		c = e.rgb;
		if (alpha_matte) {
			matte = clamp(2.0 * (1.0 - e.a), 0.0, 1.0);
		} else {
			r = mix(r, max(r, eye_lid_roughness), 1.0 - e.a);
		}
	}
	float rs = reflect_strength * (1.0 - matte);
	ALBEDO = c * (1.0 - reflect_diffuse * min(rs, 1.0));
	ROUGHNESS = mix(r, matte_roughness, matte);
	METALLIC = metallic * (1.0 - matte);
	EMISSION = emission + c * emission_albedo;
	if (rs > 0.0) {
		vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 rv = reflect(-v, n);
		vec3 room = mix(reflect_below, reflect_above, smoothstep(reflect_horizon.x, reflect_horizon.y, rv.y));
		room += vec3(reflect_key_gain) * pow(max(dot(rv, normalize(reflect_key)), 0.0), 18.0);
		float fres = mix(0.55, 1.0, pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0));
		EMISSION += room * mix(vec3(1.0), c, reflect_tint) * fres * rs;
	}
}
