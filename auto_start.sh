#!/usr/bin/env bash
set -eo pipefail

repo_dir=$(cd "$(dirname "$0")" && pwd)
ros_distro=${ROS_DISTRO:-jazzy}
ros_setup="/opt/ros/${ros_distro}/setup.bash"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/integration_rob"
mfja_repo_url="https://github.com/aip-primeca-occitanie/mfja_3rd_floor_gz.git"
mfja_branch="INTERNSHIP-ALI-2026"

fail() {
  echo "ERREUR: $*" >&2
  exit 1
}

[[ -f "$ros_setup" ]] || fail "ROS 2 introuvable: $ros_setup"
source "$ros_setup"
command -v colcon >/dev/null || fail "colcon est absent"
command -v ros2 >/dev/null || fail "ros2 est absent"

contains_room315() {
  local install_dir=$1
  find "$install_dir" -path \
    '*/share/ament_index/resource_index/packages/mfja_3rd_floor_bringup' \
    -print -quit 2>/dev/null | grep -q .
}

find_underlay() {
  local candidate
  if [[ -n "${MFJA_UNDERLAY:-}" ]] && [[ -f "$MFJA_UNDERLAY/setup.bash" ]] \
      && contains_room315 "$MFJA_UNDERLAY"; then
    printf '%s\n' "$MFJA_UNDERLAY"
    return
  fi
  candidate="$cache_root/mfja_underlay/install"
  if [[ -f "$candidate/setup.bash" ]] && contains_room315 "$candidate"; then
    printf '%s\n' "$candidate"
    return
  fi
  while IFS= read -r candidate; do
    candidate=${candidate%/setup.bash}
    if contains_room315 "$candidate"; then
      printf '%s\n' "$candidate"
      return
    fi
  done < <(find "$HOME" -type f -path '*/install/setup.bash' \
    -not -path '*/.cache/*' -not -path '*/build/*' -not -path '*/log/*' \
    2>/dev/null)
}

find_mfja_sources() {
  local package_file
  package_file=$(find "$HOME" -type f \
    -path '*/mfja_3rd_floor_bringup/package.xml' \
    -not -path '*/build/*' -not -path '*/install/*' -not -path '*/log/*' \
    -print -quit 2>/dev/null || true)
  if [[ -n "$package_file" ]]; then
    dirname "$(dirname "$package_file")"
  fi
}

underlay=$(find_underlay || true)
if [[ -z "$underlay" ]]; then
  source_root=$(find_mfja_sources || true)
  if [[ -z "$source_root" ]]; then
    source_root="$cache_root/sources/mfja_3rd_floor_gz"
    mkdir -p "$(dirname "$source_root")"
    echo "Sources Room 315 absentes; clonage de $mfja_repo_url..."
    git clone --depth 1 --branch "$mfja_branch" "$mfja_repo_url" "$source_root"
  else
    echo "Sources Room 315 trouvées: $source_root"
  fi

  underlay="$cache_root/mfja_underlay/install"
  echo "Compilation automatique de l'underlay Room 315..."
  mkdir -p "$cache_root/mfja_underlay"
  colcon --log-base "$cache_root/mfja_underlay/log" build \
    --base-paths "$source_root" \
    --build-base "$cache_root/mfja_underlay/build" \
    --install-base "$underlay" \
    --symlink-install
fi

echo "Underlay Room 315: $underlay"
source "$underlay/setup.bash"
ros2 pkg prefix mfja_3rd_floor_bringup >/dev/null \
  || fail "l'underlay trouvé ne contient pas mfja_3rd_floor_bringup"

echo "Installation des dépendances et compilation du projet..."
cd "$repo_dir"
if command -v rosdep >/dev/null; then
  rosdep install --from-paths src --ignore-src -r -y
fi
colcon build --symlink-install
source "$repo_dir/install/setup.bash"

if [[ "${AUTO_SETUP_ONLY:-0}" == "1" ]]; then
  echo "Préparation terminée. Relancez ./auto_start.sh pour ouvrir la simulation."
  exit 0
fi

launch_terminal() {
  local title=$1
  local script=$2
  local command
  printf -v command 'export MFJA_UNDERLAY=%q; cd %q; %q; code=$?; echo; echo "Processus terminé (code $code)"; exec bash' \
    "$underlay" "$repo_dir" "$script"
  if command -v gnome-terminal >/dev/null; then
    gnome-terminal --title="$title" -- bash -lc "$command"
  elif command -v x-terminal-emulator >/dev/null; then
    x-terminal-emulator -T "$title" -e bash -lc "$command"
  else
    fail "aucun terminal graphique compatible n'est installé"
  fi
}

wait_for_message() {
  local topic=$1
  local timeout_seconds=$2
  echo "Attente d'un message réel sur $topic..."
  python3 - "$topic" "$timeout_seconds" <<'PY'
import sys
import time
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import PointCloud2

topic, timeout_text = sys.argv[1:]
rclpy.init()
node = Node('integration_auto_wait')
received = False

def callback(_message):
    global received
    received = True

subscription = node.create_subscription(
    PointCloud2, topic, callback, qos_profile_sensor_data)
deadline = time.monotonic() + float(timeout_text)
while not received and time.monotonic() < deadline:
    rclpy.spin_once(node, timeout_sec=0.2)
node.destroy_subscription(subscription)
node.destroy_node()
rclpy.shutdown()
if not received:
    print(f'ERREUR: aucun message reçu sur {topic}', file=sys.stderr)
    raise SystemExit(1)
print(f'OK: message reçu sur {topic}')
PY
}

wait_for_service() {
  local service=$1
  local timeout_seconds=$2
  local deadline=$((SECONDS + timeout_seconds))
  echo "Attente du service $service..."
  while (( SECONDS < deadline )); do
    if ros2 service list 2>/dev/null | grep -Fxq "$service"; then
      echo "OK: service disponible: $service"
      return
    fi
    sleep 1
  done
  fail "service indisponible après ${timeout_seconds}s: $service"
}

launch_terminal "1 - Gazebo Room 315" "$repo_dir/gazebo.sh"
wait_for_message /room_315/perception/right_rail_rgbd/points 90 \
  || fail "la caméra Gazebo ne publie pas; consulter le terminal 1"

launch_terminal "2 - Perception RGB-D" "$repo_dir/perception.sh"
wait_for_message /hc10/collision_cloud 30 \
  || fail "la perception ne publie pas le nuage filtré; consulter le terminal 2"

launch_terminal "3 - MoveIt 2 et RViz" "$repo_dir/moveit_rviz.sh"
wait_for_service /compute_ik 60
wait_for_service /get_planning_scene 60

if [[ "${AUTO_RUN_DEMO:-1}" == "1" ]]; then
  launch_terminal "4 - Démonstration HC10" "$repo_dir/demo.sh"
  echo "Les quatre composants sont lancés."
else
  echo "Gazebo, perception et MoveIt/RViz sont prêts."
  echo "Lancer ./demo.sh manuellement pour démarrer le mouvement."
fi
