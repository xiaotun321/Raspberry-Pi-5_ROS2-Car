#!/usr/bin/env bash
# 在交互终端启动键盘控制，所有参数原样传给 ROS 节点。
# 只用于发布目录；源码工作区请直接运行 ros2 run tb6612_car_ros2 keyboard_teleop。
# 用法：bash keyboard_teleop.sh [--ros-args -p key_timeout:=0.8]
set -e
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/runtime_env.sh"
exec ros2 run tb6612_car_ros2 keyboard_teleop "$@"
