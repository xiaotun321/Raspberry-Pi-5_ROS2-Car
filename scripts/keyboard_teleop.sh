#!/usr/bin/env bash
set -e
source "$(dirname -- "${BASH_SOURCE[0]}")/ros_env.sh"
exec ros2 run tb6612_car_ros2 keyboard_teleop "$@"
