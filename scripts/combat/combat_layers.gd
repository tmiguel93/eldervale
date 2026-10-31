class_name CombatLayers
extends RefCounted
## Camadas de fisica do combate (ver docs/E2_COMBAT.md). Valores sao MASCARAS de bit.
## Camada 1 (WORLD) e a padrao ja usada por arena e player; nao e alterada.

enum Team { PLAYER, ENEMY }

const WORLD: int = 1 << 0 ## camada 1
const PLAYER_HURT: int = 1 << 1 ## camada 2
const ENEMY_HURT: int = 1 << 2 ## camada 3
const PLAYER_HIT: int = 1 << 3 ## camada 4
const ENEMY_HIT: int = 1 << 4 ## camada 5


static func hurt_layer(team: Team) -> int:
	return PLAYER_HURT if team == Team.PLAYER else ENEMY_HURT


static func hit_layer(team: Team) -> int:
	return PLAYER_HIT if team == Team.PLAYER else ENEMY_HIT


## Mascara do que um Hitbox do time `team` enxerga: as hurtboxes do time oposto.
static func hit_mask(team: Team) -> int:
	return ENEMY_HURT if team == Team.PLAYER else PLAYER_HURT
