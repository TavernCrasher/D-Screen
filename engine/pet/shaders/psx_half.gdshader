shader_type canvas_item;
// DW1 sprite texels with STP (alpha 255) on a 50/50 sprite (attribute 0x40000000): the bubble.
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.75) discard;
	COLOR = vec4(c.rgb, 0.5);
}
