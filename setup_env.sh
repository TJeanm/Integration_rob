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
# install directory explicitly. Otherwise, accept an already sourced package,
# the underlay compiled par auto_start.sh, ou les workspaces habituels situés
# à côté de ce dépôt.
if [[ -n "${MFJA_UNDERLAY:-}" ]]; then
  if [[ ! -f "$MFJA_UNDERLAY/setup.bash" ]]; then
    echo "MFJA_UNDERLAY invalide: $MFJA_UNDERLAY/setup.bash absent" >&2
    return 1
  fi
  source "$MFJA_UNDERLAY/setup.bash"
elif ! ros2 pkg prefix mfja_3rd_floor_bringup >/dev/null 2>&1; then
  for candidate in \
    "$repo_dir/.mfja_underlay" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/integration_rob/mfja_underlay/install" \
    "$repo_dir/underlay/install" \
    "$repo_dir/../mfja_3rd_floor_gz/install" \
    "$repo_dir/../hc10_ros2_ws/install"
  do
    if [[ -f "$candidate/setup.bash" ]]; then
      source "$candidate/setup.bash"
      if ros2 pkg prefix mfja_3rd_floor_bringup >/dev/null 2>&1; then
        export MFJA_UNDERLAY="$candidate"
        break
      fi
    fi
  done
fi

# Configuration des chemins de ressources Gazebo pour garantir la résolution des modèles
if ros2 pkg prefix mfja_3rd_floor_description >/dev/null 2>&1; then
  mfja_models="$(ros2 pkg prefix --share mfja_3rd_floor_description)/models"
  export GZ_SIM_RESOURCE_PATH="${GZ_SIM_RESOURCE_PATH:+${GZ_SIM_RESOURCE_PATH}:}$mfja_models"
  export GZ_SIM_MODEL_PATH="${GZ_SIM_MODEL_PATH:+${GZ_SIM_MODEL_PATH}:}$mfja_models"
fi

if [[ ! -f "$repo_dir/install/setup.bash" ]]; then
  echo "Workspace non compilé. Exécuter depuis $repo_dir:" >&2
  echo "  ./auto_start.sh          # installation et compilation automatiques" >&2
  echo "  colcon build --symlink-install   # compilation seule" >&2
  return 1
fi
source "$repo_dir/install/setup.bash"

if ros2 pkg prefix hc10_pick_place_demo >/dev/null 2>&1; then
  demo_models="$(ros2 pkg prefix --share hc10_pick_place_demo)/models"
  export GZ_SIM_RESOURCE_PATH="${GZ_SIM_RESOURCE_PATH:+${GZ_SIM_RESOURCE_PATH}:}$demo_models"
  export GZ_SIM_MODEL_PATH="${GZ_SIM_MODEL_PATH:+${GZ_SIM_MODEL_PATH}:}$demo_models"
fi

export INTEGRATION_ROB_ROOT="$repo_dir"
