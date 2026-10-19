shader_type canvas_item;
render_mode blend_add;
// DW1 sprite texels with STP (alpha 255) on an additive sprite (attribute 0x50000000): the icons.
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.75) discard;
	COLOR = vec4(c.rgb, 1.0);
}
