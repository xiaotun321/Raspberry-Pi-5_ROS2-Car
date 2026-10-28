#!/usr/bin/env bash
# 按 car.conf 中的传输配置启动 Agent，由 car_daemon 调用，无需传参。
set -e
source "$(dirname -- "${BASH_SOURCE[0]}")/runtime_env.sh"
# 从当前 ROS 环境查找安装位置，不绑定 Agent 的构建目录。
agent_prefix="$(ros2 pkg prefix micro_ros_agent)"
agent_executable="$agent_prefix/lib/micro_ros_agent/micro_ros_agent"
if [[ ! -x "$agent_executable" ]]; then
  echo "Missing micro-ROS Agent executable: $agent_executable" >&2
  exit 1
fi
# exec 用 Agent 替换当前 Shell，让守护进程直接感知其退出状态。
case "${TRANSPORT:-udp4}" in
  udp4)
    exec "$agent_executable" udp4 --port "${UDP_PORT:-8888}"
    ;;
  serial)
    exec "$agent_executable" serial --dev "${SERIAL_PORT:-/dev/ttyACM0}" \
      --baudrate "${BAUDRATE:-921600}"
    ;;
  *)
    echo "Unsupported TRANSPORT: $TRANSPORT" >&2
    exit 2
    ;;
esac
