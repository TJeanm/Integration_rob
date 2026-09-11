#!/usr/bin/env bash
set -e
script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/setup_env.sh"
cd "$INTEGRATION_ROB_ROOT"
if ! ros2 pkg prefix mfja_3rd_floor_bringup >/dev/null 2>&1; then
  echo "Paquet mfja_3rd_floor_bringup introuvable." >&2
  echo "Définir MFJA_UNDERLAY=/chemin/vers/le/workspace/install" >&2
  exit 1
fi
export GZ_PARTITION=${GZ_PARTITION:-mfja_pick_place}
# Keep Gazebo Transport on the VM loopback interface. Multicast discovery on
# the VMware adapter can leave the GUI connected to no scene (uniform grey).
# Surchargeable si la machine a besoin d'une autre interface.
export GZ_IP=${GZ_IP:-127.0.0.1}
# Sur une VM où Mesa annonce aucune accélération, Ogre2 peut publier des
# PointCloud2 entièrement NaN. Le rendu logiciel produit alors un vrai nuage.
# Une machine accélérée conserve son GPU. La variable reste surchargeable.
software_camera=0
if [[ -z "${LIBGL_ALWAYS_SOFTWARE+x}" ]] && command -v glxinfo >/dev/null \
    && glxinfo -B 2>/dev/null | grep -q 'Accelerated: *no'; then
  export LIBGL_ALWAYS_SOFTWARE=1
  software_camera=1
  echo "GPU non accéléré détecté: rendu logiciel Mesa activé pour la caméra RGB-D."
elif [[ "${LIBGL_ALWAYS_SOFTWARE:-0}" == "1" ]]; then
  software_camera=1
fi
world_name=${HC10_WORLD_NAME:-room_315_only}
spawn_timeout=${HC10_SPAWN_TIMEOUT:-120}
share=$(ros2 pkg prefix --share hc10_pick_place_demo)
create_service="/world/${world_name}/create"

# A previous terminal may leave Gazebo server / GUI processes alive. Two
# servers publishing the same world on the same partition produce a grey GUI.
# Les motifs restent volontairement tolérants: selon la version de ros_gz_sim
# le serveur apparaît en « gz sim ... » ou en « ruby /usr/bin/gz sim ... », et
# ros2 n'est pas toujours à /opt/ros/jazzy/bin/ros2.
stale_patterns=(
  "ros2 launch mfja_3rd_floor_bringup ${world_name}[.]launch[.]py"
  'gz sim -g .*room315_runtime_safe[.]gui[.]config'
  "gz sim (-r )?-s .*${world_name}.*[.]world"
)
for signal in TERM KILL; do
  for pattern in "${stale_patterns[@]}"; do
    pkill "-${signal}" -f "$pattern" 2>/dev/null || true
  done
  if [[ "$signal" == TERM ]]; then
    sleep 1
  fi
done

gui_in_launch=true
if (( software_camera )); then
  gui_in_launch=false
fi

ros2 launch mfja_3rd_floor_bringup "${world_name}.launch.py" \
  robots:=yaskawa_hc10_1 gui:="$gui_in_launch" start_paused:=false \
  enable_room315_kinematic_shuttles:=false \
  enable_room315_rail_safety_supervisor:=false \
  enable_room315_rgbd_camera_bridge:=false \
  gz_partition:="$GZ_PARTITION" &
sim_pid=$!

# Le launch MFJA bridge normalement les images, profondeurs, camera_info et
# points des deux caméras dans les deux sens. Cette démo ne consomme que le
# PointCloud2 droit: un bridge directionnel unique évite sept flux lourds et
# toute boucle ROS->Gazebo.
ros2 run ros_gz_bridge parameter_bridge \
  '/room_315/perception/right_rail_rgbd/points@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked' \
  --ros-args -r __node:=hc10_right_cloud_bridge &
camera_bridge_pid=$!

gui_pid=
if (( software_camera )); then
  gui_config=$(ros2 pkg prefix --share mfja_robot_control_config)/config/room315_runtime_safe.gui.config
  env -u LIBGL_ALWAYS_SOFTWARE gz sim -g --gui-config "$gui_config" &
  gui_pid=$!
  echo "GUI Gazebo séparée du rendu logiciel de la caméra."
fi

cleanup() {
  kill -INT "$sim_pid" "$camera_bridge_pid" ${gui_pid:+"$gui_pid"} 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Attente du service Gazebo $create_service (max ${spawn_timeout}s, partition $GZ_PARTITION)..."
deadline=$((SECONDS + spawn_timeout))
until gz service -l 2>/dev/null | grep -qx "$create_service"; do
  if ! kill -0 "$sim_pid" 2>/dev/null; then
    echo "ERREUR: le lancement Gazebo s'est arrêté avant de créer le monde." >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "ERREUR: $create_service indisponible après ${spawn_timeout}s." >&2
    echo "Le serveur Gazebo n'a pas démarré, ou il n'écoute pas sur la partition" >&2
    echo "GZ_PARTITION=$GZ_PARTITION. Vérifier avec:" >&2
    echo "  GZ_PARTITION=$GZ_PARTITION gz service -l | grep create" >&2
    exit 1
  fi
  sleep 1
done
sleep 3

# Sans ce contrôle, un refus de Gazebo passait inaperçu: la Room 315 s'affichait
# mais le HC10, la plateforme et l'obstacle n'existaient pas, et l'échec ne se
# manifestait qu'en bout de chaîne (nuage filtré vide, puis MoveIt sans robot).
spawn_model() {
  local name=$1
  local sdf=$2
  local pose=$3
  local reply
  reply=$(gz service -s "$create_service" \
    --reqtype gz.msgs.EntityFactory --reptype gz.msgs.Boolean --timeout 10000 \
    --req "sdf_filename: \"$sdf\", name: \"$name\", pose: {$pose}" 2>&1) || true
  if ! grep -q 'data: *true' <<<"$reply"; then
    echo "ERREUR: Gazebo a refusé la création du modèle '$name'." >&2
    echo "Réponse: ${reply:-<aucune>}" >&2
    echo "Fichier SDF: $sdf" >&2
    exit 1
  fi
  echo "Modèle créé dans Gazebo: $name"
}

gz service -s "/world/${world_name}/remove" --reqtype gz.msgs.Entity --reptype gz.msgs.Boolean --timeout 5000 --req 'name: "yaskawa_hc10_1", type: 2' >/dev/null || true

spawn_model yaskawa_hc10_1 "$share/models/yaskawa_hc10.sdf" \
  'position: {x: -15.1622, y: -3.0, z: 0.62}, orientation: {z: 0.70710678, w: 0.70710678}'
spawn_model mobile_pick_station "$share/models/mobile_pick_station.sdf" \
  'position: {x: -14.1122, y: -3.0}, orientation: {z: 0.70710678, w: 0.70710678}'
if [[ "${HC10_TEST_OBSTACLE:-1}" == "1" ]]; then
  # Milieu du segment A -> B, posé sur la table. Ce mur n'est déclaré qu'à
  # Gazebo : MoveIt doit le découvrir par la caméra RGB-D et l'OctoMap.
  spawn_model trajectory_test_obstacle "$share/models/trajectory_test_obstacle.sdf" \
    'position: {x: -14.6569, y: -3.5590, z: 0.62}'
  echo "Obstacle de test A-B activé (HC10_TEST_OBSTACLE=0 pour le retirer)."
fi
wait "$sim_pid"
