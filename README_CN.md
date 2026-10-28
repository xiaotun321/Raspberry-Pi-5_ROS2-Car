# 树莓派 5 ROS 2 小车控制（C++）

配套 ESP32-S3 TB6612 开环电机固件，目标环境为树莓派 Linux、ROS 2 Jazzy
和 micro-ROS Jazzy。通过 `/cmd_vel`（`geometry_msgs/msg/Twist`）发送指令，
默认使用 Wi-Fi UDP 8888。键盘节点使用 C++17 / rclcpp。

## 代码组织

参考 hs411 的公共头文件、独立进程入口、ament_cmake 包及运行脚本组织方式：

```text
src/
├── common/
│   ├── teleop_control.hpp        # 按键、速度限制、单调时钟超时控制
│   └── terminal.hpp              # POSIX 终端读取与自动恢复
└── tb6612_car_ros2/
    ├── CMakeLists.txt
    ├── package.xml
    ├── src/proc_keyboard_teleop.cpp
    ├── launch/car_bringup.launch.py
    └── test/                    # 无 ROS 依赖的 C++ 控制逻辑测试
scripts/
├── ros_env.sh
├── ros_launch.sh
└── keyboard_teleop.sh
```

`common` 为 CMake INTERFACE 目标，进程编译为 `keyboard_teleop`，安装至
`lib/tb6612_car_ros2`，保持原有运行命令。launch Python 文件只负责
启动 Agent，业务节点已改为 C++。工作区由 colcon 发现包，无需根目录 CMakeLists.txt。

## 构建

在已安装 ROS 2 Jazzy、colcon 和 rosdep 的 Linux 主机执行。
`micro_ros_agent` 是启动 Agent 所需的运行时依赖，不参与键盘节点的 C++ 编译。
若 rosdep 无法解析此名称，先跳过该项，按下节单独安装 Agent；不要删除
`package.xml` 中的运行时依赖声明。

```bash
cd Raspberry-Pi-5_ROS2-Car
source /opt/ros/jazzy/setup.bash
rosdep install --from-paths src --ignore-src --skip-keys micro_ros_agent -y
colcon build --packages-select tb6612_car_ros2 --symlink-install && source scripts/ros_env.sh
```

保留整个仓库的 `src/common` 和功能包目录。由旧 Python 包升级时，请先清理
旧工作区生成的 `build/tb6612_car_ros2`、`install/tb6612_car_ros2` 后重新构建，
在新终端加载环境，避免继续运行旧 Python 入口。如果使用 merged install，
建议使用全新的工作区构建目录和安装目录。

### 安装 micro-ROS Agent（Jazzy）

先执行 `ros2 pkg prefix micro_ros_agent`。如果能找到包，可直接使用；
如果此前已在其他工作区安装，需要先 source 那个工作区的 `install/setup.bash`。
`rosdep --skip-keys` 只跳过依赖解析，不会安装 Agent。

