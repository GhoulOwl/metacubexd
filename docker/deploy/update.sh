#!/usr/bin/env bash
set -euo pipefail
deploy_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
compose=(docker compose --project-directory "$deploy_dir" -f "$deploy_dir/compose.yaml")
"${compose[@]}" config --quiet
"${compose[@]}" pull metacubexd
"${compose[@]}" up -d --no-deps --wait --wait-timeout 120 metacubexd
