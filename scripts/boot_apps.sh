#!/usr/bin/env bash
set -e
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  echo "用法: bash boot_apps.sh [--check]（在开发板发布目录运行）"
  echo "无参数: 启动 daemon 守护 Agent；--check: 仅检查依赖，不启动控制进程。"
  exit 0
fi
[[ $# == 0 || ( $# == 1 && "$1" == --check ) ]] || {
  echo "用法: bash boot_apps.sh [--check]" >&2; exit 2;
}
source "$(dirname -- "${BASH_SOURCE[0]}")/runtime_env.sh"
car_bin="$CAR_RELEASE_DIR"

if [[ "${1:-}" == --check ]]; then
  for executable in car_daemon keyboard_teleop web_teleop; do
    "$car_bin/$executable" --version
  done
  agent_prefix="$(ros2 pkg prefix micro_ros_agent)"
  agent_executable="$agent_prefix/lib/micro_ros_agent/micro_ros_agent"
  [[ -x "$agent_executable" ]] || exit 1
  if ldd "$agent_executable" 2>&1 | grep -q 'not found'; then
    echo "micro-ROS Agent has missing shared libraries" >&2
    exit 1
  fi
  case "${TRANSPORT:-udp4}" in
    udp4|serial) ;;
    *) echo "Invalid TRANSPORT" >&2; exit 1 ;;
  esac
  exit 0
fi

mkdir -p "$ROS_LOG_DIR"
exec "$car_bin/car_daemon" \
  --lock "${CAR_DAEMON_LOCK:-/run/tb6612-car.lock}" \
  -- /bin/bash "$CAR_RELEASE_DIR/agent.sh"
