#!/usr/bin/env bash
CAR_RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -L)"
if [[ -f "${CAR_CONFIG:-/work/app/cfg/car.conf}" ]]; then
  source "${CAR_CONFIG:-/work/app/cfg/car.conf}" || return 1
fi
export ROS_DISTRO="${ROS_DISTRO:-jazzy}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
export ROS_LOG_DIR="${ROS_LOG_DIR:-/work/data/log/ros}"
if [[ ! -f "/opt/ros/$ROS_DISTRO/setup.bash" ]]; then
  echo "Missing /opt/ros/$ROS_DISTRO/setup.bash" >&2
  return 1
fi
source "/opt/ros/$ROS_DISTRO/setup.bash" || return 1
if [[ -n "${MICRO_ROS_AGENT_SETUP:-}" ]]; then
  if [[ ! -f "$MICRO_ROS_AGENT_SETUP" ]]; then
    echo "Missing Agent setup: $MICRO_ROS_AGENT_SETUP" >&2
    return 1
  fi
  source "$MICRO_ROS_AGENT_SETUP" || return 1
fi
car_prefix="$CAR_RELEASE_DIR/ros/tb6612_car_ros2"
car_setup="$car_prefix/share/tb6612_car_ros2/local_setup.bash"
if [[ ! -f "$car_setup" ]]; then
  echo "Missing installed package: $car_setup" >&2
  return 1
fi
export AMENT_CURRENT_PREFIX="$car_prefix"
source "$car_setup" || return 1
unset AMENT_CURRENT_PREFIX car_prefix car_setup
cd "$CAR_RELEASE_DIR" || return 1
