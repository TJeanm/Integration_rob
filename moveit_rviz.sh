#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
source /opt/ros/jazzy/setup.bash
source /home/mfja/Desktop/hc10_ros2_ws/install/setup.bash
source install/setup.bash

# A stale move_group makes /compute_ik nondeterministic because two servers
# answer the same request. Always start a single MoveIt instance.
pkill -TERM -f '/moveit_ros_move_group/move_group' 2>/dev/null || true
pkill -TERM -f 'ros2 launch .*moveit.*[.]launch[.]py' 2>/dev/null || true
pkill -TERM -f 'hc10_mfja_control_adapter' 2>/dev/null || true
pkill -TERM -f 'rviz2.*hc10_moveit_rviz' 2>/dev/null || true
sleep 1
pkill -KILL -f '/moveit_ros_move_group/move_group' 2>/dev/null || true
pkill -KILL -f 'ros2 launch .*moveit.*[.]launch[.]py' 2>/dev/null || true
pkill -KILL -f 'hc10_mfja_control_adapter' 2>/dev/null || true
pkill -KILL -f 'rviz2.*hc10_moveit_rviz' 2>/dev/null || true

ros2 run hc10_mfja_control_adapter hc10_control_adapter &
adapter_pid=$!
trap 'kill -INT "$adapter_pid" 2>/dev/null || true' EXIT INT TERM
ros2 launch hc10_moveit_config moveit.launch.py
