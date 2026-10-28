#!/usr/bin/env bash
# 开发调试入口：加载工作区环境并通过 launch 启动 Agent。
# 用法：bash scripts/ros_launch.sh transport:=udp4 udp_port:=8888
# 发布版的开机守护启动由 boot_apps.sh 负责。
set -e
source "$(dirname -- "${BASH_SOURCE[0]}")/ros_env.sh"
exec ros2 launch tb6612_car_ros2 car_bringup.launch.py "$@"
