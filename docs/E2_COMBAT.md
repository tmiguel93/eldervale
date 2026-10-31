# E2 — Núcleo de combate

Lógica em `scripts/combat/` (sem UI, sem autoloads); integração do jogador em `scripts/player/player_combat.gd`.
Contratos de terceiros: `StatBlock`, `DamageInfo` (não alterados).

## API
- `DamageCalculator.compute(amount, defense, resistance, is_critical=false, min_damage=1.0)`:
  `max(0, (bruto - defense) * (1 - resistance))`, bruto = `amount` (x `CRIT_MULTIPLIER`=1.5 se crítico). Se `amount > 0` o resultado é no mínimo `min_damage`; `amount <= 0` dá 0.
- `HealthComponent` (Node): `stats`, `current_health`, `invulnerable`, `apply_damage(info) -> float`, `heal`, `reset`; sinais `damaged(info, final)`, `healed`, `health_changed`, `died(source)` (uma vez até `reset()`).
- `ResourcePool` (RefCounted): `setup/set_stats`, `can_afford`, `spend` (falha sem consumir), `restore`, `tick(delta)` (regen `resource_regen`/s até `max_resource`); sinais `changed`, `spent`.
- `CooldownTracker` (RefCounted): `start(id, s)`, `is_ready`, `remaining`, `tick`, `clear`; sinal `cooldown_finished`.
- `CharacterStateMachine` (RefCounted): estados idle/move/attack/dodge/hit/dead; fases windup/active/recover; `try_attack`, `try_dodge`, `hit(stun)`, `die`, `revive`, `tick`. Tabela de transições no cabeçalho do arquivo. Todo estado temporizado volta a IDLE.
- `SkillData` (Resource, `data/skills/*.tres`): `basic_attack`, `heavy_strike`, `whirlwind`, `dodge`; `validate()` lista erros. Dano = `attack_power * damage_multiplier`.
- `Hitbox` / `Hurtbox` (Area3D): `Hitbox.begin_strike(amount, source) -> hit_id` (id novo, contador estático global) e `end_strike()`. **Dedupe autoritativo no `Hurtbox`**: chave `(source, hit_id)`, histórico de 128; o `Hitbox` também guarda um conjunto por golpe.
- `PlayerCombat` (filho `Combat` do Player): lê `attack`, `skill_1`, `skill_2`, `dodge`; `try_use(skill)` (ordem: estado, cooldown, custo; só gasta se tudo ok); `step(delta)` avança tudo (testes chamam manualmente). Trava movimento em windup/active e comanda o deslocamento da esquiva via `Player.movement_locked` / `use_forced_velocity` / `forced_velocity`. Invulnerabilidade da esquiva = `HealthComponent.invulnerable` por `i_frames` s.
- `data/player_base_stats.tres`: StatBlock base do jogador (cópia em runtime).

## Camadas de colisão (`CombatLayers`)
| Camada | Uso |
|---|---|
| 1 | mundo/corpos físicos (padrão já usado por arena e player; inalterada) |
| 2 | `player_hurt` (Hurtbox do jogador) |
| 3 | `enemy_hurt` |
| 4 | `player_hit` (Hitbox do jogador) |
| 5 | `enemy_hit` |
Hurtbox: layer = hurt do seu time, mask 0. Hitbox: layer = hit do time, mask = hurt do time oposto. Áreas não colidem fisicamente com corpos.

## Controles
Ataque: botão esquerdo do mouse; skill_1 (golpe pesado): Q; skill_2 (redemoinho): E; esquiva: Espaço. Mira = facing do jogador (mouse fica para depois). Esquiva vai na direção do input, ou do facing se parado.

## Limites conhecidos
- Sem inimigos, feedback visual/sonoro nem UI nesta entrega; `move_speed` do StatBlock ainda não alimenta o `Player`.
- Hitbox entrega o golpe no primeiro frame de física em que há sobreposição; alvo invulnerável nesse instante perde o golpe.
- Stagger (`hit_stun`) não reaplica enquanto atordoado nem durante a esquiva.
- Testes de dedupe/golpe usam `await physics_frame` com folga de frames (sensíveis ao timing da engine; passaram nas execuções feitas). Os demais são determinísticos.
- Hitbox deve ser filho de um pai sem rotação (o Player usa o yaw só no `Visual`).
- Exports tipados de nós (`@export var x: Node`) vieram nulos na cena; por isso `health_path`/`hitbox_path` (NodePath) resolvidos em `_ready`.
