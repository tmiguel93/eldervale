#!/usr/bin/env bash
# Uso: tools/shots/run_tour.sh hub|wild|ruins   (requer xvfb-run; Godot Linux em .tools/godot-linux)
set -u
cd "$(dirname "$0")/../.."
TOUR="${1:-hub}"
export XDG_DATA_HOME=$PWD/.tools/xdg/data XDG_CONFIG_HOME=$PWD/.tools/xdg/config XDG_CACHE_HOME=$PWD/.tools/xdg/cache
G=$PWD/.tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64
export SHOT_DIR=$PWD/.tools/scratch/shots; mkdir -p "$SHOT_DIR"
PORT=$((24700 + RANDOM % 200))
EXTRA=""
if [ "$TOUR" != "hub" ]; then export ELDERVALE_TEST_MODE=1; EXTRA="--test-speed-mult 4"; fi
timeout 150 "$G" --headless --path . res://scenes/server/server_boot.tscn -- --dev-mode 1 --world greenwood --port $PORT $EXTRA > "$SHOT_DIR/server_$TOUR.log" 2>&1 &
SERVER_PID=$!
sleep 6
LIBGL_ALWAYS_SOFTWARE=1 timeout 140 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/shots/screenshot_tour.gd -- --tour "$TOUR" --host 127.0.0.1 --port $PORT --name TH > "$SHOT_DIR/tour_$TOUR.log" 2>&1
kill $SERVER_PID 2>/dev/null || true
grep -E "\[tour\]" "$SHOT_DIR/tour_$TOUR.log" | tail -20
