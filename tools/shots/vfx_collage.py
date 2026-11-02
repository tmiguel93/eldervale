#!/usr/bin/env python3
"""E8.3: monta colagens (N quadros lado a lado, com o instante) a partir dos recortes do vfx_lab.
Uso: tools/shots/vfx_collage.py saida.png nome1 [nome2 ...] -- cada nome vira uma linha (arquivos <nome>_f0.png, _f1.png...)."""
import sys, glob, os
from PIL import Image, ImageDraw
out, names = sys.argv[1], sys.argv[2:]
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".tools", "scratch", "shots")
rows = []
for n in names:
    fs = sorted(glob.glob(os.path.join(d, n + "_f*.png")), key=lambda p: int(p.rsplit("_f", 1)[1][:-4]))
    rows.append((n, [Image.open(f).convert("RGB") for f in fs]))
tw = 420
cells = [[im.resize((tw, int(im.height * tw / im.width))) for im in r[1]] for r in rows]
cols = max(len(c) for c in cells)
th = cells[0][0].height
sheet = Image.new("RGB", (cols * tw, len(cells) * th), (10, 10, 14))
dr = ImageDraw.Draw(sheet)
for y, (n, _) in enumerate(rows):
    for x, im in enumerate(cells[y]):
        sheet.paste(im, (x * tw, y * th))
        dr.rectangle((x * tw, y * th, x * tw + 6 * len(n) + 30, y * th + 14), fill=(0, 0, 0))
        dr.text((x * tw + 3, y * th + 2), f"{n} #{x}", fill=(255, 255, 255))
sheet.save(out)
print(out, sheet.size)
