#!/usr/bin/env bash
# ==============================================================================
# Installation complète et autonome pour Ubuntu 24.04 LTS (Noble Numbat)
# ROS 2 Jazzy, Gazebo Harmonic, MoveIt 2 et toutes les dépendances requises.
# ==============================================================================
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
nc='\033[0m'

info()  { echo -e "${green}[INFO]${nc} $*"; }
warn()  { echo -e "${yellow}[ATTENTION]${nc} $*"; }
error() { echo -e "${red}[ERREUR]${nc} $*" >&2; }

# 1. Vérification du système d'exploitation
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "noble" ]]; then
    warn "Ce script est optimisé pour Ubuntu 24.04 (noble). Système détecté: ${PRETTY_NAME:-inconnu} (${VERSION_CODENAME:-})."
    read -r -p "Continuer quand même ? [o/N] " response || true
    if [[ ! "$response" =~ ^([oOyY])$ ]]; then
      exit 1
    fi
  else
    info "Système Ubuntu 24.04 LTS (${VERSION_CODENAME}) validé."
  fi
else
  warn "/etc/os-release introuvable. Tentative d'installation standard..."
fi

# 2. Droits sudo
if (( EUID != 0 )); then
  if ! command -v sudo >/dev/null; then
    error "sudo est requis pour installer les paquets système."
    exit 1
  fi
  SUDO="sudo"
else
  SUDO=""
fi

info "Mise à jour de la liste des paquets de base..."
$SUDO apt-get update -q

info "Installation des prérequis système (curl, certificats, dépôts)..."
$SUDO apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common

# Activer le dépôt universe
info "Activation du dépôt Ubuntu universe..."
$SUDO add-apt-repository -y universe

# 3. Configuration du dépôt ROS 2 Jazzy
ros_repo_configured=0
if [[ -f /etc/apt/sources.list.d/ros2.list ]] || [[ -f /etc/apt/sources.list.d/ros2-latest.list ]]; then
  ros_repo_configured=1
fi

if (( ! ros_repo_configured )); then
  info "Ajout de la clé et du dépôt officiel ROS 2 Jazzy..."
  $SUDO install -d -m 0755 /usr/share/keyrings
  $SUDO curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg || {
      warn "Téléchargement direct de la clé ros.key échoué, tentative via le paquet ros2-apt-source..."
      tmp_deb=$(mktemp --suffix=.deb)
      tag=$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest 2>/dev/null \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "1.0.1")
      curl -fsSL "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${tag}/ros2-apt-source_${tag}.noble_all.deb" -o "$tmp_deb"
      $SUDO dpkg -i "$tmp_deb" || true
      rm -f "$tmp_deb"
    }

  if [[ -f /usr/share/keyrings/ros-archive-keyring.gpg ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu noble main" \
      | $SUDO tee /etc/apt/sources.list.d/ros2.list >/dev/null
  fi
  $SUDO apt-get update -q
fi

# 4. Installation des paquets ROS 2, Gazebo Harmonic, MoveIt 2 et outils de dev
info "Installation de ROS 2 Jazzy, MoveIt 2, Gazebo Harmonic et outils système..."
PACKAGES=(
  # Outils de compilation et de gestion
  build-essential
  cmake
  git
  mesa-utils
  ninja-build
  pkg-config
  python3-colcon-common-extensions
  python3-pip
  python3-pytest
  python3-rosdep
  python3-numpy
  python3-yaml
  python3-setuptools
  # ROS 2 Jazzy desktop & base
  ros-jazzy-desktop
  ros-jazzy-ros-base
  # Gazebo Harmonic + bridge ROS-Gz
  ros-jazzy-ros-gz
  ros-jazzy-ros-gz-sim
  ros-jazzy-ros-gz-bridge
  ros-jazzy-ros-gz-interfaces
  # Contrôle et cinématique
  ros-jazzy-gz-ros2-control
  ros-jazzy-ros2-controllers
  ros-jazzy-control-msgs
  ros-jazzy-trajectory-msgs
  # MoveIt 2 complet
  ros-jazzy-moveit
  ros-jazzy-moveit-configs-utils
  ros-jazzy-moveit-ros-move-group
  ros-jazzy-moveit-ros-visualization
  ros-jazzy-moveit-planners-ompl
  ros-jazzy-moveit-simple-controller-manager
  ros-jazzy-kdl-kinematics-plugin
  # Modélisation et perception
  ros-jazzy-robot-state-publisher
  ros-jazzy-joint-state-publisher
  ros-jazzy-rviz2
  ros-jazzy-xacro
  ros-jazzy-tf2-ros
  ros-jazzy-sensor-msgs-py
  ros-jazzy-cv-bridge
  # Génération d'interfaces
  ros-jazzy-rosidl-default-generators
  ros-jazzy-rosidl-default-runtime
)

$SUDO apt-get install -y "${PACKAGES[@]}"

# 5. Terminal graphique (gnome-terminal ou xterm)
if ! command -v gnome-terminal >/dev/null && ! command -v konsole >/dev/null && \
   ! command -v xfce4-terminal >/dev/null && ! command -v xterm >/dev/null; then
  info "Installation d'un émulateur de terminal graphique (gnome-terminal)..."
  $SUDO apt-get install -y gnome-terminal || $SUDO apt-get install -y xterm
fi

# 6. Initialisation de rosdep
info "Configuration et mise à jour de rosdep..."
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  $SUDO rosdep init || true
fi
rosdep update --rosdistro jazzy || warn "rosdep update a émis un avertissement (utilisation des listes locales)."

# 7. Sourcing dans ~/.bashrc si non présent
if [[ -f "$HOME/.bashrc" ]] && ! grep -q '/opt/ros/jazzy/setup.bash' "$HOME/.bashrc"; then
  echo "source /opt/ros/jazzy/setup.bash" >> "$HOME/.bashrc"
  info "Ajout du sourcing automatique de ROS 2 Jazzy dans ~/.bashrc"
fi

info "Installation terminée avec succès !"
info "Vous pouvez désormais lancer: ./auto_start.sh"
