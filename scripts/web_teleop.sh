#!/usr/bin/env bash
# 启动网页控制节点：浏览器访问本机 IP 即可下发 /cmd_vel，替代键盘控制。
# 用法：bash scripts/web_teleop.sh [--ros-args -p port:=8080]
set -e
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# 有版本清单表示正在运行发布包，否则加载源码工作区环境。
if [[ -f "$script_dir/version.json" ]]; then
  source "$script_dir/runtime_env.sh"
else
  source "$script_dir/ros_env.sh"
fi
# 监听地址、端口和令牌来自 car.conf 或环境变量，命令行参数可以覆盖。
# 字符串参数加引号，避免令牌里的特殊字符被当成 YAML 结构。
ros_args=(--ros-args -p "port:=${WEB_PORT:-8080}"
          -p "bind_address:=\"${WEB_BIND:-0.0.0.0}\"")
if [[ -n "${WEB_TOKEN:-}" ]]; then
  ros_args+=(-p "token:=\"${WEB_TOKEN}\"")
fi
exec ros2 run tb6612_car_ros2 web_teleop "${ros_args[@]}" "$@"
