shader_type canvas_item;
render_mode unshaded;

// Old TV overlay on top of everything: faint scanlines and darker corners.

uniform float scanline = 0.13;
uniform float vignette = 0.38;
uniform float line_px = 3.0;      // height of one scanline in screen pixels

void fragment() {
	float y = FRAGCOORD.y / line_px;
	float dark = 0.5 + 0.5 * cos(6.2831853 * y);
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 0.92);
	float v = smoothstep(0.38, 0.92, length(d));
	COLOR = vec4(0.02, 0.01, 0.06, clamp(scanline * dark + v * vignette, 0.0, 0.85));
}
