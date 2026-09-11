# Intégration robotique — Yaskawa HC10, ROS 2 et Room 315

Ce dépôt présente une étude de faisabilité pour la génération de trajectoires
sans collision d'un bras industriel Yaskawa HC10. La cellule est simulée dans
Gazebo, la perception repose sur la caméra RGB-D de la Room 315 et MoveIt 2
calcule les trajectoires à partir de l'OctoMap affichée dans RViz.

La démonstration réalise le cycle suivant :

1. faire avancer un TIAGo jusqu'à sa pose de livraison devant le HC10 ;
2. reconstruire l'OctoMap avec le TIAGo et son plateau à quai ;
3. rejoindre un point A au-dessus du centre du plateau ;
4. descendre verticalement et fermer la pince comme si un objet était saisi ;
5. remonter, rejoindre un point B au-dessus du convoyeur puis déposer ;
6. revenir à la position initiale et faire repartir le TIAGo.

Le petit objet rouge posé sur le plateau est visuel. Aucun cube n'est attaché
artificiellement à la pince : l'ouverture et la fermeture sont simulées, comme
dans la version précédente de la démonstration.

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

TIAGo + plateau ──► arrivée à quai ──► cycle HC10 ──► départ
```

Les paquets ROS 2 du dépôt sont :

- `hc10_mfja_control_adapter` : adaptation des commandes MoveIt vers Gazebo ;
- `hc10_moveit_config` : URDF, SRDF, cinématique, OMPL, RViz et OctoMap ;
- `hc10_pick_place_demo` : perception, livraison TIAGo et cycle de démonstration.

## Dépendance Room 315

Le dépôt s'appuie sur les paquets du projet externe
[`mfja_3rd_floor_gz`](https://github.com/aip-primeca-occitanie/mfja_3rd_floor_gz/tree/INTERNSHIP-ALI-2026),
notamment `mfja_3rd_floor_bringup`, `mfja_robot_control_config` et
`mfja_3rd_floor_description`.

Ils doivent être compilés dans un workspace ROS 2 **séparé** de celui-ci. Le
dossier `install` de ce workspace sera appelé **underlay MFJA** dans la suite.

Room 315 n'est jamais compilé dans le workspace de ce dépôt : `colcon build` y
ignore les paquets `mfja_*` et `motoman_*`, afin que toutes les machines suivent
exactement le même chemin d'installation. Un éventuel clone déposé dans
`src/mfja_3rd_floor_gz` sert uniquement de source pour construire l'underlay.

Les scripts détectent l'underlay automatiquement sous l'un de ces chemins :

```text
.mfja_underlay                                   (lien symbolique automatique dans le projet)
~/.cache/integration_rob/mfja_underlay/install   (créé par auto_start.sh)
../mfja_3rd_floor_gz/install
../hc10_ros2_ws/install
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

## Installation depuis 0 sur Ubuntu 24.04 LTS

### Méthode 1 — Script d'installation tout-en-un (recommandé)

Sur une machine vierge avec Ubuntu 24.04, un seul script configure le dépôt officiel ROS 2 Jazzy, installe Gazebo Harmonic, MoveIt 2, les ponts ROS-Gazebo et toutes les dépendances :

```bash
git clone https://github.com/TJeanm/Integration_rob.git
cd Integration_rob
./install_ubuntu2404.sh
```

Ce script vérifie la distribution Noble, configure la clé officielle ROS 2, installe tous les paquets apt nécessaires, initialise `rosdep` et active `source /opt/ros/jazzy/setup.bash` dans `~/.bashrc`.

### Méthode 2 — Installation manuelle des paquets apt

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  cmake \
  git \
  mesa-utils \
  python3-colcon-common-extensions \
  python3-rosdep \
  python3-numpy \
  python3-yaml \
  python3-setuptools \
  ros-jazzy-desktop \
  ros-jazzy-ros-gz \
  ros-jazzy-ros-gz-sim \
  ros-jazzy-ros-gz-bridge \
  ros-jazzy-ros-gz-interfaces \
  ros-jazzy-gz-ros2-control \
  ros-jazzy-ros2-controllers \
  ros-jazzy-moveit \
  ros-jazzy-sensor-msgs-py \
  ros-jazzy-tf2-ros \
  ros-jazzy-xacro \
  ros-jazzy-robot-state-publisher \
  ros-jazzy-joint-state-publisher \
  ros-jazzy-rviz2 \
  gnome-terminal
