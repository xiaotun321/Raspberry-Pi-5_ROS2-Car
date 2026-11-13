#!/usr/bin/env bash
set -e
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -L)"
source "$script_dir/runtime_env.sh"
ros_args=(--ros-args -p "port:=${WEB_PORT:-8080}"
          -p "bind_address:=\"${WEB_BIND:-0.0.0.0}\"")
if [[ -n "${WEB_TOKEN:-}" ]]; then
  ros_args+=(-p "token:=\"${WEB_TOKEN}\"")
fi
exec "$CAR_RELEASE_DIR/web_teleop" "${ros_args[@]}" "$@"
