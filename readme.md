# Integration Robotique — ROS 2 / Yaskawa HC10 / Room 315

Projet d'intégration robotique sous ROS 2 autour du robot industriel Yaskawa HC10, avec simulation Gazebo, MoveIt 2 et environnement Room 315.

## Environment

Tested with:

- Ubuntu 24.04
- ROS 2 Jazzy
- Gazebo Harmonic
- MoveIt 2
- RViz2
- Python 3.12

## Repository structure

The ROS 2 packages are located in: src/


The following directories are generated locally and are not versioned:


build/
install/
log/


## Requirements

ROS 2 Jazzy must already be installed.

Install the main dependencies:


sudo apt update

sudo apt install \
  ros-jazzy-moveit \
  ros-jazzy-ros-gz \
  ros-jazzy-ros-gz-sim \
  ros-jazzy-ros-gz-bridge \
  ros-jazzy-xacro \
  ros-jazzy-robot-state-publisher \
  ros-jazzy-joint-state-publisher \
  ros-jazzy-rviz2 \
  python3-rosdep


Initialize `rosdep` if needed:


sudo rosdep init
rosdep update


## Clone


git clone https://github.com/TJeanm/Integration_rob.git
cd Integration_rob


## Install package dependencies


source /opt/ros/jazzy/setup.bash

rosdep install \
  --from-paths src \
  --ignore-src \
  -r \
  -y


## Build


source /opt/ros/jazzy/setup.bash

colcon build --symlink-install

source install/setup.bash


## Launch Room 315 with the Yaskawa HC10


ros2 launch mfja_3rd_floor_bringup room_315_only.launch.py \
  robots:=hc10 \
  gui:=true \
  start_paused:=false


## Launch the isolated HC10 simulation


ros2 launch mfja_robot_control_config \
  isolated_industrial_robot.launch.py \
  robot:=hc10 \
  gui:=true \
  start_paused:=false


## MoveIt 2

The repository contains a MoveIt 2 configuration for the HC10.

After building and sourcing the workspace:


ros2 launch hc10_moveit_config moveit.launch.py


The MoveIt setup uses the Yaskawa HC10 joint model together with the MFJA simulation interfaces.

## Gazebo rendering note

On some VMware virtual machines, the Ogre2 rendering engine may produce severe flickering.

The simulation is therefore configured to use Ogre1:


--render-engine ogre


If Gazebo flickers heavily, verify that Ogre2 has not been enabled.

## Room 315 GUI note

The HC10 is spawned dynamically in Room 315.

In the tested VMware / Gazebo Harmonic environment, the Gazebo GUI must be started after the HC10 has been spawned so that the robot is correctly displayed with Ogre1.

## Rebuilding after changes


colcon build --symlink-install
source install/setup.bash


## Clean rebuild

If needed:


rm -rf build install log

source /opt/ros/jazzy/setup.bash

colcon build --symlink-install

source install/setup.bash

