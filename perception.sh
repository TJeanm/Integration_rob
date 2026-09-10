#!/usr/bin/env bash
set -e
script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/setup_env.sh"
cd "$INTEGRATION_ROB_ROOT"

# Le motif couvre l'exécutable installé (lib/hc10_pick_place_demo/perception)
# comme la source lancée directement (src/.../scripts/perception).
pkill -TERM -f 'hc10_pick_place_demo/(scripts/)?perception( |$)' 2>/dev/null || true
sleep 1
pkill -KILL -f 'hc10_pick_place_demo/(scripts/)?perception( |$)' 2>/dev/null || true
exec ros2 run hc10_pick_place_demo perception
