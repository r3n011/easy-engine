// 角色图形特效：把 Scratch 的「颜色 / 鱼眼 / 旋转 / 像素化 / 马赛克 / 亮度 / 虚像」
// 映射成一组 uniform。积木只改参数，不改着色器。
//
// 全部角色共用一个 ShaderMaterial 的模板，每个角色实例化自己的材质。
shader_type canvas_item;

// 虚像：0 = 完全不透明，100 = 完全看不见
uniform float ghost : hint_range(0.0, 100.0) = 0.0;
// 亮度：-100 = 全黑，100 = 全白
uniform float brightness : hint_range(-100.0, 100.0) = 0.0;
// 颜色：色相偏移（度）
uniform float hue_shift : hint_range(-180.0, 180.0) = 0.0;
// 鱼眼：正数放大中心，负数收缩
uniform float fisheye : hint_range(-100.0, 200.0) = 0.0;
// 旋转：绕角色中心扭曲（度）
uniform float whirl : hint_range(-360.0, 360.0) = 0.0;
// 像素化：块大小（0 = 关闭）
uniform float pixelate : hint_range(0.0, 100.0) = 0.0;
// 马赛克：把整张贴图压到 n x n 块再放大
uniform float mosaic : hint_range(0.0, 100.0) = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	// 记下进来的 COLOR —— 它是 Godot 传进来的 modulate（含 self_modulate）。
	// 直接 COLOR = col 会把它盖掉，于是在「执行代码」里改 node.modulate 就没效果了。
	vec4 modulate = COLOR;

	vec2 uv = UV;

	// 像素化：把采样点吸附到块中心
	if (pixelate > 0.0) {
		vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
		float block = max(1.0, pixelate * 0.25);
		uv = (floor(uv * tex_size / block) + 0.5) * block / tex_size;
	}

	// 马赛克：先缩到小块再放大
	if (mosaic > 0.0) {
		float n = max(2.0, 64.0 - mosaic * 0.6);
		uv = (floor(uv * n) + 0.5) / n;
	}

	// 鱼眼 / 旋转：以中心为原点的极坐标扭曲
	if (fisheye != 0.0 || whirl != 0.0) {
		vec2 d = uv - vec2(0.5);
		float r = length(d);
		float a = atan(d.y, d.x);
		if (fisheye != 0.0) {
			r *= 1.0 + (fisheye / 100.0) * r * 0.8;
		}
		if (whirl != 0.0) {
			a += radians(whirl) * (1.0 - min(r * 2.0, 1.0));
		}
		uv = vec2(cos(a), sin(a)) * r + vec2(0.5);
	}

	// 采样：越界视作透明，避免边缘拖影
	vec4 col = vec4(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		col = texture(TEXTURE, uv);
	}

	// 颜色（色相偏移）
	if (hue_shift != 0.0 && col.a > 0.0) {
		vec3 hsv = rgb2hsv(col.rgb);
		hsv.x = fract(hsv.x + hue_shift / 360.0);
		col.rgb = hsv2rgb(hsv);
	}

	// 亮度
	if (brightness != 0.0) {
		if (brightness > 0.0) {
			col.rgb = mix(col.rgb, vec3(1.0), brightness / 100.0);
		} else {
			col.rgb = mix(col.rgb, vec3(0.0), -brightness / 100.0);
		}
	}

	// 虚像
	col.a *= clamp(1.0 - ghost / 100.0, 0.0, 1.0);

	COLOR = col * modulate;
}
