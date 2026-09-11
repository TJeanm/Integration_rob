#!/usr/bin/env bash
set -e
repo_dir="$(cd "$(dirname "$0")" && pwd)"
export RECORD_VIDEO=1
exec "$repo_dir/auto_start.sh" "$@"
