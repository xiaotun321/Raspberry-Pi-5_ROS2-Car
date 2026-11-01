#!/usr/bin/env bash
# 加载源码工作区的 ROS 环境；默认 Jazzy、ROS_DOMAIN_ID=0。
# 用法：source scripts/ros_env.sh；用 source 才能保留当前终端的环境变量。
car_workspace="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
car_ros_setup="/opt/ros/${ROS_DISTRO:-jazzy}/setup.bash"
if [[ ! -f "$car_ros_setup" ]]; then
  echo "Missing ROS setup: $car_ros_setup" >&2
  return 1
fi
source "$car_ros_setup" || return 1

# Agent 可能安装在独立工作区，与发布版 runtime_env.sh 使用同一个配置项。
# 未显式配置时，尝试 micro_ros_setup 文档里的两个常见安装位置。
car_agent_setup="${MICRO_ROS_AGENT_SETUP:-}"
if [[ -z "$car_agent_setup" ]]; then
  for car_agent_candidate in "$HOME/microros_ws/install/setup.bash" \
                            "/opt/microros_ws/install/setup.bash"; do
    if [[ -f "$car_agent_candidate" ]]; then
      car_agent_setup="$car_agent_candidate"
      break
    fi
  done
fi
if [[ -n "$car_agent_setup" ]]; then
  if [[ ! -f "$car_agent_setup" ]]; then
    echo "Missing Agent setup: $car_agent_setup" >&2
    return 1
  fi
  source "$car_agent_setup" || return 1
fi

# 优先加载工作区环境；缺少顶层脚本时，兼容单包安装的环境脚本。
# 单包回退不会自动加载其他工作区，micro-ROS Agent 环境需事先加载。
car_package_setup="share/tb6612_car_ros2/local_setup.bash"
if [[ -f "$car_workspace/install/setup.bash" ]]; then
  source "$car_workspace/install/setup.bash" || return 1
elif [[ -f "$car_workspace/install/local_setup.bash" ]]; then
  source "$car_workspace/install/local_setup.bash" || return 1
elif [[ -f "$car_workspace/install/tb6612_car_ros2/$car_package_setup" ]]; then
  source "$car_workspace/install/tb6612_car_ros2/$car_package_setup" || return 1
elif [[ -f "$car_workspace/install/$car_package_setup" ]]; then
  source "$car_workspace/install/$car_package_setup" || return 1
else
  echo "Missing workspace/package environment scripts; build the workspace first." >&2
  return 1
fi
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
unset car_workspace car_ros_setup car_package_setup car_agent_setup car_agent_candidate
