#!/usr/bin/env bash
# 启动网页控制节点：浏览器访问本机 IP 即可下发 /cmd_vel，替代键盘控制。
# 只用于发布目录；源码工作区请直接运行 ros2 run tb6612_car_ros2 web_teleop。
# 用法：bash web_teleop.sh [--ros-args -p port:=8080]
set -e
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/runtime_env.sh"
# 监听地址、端口和令牌来自 car.conf 或环境变量，命令行参数可以覆盖。
# 字符串参数加引号，避免令牌里的特殊字符被当成 YAML 结构。
ros_args=(--ros-args -p "port:=${WEB_PORT:-8080}"
          -p "bind_address:=\"${WEB_BIND:-0.0.0.0}\"")
if [[ -n "${WEB_TOKEN:-}" ]]; then
  ros_args+=(-p "token:=\"${WEB_TOKEN}\"")
fi
exec ros2 run tb6612_car_ros2 web_teleop "${ros_args[@]}" "$@"
