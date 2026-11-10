shader_type canvas_item;
// Placeholder sky behind the window glass. The texture is the glass mask (alpha only).
// Will be replaced by a parallax landscape later.

uniform vec4 top_color : source_color = vec4(0.38, 0.64, 0.96, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.80, 0.92, 1.0, 1.0);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec3 c = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, UV.y));
	COLOR = vec4(c, a);
}
