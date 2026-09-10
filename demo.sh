#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
source /opt/ros/jazzy/setup.bash
source /home/mfja/Desktop/hc10_ros2_ws/install/setup.bash
source install/setup.bash

pkill -TERM -f '/hc10_pick_place_demo/pick_place( |$)' 2>/dev/null || true
sleep 1
pkill -KILL -f '/hc10_pick_place_demo/pick_place( |$)' 2>/dev/null || true
exec python3 "$PWD/src/hc10_pick_place_demo/scripts/pick_place"
