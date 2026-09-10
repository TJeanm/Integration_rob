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

## Lancement de l'intégration Room 315

The repository also contains the project integration developed on top of the
original MoveIt configuration: the Room 315 RGB-D camera, filtered collision
cloud, OctoMap, mobile platform, animated gripper and the collision-aware A/B
demonstration. No object is spawned: the gripper closes above the platform as
if it were grasping one, then opens above the conveyor.

Le lancement utilise quatre terminaux ouverts dans le dossier du dépôt. Les
scripts arrêtent automatiquement leurs anciennes instances afin d'éviter les
serveurs Gazebo, MoveIt ou nœuds de perception en double.

Préparer le workspace une fois, quel que soit le dossier dans lequel le dépôt
a été cloné :

```bash
source /opt/ros/jazzy/setup.bash
colcon build --symlink-install
source install/setup.bash
```

Les paquets de la Room 315 viennent du workspace externe
`mfja_3rd_floor_gz`. Si son dossier `install` n'est pas situé à côté de ce
dépôt sous le nom `hc10_ros2_ws/install` ou `mfja_3rd_floor_gz/install`,
indiquer son emplacement avant les lancements :

```bash
export MFJA_UNDERLAY=/chemin/vers/le/workspace_mfja/install
```

Cette variable peut être ajoutée au `~/.bashrc`. Aucun script ne dépend d'un
nom d'utilisateur ni du dossier `Desktop`.

Ouvrir ensuite quatre terminaux dans le dossier cloné et exécuter les
commandes suivantes dans cet ordre. Répéter l'export `MFJA_UNDERLAY` dans
chaque terminal s'il n'est pas défini dans le `~/.bashrc` :

Terminal 1 — simulation Gazebo :

```bash
./gazebo.sh
```

Terminal 2 — perception Astra et nuage de collision :

```bash
./perception.sh
```

Terminal 3 — adaptateur contrôleur, MoveIt 2 et RViz :

```bash
./moveit_rviz.sh
```

Attendre que RViz affiche le robot et que le nuage soit visible, puis terminal
4 — démonstration :

```bash
./demo.sh
```

`demo.sh` vérifie que l'OctoMap est présente dans la PlanningScene MoveIt,
calcule A au-dessus du centre de la plateforme, descend verticalement,
remonte, rejoint B au-dessus du convoyeur, descend verticalement et revient à
la position initiale. La pince s'ouvre et se ferme en simulation, sans cube
ni attachement artificiel.

Pour valider toute la planification sans faire bouger le robot, utiliser le
terminal 4 avec :

```bash
./validate_demo.sh
```

Cette validation journalise les requêtes IK, le quaternion, le repère, le
code d'erreur MoveIt, la FK de `gripper_tcp`, l'orientation verticale, la
constance de X/Y pendant les descentes et la planification OMPL avec
l'OctoMap. Elle doit afficher `CYCLE DE PINCE SIMULÉ ET TRAJECTOIRE
ANTI-COLLISION TERMINÉS`.

Pour arrêter proprement, faire `Ctrl+C` dans les terminaux 4, 3, 2 puis 1.


## Clean rebuild

If needed:


rm -rf build install log

source /opt/ros/jazzy/setup.bash

colcon build --symlink-install

source install/setup.bash
