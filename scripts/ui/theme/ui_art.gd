class_name UiArt
extends RefCounted
## E8.4: arte de UI gerada por codigo (sem assets): molduras 9-patch (StyleBoxTexture) com madeira escura, bandas de ferro,
## fio de ouro velho, cantos chanfrados e rebites/ornamentos rúnicos; icones de checkbox/slider. Tudo cacheado (gera na 1a vez).
## So apresentacao; o conteudo e deterministico (mesma imagem sempre) para os testes.

const OUTLINE: Color = Color("#090706")
const IRON_LIGHT: Color = Color("#5d636e")
const IRON_DARK: Color = Color("#2a2e35")
const GOLD_DIM: Color = Color("#8a6f33")
const GOLD: Color = Color("#c9a24a")
const GOLD_BRIGHT: Color = Color("#ecca78")

static var _cache: Dictionary = {}


static func _hash(x: int, y: int) -> float:
	return fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)


## Imagem de moldura. Chaves de `sp`: size, chamfer, band, top, bottom, noise, alpha, line, light, dark, outline, ornaments, orn, glow, shadow.
static func frame_image(sp: Dictionary) -> Image:
	var s: int = int(sp.get("size", 64))
	var ch: int = int(sp.get("chamfer", 4))
	var band: int = int(sp.get("band", 2))
	var top: Color = sp.get("top", Color("#2a2018")) as Color
	var bottom: Color = sp.get("bottom", Color("#17110d")) as Color
	var noise: float = float(sp.get("noise", 0.06))
	var alpha: float = float(sp.get("alpha", 1.0))
	var line: Color = sp.get("line", GOLD_DIM) as Color
	var c_light: Color = sp.get("light", IRON_LIGHT) as Color
	var c_dark: Color = sp.get("dark", IRON_DARK) as Color
	var c_out: Color = sp.get("outline", OUTLINE) as Color
	var glow: Color = sp.get("glow", Color(0, 0, 0, 0)) as Color
	var shadow: float = float(sp.get("shadow", 0.5))
	var img: Image = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var line_depth: int = band + 2
	for y: int in s:
		for x: int in s:
			var dx: int = mini(x, s - 1 - x)
			var dy: int = mini(y, s - 1 - y)
			var e: int = mini(dx, dy)
			var c1: int = x + y - ch
			var c2: int = (s - 1 - x) + y - ch
			var c3: int = x + (s - 1 - y) - ch
			var c4: int = (s - 1 - x) + (s - 1 - y) - ch
			var depth: int = mini(e, mini(mini(c1, c2), mini(c3, c4)))
			if depth < 0:
				continue
			# lado iluminado (cima/esquerda) ou sombreado (baixo/direita)
			var tone: float = 0.5
			if depth == c1:
				tone = 1.0
			elif depth == c4:
				tone = 0.0
			elif depth == c2 or depth == c3:
				tone = 0.5
			elif depth == dy:
				tone = 1.0 if y < s / 2 else 0.0
			else:
				tone = 1.0 if x < s / 2 else 0.0
			var col: Color
			if depth == 0:
				col = c_out
			elif depth <= band:
				col = c_dark.lerp(c_light, tone)
				if depth == 1:
					col = col.lightened(0.08)
			elif depth == band + 1:
				col = c_out.lerp(c_dark, 0.35)
			elif depth == line_depth:
				col = line
			else:
				var fill: Color = top.lerp(bottom, float(y) / float(s))
				var n: float = _hash(x, y)
				fill = fill.lightened((n - 0.5) * noise)
				var inset: int = depth - line_depth
				if inset < 4:
					fill = fill.darkened(shadow * (1.0 - float(inset) / 4.0))
					if glow.a > 0.0:
						fill = fill.lerp(Color(glow.r, glow.g, glow.b, 1.0), glow.a * (1.0 - float(inset) / 4.0))
				col = fill
				col.a = alpha
			img.set_pixel(x, y, col)
	if bool(sp.get("ornaments", false)):
		_ornaments(img, s, ch, line_depth, sp.get("orn", GOLD_BRIGHT) as Color, line)
	return img


