#!/usr/bin/env python3
"""E8.4 - gera/confere a parte de game-icons e Google Fonts do exclude_filter do preset "Windows Client" em export_presets.cfg.

O Godot aplica o exclude_filter ACIMA do include_filter e a glob nao tem classes de caracteres; entao, para o cliente levar so os
icones/fontes realmente usados, o preset lista UM item por arquivo NAO usado (assets/third_party/game_icons/<autor>/<nome>.svg e as
fontes fora de scripts/ui/theme/norse_fonts.gd). Os usados vem de data/ui/icons.json e de NorseFonts.PATHS.
O preset do SERVIDOR continua com assets/* excluido (nao carrega arte).

Uso: python3 tools/gen_export_filter.py [--check]   (sem flag: reescreve o export_presets.cfg; --check: sai 1 se estiver desatualizado)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "export_presets.cfg"
ICONS = "assets/third_party/game_icons/"
FONTS = "assets/third_party/google_fonts/"


def used_icons():
    doc = json.loads((ROOT / "data/ui/icons.json").read_text(encoding="utf-8"))
    refs = set()
    for sec, d in doc.items():
        if isinstance(d, dict):
            refs.update(str(v) for v in d.values())
    return {ICONS + r + ".svg" for r in refs}


def used_fonts():
    src = (ROOT / "scripts/ui/theme/norse_fonts.gd").read_text(encoding="utf-8")
    return {FONTS + m for m in re.findall(r'DIR \+ "([^"]+\.ttf)"', src)}


def unused(prefix, ext, used):
    out = []
    for p in sorted((ROOT / prefix).rglob("*" + ext)):
        rel = p.relative_to(ROOT).as_posix()
        if rel not in used:
            out.append(rel)
    return out


def generated():
    return unused(ICONS, ".svg", used_icons()) + unused(FONTS, ".ttf", used_fonts())


def rewrite(text):
    lines = text.split("\n")
    out, in_client = [], False
    for ln in lines:
        if ln.startswith("[preset."):
            in_client = False
        if ln.startswith('name="Windows Client"'):
            in_client = True
        if in_client and ln.startswith("exclude_filter="):
            body = ln[len('exclude_filter="'):-1]
            items = [x.strip() for x in body.split(",") if x.strip()]
            items = [x for x in items if not (x.startswith(ICONS) or x.startswith(FONTS))]
            items += generated()
            ln = 'exclude_filter="' + ", ".join(items) + '"'
        out.append(ln)
    return "\n".join(out)


def main():
    text = CFG.read_text(encoding="utf-8")
    new = rewrite(text)
    if "--check" in sys.argv:
        if new != text:
            print("export_presets.cfg desatualizado: rode python3 tools/gen_export_filter.py")
            return 1
        print("export_presets.cfg em dia (%d arquivos de icone/fonte excluidos)" % len(generated()))
        return 0
    CFG.write_text(new, encoding="utf-8", newline="\n")
    print("export_presets.cfg atualizado: %d arquivos de icone/fonte nao usados excluidos do cliente" % len(generated()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
