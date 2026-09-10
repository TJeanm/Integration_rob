#!/usr/bin/env bash
# tool0 target in base_link: x y z (metres), roll pitch yaw (radians).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/demo.sh" --pose "$@"
