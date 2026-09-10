#!/usr/bin/env bash

set -e

WS="$HOME/mfja_3rd_floor_ros2_ws"
PROJECT_WS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

GOAL_EXECUTABLE=joint_goal
GOAL_LABELS=(j1 j2 j3 j4 j5 j6)
if [ "${1:-}" = "--pose" ]; then
    shift
    GOAL_EXECUTABLE=pose_goal
    GOAL_LABELS=(x y z roll pitch yaw)
fi

if [ "$#" -ne 6 ]; then
    echo
    echo "Usage:"
    echo "  ./demo.sh j1 j2 j3 j4 j5 j6"
    echo "  ./demo_pose.sh x y z roll pitch yaw (metres, radians; tool0 in base_link)"
    echo
    echo "Example:"
    echo "  ./demo.sh 0.3 -0.25 0.2 0.0 0.15 0.0"
    echo
    exit 1
fi

cd "$WS"

source /opt/ros/jazzy/setup.bash
source install/setup.bash

if [ ! -f "$PROJECT_WS/install/local_setup.bash" ]; then
    echo "Build Integration_rob first: colcon build --symlink-install --packages-select hc10_moveit_api hc10_moveit_config hc10_mfja_control_adapter" >&2
    exit 1
fi
source "$PROJECT_WS/install/local_setup.bash"

for package in pymoveit2 hc10_moveit_api hc10_moveit_config hc10_mfja_control_adapter; do
    if ! ros2 pkg prefix "$package" >/dev/null 2>&1; then
        echo "Missing package: $package. Build it in $PROJECT_WS and retry." >&2
        exit 1
    fi
done

cleanup() {
    trap - EXIT INT TERM
    echo
    echo "Stopping demo..."

    kill "${GUI_PID:-}" 2>/dev/null || true
    kill "$MOVEIT_PID" 2>/dev/null || true
    kill "$RELAY_PID" 2>/dev/null || true
    kill "$ADAPTER_PID" 2>/dev/null || true
    kill "$ROOM315_PID" 2>/dev/null || true

    pkill -f "gz sim" 2>/dev/null || true

    echo "Done."
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM


echo "========================================"
echo " HC10 MoveIt2 demo"
echo "========================================"
echo
echo "Goal:"
goal_values=("$@")
for index in 0 1 2 3 4 5; do
    echo "  ${GOAL_LABELS[$index]} = ${goal_values[$index]}"
done
echo


export GZ_PARTITION="hc10_demo_$$"
DESCRIPTION_SHARE="$(ros2 pkg prefix --share mfja_3rd_floor_description)"
export GZ_SIM_RESOURCE_PATH="$DESCRIPTION_SHARE/models${GZ_SIM_RESOURCE_PATH:+:$GZ_SIM_RESOURCE_PATH}"

echo "[1/5] Starting Room315 + HC10..."

ros2 launch mfja_3rd_floor_bringup room_315_only.launch.py \
    robots:=hc10 \
    gui:=false \
    gz_partition:="$GZ_PARTITION" \
    start_paused:=false \
    > /tmp/room315.log 2>&1 &

ROOM315_PID=$!

# Start the GUI only once Gazebo has created the HC10.
spawn_ready=false
for ((attempt=0; attempt<90; attempt++)); do
    if grep -q 'spawn_yaskawa_hc10_1.*Entity creation successful' /tmp/room315.log; then
        spawn_ready=true
        break
    fi
    if ! kill -0 "$ROOM315_PID" 2>/dev/null; then
        echo "Room315 failed; see /tmp/room315.log" >&2
        exit 1
    fi
    sleep 1
done
if [ "$spawn_ready" != true ]; then
    echo "HC10 creation timed out; see /tmp/room315.log" >&2
    exit 1
fi

gz sim -g --render-engine ogre \
    --gui-config "$PROJECT_WS/src/hc10_moveit_config/config/hc10_room315.gui.config" \
    > /tmp/hc10_gui.log 2>&1 &
GUI_PID=$!

sleep 5
if ! kill -0 "$GUI_PID" 2>/dev/null; then
    echo "Gazebo GUI failed; see /tmp/hc10_gui.log" >&2
    exit 1
fi


echo "[2/5] Starting HC10 adapter..."

ros2 run hc10_mfja_control_adapter hc10_control_adapter \
    > /tmp/hc10_adapter.log 2>&1 &

ADAPTER_PID=$!

sleep 2


echo "[3/5] Starting joint state relay..."

ros2 run topic_tools relay \
    /yaskawa_hc10_1/joint_states \
    /joint_states \
    > /tmp/joint_relay.log 2>&1 &

RELAY_PID=$!

sleep 2


echo "[4/5] Starting MoveIt..."

ros2 launch hc10_moveit_config moveit.launch.py \
    use_rviz:=false \
    > /tmp/moveit.log 2>&1 &

MOVEIT_PID=$!

sleep 5


echo "[5/5] Sending goal..."

ros2 run hc10_moveit_api "$GOAL_EXECUTABLE" \
    "$1" "$2" "$3" "$4" "$5" "$6"


echo
echo "========================================"
echo " Motion finished"
echo "========================================"
echo
echo "Simulation remains running."
echo "Press CTRL+C to stop everything."
echo

wait
