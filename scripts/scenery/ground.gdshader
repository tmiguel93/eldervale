// E8.2: chao opaco procedural (grama/terra/pedra por zona). Sem texturas: ruido em coordenadas de mundo.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://scripts/scenery/ground_common.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.30, 0.40, 0.19);
uniform vec3 color_b : source_color = vec3(0.40, 0.45, 0.22);
uniform vec3 color_c : source_color = vec3(0.40, 0.31, 0.19);
uniform vec3 grout : source_color = vec3(0.10, 0.10, 0.12);
uniform float patch_amount = 0.45;
uniform float noise_scale = 0.16;
uniform float tile_size = 0.0;
uniform float roughness_value = 0.95;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = ground_albedo(world_pos.xz, color_a, color_b, color_c, patch_amount, noise_scale, tile_size, grout);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
