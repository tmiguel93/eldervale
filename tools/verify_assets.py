#!/usr/bin/env python3
"""Verificacao estatica de assets (E8.0). Uso: python3 -I tools/verify_assets.py [--json]

Le assets/ASSET_MANIFEST.json, confere existencia, licenca presente, tamanho (<50 MB/arquivo,
total assets/ <=150 MB), e para cada modelo glb/gltf: meshes, skins, animacoes, referencias
externas (.bin/.png) e dimensoes (AABB dos POSITION). Em rigs animados confere o conjunto
minimo idle/walk/run/attack/hit/death. Sai com codigo 1 se houver falha.
"""
import json, os, re, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAN = os.path.join(ROOT, "assets", "ASSET_MANIFEST.json")
REQ = {"idle": r"idle", "walk": r"walk", "run": r"run|gallop|sprint", "attack": r"attack|swing|slice|chop|stab", "hit": r"hit|hurt", "death": r"death|die"}

def load_gltf(path):
    with open(path, "rb") as fh:
        b = fh.read()
    if path.endswith(".glb"):
        if b[:4] != b"glTF":
            raise ValueError("cabecalho glb invalido")
        jl = struct.unpack("<I", b[12:16])[0]
        return json.loads(b[20:20 + jl])
    return json.loads(b.decode("utf-8"))

def aabb(j):
    lo = [1e9] * 3; hi = [-1e9] * 3
    for m in j.get("meshes", []):
        for p in m.get("primitives", []):
            ai = p.get("attributes", {}).get("POSITION")
            if ai is None: continue
            a = j["accessors"][ai]
            if "min" in a and "max" in a:
                for i in range(3):
                    lo[i] = min(lo[i], a["min"][i]); hi[i] = max(hi[i], a["max"][i])
    return None if lo[0] > hi[0] else [round(hi[i] - lo[i], 2) for i in range(3)]

def main():
    man = json.load(open(MAN, encoding="utf-8"))
    errs, warns, models, rigs = [], [], 0, {}
    total = 0
    for aid, a in man["assets"].items():
        full = os.path.join(ROOT, a["path"])
        if not os.path.isfile(full):
            errs.append(f"{aid}: arquivo ausente {a['path']}"); continue
        sz = os.path.getsize(full)
        if sz > 50 * 1024 * 1024: errs.append(f"{aid}: >50MB")
        if a["license"] not in ("CC0-1.0", "MIT", "Apache-2.0", "OFL-1.1", "CC-BY-3.0", "CC-BY-4.0"):
            errs.append(f"{aid}: licenca nao aceita {a['license']}")
        if a["category"] != "model": continue
        models += 1
        try:
            j = load_gltf(full)
        except Exception as e:
            errs.append(f"{aid}: falha ao ler ({e})"); continue
        d = os.path.dirname(full)
        for ref in [x.get("uri") for x in j.get("buffers", []) + j.get("images", []) if x.get("uri") and not x["uri"].startswith("data:")]:
            if not os.path.isfile(os.path.join(d, ref)): errs.append(f"{aid}: referencia ausente {ref}")
        anims = [x.get("name", "") for x in j.get("animations", [])]
        dims = aabb(j)
        if dims and max(dims) > 100: warns.append(f"{aid}: dimensao grande {dims}")
        if "animated" in a["tags"]:
            if not anims: errs.append(f"{aid}: marcado animated sem animacoes")
            miss = [k for k, rx in REQ.items() if not any(re.search(rx, n, re.I) for n in anims)]
            rigs[aid] = {"anims": len(anims), "skins": len(j.get("skins", [])), "dims": dims, "missing_core": miss, "size_kb": sz // 1024}
            if miss: warns.append(f"{aid}: faltam animacoes-base {miss}")
    for dp, _, fs in os.walk(os.path.join(ROOT, "assets")):
        for f in fs: total += os.path.getsize(os.path.join(dp, f))
    if total > 150 * 1024 * 1024: errs.append("assets/ >150MB")
    res = {"models": models, "entries": len(man["assets"]), "counts": man["counts"], "total_mb": round(total / 1048576, 1), "rigs": rigs, "errors": errs, "warnings": warns}
    if "--json" in sys.argv: print(json.dumps(res, indent=1))
    else:
        print(f"entradas={res['entries']} modelos={models} total_mb={res['total_mb']} contagens={man['counts']}")
        for k, v in rigs.items(): print(f"  rig {k}: anims={v['anims']} skins={v['skins']} dims={v['dims']} faltando={v['missing_core']}")
        for w in warns: print("WARN", w)
        for e in errs: print("ERRO", e)
        print("RESULTADO:", "FALHA" if errs else "OK", f"({len(errs)} erros, {len(warns)} avisos)")
    sys.exit(1 if errs else 0)

main()
