#!/usr/bin/env bash

set -e

WS="$HOME/mfja_3rd_floor_ros2_ws"

if [ "$#" -ne 6 ]; then
    echo
    echo "Usage:"
    echo "  ./demo.sh j1 j2 j3 j4 j5 j6"
    echo
    echo "Example:"
    echo "  ./demo.sh 0.3 -0.25 0.2 0.0 0.15 0.0"
    echo
    exit 1
fi

cd "$WS"

source /opt/ros/jazzy/setup.bash
source install/setup.bash

cleanup() {
    echo
    echo "Stopping demo..."

    kill "$MOVEIT_PID" 2>/dev/null || true
    kill "$RELAY_PID" 2>/dev/null || true
    kill "$ADAPTER_PID" 2>/dev/null || true
    kill "$ROOM315_PID" 2>/dev/null || true

    pkill -f "gz sim" 2>/dev/null || true

    echo "Done."
}

trap cleanup EXIT INT TERM


echo "========================================"
echo " HC10 MoveIt2 demo"
echo "========================================"
echo
echo "Goal:"
echo "  j1 = $1"
echo "  j2 = $2"
echo "  j3 = $3"
echo "  j4 = $4"
echo "  j5 = $5"
echo "  j6 = $6"
echo


echo "[1/5] Starting Room315 + HC10..."

ros2 launch mfja_3rd_floor_bringup room_315_only.launch.py \
    robots:=hc10 \
    gui:=true \
    start_paused:=false \
    > /tmp/room315.log 2>&1 &

ROOM315_PID=$!

sleep 8


echo "[2/5] Starting HC10 adapter..."

ros2 run hc10_mfja_control_adapter hc10_control_adapter \
    > /tmp/hc10_adapter.log 2>&1 &

ADAPTER_PID=$!

sleep 2


echo "[3/5] Starting joint state relay..."

ros2 run topic_tools relay \
    /yaskawa_hc10_1/joint_states \
    /joint_states \
    > /tmp/joint_relay.log 2>&1 &

RELAY_PID=$!

sleep 2


echo "[4/5] Starting MoveIt..."

ros2 launch hc10_moveit_config moveit.launch.py \
    use_rviz:=false \
    > /tmp/moveit.log 2>&1 &

MOVEIT_PID=$!

sleep 5


echo "[5/5] Sending goal..."

ros2 run hc10_moveit_api joint_goal \
    "$1" "$2" "$3" "$4" "$5" "$6"


echo
echo "========================================"
echo " Motion finished"
echo "========================================"
echo
echo "Simulation remains running."
echo "Press CTRL+C to stop everything."
echo

wait
