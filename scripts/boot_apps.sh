#!/usr/bin/env bash
# 发布版入口：无参数时启动守护进程；--check 仅检查本地运行依赖。
# 通常由 systemd 调用，升级器在切换版本前调用 --check。
set -e
source "$(dirname -- "${BASH_SOURCE[0]}")/runtime_env.sh"
car_bin="$CAR_RELEASE_DIR/ros/tb6612_car_ros2/lib/tb6612_car_ros2"

# 升级激活前检查动态库、可执行架构和 Agent 依赖，不启动电机控制。
if [[ "${1:-}" == --check ]]; then
  "$car_bin/car_daemon" --version
  "$car_bin/keyboard_teleop" --version
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
# 只守护不需要交互终端的 Agent；keyboard_teleop 通过 carctl teleop 启动。
exec "$car_bin/car_daemon" \
  --lock "${CAR_DAEMON_LOCK:-/run/tb6612-car.lock}" \
  -- /bin/bash "$CAR_RELEASE_DIR/agent.sh"
