#!/usr/bin/env bash
# 开发板首次安装 Agent；已有可用 Agent 时无需执行。
# 前提：已安装 ROS 2 Jazzy。本脚本需要联网，会安装编译依赖。
# 用法：sudo bash scripts/install_agent.sh；安装位置为 /opt/microros_ws。
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
# 补齐构建工具与 rosdep 数据，再准备 Jazzy 分支的安装工具。
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
# 官方工具负责拉取 Agent 源码并编译；最后验证 ROS 能否找到该包。
ros2 run micro_ros_setup create_agent_ws.sh
ros2 run micro_ros_setup build_agent.sh
source install/local_setup.bash
ros2 pkg prefix micro_ros_agent
echo "Agent setup: $workspace/install/local_setup.bash"
