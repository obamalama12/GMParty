shader_type canvas_item;

// Menu background in the style of the 90s party games: bright blue sky, slowly turning sunburst rays behind the
// mascot, soft round sparkles drifting up and twinkling stars.

uniform vec4 top_color : source_color = vec4(0.14, 0.27, 0.82, 1.0);
uniform vec4 mid_color : source_color = vec4(0.30, 0.55, 0.98, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.60, 0.86, 1.0, 1.0);
uniform vec2 ray_center = vec2(0.76, 0.48);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 c = mix(top_color.rgb, mid_color.rgb, smoothstep(0.0, 0.55, uv.y));
	c = mix(c, bottom_color.rgb, smoothstep(0.5, 1.0, uv.y));

	// sunburst
	vec2 d = (uv - ray_center) * vec2(aspect, 1.0);
	float ang = atan(d.y, d.x) / 6.2831853;
	float rays = smoothstep(0.42, 0.58, abs(fract(ang * 14.0 + TIME * 0.02) - 0.5) * 2.0);
	float fade = 1.0 - smoothstep(0.1, 1.4, length(d));
	c += vec3(1.0, 0.97, 0.8) * rays * fade * 0.14;
	c += vec3(1.0, 0.95, 0.7) * (1.0 - smoothstep(0.0, 0.45, length(d))) * 0.22;

	// soft sparkles drifting upwards
	for (int l = 0; l < 2; l++) {
		float fl = float(l);
		float cells = 5.0 + fl * 4.0;
		vec2 p = vec2(uv.x * aspect, uv.y) * cells + vec2(fl * 7.3, TIME * (0.06 + fl * 0.04));
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = hash(cell + fl * 17.0);
		vec2 off = vec2(hash(cell + 3.1) - 0.5, hash(cell + 9.7) - 0.5) * 0.5;
		float r = 0.08 + 0.12 * hash(cell + 5.5);
		float dd = length(f - off);
		c += vec3(1.0) * smoothstep(r, r * 0.4, dd) * step(0.55, h) * 0.16;
	}

	// twinkling stars in the upper part
	vec2 sp = vec2(uv.x * aspect, uv.y) * 34.0;
	vec2 sc = floor(sp);
	float sh = hash(sc + 41.0);
	vec2 sf = fract(sp) - 0.5;
	float star = step(0.94, sh) * smoothstep(0.17, 0.0, length(sf)) * (0.5 + 0.5 * sin(TIME * (1.5 + sh * 3.0) + sh * 40.0));
	c += vec3(1.0) * star * (1.0 - smoothstep(0.1, 0.6, uv.y));

	float v = smoothstep(1.0, 0.4, length((uv - 0.5) * vec2(1.0, 0.9)));
	c *= mix(0.8, 1.0, v);
	COLOR = vec4(c, 1.0);
}
