class_name DamageInfo
extends RefCounted
## Pacote de dano (contrato compartilhado E2). Criado por quem ataca, consumido pelo alvo.

var amount: float = 0.0 ## dano bruto, antes de defesa/resistencia
var source: Node = null
var damage_type: StringName = &"physical"
var hit_id: int = 0 ## identifica UM golpe/ataque, para impedir dano multiplo do mesmo golpe
var is_critical: bool = false


static func make(p_amount: float, p_source: Node, p_hit_id: int, p_type: StringName = &"physical") -> DamageInfo:
	var d: DamageInfo = DamageInfo.new()
	d.amount = p_amount
	d.source = p_source
	d.hit_id = p_hit_id
	d.damage_type = p_type
	return d
