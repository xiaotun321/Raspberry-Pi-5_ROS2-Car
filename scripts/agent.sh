#!/usr/bin/env bash
set -e
source "$(dirname -- "${BASH_SOURCE[0]}")/runtime_env.sh"
agent_prefix="$(ros2 pkg prefix micro_ros_agent)"
agent_executable="$agent_prefix/lib/micro_ros_agent/micro_ros_agent"
if [[ ! -x "$agent_executable" ]]; then
  echo "Missing micro-ROS Agent executable: $agent_executable" >&2
  exit 1
fi
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