## Rebite + colchete dourado nos 4 cantos.
static func _ornaments(img: Image, s: int, ch: int, line_depth: int, orn: Color, line: Color) -> void:
	var r: int = line_depth + 5
	var centers: Array[Vector2i] = [Vector2i(r, r), Vector2i(s - 1 - r, r), Vector2i(r, s - 1 - r), Vector2i(s - 1 - r, s - 1 - r)]
	for k: int in 4:
		var c: Vector2i = centers[k]
		var sx: int = 1 if c.x < s / 2 else -1
		var sy: int = 1 if c.y < s / 2 else -1
		# colchete brilhante ao longo das duas bordas
		for t: int in range(ch + 1, ch + 11):
			var px: Vector2i = Vector2i(c.x - sx * (r - line_depth) + sx * t - sx * 0, line_depth if sy > 0 else s - 1 - line_depth)
			var qx: Vector2i = Vector2i(line_depth if sx > 0 else s - 1 - line_depth, c.y - sy * (r - line_depth) + sy * t)
			if px.x >= 0 and px.x < s:
				img.set_pixelv(px, orn)
			if qx.y >= 0 and qx.y < s:
				img.set_pixelv(qx, orn)
		# rebite em cruz com centro brilhante
		for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			img.set_pixelv(c + d, line.lerp(orn, 0.6) if d != Vector2i.ZERO else orn)
		for d2: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var p: Vector2i = c + d2
			if p.x >= 0 and p.y >= 0 and p.x < s and p.y < s:
				img.set_pixelv(p, OUTLINE)


static func nine(img: Image, margin: int, content_h: int, content_v: int, tile: bool = true) -> StyleBoxTexture:
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(float(margin))
	sb.content_margin_left = float(content_h)
	sb.content_margin_right = float(content_h)
	sb.content_margin_top = float(content_v)
	sb.content_margin_bottom = float(content_v)
	if tile:
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


static func _cached(key: String, builder: Callable) -> StyleBox:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return (_cache[key] as StyleBox).duplicate() as StyleBox


## Painel modal: madeira escura, banda de ferro, fio de ouro e ornamentos nos cantos.
static func panel() -> StyleBox:
	return _cached("panel", func() -> StyleBox:
		return nine(frame_image({"size": 64, "chamfer": 6, "band": 2, "top": Color("#2c2219"), "bottom": Color("#17110d"), "noise": 0.07, "alpha": 0.97, "ornaments": true}), 18, 20, 16))


## Painel de HUD (mais leve e translúcido).
static func hud(alpha: float = 0.78) -> StyleBox:
	return _cached("hud%.2f" % alpha, func() -> StyleBox:
		return nine(frame_image({"size": 32, "chamfer": 3, "band": 1, "top": Color("#261d15"), "bottom": Color("#120d0a"), "noise": 0.05, "alpha": alpha, "shadow": 0.35, "line": GOLD_DIM}), 9, 10, 8))


## Moldura dramatica do chefe: ferro escuro, ouro e vermelho-sangue.
static func boss() -> StyleBox:
	return _cached("boss", func() -> StyleBox:
		return nine(frame_image({"size": 64, "chamfer": 7, "band": 3, "top": Color("#2a1210"), "bottom": Color("#120807"), "noise": 0.06, "alpha": 0.94, "ornaments": true,
			"line": Color("#a4381f"), "orn": Color("#ff9a58"), "light": Color("#7a6a52"), "dark": Color("#2c2622"), "glow": Color(0.7, 0.12, 0.08, 0.35)}), 22, 18, 10))


## Estados de botao: normal, hover, pressed, disabled.
static func button(state: String) -> StyleBox:
	return _cached("btn_" + state, func() -> StyleBox:
		var sp: Dictionary = {"size": 24, "chamfer": 3, "band": 1, "noise": 0.05, "shadow": 0.3}
		match state:
			"hover":
				sp.merge({"top": Color("#4a3a26"), "bottom": Color("#2c2216"), "line": GOLD_BRIGHT, "glow": Color(0.9, 0.7, 0.3, 0.25), "light": Color("#8a8f99")})
			"pressed":
				sp.merge({"top": Color("#120d09"), "bottom": Color("#241a12"), "line": GOLD, "light": IRON_DARK, "dark": IRON_LIGHT})
			"disabled":
				sp.merge({"top": Color("#1a1714"), "bottom": Color("#12100e"), "line": Color("#3b352c"), "light": Color("#35383e"), "dark": Color("#22252a")})
			_:
				sp.merge({"top": Color("#3a2c1e"), "bottom": Color("#21190f"), "line": GOLD_DIM})
		return nine(frame_image(sp), 8, 10, 6))


