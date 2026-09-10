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
export GZ_PARTITION=mfja_pick_place
# Keep Gazebo Transport on the VM loopback interface. Multicast discovery on
# the VMware adapter can leave the GUI connected to no scene (uniform grey).
export GZ_IP=127.0.0.1
share=$(ros2 pkg prefix --share hc10_pick_place_demo)

# A previous terminal may leave Gazebo server / GUI processes alive. Two
# servers publishing the same world on the same partition produce a grey GUI.
pkill -TERM -f '^/usr/bin/python3 /opt/ros/jazzy/bin/ros2 launch mfja_3rd_floor_bringup room_315_only[.]launch[.]py' 2>/dev/null || true
pkill -TERM -f '^gz sim -g .*room315_runtime_safe[.]gui[.]config' 2>/dev/null || true
pkill -TERM -f '^gz sim -r -s /tmp/room_315_only_.*[.]world' 2>/dev/null || true
sleep 1
pkill -KILL -f '^/usr/bin/python3 /opt/ros/jazzy/bin/ros2 launch mfja_3rd_floor_bringup room_315_only[.]launch[.]py' 2>/dev/null || true
pkill -KILL -f '^gz sim -g .*room315_runtime_safe[.]gui[.]config' 2>/dev/null || true
pkill -KILL -f '^gz sim -r -s /tmp/room_315_only_.*[.]world' 2>/dev/null || true

ros2 launch mfja_3rd_floor_bringup room_315_only.launch.py \
  robots:=yaskawa_hc10_1 gui:=true start_paused:=false \
  enable_room315_kinematic_shuttles:=false \
  enable_room315_rail_safety_supervisor:=true \
  enable_room315_rgbd_camera_bridge:=true \
  gz_partition:=mfja_pick_place &
sim_pid=$!
trap 'kill -INT "$sim_pid" 2>/dev/null || true' EXIT INT TERM
until gz service -l 2>/dev/null | grep -qx /world/room_315_only/create; do sleep 1; done
sleep 3

gz service -s /world/room_315_only/remove --reqtype gz.msgs.Entity --reptype gz.msgs.Boolean --timeout 5000 --req 'name: "yaskawa_hc10_1", type: 2' >/dev/null || true
gz service -s /world/room_315_only/create --reqtype gz.msgs.EntityFactory --reptype gz.msgs.Boolean --timeout 10000 --req 'sdf_filename: "'"$share"'/models/yaskawa_hc10.sdf", name: "yaskawa_hc10_1", pose: {position: {x: -15.1622, y: -3.0, z: 0.62}, orientation: {z: 0.70710678, w: 0.70710678}}'
gz service -s /world/room_315_only/create --reqtype gz.msgs.EntityFactory --reptype gz.msgs.Boolean --timeout 10000 --req 'sdf_filename: "'"$share"'/models/mobile_pick_station.sdf", name: "mobile_pick_station", pose: {position: {x: -14.1122, y: -3.0}, orientation: {z: 0.70710678, w: 0.70710678}}'
if [[ "${HC10_TEST_OBSTACLE:-1}" == "1" ]]; then
  # Milieu du segment A -> B, posé sur la table. Ce mur n'est déclaré qu'à
  # Gazebo : MoveIt doit le découvrir par la caméra RGB-D et l'OctoMap.
  gz service -s /world/room_315_only/create \
    --reqtype gz.msgs.EntityFactory --reptype gz.msgs.Boolean --timeout 10000 \
    --req 'sdf_filename: "'"$share"'/models/trajectory_test_obstacle.sdf", name: "trajectory_test_obstacle", pose: {position: {x: -14.6569, y: -3.5590, z: 0.62}}'
  echo "Obstacle de test A-B activé (HC10_TEST_OBSTACLE=0 pour le retirer)."
fi
wait "$sim_pid"
