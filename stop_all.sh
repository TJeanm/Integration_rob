#!/usr/bin/env bash
# Stop every process created by this project's four launch scripts, including
# ROS children orphaned after a terminal or ros2 launch crash.
set -e

patterns=(
  'ros2 launch mfja_3rd_floor_bringup room_315_only[.]launch[.]py'
  'gz sim -r -s /tmp/room_315_only_.*[.]world'
  'gz sim -g .*room315_runtime_safe[.]gui[.]config'
  '__node:=room315_perception_camera_bridge'
  '__node:=hc10_right_cloud_bridge'
  '__node:=room315_world_service_bridge'
  '__node:=room315_rail_safety_supervisor'
  '__node:=conveyor_loop_mode_controller'
  '__node:=clock_bridge'
  '__node:=yaskawa_hc10_1_bridge'
  'yaskawa_hc10_1[.]robot_state_publisher'
  '/moveit_ros_move_group/move_group'
  'rviz2.*hc10_moveit_rviz'
  'hc10_mfja_control_adapter'
  'hc10_pick_place_demo/(scripts/)?perception( |$)'
  'hc10_pick_place_demo/(scripts/)?pick_place( |$)'
)

for signal in TERM KILL; do
  for pattern in "${patterns[@]}"; do
    pkill "-${signal}" -f "$pattern" 2>/dev/null || true
  done
  [[ "$signal" == TERM ]] && sleep 2
done

echo "Anciennes instances Gazebo, perception, MoveIt et RViz arrêtées."
