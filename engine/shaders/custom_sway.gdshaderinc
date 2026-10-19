// Ambient flutter for cloth that hangs free (Ninjamon's scarf tails and hood flap). CUSTOM0.x is the
// vertex's sway weight (tools/dw1_refine.py "sway": 0 at the root .. 1 at the tip, 0 elsewhere; hy3d_rig.py
// writes TEXCOORD_2.x). The weight squared leans the cloth along a travelling wave, so the root stays put
// and the tip moves most. Skinning is already applied in vertex(), VERTEX is the posed mesh-local position.
// sway_amp is the small idle breathing; sway_lag is the movement-driven part. The outline pass includes this too, so the black rim follows the cloth.
uniform float sway_amp = 0.0;           // peak tip displacement (mesh units, metres in the glb)
uniform float sway_speed = 2.2;         // rad/s of the main wave
uniform float sway_wavelength = 0.35;   // distance along the cloth between wave crests
uniform vec3 sway_dir = vec3(1.0, 0.0, 0.6);   // mesh-local lean direction of the wave (x side, z fore-aft)
uniform vec3 sway_lag = vec3(0.0);     // the cloth's inertial lag in mesh space (SwayDriver: trails a move, lifts in a fall)
uniform float sway_lag_scale = 1.0;
uniform float sway_phase = 0.0;         // per-model offset (several models, not all in step)

// kind (CUSTOM0.y): 0 a ribbon (the tails: the weight squared translates it along the lag), 1 the hood's tip, which
// stays static: it is a solid cone resting on the hood, and any move either pulls it off the hood or stretches it
// (tried as a translation and as a hinge swing, 2026-10-17; the user dropped it).
vec3 sway_offset(vec3 pos, float w, float kind) {
	if (w <= 0.0 || kind > 0.5) {
		return vec3(0.0);
	}
	vec3 lag = sway_lag * sway_lag_scale;
	float k = 6.2831853 / sway_wavelength;
	float t = TIME * sway_speed + sway_phase;
	float ph = t - (pos.x + pos.y + pos.z) * k;
	float s = sin(ph) + 0.35 * sin(2.3 * ph + 1.7);
	vec3 d = normalize(sway_dir);
	vec3 side = normalize(cross(d, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
	vec3 idle = (d * s + side * 0.4 * cos(ph * 0.8)) * sway_amp * w * w;
	return lag * w * w + idle;
}
