#!/usr/bin/env bash
# 在交互终端启动键盘控制，所有参数原样传给 ROS 节点。
# 用法：bash scripts/keyboard_teleop.sh [--ros-args -p key_timeout:=0.8]
set -e
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# 有版本清单表示正在运行发布包，否则加载源码工作区环境。
if [[ -f "$script_dir/version.json" ]]; then
  source "$script_dir/runtime_env.sh"
else
  source "$script_dir/ros_env.sh"
fi
exec ros2 run tb6612_car_ros2 keyboard_teleop "$@"
