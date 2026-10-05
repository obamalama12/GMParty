shader_type canvas_item;

// Menu background: a deep indigo-to-teal gradient with slowly rising soft bubbles and twinkling stars.

uniform vec4 top_color : source_color = vec4(0.09, 0.08, 0.30, 1.0);
uniform vec4 mid_color : source_color = vec4(0.33, 0.17, 0.60, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.16, 0.66, 0.62, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 c = mix(top_color.rgb, mid_color.rgb, smoothstep(0.0, 0.62, uv.y));
	c = mix(c, bottom_color.rgb, smoothstep(0.58, 1.0, uv.y));

	// soft bokeh bubbles drifting upwards, three layers
	for (int l = 0; l < 3; l++) {
		float fl = float(l);
		float cells = 4.0 + fl * 3.5;
		vec2 p = vec2(uv.x * aspect, uv.y) * cells + vec2(fl * 7.3, TIME * (0.05 + fl * 0.035));
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = hash(cell + fl * 17.0);
		vec2 off = vec2(hash(cell + 3.1) - 0.5, hash(cell + 9.7) - 0.5) * 0.5;
		float r = 0.14 + 0.2 * hash(cell + 5.5);
		float d = length(f - off);
		float a = smoothstep(r, r * 0.55, d) * step(0.45, h) * (0.10 + 0.06 * fl);
		float ring = smoothstep(r * 0.08, 0.0, abs(d - r * 0.8)) * 0.07;
		c += vec3(1.0, 0.92, 0.75) * (a + ring);
	}

	// twinkling stars in the upper half
	vec2 sp = vec2(uv.x * aspect, uv.y) * 38.0;
	vec2 sc = floor(sp);
	float sh = hash(sc + 41.0);
	vec2 sf = fract(sp) - 0.5;
	float star = step(0.93, sh) * smoothstep(0.17, 0.0, length(sf)) * (0.5 + 0.5 * sin(TIME * (1.5 + sh * 3.0) + sh * 40.0));
	c += vec3(1.0) * star * (1.0 - smoothstep(0.1, 0.55, uv.y));

	// vignette
	float v = smoothstep(0.95, 0.35, length((uv - 0.5) * vec2(1.0, 0.9)));
	c *= mix(0.6, 1.0, v);
	COLOR = vec4(c, 1.0);
}
