#!/usr/bin/env bash
set -eo pipefail

repo_dir=$(cd "$(dirname "$0")" && pwd)
ros_distro=${ROS_DISTRO:-jazzy}
ros_setup="/opt/ros/${ros_distro}/setup.bash"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/integration_rob"
log_dir="$repo_dir/.auto_start_logs"
mfja_repo_url="https://github.com/aip-primeca-occitanie/mfja_3rd_floor_gz.git"
mfja_branch="${MFJA_BRANCH:-INTERNSHIP-ALI-2026}"
# Commit Room 315 validé avec ce dépôt. Exporter MFJA_COMMIT= (vide) pour
# suivre la tête de branche au lieu de cette version reproductible.
mfja_commit="${MFJA_COMMIT-2321def0b05afd2c81b33d7220d41321c27f6480}"
# Les recherches sous $HOME sont bornées: un balayage complet du disque peut
# durer plusieurs minutes et sélectionner un workspace sans rapport.
search_depth=${MFJA_SEARCH_DEPTH:-6}
# Un nuage caméra n'est exploitable que s'il contient de vrais points finis.
min_camera_points=${MIN_CAMERA_POINTS:-100}
camera_timeout=${CAMERA_TIMEOUT:-120}
rosdep_usable=0

fail() {
  echo "ERREUR: $*" >&2
  exit 1
}

warn() {
  echo "ATTENTION: $*" >&2
}

[[ -f "$ros_setup" ]] || fail "ROS 2 introuvable: $ros_setup
Installer ROS 2 ${ros_distro}, ou exporter ROS_DISTRO vers une distribution installée."
source "$ros_setup"
command -v colcon >/dev/null \
  || fail "colcon est absent (sudo apt install -y python3-colcon-common-extensions)"
command -v ros2 >/dev/null || fail "ros2 est absent"
command -v git >/dev/null || fail "git est absent (sudo apt install -y git)"

# --------------------------------------------------------------------------
# Dépendances système
# --------------------------------------------------------------------------

ensure_rosdep() {
  if [[ "${AUTO_SKIP_ROSDEP:-0}" == "1" ]]; then
    warn "AUTO_SKIP_ROSDEP=1: installation automatique des dépendances désactivée."
    return
  fi
  if ! command -v rosdep >/dev/null; then
    fail "rosdep est absent. Installer puis initialiser une seule fois:
  sudo apt install -y python3-rosdep && sudo rosdep init && rosdep update
ou relancer avec AUTO_SKIP_ROSDEP=1 si les dépendances sont déjà installées."
  fi
  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    fail "rosdep n'est pas initialisé sur cette machine. Exécuter une seule fois:
  sudo rosdep init && rosdep update
puis relancer ./auto_start.sh (ou AUTO_SKIP_ROSDEP=1 ./auto_start.sh pour passer outre)."
  fi
  rosdep update >/dev/null 2>&1 || warn "'rosdep update' a échoué; utilisation du cache local."
  rosdep_usable=1
}

install_dependencies() {
  local base_path=$1
  local skip_keys=${2:-}
  (( rosdep_usable )) || return 0
  echo "Installation des dépendances ROS de $base_path (sudo peut demander le mot de passe)..."
  local command=(rosdep install --from-paths "$base_path" --ignore-src -r -y
    --rosdistro "$ros_distro")
  if [[ -n "$skip_keys" ]]; then
    command+=(--skip-keys "$skip_keys")
  fi
  "${command[@]}" \
    || warn "rosdep n'a pas résolu toutes les dépendances de $base_path"
}

