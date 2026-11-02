#!/usr/bin/env bash
# Uso: tools/shots/run_ui.sh [cenas separadas por virgula] [prefixo]   (E8.4; requer xvfb-run; sem servidor)
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=$PWD/.tools/xdg/data XDG_CONFIG_HOME=$PWD/.tools/xdg/config XDG_CACHE_HOME=$PWD/.tools/xdg/cache
G=$PWD/.tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64
export SHOT_DIR=$PWD/.tools/scratch/shots; mkdir -p "$SHOT_DIR"
SC="${1:-hud,inventory,talents,quests,dialogue,map,options,credits,menu,boss,craft,toasts,login}"
LIBGL_ALWAYS_SOFTWARE=1 timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/ui_lab.gd -- --scenes "$SC" --prefix "${2:-ui_}" > "$SHOT_DIR/ui_lab.log" 2>&1
grep -E "\[ui\]|SCRIPT ERROR|ERROR|Parse" "$SHOT_DIR/ui_lab.log" | head -40