```

Initialiser `rosdep` une seule fois sur la machine :

```bash
sudo rosdep init
rosdep update
```

### Compilation du projet

```bash
source /opt/ros/jazzy/setup.bash
if [ -n "${MFJA_UNDERLAY:-}" ]; then source "$MFJA_UNDERLAY/setup.bash"; fi
rosdep install --from-paths src --ignore-src -r -y --skip-keys "mfja_3rd_floor_bringup mfja_3rd_floor_description"
colcon build --symlink-install
```

Les scripts déterminent eux-mêmes le chemin du dépôt. Le projet peut être
cloné n'importe où et exécuté par n'importe quel utilisateur.

## Lancement — quatre terminaux

### Lancement entièrement automatique

La méthode la plus simple consiste à exécuter :

```bash
./auto_start.sh
```

Ce script recherche automatiquement ROS 2 et les paquets Room 315 dans le
dossier personnel. Il utilise un underlay déjà compilé lorsqu'il en trouve un.
Sinon, il recherche les sources MFJA, les compile automatiquement ou les clone
depuis GitHub si elles sont absentes, en se plaçant sur le commit validé avec ce
dépôt. Il installe les dépendances ROS des deux workspaces avec `rosdep`,
compile ce dépôt, puis ouvre les quatre terminaux dans le bon ordre.

Le script ne passe à l'étape suivante qu'après avoir reçu un nuage **contenant
réellement des points** (un `PointCloud2` vide est un message valide et ne prouve
rien), puis un nuage filtré, puis les services MoveIt. Le message d'erreur
distingue « aucun message » de « des messages sans point exploitable », ce qui
désigne directement l'étape responsable.

Variables utiles :

| Variable | Effet |
| --- | --- |
| `MFJA_UNDERLAY` | Chemin explicite de l'underlay Room 315 |
| `MFJA_COMMIT` | Commit Room 315 à utiliser ; vide = tête de branche |
| `AUTO_SKIP_ROSDEP=1` | Ne pas installer les dépendances automatiquement |
| `MIN_CAMERA_POINTS` | Points valides exigés côté caméra (défaut 100) |
| `CAMERA_TIMEOUT` | Délai d'attente de la caméra en secondes (défaut 120) |
| `HC10_SPAWN_TIMEOUT` | Délai d'attente du serveur Gazebo (défaut 120) |

Pour uniquement détecter les fichiers, installer les dépendances et compiler :

```bash
AUTO_SETUP_ONLY=1 ./auto_start.sh
```

Pour préparer Gazebo, la perception et RViz sans lancer le mouvement :

```bash
AUTO_RUN_DEMO=0 ./auto_start.sh
```

Pour arrêter complètement les quatre composants, y compris après un crash :

```bash
./stop_all.sh
```

### Lancement manuel

Ouvrir quatre terminaux dans le dossier `Integration_rob`. Si
`MFJA_UNDERLAY` n'est pas enregistré dans `~/.bashrc`, l'exporter dans chaque
terminal avant la commande.

### Terminal 1 — Gazebo

```bash
./gazebo.sh
```

Attendre l'affichage de la Room 315, du HC10, du convoyeur et du TIAGo. Le
TIAGo entre automatiquement dans la cellule avec son plateau, puis reste à
quai jusqu'à la fin du cycle HC10.

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
reconstruction depuis la caméra après l'arrivée du TIAGo et vérifie que l'état
initial du robot est valide. Cela permet de relancer `demo.sh` plusieurs fois
sans conserver les voxels générés pendant le cycle précédent.

Le cycle est terminé lorsque le terminal affiche :

```text
CYCLE DE PINCE SIMULÉ ET TRAJECTOIRE ANTI-COLLISION TERMINÉS
```

## Test de contournement d'un obstacle

Par défaut, `gazebo.sh` ajoute un mur orange sur la table, entre A et B. Cet
obstacle existe uniquement dans Gazebo : il est observé par la caméra RGB-D,
ajouté à l'OctoMap, puis pris en compte par OMPL. Il permet de vérifier dans
Gazebo et RViz que la trajectoire contourne un obstacle qui n'a pas été ajouté
manuellement à la PlanningScene.

Pour comparer avec la scène sans cet obstacle, lancer le terminal 1 ainsi :

```bash
HC10_TEST_OBSTACLE=0 ./gazebo.sh
```

Après chaque changement, relancer également `perception.sh` et
`moveit_rviz.sh` afin de reconstruire une OctoMap correspondant à la scène.

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

### `auto_start.sh` reste bloqué sur un nuage de points

`auto_start.sh` écrit un journal par terminal dans `.auto_start_logs/` :

```bash
tail -n 40 .auto_start_logs/gazebo.log
tail -n 40 .auto_start_logs/perception.log
```

Le message du nœud de perception indique la cause :

| Message | Cause |
| --- | --- |
| `Aucun message reçu sur /room_315/perception/right_rail_rgbd/points depuis Ns` | Gazebo n'est pas lancé, ou le pont RGB-D est absent |
| `aucun point fini` | Le capteur RGB-D ne rend rien (pas d'accélération 3D côté serveur Gazebo) |
| `aucun des N points ne passe le filtre spatial` | La caméra ne voit que le sol : les modèles n'ont pas été créés dans le monde |
| `ModuleNotFoundError` | `python3-numpy` ou `ros-jazzy-sensor-msgs-py` manquant |

Contrôles directs :

```bash
source setup_env.sh
ros2 topic echo /room_315/perception/right_rail_rgbd/points --no-arr --once
gz service -l | grep create
```

`width` et `height` doivent être différents de zéro, et le service
`/world/room_315_only/create` doit apparaître.

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
