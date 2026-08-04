# 树莓派5 ROS 2 控制代码

从电脑复制到树莓派、创建工作区、串口权限、构建和启动的逐步操作，请阅读 [树莓派部署操作说明.md](树莓派部署操作说明.md)。

## 包含功能

- 启动串口 micro-ROS Agent；
- 启动 WiFi UDP micro-ROS Agent；
- 提供简单的 ROS 2 键盘遥控节点；
- 通过 `/cmd_vel` 向 ESP32-S3 发送速度命令。

该包不启动 EKF、SLAM、Nav2 和 robot_state_publisher，因为当前电机没有编码器、设备也没有提供真实里程计和 IMU。启动这些模块只会产生错误或虚假位姿。

## 构建

将整个 `tb6612_car_ros2` 文件夹放到 ROS 2 工作区的 `src` 下。例如当前仓库内直接构建：

```bash
cd pi-ros2
source /opt/ros/$ROS_DISTRO/setup.bash
colcon build --packages-select tb6612_car_ros2 --symlink-install
source install/setup.bash
```

## 运行

终端 1 启动 Agent：

```bash
source /opt/ros/$ROS_DISTRO/setup.bash
source pi-ros2/install/setup.bash
ros2 launch tb6612_car_ros2 car_bringup.launch.py \
  transport:=udp4 udp_port:=8888
```

WiFi 模式下，ESP32 固件里的 `MICRO_ROS_AGENT_IP` 必须是树莓派连接同一个 WiFi 后的 IP。树莓派可用 `hostname -I` 查看。

终端 2 启动键盘控制：

```bash
source /opt/ros/$ROS_DISTRO/setup.bash
source pi-ros2/install/setup.bash
ros2 run tb6612_car_ros2 keyboard_teleop
```

确认连接：

```bash
ros2 node list
ros2 topic info /cmd_vel -v
```

应能看到 `/tb6612_base_node` 和键盘控制节点。micro-ROS Agent 本身不一定作为普通 ROS 2 节点出现在节点列表中。

## 安全说明

第一次运行必须把车轮架空。先按 `w` 短暂测试，再按空格停车。ESP32 固件自身还有 200 ms 命令超时和 Agent 断开停车保护，但仍建议准备可立即断开的电机电源。
