#!/usr/bin/env bash
# 一键拉起 Agent、键盘控制和网页控制，全部参数原样传给 launch 文件。
# 只用于发布目录；源码工作区请先 source install/setup.bash 再执行 ros2 launch。
# 用法：bash ros_launch.sh [启动参数]
#   transport:=udp4|serial   Agent 传输方式，默认 udp4
#   agent:=true|false         是否在本机启动 Agent，默认 true
#   keyboard:=true|false      是否启动键盘控制，需要控制终端，默认 false
#   web:=true|false           是否启动网页控制，默认 true
#   web_port:=8080            网页控制端口
#   web_token:=secret         网页控制令牌，非空时命令需要携带 ?token=
set -e
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/runtime_env.sh"
exec ros2 launch tb6612_car_ros2 car_bringup.launch.py "$@"
