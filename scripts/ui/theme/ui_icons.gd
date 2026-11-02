class_name UiIcons
extends RefCounted
## E8.4: icones game-icons.net (CC BY 3.0; credito na tela de Creditos) mapeados por dados em data/ui/icons.json
## (habilidades, itens, tipos de item, slots, atributos, classes, recursos, inimigos, UI). Os SVG sao brancos sobre fundo preto: aqui o
## preto vira transparencia e o branco recebe a cor (modulate), gerando uma textura RGBA cacheada em 96 px. Icone ausente =>
## fallback (monograma em moldura), nunca erro. Headless: devolve a textura importada crua (nao ha renderizador).

const DATA_PATH: String = "res://data/ui/icons.json"
const ICON_DIR: String = "res://assets/third_party/game_icons/"
const BAKE_PX: int = 96
const SECTIONS: Array[String] = ["skills", "items", "item_types", "equip_slots", "attributes", "classes", "resources", "enemies", "ui", "talent_tiers"]

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _tex: Dictionary = {}


static func data() -> Dictionary:
	if _loaded:
		return _data
	_loaded = true
	_data = {}
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


static func reload() -> void:
	_loaded = false
	_tex.clear()
	data()


## "autor/nome" da secao (vazio se nao ha mapeamento).
static func ref(section: String, id: String) -> String:
	var sec: Variant = data().get(section, {})
	if sec is Dictionary and (sec as Dictionary).has(id):
		return String((sec as Dictionary)[id])
	return ""


static func path_for(icon_ref: String) -> String:
	return ICON_DIR + icon_ref + ".svg"


static func exists(icon_ref: String) -> bool:
	return not icon_ref.is_empty() and ResourceLoader.exists(path_for(icon_ref))


## Todas as referencias do mapeamento (para validacao/precarga).
static func all_refs() -> Array[String]:
	var out: Array[String] = []
	for sec: String in SECTIONS:
		var d: Variant = data().get(sec, {})
		if d is Dictionary:
			for k: Variant in (d as Dictionary).keys():
				out.append(String((d as Dictionary)[k]))
	return out


## Erros do mapeamento (vazio = ok): referencia mal formada ou arquivo inexistente.
static func validate() -> Array[String]:
	var errs: Array[String] = []
	if data().is_empty():
		errs.append("data/ui/icons.json ausente ou invalido")
		return errs
	for sec: String in SECTIONS:
		var d: Variant = data().get(sec, null)
		if not (d is Dictionary):
			errs.append("secao '%s' ausente" % sec)
			continue
		for k: Variant in (d as Dictionary).keys():
			var r: String = String((d as Dictionary)[k])
			var parts: PackedStringArray = r.split("/")
			if parts.size() != 2 or not (parts[0] in ["lorc", "delapouite"]):
				errs.append("%s.%s: referencia invalida '%s'" % [sec, k, r])
			elif not exists(r):
				errs.append("%s.%s: arquivo ausente '%s'" % [sec, k, r])
	return errs


# ------------------------------------------------------------------ resolucao por tipo de conteudo

static func skill_ref(skill_id: String) -> String:
	return ref("skills", skill_id)


static func attribute_ref(stat: String) -> String:
	return ref("attributes", stat)


static func class_ref(class_id: String) -> String:
	return ref("classes", class_id)


## Icone de item: por id; senao pelo tipo (slot do ItemData, consumivel/material).
static func item_ref(item_id: String) -> String:
	var r: String = ref("items", item_id)
	if not r.is_empty():
		return r
	var path: String = UiText.ITEMS_DIR + item_id + ".tres"
	if Protocol.is_content_id(item_id) and ResourceLoader.exists(path):
		var it: ItemData = load(path) as ItemData
		if it != null:
			if it.is_equippable():
				return ref("item_types", String(ItemRules.SLOT_NAMES.get(int(it.slot), "weapon")))
			return ref("item_types", "material" if it.stackable and item_id.contains("material") else ("consumable" if it.stackable else "misc"))
	return ref("item_types", "misc")


## Icone de no de talento: 1o efeito (habilidade modificada ou atributo); senao o da camada do no.
static func talent_ref(node: Dictionary) -> String:
	for e: Variant in node.get("effects", []):
		if e is Dictionary:
			var ed: Dictionary = e
			if String(ed.get("type", "")) == "skill_mod":
				var s: String = skill_ref(String(ed.get("skill", "")))
				if not s.is_empty():
					return s
			elif String(ed.get("type", "")) == "stat":
				var a: String = attribute_ref(String(ed.get("stat", "")))
				if not a.is_empty():
					return a
	return ref("talent_tiers", String(node.get("tier", "small")))


# ------------------------------------------------------------------ texturas

## Textura RGBA (glifo branco, fundo transparente) ou null se o arquivo nao existe.
static func texture(icon_ref: String) -> Texture2D:
	if icon_ref.is_empty():
		return null
	if _tex.has(icon_ref):
		return _tex[icon_ref] as Texture2D
	var path: String = path_for(icon_ref)
	if not ResourceLoader.exists(path):
		return null
	var raw: Texture2D = load(path) as Texture2D
	var out: Texture2D = raw
	if raw != null and DisplayServer.get_name() != "headless":
		var img: Image = raw.get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != BAKE_PX:
				img.resize(BAKE_PX, BAKE_PX, Image.INTERPOLATE_LANCZOS)
			var bytes: PackedByteArray = img.get_data()
			var n: int = bytes.size()
			var i: int = 0
			while i < n:
				bytes[i + 3] = bytes[i]
				bytes[i] = 255
				bytes[i + 1] = 255
				bytes[i + 2] = 255
				i += 4
			var baked: Image = Image.create_from_data(BAKE_PX, BAKE_PX, false, Image.FORMAT_RGBA8, bytes)
			baked.generate_mipmaps()
			out = ImageTexture.create_from_image(baked)
	_tex[icon_ref] = out
	return out


## Controle de icone: TextureRect com a cor `tint`; sem arquivo => monograma (letra) para nunca ficar vazio.
static func make(icon_ref: String, px: float = 32.0, tint: Color = Color.WHITE, fallback_text: String = "?") -> Control:
	var tex: Texture2D = texture(icon_ref)
	if tex != null:
		var tr: TextureRect = TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(px, px)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.modulate = tint
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_meta("icon_ref", icon_ref)
		return tr
	return make_fallback(px, tint, fallback_text)


static func make_fallback(px: float, tint: Color, text: String) -> Control:
	var l: Label = Label.new()
	l.text = text.substr(0, 1).to_upper() if not text.is_empty() else "?"
	l.custom_minimum_size = Vector2(px, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", NorseFonts.font("title"))
	l.add_theme_font_size_override("font_size", int(px * 0.6))
	l.add_theme_color_override("font_color", tint)
	l.set_meta("icon_fallback", true)
	return l
