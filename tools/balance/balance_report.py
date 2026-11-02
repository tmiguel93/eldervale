#!/usr/bin/env python3
"""E6.5: renderiza em Markdown as tabelas medidas pelo simulador (docs/balance/e6_before.json / e6_after.json).
Uso: python3 tools/balance/balance_report.py [before.json] [after.json] > tabelas.md
Somente leitura dos JSONs; nenhum numero e escrito a mao."""
import json
import math
import sys

BEFORE = sys.argv[1] if len(sys.argv) > 1 else "docs/balance/e6_before.json"
AFTER = sys.argv[2] if len(sys.argv) > 2 else "docs/balance/e6_after.json"
b = json.load(open(BEFORE))
a = json.load(open(AFTER))
CLASSES = ["warrior", "mage", "ranger"]
BOSS = "blight_treant"
STD = str(int(a["meta"]["standard_level"]))


def f(x, d=1):
    return "-" if x is None else ("%.*f" % (d, x))


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out) + "\n"


def tier(res, cid, lv, build, t):
    return res["classes"][cid][lv]["builds"][build]["tiers"][t]


def boss_dps(x): return x["dps"][BOSS]["mean"]
def boss_ttk(x): return x["ttk"][BOSS]["mean"]
def boss_surv(x): return x["survive_s"][BOSS]["mean"]
def power(x): return math.sqrt(boss_dps(x) * boss_surv(x))


print("### R1. Criterios: antes x depois\n")
cb = {c["id"]: c for c in b["criteria"]}
ca = {c["id"]: c for c in a["criteria"]}
print("Antes: %d criterios, %d falhas. Depois: %d criterios, %d falhas.\n" % (
    len(cb), sum(1 for c in cb.values() if not c["pass"]), len(ca), sum(1 for c in ca.values() if not c["pass"])))
rows = []
for cid, c in cb.items():
    if not c["pass"]:
        rows.append(["`%s`" % cid, "FALHA: " + c["detail"], ("OK: " if ca[cid]["pass"] else "FALHA: ") + ca[cid]["detail"]])
print(table(["Criterio", "Antes (dados originais)", "Depois (dados ajustados)"], rows))
still = [cid for cid, c in ca.items() if not c["pass"]]
print("Criterios que falham depois: %s.\n" % (", ".join(still) if still else "nenhum"))

print("### R2. Paridade de DPS entre classes (nivel %s, sem talentos, equipamento Comum)\n" % STD)
rows = []
for cid in CLASSES:
    xb = tier(b, cid, STD, "none", "common")
    xa = tier(a, cid, STD, "none", "common")
    rows.append([cid, f(boss_dps(xb)), f(boss_dps(xa)), f(xb["dps"]["pack"]["mean"]), f(xa["dps"]["pack"]["mean"]),
                 f(boss_ttk(xb)), f(boss_ttk(xa)), f(xb["boss_ttk_4p"]), f(xa["boss_ttk_4p"])])
print(table(["Classe", "DPS chefe antes", "DPS chefe depois", "DPS bando antes", "DPS bando depois", "TTK chefe 1p antes (s)", "TTK chefe 1p depois (s)", "TTK chefe 4p antes (s)", "TTK chefe 4p depois (s)"], rows))
vals = [boss_dps(tier(a, c, STD, "none", "common")) for c in CLASSES]
med = sorted(vals)[1]
print("Desvio do DPS de chefe (depois) em relacao a mediana: " + ", ".join("%s %+.1f%%" % (c, (v / med - 1) * 100) for c, v in zip(CLASSES, vals)) + ".\n")

print("### R3. Sobrevivencia e duelo (nivel %s, Comum, sem talentos)\n" % STD)
rows = []
for cid in CLASSES:
    xa = tier(a, cid, STD, "none", "common")
    st = xa["stats"]
    rows.append([cid, f(st["max_health"], 0), f(st["attack_power"], 1), f(st["defense"], 1), f(boss_surv(xa)), f(xa["duel_ratio"][BOSS]["mean"], 2), f(xa["ttk"]["melee_grunt"]["mean"], 2), f(xa["ttk"]["pack"]["mean"])])
print(table(["Classe", "Vida", "Ataque", "Defesa", "Sobrevive ao chefe (s)", "Razao de duelo vs chefe", "TTK grunt (s)", "TTK bando (s)"], rows))

for lv in ["10", "20"]:
    print("### R4. Builds de talento, nivel %s (equipamento Comum, 1 jogador)\n" % lv)
    rows = []
    for cid in CLASSES:
        builds = a["classes"][cid][lv]["builds"]
        for bid, bd in builds.items():
            x = bd["tiers"]["common"]
            rows.append([cid, bid, "%d/%d" % (bd["points_spent"], bd["points_available"]), f(boss_dps(x)), f(x["dps"]["pack"]["mean"]), f(boss_ttk(x)), f(boss_surv(x)), f(power(x))])
    print(table(["Classe", "Build", "Pontos", "DPS chefe", "DPS bando", "TTK chefe (s)", "Sobrevive (s)", "Indice de poder"], rows))

print("### R5. Escada de equipamento (nivel %s, build `none`, DPS contra o chefe / indice de poder)\n" % STD)
tiers = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "fixed_best"]
rows = []
for cid in CLASSES:
    row = [cid]
    for t in tiers:
        x = tier(a, cid, STD, "none", t)
        row.append("%s / %s" % (f(boss_dps(x)), f(power(x))))
    rows.append(row)
print(table(["Classe"] + tiers, rows))

