class_name PlayerLoadout
extends Node
## Inventario, equipamento e progressao do jogador (filho "Loadout" do Player, depois de "Combat").
## Recalcula os stats finais com StatCalculator (base + nivel + equipados) e os aplica em
## HealthComponent.stats e no ResourcePool de PlayerCombat. Como o dano do golpe e
## `health.stats.attack_power * multiplicador`, equipar uma arma muda o dano real.
##
## POLITICA DE VIDA/RECURSO ao mudar o maximo: preserva a PROPORCAO atual (current/max_antigo *
## max_novo). Assim equipar nao "enche" de graca e desequipar/reequipar nao cria vida (sem
## exploit de troca). Subir de nivel usa a mesma regra (vida sobe proporcionalmente ao novo maximo).
## Jogador morto: stats sao recalculados mas a vida permanece 0.
## Autoridade local (E2): nada aqui e validado por servidor (E3).

signal stats_changed(final_stats: StatBlock)
signal inventory_message(text: String)

@export var combat_path: NodePath = NodePath("../Combat")
@export var inventory_capacity: int = 20

var registry: ContentRegistry
var inventory: Inventory
var equipment: Equipment
var progress: CharacterProgress = CharacterProgress.new()
## E5.1: estado persistido de quests do personagem (o QuestTracker do servidor opera sobre ESTA instancia;
## CharacterCodec restaura/captura em-place). O cliente nunca escreve aqui.
var quest_state: QuestState = QuestState.new()
var final_stats: StatBlock
## E6.1: classe aplicada pelo servidor (`apply_class`); null = jogador legado/offline (crescimento e habilidades padrao da cena).
var class_def: ClassDef
## E6.2: talentos do personagem (estado persistido pelo backend; so o servidor altera, via TalentService/CharacterCodec). O bonus de
## stats e os modificadores de habilidade derivam dele em `apply_talents`.
var talents: TalentState = TalentState.new()
var _talent_bonus: StatBlock = null

var combat: PlayerCombat
var health: HealthComponent
var base_stats: StatBlock


## Acha o Loadout do jogador a partir do Player (ou de qualquer no cujo filho seja "Loadout").
static func find_for(node: Node) -> PlayerLoadout:
	if node == null:
		return null
	return node.get_node_or_null("Loadout") as PlayerLoadout


func _ready() -> void:
	if registry == null:
		registry = ContentRegistry.new()
		registry.load_all()
	inventory = Inventory.new(registry, inventory_capacity)
	equipment = Equipment.new(registry, inventory)
	combat = get_node_or_null(combat_path) as PlayerCombat
	if combat == null or combat.health == null:
		push_error("PlayerLoadout: requer irmao Combat (PlayerCombat) pronto; coloque Loadout depois de Combat.")
		return
	health = combat.health
	base_stats = combat.base_stats.copy() if combat.base_stats != null else health.stats.copy()
	equipment.equipment_changed.connect(func(_slot: int) -> void: recalculate())
	progress.leveled_up.connect(func(_lvl: int, _gained: int) -> void: recalculate())
	recalculate()


## E6.1: aplica a classe: habilidades dos slots (+ restricao de uso em PlayerCombat) e o crescimento por nivel. Os stats BASE nao
## mudam aqui (vem do personagem salvo / da cena). So o servidor chama; o cliente nunca escolhe habilidades.
func apply_class(def: ClassDef) -> bool:
	if def == null or combat == null or not combat.apply_class(def):
		return false
	class_def = def
	progress.bonus_per_level = def.growth.copy()
	talents = TalentState.new() # a arvore e da classe: estado anterior (outra classe) nao vale
	apply_talents()
	return true


## E6.2: arvore de talentos da classe aplicada (null = sem classe/arvore).
func talent_tree() -> TalentTree:
	return TalentCatalog.shared().get_tree(class_def.id) if class_def != null else null


## E6.2: pontos de talento disponiveis agora (nivel atual - gastos).
func talent_points_available() -> int:
	var tree: TalentTree = talent_tree()
	return talents.points_available(tree, progress.level, TalentCatalog.shared()) if tree != null else 0


## E6.2: (re)deriva bonus de stats e modificadores de habilidade a partir de `talents` e recalcula os stats finais. Chame apos qualquer
## mudanca do estado de talentos (alocar/respec/escolher/carregar). Subir de nivel NAO precisa: os bonus dependem so dos ranks.
func apply_talents() -> void:
	var tree: TalentTree = talent_tree()
	var col: Dictionary = SkillMods.collect(tree, talents)
	_talent_bonus = col["stats"]
	if combat != null:
		combat.set_skill_mods(col["skills"])
	recalculate()


func class_id() -> String:
	return class_def.id if class_def != null else ""


## Recalcula e aplica os stats finais (ver politica de proporcao no cabecalho).
func recalculate() -> void:
	if health == null:
		return
	var old_hp_max: float = health.max_health()
	var pool: ResourcePool = combat.resource_pool
	var old_res_max: float = pool.max_value()
	var hp_ratio: float = health.current_health / old_hp_max if old_hp_max > 0.0 else 1.0
	var res_ratio: float = pool.current / old_res_max if old_res_max > 0.0 else 1.0
	final_stats = StatCalculator.compute(base_stats, equipment, progress, _talent_bonus)
	health.stats = final_stats
	if not health.is_dead:
		health.current_health = clampf(hp_ratio * final_stats.max_health, 0.0, final_stats.max_health)
	health.health_changed.emit(health.current_health, final_stats.max_health)
	pool.stats = final_stats
	pool.current = clampf(res_ratio * final_stats.max_resource, 0.0, final_stats.max_resource)
	pool.changed.emit(pool.current, final_stats.max_resource)
	stats_changed.emit(final_stats)


## Concede XP (apenas via inimigo/sistema local). Retorna niveis ganhos.
func grant_xp(amount: int) -> int:
	return progress.add_xp(amount)


## Equipa o item da pilha `index` (0-based, ordem de inventory.contents()). false se nao equipavel.
func equip_from_index(index: int) -> bool:
	var contents: Array[Dictionary] = inventory.contents()
	if index < 0 or index >= contents.size():
		return false
	var id: StringName = contents[index]["id"] as StringName
	if not equipment.equip(id):
		inventory_message.emit(equipment.last_error)
		return false
	return true


func unequip_slot(slot: int) -> bool:
	if not equipment.unequip(slot):
		inventory_message.emit(equipment.last_error)
		return false
	return true
