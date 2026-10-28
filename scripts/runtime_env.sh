#!/usr/bin/env bash
# 发布目录环境。配置在版本目录外，升级时保留开发板的网络/串口设置。
# 由发布包中的其他脚本 source；CAR_CONFIG 可指定替代配置文件。
CAR_RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
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
# Agent 可位于独立工作区，配置非空时同时加载它的环境。
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
# ament 包内脚本可重定位；不加载构建机的工作区 setup.bash。
export AMENT_CURRENT_PREFIX="$car_prefix"
source "$car_setup" || return 1
unset AMENT_CURRENT_PREFIX car_prefix car_setup
