# 树莓派 5 ROS 2 小车控制（C++）

配套 ESP32-S3 TB6612 开环电机固件，目标环境为树莓派 Linux、ROS 2 Jazzy
和 micro-ROS Jazzy。通过 `/cmd_vel`（`geometry_msgs/msg/Twist`）发送指令，
默认使用 Wi-Fi UDP 8888。键盘和网页控制节点使用 C++17 / rclcpp。

构建、打包、部署脚本的最短操作步骤见 [脚本使用说明](scripts/README.md)。

提交信息格式为 `<类型>#<任务号>: <说明>`，由 `.githooks/commit-msg` 强制检查：

```text
feat  新增功能        fix   修复问题        docs  文档修改
refactor 重构         test  测试相关        perf  性能优化
build 构建配置        ci   CI 配置         chore 其他维护
```

## 目录与构建

```text
src/                       # 功能源码
cmake/                     # ARM64 交叉编译配置
version/autogen.sh         # 测试、编译、打包
version/vergen.sh          # 复用 target/ 重新打包
version/cross.conf         # 工具链与 sysroot 路径
version/tools/             # 包校验、包头和 sysroot 链接工具
version/update.py          # 板端更新器
scripts/                   # 安装、部署和运行
target/                    # 最近一次编译产物及 version.json
version/out/               # .bin、.bivi 和首次安装包
version/tmp/               # 构建日志和打包暂存文件
```

发布构建：

```bash
bash version/autogen.sh 1.0.0 arm64
```

自动执行主机测试、编译、strip 和打包。x86_64 主机编译 ARM64 时读取
`version/cross.conf`；在树莓派上原生编译无需交叉配置。所有发布包在
`version/out/`，根目录开发工作区不会被清空。完整安装与部署步骤见
[脚本使用说明](scripts/README.md)。

开发调试：

```bash
source /opt/ros/jazzy/setup.bash
colcon build --packages-select tb6612_car_ros2
source install/setup.bash
```

`micro_ros_agent` 是运行依赖，不参与应用编译。板端已有 Agent 时加载其环境；
没有时可执行 `sudo bash scripts/install_agent.sh` 安装到 `/opt/microros_ws`。

## 运行

开发板上由 systemd 拉起 `car_daemon`，它再守护 micro-ROS Agent；服务随开机
自启，升级重启后自动运行新版本。日常操作用 `carctl`：

```bash
carctl status                 # 服务状态
carctl version                # 当前版本
carctl logs                   # 跟踪 daemon/Agent 日志
carctl teleop                 # 键盘控制（需要交互式终端）
carctl web                    # 网页控制节点
```

键盘控制需要终端按键，网页控制不需要终端：

```bash
carctl teleop
# 可选：方向按键超时时间，合法范围 0 < key_timeout <= 5 秒
carctl teleop --ros-args -p key_timeout:=0.8
```

### 一键拉起整套进程

`carctl bringup` 在前台启动 launch 文件，由它统一编排 Agent、键盘控制和网页控制：

```bash
carctl bringup                                  # Agent(UDP) + 网页控制
carctl bringup transport:=serial                # 串口 Agent
carctl bringup keyboard:=true web:=false        # 键盘控制（需要控制终端）
carctl bringup web_port:=8081 web_token:=secret # 网页控制改端口并加令牌
```

参数与 launch 文件一致，完整说明见 `ros2 launch tb6612_car_ros2
car_bringup.launch.py --show-args`。键盘控制和网页控制发布同一个 `/cmd_vel`，
同时打开会互相覆盖指令，默认只开网页控制。

键盘节点从 `/dev/tty` 读取按键，因此在 `ros2 launch` 下也能用；没有控制终端时
（比如 systemd 服务里）会直接退出并提示需要交互式终端。

`scripts/keyboard_teleop.sh` 和 `scripts/web_teleop.sh` 只用于发布目录；源码
工作区里直接运行节点即可：

```bash
source /opt/ros/jazzy/setup.bash && source install/setup.bash
ros2 run tb6612_car_ros2 keyboard_teleop
```

