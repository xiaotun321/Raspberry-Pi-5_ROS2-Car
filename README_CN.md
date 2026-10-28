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
│   ├── terminal.hpp              # POSIX 终端读取与自动恢复
│   └── build_version.hpp.in      # 编译版本信息模板
└── tb6612_car_ros2/
    ├── CMakeLists.txt
    ├── package.xml
    ├── src/proc_keyboard_teleop.cpp
    ├── src/proc_daemon.cpp
    ├── launch/car_bringup.launch.py
    └── test/                    # 控制逻辑与守护进程测试
scripts/
├── ros_env.sh
├── ros_launch.sh
├── keyboard_teleop.sh
├── bootstrap.sh                 # 首次安装更新器和 systemd 服务
├── boot_apps.sh                 # 发布目录应用入口
├── carctl.sh                    # 日常启停、版本、日志和遥控命令
└── deploy.sh                    # 上传版本并按需重启
version/
├── autogen.sh                   # 带版本编译和测试
├── vergen.sh                    # 生成 .ver 和首次安装包
├── update.py                    # 启动前校验和版本切换
└── test_update.py               # 更新器回归测试
```

`common` 为 CMake INTERFACE 目标，进程编译为 `keyboard_teleop`，安装至
`lib/tb6612_car_ros2`，保持原有运行命令。launch Python 文件只负责
启动 Agent，业务节点已改为 C++。工作区由 colcon 发现包，无需根目录 CMakeLists.txt。

## 构建

开发调试使用本节的 colcon 命令；开发板自动启动与版本发布使用后面的
[脚本发布、开机更新与守护进程](#脚本发布开机更新与守护进程)。

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

## 脚本发布、开机更新与守护进程

### 与 hs411 的对应关系

沿用 `version/autogen.sh` 编译、`version/vergen.sh` 打包、`vmonitor.sh` /
`vinstall.sh` 启动前更新、`boot_apps.sh` 启动应用的分工。
`.ver` 外层采用 hs411 的 tar.bz2 + `.deb` + MD5 组织，增加 SHA-256。
内部产品名为 `tb6612-car`，不能混用 hs411 的版本包，也不使用其 `.tricam` 封装。

守护进程参考 spx-lib `tools/daemon.cpp` 的单实例锁及 `fork/exec/waitpid`
模式，由本项目 C++ 实现 `car_daemon`。它没有 ROS 依赖，子进程退出后按
2–30 秒退避重启；收到停止信号后清理子进程组。未复制或修改 spx-lib。
systemd 负责开机运行和 daemon 自身崩溃后的重启，并把输出收集到 journal。

后台只启动 micro-ROS Agent。键盘节点必须连接真实终端，通过 `carctl teleop`
启动；不把键盘程序放进后台造成反复退出，也不在开机时发布非零运动指令。

### 1. 编译一个版本

在 Ubuntu 24.04 / ROS 2 Jazzy 环境执行，树莓派 5 使用 arm64：

```bash
bash version/autogen.sh 1.0.0
```

脚本自动加载 ROS 环境，编译 Release，运行 CTest，并生成：

```text
version/out/tb6612-car_1.0.0_arm64.ver
version/out/tb6612-car-bootstrap.tar.gz
```

x86_64 Linux 主机原生生成 amd64 包用于本机测试时，显式指定架构：

```bash
bash version/autogen.sh 1.0.0 amd64
```

amd64 包不能用于树莓派。在 x86_64 主机上选择默认 arm64 时，脚本会自动进入
下面的交叉编译流程。首次构建依赖见前文，打包还需 `dpkg-dev`、
`bzip2`、`python3`、`tar`。每次使用新的版本号；`version.json` 同时记录 Git 提交、
源码是否有未提交修改、构建时间和架构。程序支持 `--version`。

每次构建使用独立 `target/` 子目录，禁止发布目录中的符号链接依赖源码目录。
这些目录会保留以便排查构建问题，可在确认不需要后自行清理。

#### x86_64 主机交叉编译 ARM64

`version/cross.conf` 默认配置你使用的 Arm GNU 10.3 工具链：

```bash
CAR_TOOLCHAIN_ROOT="$HOME/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu"
CAR_CROSS_PREFIX="$CAR_TOOLCHAIN_ROOT/bin/aarch64-none-linux-gnu-"
CAR_SYSROOT="$HOME/rpi5-sysroot"
```

**主机的 `/opt/ros/jazzy` 不是 ARM64 sysroot。** 它提供主机运行的构建工具；
目标头文件和库必须来自开发板。sysroot 是开发板文件系统的本地副本，应至少包含：

```text
rpi5-sysroot/
├── opt/ros/jazzy/               # ARM64 ROS 库、头文件、CMake 配置
├── usr/include/                # 开发板系统头文件
├── usr/lib/aarch64-linux-gnu/   # glibc 等目标系统库
├── usr/lib/gcc/aarch64-linux-gnu/ # 目标 libstdc++.so 开发链接
└── lib/                        # 系统库/加载器，可能链接到 usr/lib
```

主机与开发板均需安装 rsync。开发板需要 Jazzy、rclcpp、geometry_msgs 和 g++
开发文件，不能只复制一个缺少头文件的运行环境。首次在主机仓库根目录同步：

```bash
sudo apt install rsync
bash version/sync_sysroot.sh shuaijie@开发板IP
```

脚本只读取开发板，复制 `/usr`、`/opt/ros/jazzy` 和系统库；它将副本中的绝对
符号链接转换成相对链接，防止误指向主机库。目标目录已存在时拒绝覆盖；更新副本
可指定新目录，然后修改 `cross.conf` 的 `CAR_SYSROOT`。整个 `/usr` 可能较大，
需预留空间并等待同步完成。也可通过环境变量指定已准备好的完整 sysroot：

```bash
CAR_SYSROOT=/home/shuaijie/board-sysroot bash version/autogen.sh 1.0.0.0t
```

使用默认路径时，在你当前的 `version` 目录直接执行：

```bash
bash autogen.sh 1.0.0.0t
```

生成 `version/out/tb6612-car_1.0.0.0t_arm64.ver`。`1.0.0.0t` 在构建、打包和
更新器中均为有效版本号。交叉构建的行为是：

1. 核对编译器目标、sysroot 的 ROS 库架构，并实际链接一个 ARM64 C++ 小程序。
2. 使用主机 g++ 编译并运行控制逻辑、更新器和 daemon 测试。
3. 使用 `cmake/toolchain_aarch64.cmake` 编译 ARM64 应用，不运行 ARM 程序。
4. 打包前读取 ELF 头与嵌入的版本/提交标记，避免把 x86 程序或旧版本装入 ARM 包。

主机测试不能替代开发板测试。GCC 10.3 与开发板较新的 glibc/libstdc++ 或 ROS
头文件未必兼容；若预检查失败，查看输出及 `target/release.*/probe/link.log`。
应修正 sysroot 或使用与开发板匹配的工具链，不要跳过链接错误。若主机安装了
Ubuntu 的 AArch64 交叉编译器，可显式切换，例如：

```bash
CAR_CROSS_PREFIX=/usr/bin/aarch64-linux-gnu- bash version/autogen.sh 1.0.0.0t
```

该方式仍然需要开发板 sysroot；不会复用主机的 x86 ROS 库。

### 2. 首次初始化开发板（仅一次）

开发板需已安装 Ubuntu/systemd 和 ROS 2 Jazzy，且 `/work` 在重启后持久保留。
先把 `tb6612-car-bootstrap.tar.gz` 复制到开发板，解压后执行：

```bash
mkdir -p ~/car-bootstrap
tar -xzf tb6612-car-bootstrap.tar.gz -C ~/car-bootstrap
cd ~/car-bootstrap