print("### R6. Unicos: ganho sobre o mesmo personagem sem o unico (depois do ajuste)\n")
rows = []
mx = []
for cid, builds in a["uniques"].items():
    for bid, us in builds.items():
        for uid, v in us.items():
            rows.append([cid, bid, uid.replace("unique_", ""), f(v["dps_gain_pct_hp100"]), f(v["dps_gain_pct_hp30"]), f(v["pack_dps_gain_pct"]), f(v["survive_gain_pct_boss"]), f(v["max_health_delta"], 0), f(v["defense_delta"], 1)])
print(table(["Classe", "Build", "Unico", "DPS% (vida 100%)", "DPS% (vida 30%)", "DPS% bando", "Sobrevive% chefe", "dVida", "dDefesa"], rows))
print("Antes do ajuste (mesma tabela, so os maiores ganhos de DPS a vida 30%):\n")
rows = []
for cid, builds in b["uniques"].items():
    for bid, us in builds.items():
        for uid, v in us.items():
            rows.append((v["dps_gain_pct_hp30"], [cid, bid, uid.replace("unique_", ""), f(v["dps_gain_pct_hp100"]), f(v["dps_gain_pct_hp30"]), f(v["pack_dps_gain_pct"])]))
rows.sort(key=lambda r: -r[0])
print(table(["Classe", "Build", "Unico", "DPS% (100%)", "DPS% (30%)", "DPS% bando"], [r[1] for r in rows[:6]]))

print("### R7. Talentos: ganho isolado por ponto (nivel 20, DPS contra o chefe), depois do ajuste\n")
rows = []
for cid in CLASSES:
    nodes = a["talents"][cid]["nodes"]
    ranked = sorted(nodes.items(), key=lambda kv: -kv[1]["gain_per_point_pct"])
    pos = [kv for kv in ranked if kv[1]["gain_per_point_pct"] > 0]
    zero = [k for k, v in nodes.items() if v["gain_per_point_pct"] == 0]
    med = sorted(v["gain_per_point_pct"] for _, v in pos)[len(pos) // 2] if pos else 0
    top = ranked[0]
    rows.append([cid, len(nodes), len(pos), len(zero), f(med, 2), "%s (%s)" % (top[0], f(top[1]["gain_per_point_pct"], 2)), f(top[1]["gain_per_point_pct"] / med if med else 0, 1)])
print(table(["Classe", "Nos", "Com efeito de DPS", "Sem efeito de DPS (utilidade)", "Mediana %/ponto", "Maior %/ponto (no)", "Maior / mediana"], rows))

print("### R8. Curva de XP e fontes\n")
lv = a["xp"]["levels"]
rows = [[x["level"], x["to_next"], x["cumulative_at_next"], f(x["ratio"], 2)] for x in lv if x["level"] in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 30, 40, 49)]
print(table(["Nivel", "XP p/ proximo", "XP acumulado", "Razao vs nivel anterior"], rows))
x = a["xp"]
print(table(["Fonte", "XP total", "Participacao"], [["Abates (um de cada, chefe incl.)", x["kills_xp"], "%.0f%%" % (x["share"]["kills"] * 100)], ["Quests (%d)" % x["quest_count"], x["quests_xp"], "%.0f%%" % (x["share"]["quests"] * 100)], ["Exploracao (%d pontos)" % x["poi_count"], x["poi_xp"], "%.0f%%" % (x["share"]["exploration"] * 100)], ["Total", x["total_xp"], "100%"]]))
print("Nivel final: tudo = %d; so abates = %d; so quests = %d.\n" % (x["final_level_all"], x["final_level_kills_only"], x["final_level_quests_only"]))

print("### R9. Drops por raridade (Monte Carlo com o LootManager real, %d abates por tipo, semente fixa; analitico entre parenteses)\n" % a["meta"]["sim"]["loot_kills"])
def lootrows(res, only=None):
    rows = []
    for en, v in res["loot"]["by_enemy"].items():
        if only and v["tier"] not in only:
            continue
        k = v["kills"]
        rc = v["rarity_counts"]
        ar = v["analytic"]["rarity_per_kill"]
        rows.append([en, v["tier"], f(v["gear_per_kill"], 3)] + ["%.4f (%.4f)" % (rc[r] / k, ar[r]) for r in ["rare", "epic", "legendary", "mythic"]] + [f(v["analytic"]["unique_per_kill"], 3)])
    return rows
head = ["Inimigo", "Tier", "Equip./abate", "Raro/abate", "Epico/abate", "Lendario/abate", "Mitico/abate", "Unico/abate (analitico)"]
print("Depois do ajuste:\n")
print(table(head, lootrows(a)))
print("Antes do ajuste:\n")
print(table(head, lootrows(b)))
print("Abates da melhor fonte por unico (analitico):\n")
rows = []
for uid in a["loot"]["uniques_obtain"].keys():
    rows.append([uid, json.dumps(b["loot"]["uniques_obtain"][uid]), json.dumps(a["loot"]["uniques_obtain"][uid])])
print(table(["Unico", "Antes", "Depois"], rows))

print("### R10. Uso de habilidades e pontos de talento (nivel %s, sem talentos / nivel 20 builds de pico)\n" % STD)
rows = []
for cid in CLASSES:
    xa = tier(a, cid, STD, "none", "common")
    for sk, v in xa["skills"].items():
        rows.append([cid, sk, f(v["casts_per_min"]), "%.0f%%" % (v["dmg_share"] * 100)])
print(table(["Classe", "Habilidade", "Usos/min (luta vs chefe)", "Parcela do dano"], rows))
rows = []
for L in ["5", "10", "20"]:
    rows.append([L, a["classes"]["warrior"][L]["builds"]["none"]["points_available"]])
print(table(["Nivel", "Pontos de talento disponiveis"], rows))