串口传输仍保留，但只有 ESP32 固件启用了串口 micro-ROS 传输才能使用；传输方式
由 `/work/app/cfg/car.conf` 的 `TRANSPORT` 决定（`udp4` 或 `serial`）。

ESP32 的 `MICRO_ROS_AGENT_IP` 应配置为树莓派在同一局域网的地址，使用
`hostname -I` 查看；端口和 ROS_DOMAIN_ID 也必须与两端配置一致。

### 网页控制

网页控制节点提供 HTTP 接口，浏览器访问树莓派 IP 即可代替键盘操作小车：

```bash
carctl web
# 浏览器打开 http://<树莓派 IP>:8080/
# 可选：改端口、监听地址或令牌
carctl web --ros-args -p port:=8081 -p bind_address:=0.0.0.0
```

页面内嵌在可执行文件中，不依赖外部静态资源，断网的局域网也能直接打开。
按住方向按钮持续下发指令，松开立即停车；也支持键盘 w/a/s/d/x 和空格。
网页与键盘控制共用同一个 `/cmd_vel`，**不要同时使用**，否则两路指令会互相覆盖。

网页节点只负责把界面操作转成 `/cmd_vel` 上的 Twist，不关心树莓派到 ESP32
的物理链路：串口、Wi-Fi 或蓝牙都可以，只要 Pi 侧有组件把 `/cmd_vel`
转发给 ESP32（micro-ROS Agent 的传输，或蓝牙桥接节点），网页指令就能到达电机。

| 接口 | 方法 | 说明 |
| --- | --- | --- |
| `/` | GET | 返回控制页面 |
| `/cmd` | POST | 正文 `linear=0.15&angular=0`，也接受 JSON |
| `/cmd` | GET | 查询参数 `?linear=0.15&angular=0` |
| `/stop` | POST | 立即停车 |
| `/state` | GET | 当前指令 JSON |

发布版可以用 `carctl web` 前台启动，或用可选的 systemd 服务常驻：

```bash
sudo systemctl enable --now tb6612-car-web.service
```

监听地址、端口和令牌在 `car.conf` 中配置（`WEB_BIND`、`WEB_PORT`、`WEB_TOKEN`）。
`WEB_TOKEN` 非空时，命令必须携带令牌，页面地址写作
`http://<树莓派 IP>:8080/?token=<令牌>`。该接口没有身份认证，等同于把
小车遥控权交给整个局域网，请只在可信网络中使用。

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

网页控制复用同一套限幅和超时：网页下发的绝对速度按线速度 ±0.50、
角速度 ±2.5 裁剪，非法数值被拒绝；停止后默认 0.6 秒清零，浏览器关闭、
网络中断或页面失去焦点都会停车。网页节点以 20 Hz 刷新 `/cmd_vel`。

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

网页控制另需检查：浏览器打开后状态显示"就绪"，按住方向键时
`ros2 topic echo /cmd_vel` 出现对应速度，松开后 0.6 秒内回到零。
命令行自检：

```bash
curl -s http://127.0.0.1:8080/state
curl -s -X POST -d "linear=0&angular=0" http://127.0.0.1:8080/cmd
```

## 发布与开机运行

构建、首次安装、上传和日常运行统一见 [脚本使用说明](scripts/README.md)。

```text
autogen.sh -> 测试 -> colcon -> target/ -> vergen.sh -> version/out/

systemd -> update.py apply -> boot_apps.sh -> car_daemon -> agent.sh
```

版本包保留现有 deb、MD5/SHA-256 和可选头部格式。更新器校验包、检查运行依赖后，
切换 `/work/app/daemon`；旧版保留在 `/work/app/previous`。
配置保存在 `/work/app/cfg/car.conf`，应用升级不会覆盖。失败记录见
`/work/app/status/update/result`。

```bash
sudo carctl rollback
```

回退前需移走待更新包；命令会停止服务，检查并切换到上一版本后再启动。
构建和主机测试不能代替开发板上的升级、重启及实车验证。