# 若尚未安装 Agent，执行此命令（联网安装到 /opt/microros_ws）
sudo bash scripts/install_agent.sh

# 初始化更新器、服务和配置；参数为 Agent 环境脚本的绝对路径
sudo bash scripts/bootstrap.sh /opt/microros_ws/install/local_setup.bash
```

如果已有 Agent，跳过安装步骤，将 bootstrap 参数换成已有工作区的环境脚本。
若 Agent 本身已在 `/opt/ros/jazzy` 中，bootstrap 不需要参数。
配置保存到 `/work/app/cfg/car.conf`，包含传输方式、端口、ROS_DOMAIN_ID 和
Agent 环境脚本路径；后续 `.ver` 更新不会覆盖配置。

初始化仅启用开机服务，不会立即启动尚未安装的应用。它也不会覆盖 `/work/vinstall.sh`
等其他项目入口。更新器固定安装在 `/work/car-bootstrap`，普通版本包不升级更新器本身。
ROS、Agent 和系统共享库不包含在 `.ver` 中；它们是开发板一次性安装的运行环境。

### 3. 上传并重启更新

从构建机使用脚本上传（替换用户名和开发板地址）：

```bash
bash scripts/deploy.sh version/out/tb6612-car_1.0.0_arm64.ver shuaijie@192.168.0.106 --reboot
```

上传使用 SSH/SCP，远端用户需要 sudo 权限。脚本先复制到临时文件，再通过 sudo
安装为 `/work/app/tmp/ver/1.ver.partial`，完整落盘后原子重命名为 `1.ver`。
省略 `--reboot` 时只上传，不重启；远端已有待更新 `1.ver` 时拒绝覆盖。
SSH 在重启时提示连接关闭属于正常现象，应在开发板恢复后检查版本。

也可以在开发板本地投递版本包：

```bash
sudo install -m 600 tb6612-car_1.0.0_arm64.ver /work/app/tmp/ver/1.ver.partial
sudo sync
sudo mv /work/app/tmp/ver/1.ver.partial /work/app/tmp/ver/1.ver
sudo sync
sudo reboot
```

不要在服务启动期间直接写 `1.ver`，应使用上述临时文件改名方式。
服务每次启动（包括 `carctl restart`）都会检查更新包。

启动链为：

```text
systemd: tb6612-car.service
  -> /work/car-bootstrap/vmonitor.sh -> vinstall.sh -> update.py
  -> /work/app/daemon/boot_apps.sh
  -> car_daemon -> agent.sh -> micro_ros_agent
