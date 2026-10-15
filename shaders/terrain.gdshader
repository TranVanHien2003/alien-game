shader_type canvas_item;
// Vẽ địa hình mở từ bản đồ màu theo ô (TEXTURE, lọc tuyến tính để các vùng hòa vào nhau),
// cộng texture chi tiết, đổ bóng đồi theo độ cao, nước gợn sóng và viền vách đá.

uniform sampler2D height_map : filter_linear;
uniform sampler2D detail_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 cells = vec2(140.0, 100.0);
uniform float detail_strength = 0.6;
uniform float shade_strength = 1.5;
uniform vec4 water_color : source_color = vec4(0.25, 0.5, 0.75, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 texel = 1.0 / cells;
	float h = texture(height_map, UV).r;
	float hx = texture(height_map, UV + vec2(texel.x, 0.0)).r - texture(height_map, UV - vec2(texel.x, 0.0)).r;
	float hy = texture(height_map, UV + vec2(0.0, texel.y)).r - texture(height_map, UV - vec2(0.0, texel.y)).r;
	// Ánh sáng từ phía trên-trái
	float shade = clamp(1.0 - (hx * 0.8 + hy * 1.2) * shade_strength, 0.65, 1.18);
	vec3 detail = texture(detail_tex, UV * cells * 0.5).rgb;
	float lum = dot(detail, vec3(0.299, 0.587, 0.114));
	float big = texture(noise_tex, UV * 3.0).r * 0.6 + texture(noise_tex, UV * cells * 0.12).r * 0.4;
	vec3 col = base.rgb * mix(1.0, 0.6 + lum * 0.8, detail_strength) * (0.88 + big * 0.24) * shade;
	// Nước: alpha của bản đồ màu < 0.5 đánh dấu ô nước
	if (base.a < 0.6) {
		float ripple = texture(noise_tex, UV * cells * 0.08 + vec2(TIME * 0.02, TIME * 0.015)).r;
		col = mix(water_color.rgb * (0.8 + ripple * 0.4), col, 0.15);
		col += vec3(0.08) * smoothstep(0.7, 0.95, ripple);
	}
	// Viền tối ở chân vách đá
	col *= mix(1.0, 0.75, smoothstep(0.58, 0.66, h) * (1.0 - smoothstep(0.66, 0.75, h)));
	COLOR = vec4(col, 1.0);
}
