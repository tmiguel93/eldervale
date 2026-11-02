// E8.3: circulo de runas procedural no chao (quad XZ). style 0 = aneis + faixa de glifos, 1 = valknut, 2 = so aneis (telegrafo).
// `fill` = disco preenchido; `sweep` = raio (0..1) ja "carregado" (telegrafo de area).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_a : source_color = vec3(0.7, 0.95, 1.0);
uniform vec3 color_b : source_color = vec3(0.2, 0.45, 1.0);
uniform float cover = 0.6;
uniform float intensity = 1.6;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float appear = 0.2;
uniform float vanish = 0.35;
uniform float rot = 0.0;
uniform float pulse = 0.0;
uniform float fill = 0.0;
uniform float sweep = 0.0;
uniform float glyphs = 12.0;
uniform int style = 0;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a; vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}
float line(float d, float w) { return 1.0 - smoothstep(w * 0.4, w, d); }
float ringf(float r, float r0, float w) { return line(abs(r - r0), w); }
vec2 rot2(vec2 p, float a) { float c = cos(a), s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }

float tri(vec2 p, vec2 c, float rad, float ang, float w) {
	float m = 0.0;
	for (int i = 0; i < 3; i++) {
		float a0 = ang + float(i) * 2.0943951;
		float a1 = ang + float(i + 1) * 2.0943951;
		vec2 v0 = c + vec2(cos(a0), sin(a0)) * rad;
		vec2 v1 = c + vec2(cos(a1), sin(a1)) * rad;
		m = max(m, line(seg(p, v0, v1), w));
	}
	return m;
}

float glyph(vec2 q, float h) {
	// q: x centrado (unidades de altura da celula), y 0..1. Runa estilo futhark: haste + ramos.
	float d = seg(q, vec2(0.0, 0.08), vec2(0.0, 0.92));
	float sg = h11(h * 7.1) > 0.5 ? 1.0 : -1.0;
	float y0 = 0.2 + 0.4 * h11(h * 3.3);
	if (h11(h * 1.7) > 0.25) d = min(d, seg(q, vec2(0.0, y0 + 0.28), vec2(0.3 * sg, y0)));
	if (h11(h * 5.9) > 0.45) d = min(d, seg(q, vec2(0.0, y0 + 0.2), vec2(-0.3 * sg, y0 + 0.4)));
	if (h11(h * 9.1) > 0.7) d = min(d, seg(q, vec2(0.0, 0.5), vec2(0.28 * sg, 0.72)));
	return line(d, 0.075);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) discard;
	float m = 0.0;
	float w = 0.028;
	m = max(m, ringf(r, 0.97, w * 1.4));
	if (style != 2) {
		m = max(m, ringf(r, 0.88, w * 0.8));
		float ticks = step(0.5, fract((atan(p.y, p.x) + rot * 0.5) / 6.2831853 * 48.0)) * line(abs(r - 0.925), 0.03);
		m = max(m, ticks * 0.9);
	}
	if (style == 0) {
		m = max(m, ringf(r, 0.6, w * 0.8));
		float a = atan(p.y, p.x) + rot;
		float cells = a / 6.2831853 * glyphs;
		float cid = floor(cells);
		float u = fract(cells) - 0.5;
		float v = (r - 0.62) / 0.24;
		float aspect = (6.2831853 * 0.74 / glyphs) / 0.24;
		if (v > 0.0 && v < 1.0) m = max(m, glyph(vec2(u * aspect, v), cid) * 0.95);
		m = max(m, tri(p, vec2(0.0), 0.42, -rot * 0.7, w) * 0.7);
	} else if (style == 1) {
		for (int k = 0; k < 3; k++) {
			float ka = -rot * 0.5 + float(k) * 2.0943951 + 1.5707963;
			vec2 c = vec2(cos(ka), sin(ka)) * 0.2;
			m = max(m, tri(p, c, 0.5, ka + 3.14159, w * 1.1));
		}
		m = max(m, ringf(r, 0.6, w * 0.7) * 0.6);
	} else {
		m = max(m, ringf(r, 0.82, w * 0.6) * 0.5);
	}
	float glow = exp(-r * 3.5) * (0.35 + 0.65 * pulse);
	float edge_glow = smoothstep(0.82, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r)) * (0.3 + 0.5 * pulse);
	float fillv = fill * (1.0 - smoothstep(0.95, 1.0, r)) * 0.28;
	float sw = (1.0 - smoothstep(sweep - 0.04, sweep, r)) * step(0.001, sweep) * 0.4;
	float reveal = smoothstep(r - 0.12, r, progress / max(appear, 0.001) * 1.15);
	float fade = 1.0 - smoothstep(1.0 - vanish, 1.0, progress);
	float a = (m * (0.75 + 0.25 * pulse) + glow * 0.35 + edge_glow + fillv + sw) * reveal * fade;
	vec3 col = mix(color_b, color_a, clamp(m + glow + sw, 0.0, 1.0));
	a = clamp(a, 0.0, 1.0);
	ALBEDO = col * intensity * a;
	ALPHA = a * cover;
}
