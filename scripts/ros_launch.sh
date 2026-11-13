#!/usr/bin/env bash
set -e
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -L)"
source "$script_dir/runtime_env.sh"
exec ros2 launch tb6612_car_ros2 car_bringup.launch.py "$@"
