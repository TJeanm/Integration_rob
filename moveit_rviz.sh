#!/usr/bin/env bash
set -e
script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/setup_env.sh"
cd "$INTEGRATION_ROB_ROOT"

# A stale move_group makes /compute_ik nondeterministic because two servers
# answer the same request. Always start a single MoveIt instance.
stale_patterns=(
  '/moveit_ros_move_group/move_group'
  'ros2 launch .*moveit.*[.]launch[.]py'
  'hc10_mfja_control_adapter'
  'rviz2.*hc10_moveit_rviz'
)
for signal in TERM KILL; do
  for pattern in "${stale_patterns[@]}"; do
    pkill "-${signal}" -f "$pattern" 2>/dev/null || true
  done
  if [[ "$signal" == TERM ]]; then
    sleep 1
  fi
done

# use_sim_time doit valoir true comme dans bringup.launch.py: sans cela
# l'adaptateur et MoveIt ne partagent pas la même horloge.
ros2 run hc10_mfja_control_adapter hc10_control_adapter \
  --ros-args -p use_sim_time:=true &
adapter_pid=$!
trap 'kill -INT "$adapter_pid" 2>/dev/null || true' EXIT INT TERM
ros2 launch hc10_moveit_config moveit.launch.py
