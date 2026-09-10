#!/usr/bin/env bash
set -e

cd ~/mfja_3rd_floor_ros2_ws

source /opt/ros/jazzy/setup.bash
source install/setup.bash

echo "[1/5] Starting Room315 + HC10..."
ros2 launch mfja_3rd_floor_bringup room_315_only.launch.py \
  robots:=hc10 \
  gui:=true \
  start_paused:=false \
  > /tmp/room315.log 2>&1 &

ROOM315_PID=$!

sleep 8

echo "[2/5] Starting HC10 control adapter..."
ros2 run hc10_mfja_control_adapter hc10_control_adapter \
  > /tmp/hc10_adapter.log 2>&1 &

ADAPTER_PID=$!

sleep 2

echo "[3/5] Starting joint_states relay..."
ros2 run topic_tools relay \
  /yaskawa_hc10_1/joint_states \
  /joint_states \
  > /tmp/joint_relay.log 2>&1 &

RELAY_PID=$!

sleep 2

echo "[4/5] Starting MoveIt headless..."
ros2 launch hc10_moveit_config moveit.launch.py \
  use_rviz:=false \
  > /tmp/moveit.log 2>&1 &

MOVEIT_PID=$!

sleep 5

echo "[5/5] Sending Python MoveIt goal..."
ros2 run hc10_moveit_api joint_goal

echo
echo "Demo finished."
echo "Press Ctrl+C to stop everything."

cleanup() {
    echo
    echo "Stopping processes..."

    kill "$MOVEIT_PID" 2>/dev/null || true
    kill "$RELAY_PID" 2>/dev/null || true
    kill "$ADAPTER_PID" 2>/dev/null || true
    kill "$ROOM315_PID" 2>/dev/null || true

    pkill -f "gz sim" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

wait