```

### 4. 日常运行

```bash
carctl version                   # 当前应用版本、架构和提交号
carctl status                    # 服务状态
carctl logs                      # 跟踪 daemon/Agent/升级日志
carctl teleop                    # 当前终端运行键盘控制，无需手动 source
carctl teleop --ros-args -p key_timeout:=0.8
sudo carctl stop
sudo carctl start
sudo carctl restart
```

键盘遥控是独立的终端进程，退出时使用 Ctrl-C。停止后台服务会断开 Agent，
实际电机停车仍依赖 ESP32 的断连与命令超时保护。

### 5. 校验、失败处理与回退

升级前校验包名、MD5/SHA-256、目标架构、Jazzy 标识、版本元数据和归档路径，
拒绝路径越界、链接和设备节点。SHA-256 用于传输完整性检查，不是发布者数字签名。
`.deb` 在这里作为载荷容器：只读取数据区，不执行 Debian 维护脚本，也不修改
系统 dpkg 安装数据库。应用包不声明或自动安装系统依赖。

新版本先进入独立目录，运行 `boot_apps.sh --check` 检查两个 C++ 程序能否执行
及 Agent 依赖是否存在，通过后原子切换 `/work/app/daemon` 链接。
旧版本通过 `/work/app/previous` 保留。包损坏、架构不符或依赖检查失败时，
不会激活候选版本；已有应用继续启动，首次安装则保持失败状态。

```text
/work/app/
├── daemon -> releases/<当前版本目录>
├── previous -> releases/<上一版本目录>
├── releases/                     # 独立应用版本
├── cfg/car.conf                  # 持久配置
├── tmp/ver/1.ver                 # 待安装包
├── .ver/                         # 成功包和 failed-* 失败包
└── status/
    ├── verno                     # 当前版本号
    └── update/result             # 最近一次升级结果
```

开机检查只验证本地依赖，不证明 ESP32 网络连通或电机工作正常；运行期故障会重启
Agent，不会自动回退应用版本。需要回退时先确认没有待安装的 `1.ver`，然后执行：

```bash
sudo carctl rollback
cat /work/app/status/update/result
```

该命令停止服务、检查并切换到 previous，再启动服务；检查失败则保持服务停止，
以便排查。更新中断会在下次启动时重试 `.installing.ver`；升级校验失败的包会移到
`.ver/failed-*`，修复依赖后需要重新投递版本。版本目录和历史包不会自动删除，
需定期检查磁盘空间并保留当前与上一版本。

### 发布流程验证

`autogen.sh` 的 CTest 包括控制逻辑、归档校验以及 Linux daemon 生命周期测试。
也可独立运行不依赖 ROS 的测试：

```bash
cmake -S src/tb6612_car_ros2/test -B build/runtime-tests
cmake --build build/runtime-tests
ctest --test-dir build/runtime-tests --output-on-failure
python3 version/update.py check version/out/tb6612-car_1.0.0_arm64.ver
```

发布前在开发板确认：首次安装、重启自启、Agent 退出重启、升级至新版本、坏包拒绝、
架构不符拒绝、手动回退，以及配置在升级后保持不变。硬件控制仍按前文架空车轮验证。