check_runtime_modules() {
  local missing=()
  python3 -c 'import numpy' >/dev/null 2>&1 || missing+=("python3-numpy")
  python3 -c 'from sensor_msgs_py import point_cloud2' >/dev/null 2>&1 \
    || missing+=("ros-${ros_distro}-sensor-msgs-py")
  if (( ${#missing[@]} )); then
    fail "modules Python manquants pour la perception RGB-D. Installer:
  sudo apt install -y ${missing[*]}"
  fi
}

# --------------------------------------------------------------------------
# Underlay Room 315
# --------------------------------------------------------------------------

contains_room315() {
  local install_dir=$1
  find "$install_dir" -maxdepth 6 -path \
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
  done < <(find "$HOME" -maxdepth "$search_depth" -type f -path '*/install/setup.bash' \
    -not -path '*/.cache/*' -not -path '*/build/*' -not -path '*/log/*' \
    2>/dev/null)
}

find_mfja_sources() {
  local package_file
  # Un dépôt Room 315 déposé dans src/ est prioritaire sur le reste du HOME.
  if [[ -f "$repo_dir/src/mfja_3rd_floor_gz/mfja_3rd_floor_bringup/package.xml" ]]; then
    printf '%s\n' "$repo_dir/src/mfja_3rd_floor_gz"
    return
  fi
  package_file=$(find "$HOME" -maxdepth "$search_depth" -type f \
    -path '*/mfja_3rd_floor_bringup/package.xml' \
    -not -path '*/build/*' -not -path '*/install/*' -not -path '*/log/*' \
    -print -quit 2>/dev/null || true)
  if [[ -n "$package_file" ]]; then
    dirname "$(dirname "$package_file")"
  fi
}

clone_mfja_sources() {
  local target=$1
  mkdir -p "$(dirname "$target")"
  echo "Sources Room 315 absentes; clonage de $mfja_repo_url ($mfja_branch)..."
  git clone --depth 1 --branch "$mfja_branch" "$mfja_repo_url" "$target"
  [[ -n "$mfja_commit" ]] || return 0
  if git -C "$target" rev-parse --verify --quiet "${mfja_commit}^{commit}" >/dev/null \
      || git -C "$target" fetch --depth 1 origin "$mfja_commit" >/dev/null 2>&1; then
    git -C "$target" checkout --quiet --detach "$mfja_commit"
    echo "Sources Room 315 fixées sur le commit validé $mfja_commit"
  else
    warn "commit $mfja_commit indisponible; utilisation de la tête de $mfja_branch"
  fi
}

build_underlay() {
  local source_root=$1
  # Torch sert aux outils IA optionnels de Room 315. La simulation HC10,
  # les caméras et les bridges ne l'utilisent pas; ne pas imposer ~1 Go de
  # paquets ni une demande sudo inutile sur une machine vierge.
  install_dependencies "$source_root" "python3-torch python3-torchvision"
  echo "Compilation de l'underlay Room 315 depuis $source_root..."
  mkdir -p "$cache_root/mfja_underlay"
  colcon --log-base "$cache_root/mfja_underlay/log" build \
    --base-paths "$source_root" \
    --build-base "$cache_root/mfja_underlay/build" \
    --install-base "$cache_root/mfja_underlay/install" \
    --symlink-install
}

optimize_cached_rgbd() {
  local source_model="$cache_root/sources/mfja_3rd_floor_gz/mfja_3rd_floor_description/models/room315_visual_observation_rig/model.sdf"
  local installed_model="$cache_root/mfja_underlay/install/mfja_3rd_floor_description/share/mfja_3rd_floor_description/models/room315_visual_observation_rig/model.sdf"
  [[ -f "$source_model" ]] || return 0
  python3 - "$source_model" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
for sensor in root.findall('.//sensor'):
    image = sensor.find('./camera/image')
    if sensor.get('name') == 'room315_right_rail_rgbd':
        sensor.find('always_on').text = 'true'
        sensor.find('update_rate').text = '2'
        image.find('width').text = '320'
        image.find('height').text = '240'
    elif sensor.get('name') == 'room315_left_rail_rgbd':
        sensor.find('always_on').text = 'false'
        sensor.find('update_rate').text = '1'
        image.find('width').text = '160'
        image.find('height').text = '120'
tree.write(path, encoding='unicode', xml_declaration=True)
PY
  # Avec --symlink-install, le fichier installé pointe normalement vers la
  # source. Couvrir aussi une installation copiée.
  if [[ -f "$installed_model" ]] && [[ ! "$installed_model" -ef "$source_model" ]]; then
    cp "$source_model" "$installed_model"
  fi
  echo "Profil RGB-D léger appliqué à l'underlay automatique."
}

ensure_rosdep

underlay=$(find_underlay || true)
if [[ -z "$underlay" ]]; then
  source_root=$(find_mfja_sources || true)
  if [[ -z "$source_root" ]]; then
    source_root="$cache_root/sources/mfja_3rd_floor_gz"
    if [[ -d "$source_root/.git" ]]; then
      echo "Sources Room 315 déjà en cache: $source_root"
    else
      clone_mfja_sources "$source_root"
    fi
  else
    echo "Sources Room 315 trouvées: $source_root"
  fi
  build_underlay "$source_root"
  underlay="$cache_root/mfja_underlay/install"
fi

if [[ "$underlay" == "$cache_root/mfja_underlay/install" ]]; then
  optimize_cached_rgbd
fi

echo "Underlay Room 315: $underlay"
source "$underlay/setup.bash"
ros2 pkg prefix mfja_3rd_floor_bringup >/dev/null \
  || fail "l'underlay trouvé ne contient pas mfja_3rd_floor_bringup"

# --------------------------------------------------------------------------
# Workspace du dépôt
# --------------------------------------------------------------------------

echo "Installation des dépendances et compilation du projet..."
cd "$repo_dir"
install_dependencies "$repo_dir/src"
# Room 315 est toujours consommé comme underlay, jamais compilé dans ce
# workspace: les deux chemins doivent rester identiques sur toutes les machines.
colcon build --symlink-install --packages-ignore-regex '^mfja_' '^motoman_'
source "$repo_dir/install/setup.bash"
check_runtime_modules

if [[ "${AUTO_SETUP_ONLY:-0}" == "1" ]]; then
  echo "Préparation terminée. Relancez ./auto_start.sh pour ouvrir la simulation."
  exit 0
fi

mkdir -p "$log_dir"

echo "Nettoyage des anciennes instances..."
"$repo_dir/stop_all.sh"

cleanup_after_failure() {
  local status=$?
  if (( status != 0 )); then
    echo "Échec du lancement: arrêt des composants déjà ouverts." >&2
    "$repo_dir/stop_all.sh" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup_after_failure EXIT

# --------------------------------------------------------------------------
# Lancement des quatre terminaux
# --------------------------------------------------------------------------

launch_terminal() {
  local title=$1
  local script=$2
  local log_file=$3
  local command
  : > "$log_file"
  printf -v command 'set -o pipefail; export MFJA_UNDERLAY=%q; cd %q; %q 2>&1 | tee %q; code=${PIPESTATUS[0]}; echo; echo "Processus terminé (code $code)" | tee -a %q; exec bash' \
    "$underlay" "$repo_dir" "$script" "$log_file" "$log_file"
  if command -v gnome-terminal >/dev/null; then
    gnome-terminal --title="$title" -- bash -lc "$command"
  elif command -v konsole >/dev/null; then
    konsole -p "tabtitle=$title" -e bash -lc "$command" &
  elif command -v xfce4-terminal >/dev/null; then
    xfce4-terminal --title="$title" -x bash -lc "$command" &
  elif command -v xterm >/dev/null; then
    xterm -T "$title" -e bash -lc "$command" &
  elif command -v x-terminal-emulator >/dev/null; then
    x-terminal-emulator -T "$title" -e bash -lc "$command" &
  else
    fail "aucun terminal graphique compatible n'est installé.
Installer gnome-terminal ou xterm, ou lancer les quatre scripts à la main (voir readme.md)."
  fi
}

# Un PointCloud2 vide est un message valide: attendre « un message » ne prouve
# rien. On exige donc un nombre minimal de points finis avant de continuer.
wait_for_cloud() {
  local topic=$1
  local timeout_seconds=$2
  local min_points=$3
  echo "Attente d'un nuage exploitable sur $topic (max ${timeout_seconds}s, >= ${min_points} points)..."
  python3 - "$topic" "$timeout_seconds" "$min_points" <<'PY'
import sys
import time

import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import PointCloud2
from sensor_msgs_py import point_cloud2

topic, timeout_text, min_points_text = sys.argv[1:]
min_points = int(min_points_text)
state = {'messages': 0, 'best': 0, 'ok': False}


def finite_points(message):
    try:
        data = point_cloud2.read_points_numpy(message, field_names=['x', 'y', 'z'])
        data = np.asarray(data, dtype=np.float32).reshape(-1, 3)
        return int(np.isfinite(data).all(axis=1).sum())
    except Exception:
        return int(message.width) * int(message.height)


def callback(message):
    state['messages'] += 1
    count = finite_points(message)
    state['best'] = max(state['best'], count)
    if count >= min_points:
        state['ok'] = True


rclpy.init()
node = Node('integration_auto_wait')
subscription = node.create_subscription(
    PointCloud2,
    topic,
    callback,
    QoSProfile(
        history=HistoryPolicy.KEEP_LAST,
        depth=1,
        reliability=ReliabilityPolicy.RELIABLE,
    ))
deadline = time.monotonic() + float(timeout_text)
while not state['ok'] and time.monotonic() < deadline:
    rclpy.spin_once(node, timeout_sec=0.2)
node.destroy_subscription(subscription)
node.destroy_node()
rclpy.shutdown()

if state['ok']:
    print(f"OK: nuage exploitable sur {topic} ({state['best']} points valides)")
    raise SystemExit(0)
if state['messages']:
    print(
        f"ERREUR: {state['messages']} message(s) reçu(s) sur {topic}, mais au mieux "
        f"{state['best']} point(s) valide(s) pour un minimum de {min_points}",
        file=sys.stderr)
else:
    print(f'ERREUR: aucun message reçu sur {topic}', file=sys.stderr)
raise SystemExit(1)
PY
}

wait_for_service() {
  local service=$1
  local timeout_seconds=$2
  echo "Attente du service $service..."
  if python3 - "$service" "$timeout_seconds" <<'PYROS'
import sys
import rclpy
from moveit_msgs.srv import GetPositionIK, GetPlanningScene
from std_srvs.srv import Empty

service, timeout_text = sys.argv[1:]
service_types = {
    '/compute_ik': GetPositionIK,
    '/get_planning_scene': GetPlanningScene,
    '/clear_octomap': Empty,
}
rclpy.init()
node = rclpy.create_node('integration_wait_for_service')
try:
    client = node.create_client(service_types[service], service)
    available = client.wait_for_service(timeout_sec=float(timeout_text))
finally:
    node.destroy_node()
    rclpy.shutdown()
raise SystemExit(0 if available else 1)
PYROS
  then
    echo "OK: service disponible: $service"
    return
  fi
  tail -n 80 "$moveit_log" >&2
  fail "service indisponible après ${timeout_seconds}s: $service; journal: $moveit_log"
}

wait_for_joints() {
  echo "Attente de l'état complet des six articulations HC10..."
  python3 - <<'PY'
import time
import rclpy
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import JointState

required = {'joint_1_s', 'joint_2_l', 'joint_3_u', 'joint_4_r', 'joint_5_b', 'joint_6_t'}
state = {'ok': False}

def callback(message):
    state['ok'] = required.issubset(message.name)

rclpy.init()
node = Node('integration_joint_wait')
node.create_subscription(
    JointState,
    '/yaskawa_hc10_1/joint_states',
    callback,
    QoSProfile(
        history=HistoryPolicy.KEEP_LAST,
        depth=1,
        reliability=ReliabilityPolicy.RELIABLE,
    ))
deadline = time.monotonic() + 60.0
while not state['ok'] and time.monotonic() < deadline:
    rclpy.spin_once(node, timeout_sec=0.2)
node.destroy_node()
rclpy.shutdown()
if not state['ok']:
    raise SystemExit('ERREUR: aucun état articulaire HC10 complet après 60s')
print('OK: état articulaire HC10 complet reçu')
PY
}

wait_for_demo() {
  local deadline=$((SECONDS + ${DEMO_TIMEOUT:-420}))
  echo "Attente de la fin du cycle de démonstration..."
  while (( SECONDS < deadline )); do
    if grep -Fq 'Processus terminé (code 0)' "$demo_log"; then
      echo "OK: cycle complet terminé."
      return 0
    fi
    if grep -Eq 'Processus terminé \(code [1-9][0-9]*\)' "$demo_log"; then
      tail -n 100 "$demo_log" >&2
      return 1
    fi
    sleep 2
  done
  tail -n 100 "$demo_log" >&2
  echo "ERREUR: la démo n'est pas terminée après ${DEMO_TIMEOUT:-420}s" >&2
  return 1
}

gazebo_log="$log_dir/gazebo.log"
perception_log="$log_dir/perception.log"
moveit_log="$log_dir/moveit.log"
demo_log="$log_dir/demo.log"

launch_terminal "1 - Gazebo Room 315" "$repo_dir/gazebo.sh" "$gazebo_log"
if ! wait_for_cloud /room_315/perception/right_rail_rgbd/points \
    "$camera_timeout" "$min_camera_points"; then
  tail -n 80 "$gazebo_log" >&2
  fail "la caméra RGB-D Room 315 ne fournit pas de nuage exploitable.
Causes fréquentes:
  - les modèles n'ont pas été créés dans le monde (voir la fin de $gazebo_log);
  - le rendu 3D n'est pas disponible côté serveur Gazebo (VM sans accélération);
  - une ancienne instance Gazebo occupe encore la partition Gazebo Transport.
Journal: $gazebo_log"
fi

launch_terminal "2 - Perception RGB-D" "$repo_dir/perception.sh" "$perception_log"
if ! wait_for_cloud /hc10/collision_cloud 60 1; then
  tail -n 80 "$perception_log" >&2
  fail "la perception ne publie pas le nuage filtré; journal: $perception_log"
fi

launch_terminal "3 - MoveIt 2 et RViz" "$repo_dir/moveit_rviz.sh" "$moveit_log"
wait_for_service /compute_ik 60
wait_for_service /get_planning_scene 60
wait_for_service /clear_octomap 60
wait_for_joints

if [[ "${AUTO_RUN_DEMO:-1}" == "1" ]]; then
  launch_terminal "4 - Démonstration HC10" "$repo_dir/demo.sh" "$demo_log"
  wait_for_demo || fail "le cycle de démonstration a échoué; journal: $demo_log"
  echo "Les quatre composants fonctionnent et la démonstration est terminée."
else
  echo "Gazebo, perception et MoveIt/RViz sont prêts."
  echo "Lancer ./demo.sh manuellement pour démarrer le mouvement."
fi

trap - EXIT
