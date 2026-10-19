shader_type canvas_item;
// DW1 sprite texels without STP (alpha 128 in the exported sheets): opaque.
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.25 || c.a > 0.75) discard;
	COLOR = vec4(c.rgb, 1.0);
}