尚未安装时，参考 [micro_ros_setup 官方 Jazzy 说明](https://github.com/micro-ROS/micro_ros_setup/tree/jazzy#building-micro-ros-agent)，
在独立工作区构建（以下目录用于首次安装）：

```bash
source /opt/ros/jazzy/setup.bash
mkdir -p ~/microros_ws/src
cd ~/microros_ws
git clone -b jazzy https://github.com/micro-ROS/micro_ros_setup.git src/micro_ros_setup
rosdep update
rosdep install --from-paths src --ignore-src -y
colcon build --packages-select micro_ros_setup && source install/local_setup.bash
ros2 run micro_ros_setup create_agent_ws.sh
ros2 run micro_ros_setup build_agent.sh && source install/local_setup.bash
ros2 pkg prefix micro_ros_agent
```

每一步成功后再执行下一步。启动 Agent 的新终端加载两个工作区：

```bash
source /opt/ros/jazzy/setup.bash
source ~/microros_ws/install/setup.bash
cd ~/Projects/Raspberry-Pi-5_ROS2-Car
source install/local_setup.bash
bash scripts/ros_launch.sh transport:=udp4 udp_port:=8888
```

### 构建错误排查

若出现 `target_link_libraries` 的 keyword/plain 混用错误，确认代码为：

```cmake
target_link_libraries(keyboard_teleop PRIVATE common)
ament_target_dependencies(keyboard_teleop PUBLIC rclcpp geometry_msgs)
```

Jazzy 的 `ament_target_dependencies` 需要显式 `PUBLIC` 才会在内部链接调用中
使用关键字形式。更新后重新运行 colcon 即可；必要时添加 `--cmake-clean-cache`。
只有构建成功后才加载环境。若已有 `Finished <<< tb6612_car_ros2`，但缺少
`install/setup.bash`，应排查 colcon 的环境脚本生成，而不是重新修改 C++ 代码。
包内脚本与工作区顶层脚本由不同层负责，包内脚本存在不代表顶层脚本一定已生成。

可先加载日志中已经安装的包内环境（默认隔离安装布局）：

```bash
source /opt/ros/jazzy/setup.bash
source install/tb6612_car_ros2/share/tb6612_car_ros2/local_setup.bash
ros2 pkg prefix tb6612_car_ros2
ros2 run tb6612_car_ros2 keyboard_teleop
```

`scripts/ros_env.sh` 也支持这种回退，以及 merged install 的包内脚本。
单包回退不负责加载 micro-ROS Agent 所在的其他工作区。

顶层脚本缺失可能是 colcon Bash 扩展未安装、未加载或混用了不同安装来源。
Ubuntu apt 安装方式可先补齐官方推荐的常用扩展，再用系统 colcon 构建：

```bash
sudo apt update
sudo apt install python3-colcon-common-extensions python3-colcon-bash
source /opt/ros/jazzy/setup.bash
/usr/bin/colcon build --packages-select tb6612_car_ros2 --symlink-install
ls -l install/setup.bash install/local_setup.bash
```

若仍缺失，检查 `type -a colcon`、`/usr/bin/colcon extensions` 和
`printenv COLCON_EXTENSION_BLOCKLIST`，以及 `log/latest_build/logger_all.log` 中的
扩展加载错误。此时无需删除已编译成功的可执行文件。

## 运行

终端 1 启动 Agent：

```bash
bash scripts/ros_launch.sh transport:=udp4 udp_port:=8888
```

终端 2 启动键盘控制（需要交互式终端）：

```bash
bash scripts/keyboard_teleop.sh
# 可选：方向按键超时时间，合法范围 0 < key_timeout <= 5 秒
bash scripts/keyboard_teleop.sh --ros-args -p key_timeout:=0.8
```

脚本默认 ROS_DISTRO=jazzy、ROS_DOMAIN_ID=0，保留已设置的值。也可直接运行：

```bash
source scripts/ros_env.sh
ros2 launch tb6612_car_ros2 car_bringup.launch.py transport:=udp4 udp_port:=8888
# 在另一个加载相同环境的终端执行
ros2 run tb6612_car_ros2 keyboard_teleop
```

串口启动配置仍保留，但只有 ESP32 固件启用了串口 micro-ROS 传输才能使用：

```bash
bash scripts/ros_launch.sh transport:=serial serial_port:=/dev/ttyACM0 baudrate:=921600
```

ESP32 的 `MICRO_ROS_AGENT_IP` 应配置为树莓派在同一局域网的地址，使用
`hostname -I` 查看；端口和 ROS_DOMAIN_ID 也必须与两端配置一致。

## 控制行为

| 按键 | 行为 |
| --- | --- |
| w / x | 前进 / 后退 |
| a / d | 左转 / 右转 |
| s / 空格 | 立即发送零指令 |
| q / e | 线速度指令增减 0.02，范围 0.02–0.50 |
| z / c | 角速度指令增减 0.1，范围 0.1–2.5 |
| Ctrl-C | 发送零指令并退出、恢复终端 |

默认线速度指令 0.15、角速度指令 0.8。方向键立即发送指令，并以 10 Hz
刷新；最后一次方向键后默认 0.6 秒清零。按住按键依赖终端的按键重复。
调速键在下一次方向键时生效，不延长运动超时；其他按键也不延长超时。
超时使用单调时钟，不受 ROS 仿真时间或系统时间调整影响。

SIGINT、SIGTERM、输入断开和可捕获异常退出时会尝试发送零指令并恢复终端。
SIGKILL、断电、通信中断无法保证发送停车消息，需要 ESP32 固件的命令看门狗兜底。
原配固件有 500 ms 命令超时及 Agent 断开停车保护；首次测试请架空车轮。

速度为开环控制量，不是实测或保证的 m/s、rad/s。原配固件将 `linear.x=0.15`
映射为两轮 PWM 80，`angular.z=0.8` 映射为左 -80、右 80，并保留右轮方向修正。
本项目不新增 PID、里程计、IMU、EKF、SLAM、Nav2 或 robot_state_publisher。

## 验证

### C++ 静态检查

根目录 `.clang-format` 负责缩进、换行等排版，`.clang-tidy` 配置 C++ 静态检查，
用于发现潜在错误、不必要的复制和可读性问题。配置参考 hs411 的分类方式，
选取当前项目适用的规则并提供中文注释。静态检查不能代替编译、测试和实车验证。

安装 `clang-tidy` 后，可在构建时启用检查（默认关闭，不自动修改代码）：

```bash
colcon build --packages-select tb6612_car_ros2 --cmake-args -DENABLE_CLANG_TIDY=ON
```

也可在正常构建完成后，使用包构建目录内生成的 `compile_commands.json` 手动检查：

```bash
clang-tidy -p build/tb6612_car_ros2 src/tb6612_car_ros2/src/proc_keyboard_teleop.cpp
```

检查 ROS 节点需要在具有 ROS 2 和 POSIX 头文件的 Linux 环境中进行。
关闭构建时检查可重新配置 `-DENABLE_CLANG_TIDY=OFF`。

### 控制逻辑与实车验证

```bash
colcon test --packages-select tb6612_car_ros2 --event-handlers console_direct+
colcon test-result --verbose
```

纯控制逻辑可在安装 C++17 编译器和 CMake 的主机独立测试：

```bash
cmake -S src/tb6612_car_ros2/test -B build/control-test
cmake --build build/control-test --config Release
ctest --test-dir build/control-test -C Release --output-on-failure
```

连接树莓派和 ESP32 后检查：

```bash
ros2 node list
ros2 topic info /cmd_vel -v
ros2 topic echo /cmd_vel
ros2 topic hz /cmd_vel
```

应出现 `/tb6612_keyboard_teleop` 和固件节点 `/tb6612_base_node`，且 `/cmd_vel`
有 ESP32 订阅者。Agent 自身不一定作为普通 ROS 节点显示。检查四个方向、停止键、
超时清零和 Ctrl-C 最后一条零指令；再验证串口模式（需匹配固件）。
连接正常但电机不动时，可在原配 ESP32 串口输入 `status` 查看 `ros=connected`
和 PWM，输入 `version` 检查固件版本。
