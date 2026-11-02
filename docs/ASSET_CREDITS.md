# Creditos de assets

Todo asset externo deve ser listado aqui com origem, autor, licenca e alteracoes (AGENTS.md, secao 8).
Arte de placeholder deve ser claramente identificada.

**Inventario real (E7.1, verificado em 2026-11-02):** varredura da arvore versionada (excluindo `.tools/`, `build/`, `node_modules/`, `.git/`) por imagens (png/jpg/svg/webp/ico), audio (ogg/wav/mp3), fontes (ttf/otf/woff) e modelos (glb): **nenhum arquivo encontrado**. O jogo usa apenas formas/cores geradas por codigo e a fonte padrao do Godot (parte do motor). `project.godot` nao define icone nem fonte customizada.

| Asset | Origem (URL/fonte) | Autor | Licenca | Alteracoes |
|-------|--------------------|-------|---------|------------|
| Fonte padrao e icone do motor embutidos nos executaveis | Godot Engine 4.7.2 (templates de exportacao) | Godot Engine contributors | MIT (ver licencas de terceiros do Godot) | nenhuma |

Observacoes: o executavel exportado embute o motor Godot; a distribuicao deve incluir os avisos de licenca do Godot (Projeto > Licencas) **[o dono deve incluir o texto na distribuicao]**. Dependencias de codigo do backend: `docs/DEPENDENCIES.md`.
