#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
export HC10_DRY_RUN=1
exec ./demo.sh
