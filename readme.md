# Intégration robotique — Yaskawa HC10, ROS 2 et Room 315

Ce dépôt présente une étude de faisabilité pour la génération de trajectoires
sans collision d'un bras industriel Yaskawa HC10. La cellule est simulée dans
Gazebo, la perception repose sur la caméra RGB-D de la Room 315 et MoveIt 2
calcule les trajectoires à partir de l'OctoMap affichée dans RViz.

La démonstration réalise le cycle suivant :

1. rejoindre un point A au-dessus du centre de la plateforme mobile ;
2. descendre verticalement et fermer la pince comme si un objet était saisi ;
3. remonter verticalement ;
4. rejoindre un point B au-dessus du convoyeur ;
5. descendre verticalement et ouvrir la pince ;
6. remonter puis revenir à la position initiale.

Aucun cube n'est attaché artificiellement à la pince. L'ouverture et la
fermeture sont simulées sans objet.

## Environnement validé

- Ubuntu 24.04 ;
- ROS 2 Jazzy ;
- Gazebo Harmonic ;
- MoveIt 2 ;
- RViz 2 ;
- Python 3.12.

## Architecture

```text
Caméra RGB-D Room 315
        │
        ▼
Nuage PointCloud2 filtré ──────► affichage RViz
        │
        ▼
OctoMap de la PlanningScene MoveIt
        │
        ▼
IK verticale + planification OMPL + trajets cartésiens
        │
        ▼
Adaptateur FollowJointTrajectory ──────► robot HC10 dans Gazebo
```

Les paquets ROS 2 du dépôt sont :

- `hc10_mfja_control_adapter` : adaptation des commandes MoveIt vers Gazebo ;
- `hc10_moveit_config` : URDF, SRDF, cinématique, OMPL, RViz et OctoMap ;
- `hc10_pick_place_demo` : perception, plateforme et cycle de démonstration.

## Dépendance Room 315

