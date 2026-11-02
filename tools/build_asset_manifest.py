#!/usr/bin/env python3
"""Gera assets/ASSET_MANIFEST.json a partir de assets/third_party/ (E8.0).

Uso (na raiz do projeto):  python3 tools/build_asset_manifest.py
Cada arquivo de modelo/audio/fonte/icone/sprite vira uma entrada (id logico -> caminho,
categoria, pacote, licenca, tags). A secao "aliases" mapeia ids de jogo -> ids de asset
(mapeamento proposto para o E8.1; editar ALIASES abaixo).
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TP = os.path.join(ROOT, "assets", "third_party")
OUT = os.path.join(ROOT, "assets", "ASSET_MANIFEST.json")

PACKAGES = {
    "kaykit_adventurers": ("KayKit Adventurers Character Pack 1.0", "Kay Lousberg", "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0", "CC0-1.0"),
    "kaykit_skeletons": ("KayKit Skeletons Character Pack 1.0", "Kay Lousberg", "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0", "CC0-1.0"),
    "kaykit_dungeon_remastered": ("KayKit Dungeon Remastered 1.0", "Kay Lousberg", "https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0", "CC0-1.0"),
    "kaykit_halloween_bits": ("KayKit Halloween Bits 1.0", "Kay Lousberg", "https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0", "CC0-1.0"),
    "kaykit_medieval_hexagon": ("KayKit Medieval Hexagon Pack 1.0", "Kay Lousberg", "https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0", "CC0-1.0"),
    "quaternius_animals": ("Quaternius Ultimate Animated Animal Pack", "Quaternius", "https://quaternius.com/packs/ultimateanimatedanimals.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_easy_enemies": ("Quaternius Easy Enemy Pack", "Quaternius", "https://quaternius.com/packs/easyenemy.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_knight": ("Quaternius Animated Knight Pack", "Quaternius", "https://quaternius.com/packs/knightcharacter.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_nature": ("Quaternius Ultimate Nature Pack", "Quaternius", "https://quaternius.com/packs/ultimatenature.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_medieval_village": ("Quaternius Medieval Village Pack", "Quaternius", "https://quaternius.com/packs/medievalvillage.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_medieval_buildings": ("Quaternius Modular Medieval Building Pack", "Quaternius", "https://quaternius.com/packs/modularmedievalbuildings.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_rpg_items": ("Quaternius Ultimate RPG Pack", "Quaternius", "https://quaternius.com/packs/ultimaterpg.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_survival": ("Quaternius Survival Pack", "Quaternius", "https://quaternius.com/packs/survival.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_rts": ("Quaternius Ultimate Fantasy RTS", "Quaternius", "https://quaternius.com/packs/ultimatefantasyrts.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "quaternius_modular_dungeon": ("Quaternius Modular Dungeon Pack", "Quaternius", "https://quaternius.com/packs/medievaldungeon.html (via github.com/trebeljahr/quaternius-showcase)", "CC0-1.0"),
    "kenney_mini_arena": ("Kenney Mini Arena 1.0 (from Starter-Kit-Basic-Scene)", "Kenney (credit: Tony Schaer)", "https://github.com/KenneyNL/Starter-Kit-Basic-Scene", "CC0-1.0"),
    "kenney_starter_kits": ("Kenney Starter Kits (sprites + SFX)", "Kenney", "https://github.com/KenneyNL (Starter-Kit-3D-Platformer, -FPS, -City-Builder, -Racing)", "CC0-1.0"),
    "oculus_audio_pack": ("Oculus Audio Pack 01 (subset)", "Oculus VR, LLC", "https://github.com/facebookincubator/Meta-open-sound (corpora/oculus-audio-pack)", "CC-BY-4.0"),
    "google_fonts": ("Google Fonts (Cinzel, Cinzel Decorative, Almendra, Uncial Antiqua, MedievalSharp, IM Fell Double Pica, Metamorphous, Noto Sans Runic)", "various (see OFL.txt per font)", "https://github.com/google/fonts (ofl/)", "OFL-1.1"),
    "game_icons": ("game-icons.net (Lorc, Delapouite)", "Lorc, Delapouite", "https://github.com/game-icons/icons", "CC-BY-3.0"),
}

def tags_for(pkg, rel, name):
    n = name.lower()
    t = []
    def has(rx): return re.search(rx, n) is not None
    if pkg == "kaykit_adventurers":
        t = ["character", "player-class", "rig:kaykit-rig-medium", "animated"]
        t.append({"barbarian": "class:warrior", "knight": "class:warrior", "mage": "class:mage", "rogue": "class:ranger", "rogue_hooded": "class:ranger"}[n])
    elif pkg == "kaykit_skeletons":
        t = ["character", "enemy", "undead", "rig:kaykit-rig-medium", "animated", "role:" + n.replace("skeleton_", "")]
    elif pkg == "quaternius_animals":
        t = ["character", "animal", "animated", "rig:quaternius-animal"] + (["enemy", "beast", "wolf"] if n == "wolf" else ["enemy-candidate"] if n in ("fox", "husky", "stag") else [])
    elif pkg == "quaternius_easy_enemies":
        t = ["character", "enemy", "beast", "animated"]
    elif pkg == "quaternius_knight":
        t = ["character", "animated", "class:warrior-alt", "rig:quaternius-human"]
    elif pkg == "kenney_mini_arena" and n == "character-soldier":
        t = ["character", "animated", "prototype"]
    elif pkg == "quaternius_rpg_items":
        t = ["item", "icon-model"] + [k for k in ("weapon", "armor", "potion", "treasure", "jewelry", "book", "key") if has({"weapon": "sword|axe|dagger|hammer|bow|arrow|dart", "armor": "armor|glove", "potion": "potion", "treasure": "coin|gold|crown|chalice|chest|crystal|mineral", "jewelry": "ring|necklace", "book": "book|scroll|parchment", "key": "key|padlock"}[k])]
    elif pkg == "quaternius_survival":
        t = ["prop"] + (["fire", "light"] if has("torch|bonfire") else [])
    elif pkg in ("quaternius_nature",):
        t = ["env"] + [k for k, rx in (("tree", "tree"), ("pine", "pine"), ("snow", "snow"), ("rock", "rock"), ("bush", "bush"), ("dead", "dead"), ("log", "log|stump"), ("foliage", "grass|plant|flowers")) if re.search(rx, n)]
    elif pkg == "quaternius_rts":
        t = ["env"] + [k for k, rx in (("wall", "wall"), ("tower", "tower"), ("house", "house|town|barracks|storage|temple|wonder|dock"), ("tree", "tree"), ("rock", "rock|mountain|mine|gold"), ("prop", "crate|barrel|logs")) if re.search(rx, n)]
    elif pkg in ("quaternius_medieval_village", "quaternius_medieval_buildings", "quaternius_modular_dungeon", "kenney_mini_arena"):
        t = ["env"] + [k for k, rx in (("building", "house|inn|blacksmith|mill|stable|sawmill|bell_tower|tower|gazebo"), ("wall", "wall|fence"), ("fire", "bonfire|torch"), ("prop", "barrel|crate|cart|bench|well|cauldron|hay|bag|package|market|bell|dummy|target|banner|statue|trophy|weapon"), ("rock", "rock|stone")) if re.search(rx, n)]
    elif pkg == "kaykit_dungeon_remastered":
        t = ["env", "dungeon"] + [k for k, rx in (("wall", "^wall"), ("floor", "^floor"), ("pillar", "pillar|column"), ("stairs", "stairs"), ("fire", "torch|candle"), ("prop", "barrel|box|crate|keg|table|chair|stool|trunk|coin|key|sword|banner|shelf|rubble|barrier")) if re.search(rx, n)]
    elif pkg == "kaykit_halloween_bits":
        t = ["env", "graveyard", "ruin"] + [k for k, rx in (("tree", "tree"), ("grave", "grave|crypt|coffin|shrine|plaque"), ("fence", "fence"), ("light", "lantern|candle"), ("bone", "bone|skull|ribcage"), ("path", "path|floor"), ("arch", "arch|pillar")) if re.search(rx, n)]
    elif pkg == "kaykit_medieval_hexagon":
        sub = rel.split("/")[3]
        t = ["env", "hex-pack-scale", sub]
    return t

def main():
    assets, counts = {}, {}
    for pkg in sorted(os.listdir(TP)):
        pdir = os.path.join(TP, pkg)
        if not os.path.isdir(pdir):
            continue
        for dp, _, fs in os.walk(pdir):
            for f in sorted(fs):
                ext = os.path.splitext(f)[1].lower()
                full = os.path.join(dp, f)
                rel = "assets/third_party/" + os.path.relpath(full, TP).replace(os.sep, "/")
                base = os.path.splitext(f)[0]
                sub = os.path.relpath(dp, pdir).replace(os.sep, "/")
                if ext in (".glb", ".gltf"):
                    cat = "model"; tg = tags_for(pkg, rel, base)
                elif ext in (".ogg", ".wav"):
                    cat = "audio"; tg = ["audio", "music-sting" if "MUSC" in f else "sfx"]
                    if pkg == "oculus_audio_pack":
                        m = re.match(r"([A-Z]+)", f); tg.append("ucs:" + (m.group(1) if m else "?"))
                elif ext in (".ttf", ".otf"):
                    cat = "font"; tg = ["font", "ui"]
                elif ext == ".svg":
                    cat = "icon"; tg = ["icon", "ui", "author:" + sub]
                elif ext == ".png" and pkg == "kenney_starter_kits":
                    cat = "vfx"; tg = ["vfx", "particle-texture"]
                else:
                    continue  # LICENSE, .bin, texturas embutidas por modelo
                idb = re.sub(r"[^a-z0-9_]+", "_", base.lower()).strip("_")
                if sub != "." and pkg in ("kaykit_medieval_hexagon", "game_icons", "google_fonts"):
                    idb = re.sub(r"[^a-z0-9_]+", "_", sub.lower()) + "." + idb
                aid = f"{cat}.{pkg}.{idb}"
                n = 2
                while aid in assets:
                    aid = f"{cat}.{pkg}.{idb}_{n}"; n += 1
                assets[aid] = {"path": rel, "category": cat, "package": pkg, "license": PACKAGES[pkg][3], "tags": tg}
                counts[cat] = counts.get(cat, 0) + 1
    A = lambda cat, pkg, n: f"{cat}.{pkg}.{n}"
    aliases = {
        "class.warrior": A("model", "kaykit_adventurers", "barbarian"),
        "class.warrior_alt": A("model", "kaykit_adventurers", "knight"),
        "class.mage": A("model", "kaykit_adventurers", "mage"),
        "class.ranger": A("model", "kaykit_adventurers", "rogue_hooded"),
        "class.ranger_alt": A("model", "kaykit_adventurers", "rogue"),
        "enemy.skeleton_warrior": A("model", "kaykit_skeletons", "skeleton_warrior"),
        "enemy.skeleton_archer": A("model", "kaykit_skeletons", "skeleton_rogue"),
        "enemy.skeleton_conjurer": A("model", "kaykit_skeletons", "skeleton_mage"),
        "enemy.minion": A("model", "kaykit_skeletons", "skeleton_minion"),
        "enemy.brute": A("model", "kaykit_skeletons", "skeleton_warrior") ,
        "enemy.wolf": A("model", "quaternius_animals", "wolf"),
        "enemy.beast_fox": A("model", "quaternius_animals", "fox"),
        "enemy.beast_stag": A("model", "quaternius_animals", "stag"),
        "enemy.spider": A("model", "quaternius_easy_enemies", "spider"),
        "enemy.boss": A("model", "kaykit_skeletons", "skeleton_warrior"),
        "enemy.corrupted_tree": A("model", "quaternius_nature", "commontree_dead_snow_1"),
        "prop.tree_pine_snow": A("model", "quaternius_nature", "pinetree_snow_1"),
        "prop.tree_dead_snow": A("model", "quaternius_nature", "commontree_dead_snow_2"),
        "prop.rock_snow": A("model", "quaternius_nature", "rock_snow_1"),
        "prop.bush_snow": A("model", "quaternius_nature", "bush_snow_1"),
        "prop.house_viking_1": A("model", "quaternius_medieval_village", "house_1"),
        "prop.house_viking_2": A("model", "quaternius_medieval_village", "house_2"),
        "prop.longhouse_inn": A("model", "quaternius_medieval_village", "inn"),
        "prop.blacksmith": A("model", "quaternius_medieval_village", "blacksmith"),
        "prop.bonfire": A("model", "quaternius_medieval_village", "bonfire_lit"),
        "prop.torch_wall": A("model", "kaykit_dungeon_remastered", "torch_mounted"),
        "prop.torch_lit": A("model", "kaykit_dungeon_remastered", "torch_lit"),
        "prop.chest": A("model", "quaternius_rpg_items", "chest_closed"),
        "prop.chest_open": A("model", "quaternius_rpg_items", "chest_open"),
        "prop.wall_stone": A("model", "kaykit_dungeon_remastered", "wall"),
        "prop.ruin_wall": A("model", "kaykit_dungeon_remastered", "wall_broken"),
        "prop.ruin_pillar": A("model", "kaykit_halloween_bits", "pillar"),
        "prop.rune_shrine": A("model", "kaykit_halloween_bits", "shrine"),
        "prop.gravestone": A("model", "kaykit_halloween_bits", "gravestone"),
        "prop.bridge": A("model", "kaykit_medieval_hexagon", "buildings_neutral.building_bridge_a"),
        "prop.watchtower": A("model", "quaternius_rts", "watchtower_firstage_level1"),
        "vfx.particle_soft": A("vfx", "kenney_starter_kits", "particle"),
        "vfx.smoke": A("vfx", "kenney_starter_kits", "smoke"),
        "vfx.burst": A("vfx", "kenney_starter_kits", "burst"),
        "vfx.hit": A("vfx", "kenney_starter_kits", "hit"),
        "font.title": A("font", "google_fonts", "cinzeldecorative.cinzeldecorative_bold"),
        "font.heading": A("font", "google_fonts", "cinzel.cinzel_variable"),
        "font.body": A("font", "google_fonts", "imfelldoublepica.imfelldoublepica_regular"),
        "font.runes": A("font", "google_fonts", "notosansrunic.notosansrunic_regular"),
    }
    missing = [f"{k}->{v}" for k, v in aliases.items() if v not in assets]
    if missing:
        print("ALIASES SEM ASSET:", *missing, sep="\n  "); sys.exit(1)
    pk = {k: {"name": v[0], "author": v[1], "source": v[2], "license": v[3], "license_file": None} for k, v in PACKAGES.items()}
    for k in pk:
        for cand in ("LICENSE.txt", "LICENSE.md", "license.txt", "ATTRIBUTION.txt"):
            if os.path.exists(os.path.join(TP, k, cand)):
                pk[k]["license_file"] = f"assets/third_party/{k}/{cand}"; break
    pk["google_fonts"]["license_file"] = "assets/third_party/google_fonts/<familia>/OFL.txt (um por familia)"
    out = {"version": 1, "generated_by": "tools/build_asset_manifest.py", "counts": counts, "packages": pk, "aliases": aliases, "assets": assets}
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1, sort_keys=False); fh.write("\n")
    print("OK", len(assets), "entradas;", counts, "aliases:", len(aliases))

main()
