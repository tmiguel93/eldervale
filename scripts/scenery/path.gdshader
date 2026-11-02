// E8.2: decal de caminho/praca/piso (caixa fina): mesmo ruido do chao, com borda suave opcional (soft > 0 em metros).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, depth_draw_always;
#include "res://scripts/scenery/ground_common.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.48, 0.38, 0.26);
uniform vec3 color_b : source_color = vec3(0.56, 0.45, 0.30);
uniform vec3 color_c : source_color = vec3(0.38, 0.30, 0.20);
uniform vec3 grout : source_color = vec3(0.10, 0.10, 0.12);
uniform float patch_amount = 0.5;
uniform float noise_scale = 0.3;
uniform float tile_size = 0.0;
uniform float roughness_value = 0.92;
uniform float soft = 0.0;
uniform vec2 half_size = vec2(1.0, 1.0);

varying vec3 world_pos;
varying vec3 local_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
}

void fragment() {
	ALBEDO = ground_albedo(world_pos.xz, color_a, color_b, color_c, patch_amount, noise_scale, tile_size, grout);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
	if (soft > 0.0) {
		float d = min(half_size.x - abs(local_pos.x), half_size.y - abs(local_pos.z));
		float n = g_noise(world_pos.xz * 1.7);
		ALPHA = smoothstep(0.0, soft, d + (n - 0.5) * soft * 0.9);
	}
}
