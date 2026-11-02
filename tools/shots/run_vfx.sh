#!/usr/bin/env bash
# E8.3: bancada de efeitos (ver vfx_lab.gd). Uso: tools/shots/run_vfx.sh --shot nome,modo,t1;t2;t3 [--shot ...] [--zone z] [--at x,z] [--quality high]
# Recortes em .tools/scratch/shots/<nome>_f<i>.png. Requer xvfb-run e o Godot Linux em .tools/godot-linux. Colagens: tools/shots/vfx_collage.py
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=$PWD/.tools/xdg/data XDG_CONFIG_HOME=$PWD/.tools/xdg/config XDG_CACHE_HOME=$PWD/.tools/xdg/cache
G=$PWD/.tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64
export SHOT_DIR=$PWD/.tools/scratch/shots; mkdir -p "$SHOT_DIR"
LIBGL_ALWAYS_SOFTWARE=1 timeout 170 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/vfx_lab.gd -- "$@" > "$SHOT_DIR/vfx_lab.log" 2>&1
grep -E "\[vfx\]|SCRIPT ERROR|ERROR|Parse Error|SHADER" "$SHOT_DIR/vfx_lab.log" | head -40
