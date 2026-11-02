class_name UiFx
extends RefCounted
## E8.4: efeitos de interface (Tween) SO cosmeticos. Duas regras: (1) headless/bot/teste nao anima (tudo instantaneo e
## deterministico; `force_enabled` liga para os testes de animacao); (2) `VfxSettings.reduce_motion` (--reduce-motion do E8.3)
## remove movimento, escala, tremor, pulsos e brilho em loop, mantendo apenas fades curtos. Nada aqui decide jogo.

const META_TWEEN: StringName = &"_ui_fx_tween"
const META_BASE_POS: StringName = &"_ui_fx_base_pos"

static var force_enabled: bool = false


## Animacoes de qualquer tipo disponiveis (ha janela de verdade ou os testes forcaram).
static func available() -> bool:
	return force_enabled or DisplayServer.get_name() != "headless"


## Movimento/escala/pulsos/tremor/brilho em loop: so sem reduce_motion.
static func motion() -> bool:
	return available() and not VfxSettings.reduce_motion


## Duracao de um fade: 0 em headless, 55% com reduce_motion.
static func fade_time(base: float) -> float:
	if not available():
		return 0.0
	return base * 0.55 if VfxSettings.reduce_motion else base


static func _kill(c: CanvasItem) -> void:
	if c.has_meta(META_TWEEN):
		var old: Variant = c.get_meta(META_TWEEN)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		c.remove_meta(META_TWEEN)


static func _tween(c: CanvasItem) -> Tween:
	_kill(c)
	var tw: Tween = c.create_tween()
	c.set_meta(META_TWEEN, tw)
	return tw


## Esconde AGORA (sem animacao) e restaura alpha/escala.
static func hide_now(c: Control) -> void:
	_kill(c)
	c.visible = false
	c.modulate.a = 1.0
	c.scale = Vector2.ONE


## Painel/caixa aparece: fade + leve escala/subida (so com movimento). Fica visivel imediatamente.
static func appear(c: Control, rise: float = 8.0) -> void:
	_kill(c)
	c.visible = true
	if not available() or not c.is_inside_tree():
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
		return
	var t: float = fade_time(0.18)
	c.modulate.a = 0.0
	var tw: Tween = _tween(c)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if motion():
		c.pivot_offset = c.get_combined_minimum_size().max(c.size) * 0.5
		c.scale = Vector2(0.94, 0.94)
		tw.tween_property(c, "scale", Vector2.ONE, t * 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if not (c.get_parent() is Container):  # ancorado: sobe pelos offsets (position seria sobrescrito pelo layout)
			var top: float = c.offset_top
			var bottom: float = c.offset_bottom
			c.offset_top = top + rise
			c.offset_bottom = bottom + rise
			tw.tween_property(c, "offset_top", top, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "offset_bottom", bottom, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Painel/caixa some: fade; `visible` vira false ao fim (imediato em headless).
static func vanish(c: Control, after: Callable = Callable()) -> void:
	_kill(c)
	if not available() or not c.is_inside_tree() or not c.visible:
		c.visible = false
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
		if after.is_valid():
			after.call()
		return
	var tw: Tween = _tween(c)
	tw.tween_property(c, "modulate:a", 0.0, fade_time(0.12)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		c.visible = false
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
		if after.is_valid():
			after.call())


## Pulso curto de brilho (modulate) e de escala; sem movimento so um flash de brilho fraco.
static func pulse(c: CanvasItem, color: Color = Color(1.6, 1.5, 1.2, 1.0), time: float = 0.35) -> void:
	if not available() or not c.is_inside_tree():
		return
	if not motion():
		return
	var tw: Tween = _tween(c)
	c.modulate = color
	tw.tween_property(c, "modulate", Color.WHITE, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if c is Control:
		var ctl: Control = c as Control
		ctl.pivot_offset = ctl.size * 0.5
		ctl.scale = Vector2(1.08, 1.08)
		tw.parallel().tween_property(ctl, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Tremor leve de um Control do HUD (dano sofrido). Nulo com reduce_motion.
static func shake(c: Control, amount: float = 5.0, time: float = 0.28) -> void:
	if not motion() or not c.is_inside_tree():
		return
	var base: Vector2 = c.get_meta(META_BASE_POS) as Vector2 if c.has_meta(META_BASE_POS) else c.position
	c.set_meta(META_BASE_POS, base)
	var tw: Tween = _tween(c)
	var steps: int = 6
	for i: int in steps:
		var k: float = 1.0 - float(i) / float(steps)
		var off: Vector2 = Vector2(amount * k * (1.0 if i % 2 == 0 else -1.0), amount * 0.4 * k * (-1.0 if i % 3 == 0 else 1.0))
		tw.tween_property(c, "position", base + off, time / float(steps)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "position", base, 0.04)
	tw.tween_callback(func() -> void: c.remove_meta(META_BASE_POS))


## Entrada de um toast/notificacao: desliza lateralmente com ease (so com movimento) + fade.
static func slide_in(c: Control, from_x: float = 36.0, time: float = 0.28) -> void:
	if not available() or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw: Tween = _tween(c)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, fade_time(time)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if motion():
		# o container manda na posicao: anima so o deslocamento visual por `pivot`/scale horizontal
		c.pivot_offset = Vector2(c.size.x, c.size.y * 0.5)
		c.scale = Vector2(0.9, 1.0)
		tw.tween_property(c, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fade de tela/camada (transicao de telas): alvo de alpha em `time`.
static func fade_to(c: CanvasItem, alpha: float, time: float, after: Callable = Callable()) -> void:
	if not available() or not c.is_inside_tree():
		c.modulate.a = alpha
		if after.is_valid():
			after.call()
		return
	var tw: Tween = _tween(c)
	tw.tween_property(c, "modulate:a", alpha, fade_time(time)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if after.is_valid():
		tw.tween_callback(after)
