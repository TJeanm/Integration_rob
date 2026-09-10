#!/usr/bin/env bash
# Shared, relocatable ROS environment setup for all launch scripts.

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ros_distro=${ROS_DISTRO:-jazzy}
ros_setup="/opt/ros/${ros_distro}/setup.bash"

if [[ ! -f "$ros_setup" ]]; then
  echo "ROS 2 introuvable: $ros_setup" >&2
  return 1
fi
source "$ros_setup"

# The Room 315 packages live in an external workspace. Users may provide its
# install directory explicitly. Otherwise, accept an already sourced package
# or common workspaces located next to this repository.
if [[ -n "${MFJA_UNDERLAY:-}" ]]; then
  if [[ ! -f "$MFJA_UNDERLAY/setup.bash" ]]; then
    echo "MFJA_UNDERLAY invalide: $MFJA_UNDERLAY/setup.bash absent" >&2
    return 1
  fi
  source "$MFJA_UNDERLAY/setup.bash"
elif ! ros2 pkg prefix mfja_3rd_floor_bringup >/dev/null 2>&1; then
  for candidate in \
    "$repo_dir/../hc10_ros2_ws/install" \
    "$repo_dir/../mfja_3rd_floor_gz/install"
  do
    if [[ -f "$candidate/setup.bash" ]]; then
      source "$candidate/setup.bash"
      if ros2 pkg prefix mfja_3rd_floor_bringup >/dev/null 2>&1; then
        break
      fi
    fi
  done
fi

if [[ ! -f "$repo_dir/install/setup.bash" ]]; then
  echo "Workspace non compilé. Exécuter: colcon build --symlink-install" >&2
  return 1
fi
source "$repo_dir/install/setup.bash"

export INTEGRATION_ROB_ROOT="$repo_dir"
