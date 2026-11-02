#!/usr/bin/env bash
# E8.2: bancada de cenario sem servidor (ver scenery_lab.gd). Uso: tools/shots/run_lab.sh --shot nome,zona,x,z,zoom [--shot ...] [--quality high] [--mood k=v;k=v]
# Prints em .tools/scratch/shots/<nome>.png. Requer xvfb-run e o Godot Linux em .tools/godot-linux.
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=$PWD/.tools/xdg/data XDG_CONFIG_HOME=$PWD/.tools/xdg/config XDG_CACHE_HOME=$PWD/.tools/xdg/cache
G=$PWD/.tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64
export SHOT_DIR=$PWD/.tools/scratch/shots; mkdir -p "$SHOT_DIR"
LIBGL_ALWAYS_SOFTWARE=1 timeout 170 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/scenery_lab.gd -- "$@" > "$SHOT_DIR/lab.log" 2>&1
grep -E "\[lab\]|SCRIPT ERROR|^ERROR|Parse Error" "$SHOT_DIR/lab.log" | head -40
