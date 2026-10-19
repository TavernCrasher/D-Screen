shader_type spatial;
// Fire on a custom model (DigimonModel.CUSTOM_FIRE, e.g. DemiMeramon): the painted texture, the
// flame tongues flickering (flame_wobble.gdshaderinc), and a glow that flows along them like TS's
// fire (ts_fire.gdshader): TS's flame distortion map scrolled through model space (the generated
// UVs don't follow the flames) brightens and darkens the glow. Emission follows COLOR_0.a (none
// on the eyes and stitches, low on the face, full on the tongues).
render_mode cull_back;

#include "res://shaders/flame_wobble.gdshaderinc"
#include "res://shaders/custom_eye.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float roughness = 0.5;
uniform float metallic = 0.0;         // a metal part (Flarerizamon's helmet, claws and teeth)
uniform vec3 emission_tint = vec3(1.0, 0.47, 0.11);    // Meramon's EmissiveIntensity
uniform float emission_strength = 1.0;
uniform vec2 flow = vec2(0.0, -0.75);                    // the scroll, in noise tiles per second
uniform float noise_scale = 2.5;                         // noise tiles per metre
uniform float flow_contrast = 0.6;
uniform float core_glow = 0.5;        // the body glows less than the tongues, so the light still shapes it
uniform float eye_floor = 0.45;       // unlit parts (eyes, stitches) keep their colour in dark caves

varying vec3 model_pos;
varying vec4 flame;

void vertex() {
	flame = COLOR;
	VERTEX = flame_wobble(VERTEX, COLOR);
	model_pos = VERTEX;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	float r = roughness;
	vec4 e;
	if (eye_override(UV, e)) {          // DW1's eye states (EyeDriver)
		a.rgb = e.rgb;
		r = mix(r, max(r, eye_lid_roughness), 1.0 - e.a);
	}
	ALBEDO = a.rgb;
	ROUGHNESS = r;
	METALLIC = metallic;
	// flow: the flames run backwards (+z in noise space) and a little up
	vec2 p = vec2(model_pos.x + model_pos.y * 0.5, -model_pos.z) * noise_scale;
	float n = texture(noise_tex, p + TIME * flow).r;
	n = mix(n, texture(noise_tex, p * 0.6 + TIME * flow * vec2(-0.5, 0.7)).g, 0.5);
	float pulse = mix(1.0, 0.4 + 1.2 * n, flow_contrast * flame.r);
	float glow = flame.a * mix(core_glow, 1.0, flame.r);
	EMISSION = a.rgb * emission_tint * emission_strength * glow * pulse
		+ a.rgb * eye_floor * smoothstep(0.15, 0.0, flame.a);
}
