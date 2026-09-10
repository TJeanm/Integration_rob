#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
source /opt/ros/jazzy/setup.bash
source /home/mfja/Desktop/hc10_ros2_ws/install/setup.bash
source install/setup.bash
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
wait "$sim_pid"
