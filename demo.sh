#!/usr/bin/env bash
set -e
script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/setup_env.sh"
cd "$INTEGRATION_ROB_ROOT"

# Le motif couvre l'exécutable installé (lib/hc10_pick_place_demo/pick_place)
# comme la source lancée directement ci-dessous.
pkill -TERM -f 'hc10_pick_place_demo/(scripts/)?pick_place( |$)' 2>/dev/null || true
sleep 1
pkill -KILL -f 'hc10_pick_place_demo/(scripts/)?pick_place( |$)' 2>/dev/null || true
exec python3 "$INTEGRATION_ROB_ROOT/src/hc10_pick_place_demo/scripts/pick_place"
