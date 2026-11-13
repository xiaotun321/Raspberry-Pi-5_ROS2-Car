#!/usr/bin/env bash
set -e
[[ "$EUID" == 0 ]] || { echo "Run with sudo" >&2; exit 1; }
workspace="/opt/microros_ws"
source /opt/ros/jazzy/setup.bash
if [[ -f "$workspace/install/local_setup.bash" ]]; then
  source "$workspace/install/local_setup.bash"
  if ros2 pkg prefix micro_ros_agent >/dev/null 2>&1; then
    echo "Agent already installed: $workspace/install/local_setup.bash"
    exit 0
  fi
fi
apt-get update
apt-get install -y git build-essential cmake python3-colcon-common-extensions \
  python3-rosdep python3-vcstool
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  rosdep init
fi
rosdep update --rosdistro jazzy
mkdir -p "$workspace/src"
cd "$workspace"
if [[ ! -d src/micro_ros_setup ]]; then
  git clone -b jazzy https://github.com/micro-ROS/micro_ros_setup.git src/micro_ros_setup
fi
rosdep install --from-paths src --ignore-src -y
/usr/bin/colcon build --packages-select micro_ros_setup
source install/local_setup.bash
ros2 run micro_ros_setup create_agent_ws.sh
ros2 run micro_ros_setup build_agent.sh
source install/local_setup.bash
ros2 pkg prefix micro_ros_agent
echo "Agent setup: $workspace/install/local_setup.bash"