## Slot de inventario/habilidade com borda na cor da raridade (`glow` > 0 acende o interior).
static func slot(rarity: Color, glow: float = 0.0, state: String = "normal") -> StyleBox:
	var key: String = "slot_%s_%.2f_%s" % [rarity.to_html(false), glow, state]
	return _cached(key, func() -> StyleBox:
		var sp: Dictionary = {"size": 24, "chamfer": 2, "band": 1, "top": Color("#1a140f"), "bottom": Color("#0f0b08"), "noise": 0.04, "shadow": 0.45,
			"line": rarity.darkened(0.15), "light": rarity.darkened(0.45), "dark": rarity.darkened(0.7)}
		if glow > 0.0:
			sp["glow"] = Color(rarity.r, rarity.g, rarity.b, glow)
		if state == "hover":
			sp.merge({"top": Color("#2b2217"), "line": rarity.lightened(0.35), "light": rarity.lightened(0.1)})
		elif state == "selected":
			sp.merge({"top": Color("#33281a"), "bottom": Color("#1c150e"), "line": GOLD_BRIGHT, "light": GOLD, "dark": GOLD_DIM, "glow": Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, 0.3)})
		return nine(frame_image(sp), 7, 6, 4))


static func tooltip() -> StyleBox:
	return _cached("tooltip", func() -> StyleBox:
		return nine(frame_image({"size": 32, "chamfer": 3, "band": 1, "top": Color("#1d150f"), "bottom": Color("#0e0a07"), "noise": 0.03, "alpha": 0.98, "shadow": 0.3, "line": GOLD}), 9, 10, 8))


## Toast: caixa colorida pelo tipo de aviso.
static func toast(accent: Color) -> StyleBox:
	return _cached("toast_" + accent.to_html(false), func() -> StyleBox:
		return nine(frame_image({"size": 32, "chamfer": 3, "band": 1, "top": Color("#241b13"), "bottom": Color("#110c09"), "noise": 0.04, "alpha": 0.92, "shadow": 0.3,
			"line": accent.darkened(0.2), "glow": Color(accent.r, accent.g, accent.b, 0.12)}), 9, 12, 6))


## Mini-moldura simples (barra de ferro + fio) para o minimapa.
static func minimap() -> StyleBox:
	return _cached("minimap", func() -> StyleBox:
		return nine(frame_image({"size": 48, "chamfer": 5, "band": 2, "top": Color("#241b13"), "bottom": Color("#120d0a"), "alpha": 0.9, "ornaments": true, "shadow": 0.3}), 14, 12, 10))


## Icone 20x20 de checkbox (marcado/desmarcado).
static func check_icon(checked: bool) -> Texture2D:
	var key: String = "check_%s" % checked
	if not _cache.has(key):
		var img: Image = Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y: int in range(2, 18):
			for x: int in range(2, 18):
				var edge: int = mini(mini(x - 2, 17 - x), mini(y - 2, 17 - y))
				var col: Color = OUTLINE if edge == 0 else (GOLD_DIM if edge == 1 else Color("#1a130d"))
				img.set_pixel(x, y, col)
		if checked:
			for i: int in range(-5, 6):
				for j: int in range(-5, 6):
					if absi(i) + absi(j) <= 5:
						img.set_pixel(10 + i, 10 + j, GOLD_BRIGHT if absi(i) + absi(j) <= 3 else GOLD)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key] as Texture2D


## Punho de slider: losango dourado 18x18.
static func grabber_icon(hot: bool = false) -> Texture2D:
	var key: String = "grab_%s" % hot
	if not _cache.has(key):
		var img: Image = Image.create(18, 18, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y: int in 18:
			for x: int in 18:
				var d: float = absf(float(x) - 8.5) + absf(float(y) - 8.5)
				if d <= 8.5:
					img.set_pixel(x, y, OUTLINE if d > 7.0 else (GOLD_BRIGHT if hot else GOLD).lerp(GOLD_DIM, clampf((d - 2.0) / 6.0, 0.0, 1.0)))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key] as Texture2D


static func clear_cache() -> void:
	_cache.clear()
