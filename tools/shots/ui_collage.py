#!/usr/bin/env python3
"""E8.4 - monta as colagens de evidencia da UI (2x2 / antes-depois) a partir de .tools/scratch/shots. Uso: python3 tools/shots/ui_collage.py"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / ".tools" / "scratch" / "shots"
OUT = ROOT / "docs" / "img"
W, H = 640, 360


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


def cell(name, label):
    im = Image.open(SH / f"{name}.png").convert("RGB").resize((W, H), Image.LANCZOS)
    d = ImageDraw.Draw(im, "RGBA")
    f = font(14)
    tw = d.textlength(label, font=f)
    d.rectangle((0, 0, tw + 16, 24), fill=(0, 0, 0, 170))
    d.text((8, 4), label, font=f, fill=(255, 235, 170, 255))
    return im


def grid(items, cols, out):
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * W + (cols + 1) * 4, rows * H + (rows + 1) * 4), (12, 9, 7))
    for i, (n, lbl) in enumerate(items):
        sheet.paste(cell(n, lbl), (4 + (i % cols) * (W + 4), 4 + (i // cols) * (H + 4)))
    sheet.save(OUT / out, optimize=True)
    print("ok", out, sheet.size)


def main():
    grid([("ui_alpha_01_longe_sem_barra", "cliente real: longe do Alfa (sem barra) + banner da zona"),
          ("ui_alpha_02_combate1", "cliente real: combate com o Alfa (barra do chefe)"),
          ("ui_alpha_03_afastou_sem_barra", "cliente real: afastou-se / respawn (barra SOME)"),
          ("ui_hud", "HUD: chefe, grupo, minimapa, hotbar com recarga, avisos")], 2, "e8_4_ui_hud_boss.png")
    grid([("ui_inventory", "Inventario: raridades (comum a mitico) + equipamento"),
          ("ui_talents", "Talentos"), ("ui_quests", "Diario de quests"), ("ui_dialogue", "Dialogo com NPC")], 2, "e8_4_ui_panels_a.png")
    grid([("ui_map", "Mapa"), ("ui_craft", "Bancada"), ("ui_options", "Opcoes (qualidade/escala/movimento/volume)"), ("ui_credits", "Creditos (CC BY / CC0 / OFL)")], 2, "e8_4_ui_panels_b.png")
    grid([("ui_login", "Tela de login / personagens"), ("ui_menu", "Menu (Esc)"),
          ("ui_hub_08_creditos", "cliente real: Creditos (F1)"), ("ui_hub_07_opcoes", "cliente real: Opcoes (O)")], 2, "e8_4_ui_login_menu.png")
    grid([("hub_04_dialogo", "ANTES: dialogo"), ("ui_dialogue", "DEPOIS: dialogo (bancada de UI)"),
          ("hub_06_inventario", "ANTES: inventario"), ("ui_hub_04_inventario", "DEPOIS: inventario"),
          ("hub_07_talentos", "ANTES: talentos"), ("ui_hub_05_talentos", "DEPOIS: talentos"),
          ("hub_05_quests", "ANTES: quests"), ("ui_hub_03_quests", "DEPOIS: quests")], 2, "e8_4_ui_antes_depois.png")


if __name__ == "__main__":
    sys.exit(main())
