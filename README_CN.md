# 树莓派5 ROS 2 控制代码

配套 ESP32-Motor 使用 ROS 2 Jazzy / micro-ROS Jazzy，通过 Wi-Fi UDP 8888 通信。

## 包含功能

- 启动串口 micro-ROS Agent；
- 启动 WiFi UDP micro-ROS Agent；
- 提供简单的 ROS 2 键盘遥控节点；
- 通过 `/cmd_vel` 向 ESP32-S3 发送速度命令。

该包不启动 EKF、SLAM、Nav2 和 robot_state_publisher，因为当前 ESP32 固件只提供开环 PWM 控制，没有发布 ROS 里程计或 IMU；电机自带编码器仅在 ESP32 串口中显示。启动这些模块只会产生错误或虚假位姿。

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

第一次运行必须把车轮架空。先按 `w` 短暂测试，再按空格停车。ESP32 固件自身还有 500 ms 命令超时和 Agent 断开停车保护，但仍建议准备可立即断开的电机电源。

## ESP32 Wi-Fi 适配说明

ESP32 连接 Wi-Fi 804，Agent 地址配置为 192.168.0.106:8888。两端需在可互通的局域网内；树莓派运行 `hostname -I` 确认地址。ESP32 通过 UDP micro-ROS 订阅 `/cmd_vel`（`geometry_msgs/msg/Twist`），节点为 `/tb6612_base_node`，ROS_DOMAIN_ID 默认为 0。当前 ESP32 固件没有启用 micro-ROS 串口传输，使用 `transport:=udp4`。

启动前在两个终端均设置：

```bash
source /opt/ros/jazzy/setup.bash
export ROS_DOMAIN_ID=0
source install/setup.bash
```

终端一运行 `ros2 launch tb6612_car_ros2 car_bringup.launch.py transport:=udp4 udp_port:=8888`，终端二运行 `ros2 run tb6612_car_ros2 keyboard_teleop`。入口已修正为 `tb6612_car_ros2.keyboard_teleop:main`，修改后需重新 colcon build 并 source 工作区。

键盘：w 前进、x 后退、a 左转、d 右转、s/空格停止。与 ESP32 本地串口快捷键不同。方向按键后以 10 Hz 重发，最后一次方向按键后默认 0.6 秒清零；按住方向键依靠终端按键重复持续行驶，可用 `--ros-args -p key_timeout:=0.8` 调整。Ctrl-C 发布零指令，节点异常退出则由 ESP32 的 500 ms 看门狗停车。

保持纯开环：`linear.x=0.15` 映射为两轮 PWM 80，`angular.z=0.8` 映射为左 -80、右 80；这是可调开环增益，不是测量或保证的 m/s、rad/s。无 PID、IMU、轮距依赖。ESP32 保留右轮反向修正。

检查：`ros2 topic info /cmd_vel -v` 应有 ESP32 订阅者。连接正常但不动时，在 ESP32 串口发 `status` 检查 `ros=connected` 和 PWM；发 `version` 应显示 `pwm-r3-wifi-jazzy`。
