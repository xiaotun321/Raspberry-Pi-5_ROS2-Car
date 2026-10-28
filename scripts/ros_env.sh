#!/usr/bin/env bash
# Source this file to keep the environment in the caller's shell.
car_workspace="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
car_ros_setup="/opt/ros/${ROS_DISTRO:-jazzy}/setup.bash"
if [[ ! -f "$car_ros_setup" || ! -f "$car_workspace/install/setup.bash" ]]; then
  echo "Missing ROS setup or workspace install/setup.bash; build the workspace first." >&2
  return 1
fi
source "$car_ros_setup" || return 1
source "$car_workspace/install/setup.bash" || return 1
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
unset car_workspace car_ros_setup