Le dépôt s'appuie sur les paquets du projet externe
[`mfja_3rd_floor_gz`](https://github.com/aip-primeca-occitanie/mfja_3rd_floor_gz/tree/INTERNSHIP-ALI-2026),
notamment `mfja_3rd_floor_bringup`, `mfja_robot_control_config` et
`mfja_3rd_floor_description`.

Ils doivent être compilés dans un workspace ROS 2 avant ce projet. Le dossier
`install` de ce workspace sera appelé **underlay MFJA** dans la suite.

Les scripts le détectent automatiquement s'il se trouve à côté de ce dépôt
sous l'un de ces chemins :

```text
../hc10_ros2_ws/install
../mfja_3rd_floor_gz/install
```

Dans tous les autres cas, indiquer son chemin :

```bash
export MFJA_UNDERLAY=/chemin/vers/le/workspace_mfja/install
```

Pour conserver ce réglage dans les nouveaux terminaux :

```bash
echo 'export MFJA_UNDERLAY=/chemin/vers/le/workspace_mfja/install' >> ~/.bashrc
source ~/.bashrc
```

## Installation

Installer les dépendances principales :

```bash
sudo apt update
sudo apt install -y \
  ros-jazzy-moveit \
  ros-jazzy-ros-gz \
  ros-jazzy-ros-gz-sim \
  ros-jazzy-ros-gz-bridge \
  ros-jazzy-xacro \
  ros-jazzy-robot-state-publisher \
  ros-jazzy-joint-state-publisher \
  ros-jazzy-rviz2 \
  python3-rosdep
```

Initialiser `rosdep` une seule fois sur la machine si nécessaire :

```bash
sudo rosdep init
rosdep update
```

Cloner la branche de travail :

```bash
git clone --branch integration-avancement \
  https://github.com/TJeanm/Integration_rob.git
cd Integration_rob
```

Installer les dépendances ROS du dépôt et compiler :

```bash
source /opt/ros/jazzy/setup.bash
if [ -n "${MFJA_UNDERLAY:-}" ]; then source "$MFJA_UNDERLAY/setup.bash"; fi
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
```

Les scripts déterminent eux-mêmes le chemin du dépôt. Le projet peut être
cloné ailleurs que dans `~/Desktop` et utilisé par n'importe quel utilisateur.

## Lancement — quatre terminaux

Ouvrir quatre terminaux dans le dossier `Integration_rob`. Si
`MFJA_UNDERLAY` n'est pas enregistré dans `~/.bashrc`, l'exporter dans chaque
terminal avant la commande.

### Terminal 1 — Gazebo

```bash
./gazebo.sh
```

Attendre l'affichage de la Room 315, du HC10, du convoyeur et de la plateforme
mobile.

### Terminal 2 — perception RGB-D

```bash
./perception.sh
```

Ce nœud filtre le nuage de la caméra Room 315 et publie
`/hc10/collision_cloud` pour MoveIt.

### Terminal 3 — MoveIt 2 et RViz

```bash
./moveit_rviz.sh
```

Attendre que RViz affiche le robot et le nuage de points. MoveIt construit
alors l'OctoMap utilisée par OMPL pour les contrôles de collision.

### Terminal 4 — démonstration

```bash
./demo.sh
```

Au début de chaque cycle, le script vide l'ancienne OctoMap, attend sa
reconstruction depuis la caméra et vérifie que l'état initial du robot est
valide. Cela permet de relancer `demo.sh` plusieurs fois sans conserver les
voxels générés pendant le cycle précédent.

Le cycle est terminé lorsque le terminal affiche :

```text
CYCLE DE PINCE SIMULÉ ET TRAJECTOIRE ANTI-COLLISION TERMINÉS
```

## Validation sans mouvement

Pour calculer et vérifier le cycle sans envoyer les trajectoires au robot :

```bash
./validate_demo.sh
```

Cette commande contrôle notamment :

- la présence et la reconstruction de l'OctoMap ;
- les requêtes IK et leurs codes MoveIt ;
- la pose du TCP par cinématique directe ;
- l'orientation verticale de la pince ;
- la conservation de X/Y pendant les descentes ;
- les trajectoires OMPL vers A, B et la position initiale.

## Arrêt

Utiliser `Ctrl+C` dans l'ordre suivant : terminal 4, terminal 3, terminal 2,
puis terminal 1.

Chaque script ferme ses anciennes instances avant un nouveau lancement afin
d'éviter plusieurs serveurs Gazebo, MoveIt, RViz ou perception concurrents.

## Dépannage

### `mfja_3rd_floor_bringup` introuvable

Vérifier le chemin de l'underlay :

```bash
export MFJA_UNDERLAY=/chemin/vers/le/workspace_mfja/install
test -f "$MFJA_UNDERLAY/setup.bash" && echo "Underlay trouvé"
```

### Workspace non compilé

Depuis la racine du dépôt :

```bash
source /opt/ros/jazzy/setup.bash
if [ -n "${MFJA_UNDERLAY:-}" ]; then source "$MFJA_UNDERLAY/setup.bash"; fi
colcon build --symlink-install
```

### OctoMap vide

Vérifier que `perception.sh` est encore actif et que le nuage est publié :

```bash
source setup_env.sh
ros2 topic info /hc10/collision_cloud
```

Le nombre de publishers doit être au moins égal à 1.

### Gazebo affiche une fenêtre grise

Fermer le terminal Gazebo avec `Ctrl+C`, puis relancer :

```bash
./gazebo.sh
```

Le script supprime les anciennes instances qui pourraient publier le même
monde sur la même partition.

### La démonstration refuse de démarrer

Lancer d'abord la validation :

```bash
./validate_demo.sh
```

Le journal indique si l'échec vient d'une dépendance absente, de l'IK, d'une
collision avec l'OctoMap ou d'un trajet cartésien incomplet.

## Reconstruction après modification

```bash
source /opt/ros/jazzy/setup.bash
if [ -n "${MFJA_UNDERLAY:-}" ]; then source "$MFJA_UNDERLAY/setup.bash"; fi
colcon build --symlink-install
```

Les dossiers `build/`, `install/` et `log/` sont générés localement et ne sont
pas versionnés.
