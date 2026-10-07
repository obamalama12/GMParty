shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Floors of the arcade arenas, painted from the position (no textures needed).
// mode 0: mown lawn: light and dark rings, a sand rim
// mode 1: circus ring: coloured sectors, a gold centre, a bright rim
// mode 2: picnic cloth: checks in the middle, lawn outside
// mode 3: volcano rock: dark tiles with glowing cracks and a hot rim
// mode 4: sports field: two coloured halves with a white centre line

uniform int mode = 0;
uniform float radius = 7.0;
uniform vec3 color_a : source_color = vec3(0.45, 0.78, 0.30);
uniform vec3 color_b : source_color = vec3(0.38, 0.70, 0.26);
uniform vec3 color_c : source_color = vec3(0.95, 0.85, 0.50);
uniform vec3 color_d : source_color = vec3(1.0, 0.8, 0.2);
uniform float count = 12.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = local_pos.xz;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 c = color_a;
	float emit = 0.0;
	if (mode == 0) {
		float ring = step(0.5, fract(r / (radius / count)));
		c = mix(color_a, color_b, ring);
		c = mix(c, color_c, smoothstep(radius * 0.9, radius * 0.93, r));
		c = mix(c, color_d, smoothstep(radius * 0.965, radius * 0.975, r));
	} else if (mode == 1) {
		float sector = step(0.5, fract(a / 6.2831853 * count));
		c = mix(color_a, color_b, sector);
		c = mix(c, color_d, 1.0 - smoothstep(radius * 0.16, radius * 0.19, r));
		c = mix(c, color_c, smoothstep(radius * 0.9, radius * 0.92, r));
		c = mix(c, color_d, smoothstep(radius * 0.96, radius * 0.97, r));
	} else if (mode == 2) {
		vec2 g = floor(p / (radius / count));
		float check = mod(g.x + g.y, 2.0);
		vec3 cloth = mix(vec3(1.0, 0.97, 0.95), color_c, check);
		float inside = 1.0 - smoothstep(radius * 0.62, radius * 0.64, max(abs(p.x), abs(p.y) * 1.25));
		float ring = step(0.5, fract(r / (radius / 10.0)));
		vec3 lawn = mix(color_a, color_b, ring);
		c = mix(lawn, cloth, inside);
		c = mix(c, color_d, smoothstep(radius * 0.94, radius * 0.96, r));
	} else if (mode == 3) {
		vec2 g = p * (count / radius);
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float tone = hash(cell);
		// rock slabs of different brightness; only some of the joints glow, and they glow more near the edge
		float edge_x = min(f.x, 1.0 - f.x);
		float edge_y = min(f.y, 1.0 - f.y);
		float joint_x = 1.0 - smoothstep(0.02, 0.06, edge_x);
		float joint_y = 1.0 - smoothstep(0.02, 0.06, edge_y);
		float lit = step(0.55, hash(cell + vec2(floor(g.x * 0.5), 3.0)));
		float crack = max(joint_x, joint_y) * mix(0.25, 1.0, lit);
		float heat = smoothstep(radius * 0.5, radius * 0.97, r);
		c = color_a * (0.75 + tone * 0.6);
		c = mix(c, color_c, crack * (0.35 + heat * 0.65));
		emit = crack * (0.15 + heat * 1.1);
		float rim = smoothstep(radius * 0.955, radius * 0.985, r);
		c = mix(c, color_d, rim);
		emit += rim * 1.0;
	} else {
		float team = step(0.0, p.x);
		c = mix(color_a, color_b, team);
		float stripe = step(0.5, fract(p.y / 2.2));
		c *= 0.93 + stripe * 0.1;
		c = mix(c, vec3(1.0), 1.0 - smoothstep(0.06, 0.14, abs(p.x)));
		c = mix(c, color_c, smoothstep(radius * 0.93, radius * 0.95, r));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = color_d * emit * 0.7;
}
