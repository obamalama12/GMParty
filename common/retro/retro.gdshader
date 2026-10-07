shader_type canvas_item;
render_mode unshaded;

// Nintendo 64 look for the 3D picture: a low resolution (about 320x240 lines), the console's three-point texture
// filter instead of bilinear, 16 bit colour (5 bits per channel) with ordered dithering and slightly punchy colours.
// It is drawn behind the user interface, so menus and text stay sharp.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 res = vec2(427.0, 240.0);       // size of the low resolution picture
uniform float levels = 31.0;                  // 32 levels = 5 bits per channel
uniform float dither_amount = 1.0;
uniform float saturation = 1.1;
uniform float contrast = 1.05;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

vec3 texel(vec2 cell) {
	// average a few samples inside the low resolution pixel so the picture does not shimmer
	vec2 uv = (cell + 0.5) / res;
	vec2 q = vec2(0.25) / res;
	return (texture(screen_texture, uv + vec2(-q.x, -q.y)).rgb
			+ texture(screen_texture, uv + vec2(q.x, -q.y)).rgb
			+ texture(screen_texture, uv + vec2(-q.x, q.y)).rgb
			+ texture(screen_texture, uv + vec2(q.x, q.y)).rgb) * 0.25;
}

void fragment() {
	vec2 p = SCREEN_UV * res - 0.5;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec3 c10 = texel(cell + vec2(1.0, 0.0));
	vec3 c01 = texel(cell + vec2(0.0, 1.0));
	vec3 c;
	// three-point filter: only the three nearest texels of the triangle the pixel lies in are blended
	if (f.x + f.y <= 1.0) {
		c = texel(cell) * (1.0 - f.x - f.y) + c10 * f.x + c01 * f.y;
	} else {
		c = texel(cell + vec2(1.0, 1.0)) * (f.x + f.y - 1.0) + c10 * (1.0 - f.y) + c01 * (1.0 - f.x);
	}
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	ivec2 ip = ivec2(floor(SCREEN_UV * res));
	float d = BAYER[(ip.x & 3) + (ip.y & 3) * 4] / 16.0 - 0.5;
	c += vec3(d) * dither_amount / levels;
	c = floor(clamp(c, 0.0, 1.0) * levels + 0.5) / levels;
	COLOR = vec4(c, 1.0);
}
