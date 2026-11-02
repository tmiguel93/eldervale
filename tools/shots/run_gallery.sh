#!/usr/bin/env bash
# E8.1: galeria de modelos (sem servidor). Uso: tools/shots/run_gallery.sh [estados,separados,por,virgula] [enemy,class,npc]
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=$PWD/.tools/xdg/data XDG_CONFIG_HOME=$PWD/.tools/xdg/config XDG_CACHE_HOME=$PWD/.tools/xdg/cache
G=$PWD/.tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64
export SHOT_DIR=$PWD/.tools/scratch/shots; mkdir -p "$SHOT_DIR"
LIBGL_ALWAYS_SOFTWARE=1 timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/model_gallery.gd -- --states "${1:-idle,move,attack,hit,death,spawn}" --only "${2:-enemy,class,npc}" --matrix "${3:-}" > "$SHOT_DIR/gallery.log" 2>&1
grep -E "\[gallery\]|ERROR|SCRIPT" "$SHOT_DIR/gallery.log" | head -40
