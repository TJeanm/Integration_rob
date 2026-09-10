#!/usr/bin/env bash
set -e
script_dir=$(cd "$(dirname "$0")" && pwd)
export HC10_DRY_RUN=1
exec "$script_dir/demo.sh"
