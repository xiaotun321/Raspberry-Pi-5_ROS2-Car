# 构建与部署

## 构建

主机需已安装 ROS 2 Jazzy、colcon、CMake、g++、Python 3、dpkg-dev 和 bzip2。

```bash
bash version/autogen.sh 1.0.0 arm64
```

一条命令完成：**测试 → 编译 → 打包**。省略架构默认 `arm64`；
本机 amd64 构建用 `bash version/autogen.sh 1.0.0 amd64`。

x86_64 交叉编译时，只需在 `version/cross.conf` 配置两项，也可用环境变量覆盖：

```bash
CAR_SYSROOT="$HOME/rpi5-sysroot"
CAR_CROSS_PREFIX="/usr/bin/aarch64-linux-gnu-"
```

使用现成的 ARM64 sysroot，须包含 `opt/ros/jazzy`、系统头文件、库及 GCC 开发库。
工具链可安装 `gcc-aarch64-linux-gnu`、`g++-aarch64-linux-gnu`；
已有用户工具链时填写其实际前缀。默认优先用 `/usr/bin/`，否则用 `$HOME/bin/`。
在 ARM64 树莓派上原生编译无需配置这些路径。

新建 sysroot 可从已安装 Jazzy、rclcpp、geometry_msgs 和 g++ 的开发板同步：
```bash
mkdir -p "$HOME/rpi5-sysroot"
rsync -aR pi@BOARD:/usr/include :/usr/lib :/lib :/opt/ros/jazzy "$HOME/rpi5-sysroot/"
python3 version/tools/relativize_sysroot.py "$HOME/rpi5-sysroot"
```

只修改发布脚本时，直接复用最近一次编译结果：

```bash
bash version/vergen.sh
```

版本和架构从 `target/version.json` 读取；要换版本号或改功能源码，重新运行
`autogen.sh`。版本号示例 `1.0.0`、`1.0.0.0t`，最多 31 个字符。
同一工作区一次运行一个构建/打包任务。

## 产物

```text
target/tb6612_car_ros2/                      已 strip 的安装文件
target/version.json                         版本、架构、提交号
version/out/tb6612-car_<版本>_<架构>.bin       升级包
version/out/tb6612-car_<版本>_<架构>.bivi      同一升级包附加头部
version/out/tb6612-car-bootstrap.tar.gz       首次安装包
version/tmp/                                构建日志与打包暂存文件
```

`.bin`、`.bivi` 任选一个上传。新版本打包成功后清空 `version/out/`，只保留本次产物；编译或打包失败时保留上次产物。
从旧脚本迁移后先运行一次 `autogen.sh` 生成新的版本清单。

## 首次安装到开发板

将 `tb6612-car-bootstrap.tar.gz` 复制到已安装 ROS 2 Jazzy 的开发板：

```bash
mkdir -p ~/car-bootstrap
tar -xzf tb6612-car-bootstrap.tar.gz -C ~/car-bootstrap
cd ~/car-bootstrap
sudo bash scripts/install_agent.sh
sudo bash scripts/bootstrap.sh /opt/microros_ws/install/local_setup.bash
```

已有 Agent 时跳过安装，传入已有环境脚本路径；Agent 已在 `/opt/ros/jazzy` 中时
`bootstrap.sh` 无需参数。初始化只启用开机服务，装入应用包后才能运行。
板端配置在 `/work/app/cfg/car.conf`。

旧安装要切换到精简后的服务入口，先 `sudo carctl stop`，再解压新的首次安装包，
重新执行 `bootstrap.sh`；已有配置会保留。旧更新器转发脚本不再被服务调用。

## 上传与运行

构建机执行（替换用户名/IP）：

```bash
bash scripts/deploy.sh version/out/tb6612-car_1.0.0_arm64.bin pi@192.168.1.10 --reboot
```

省略 `--reboot` 只上传；已有待更新包时拒绝覆盖。开发板每次启动服务先执行更新器，
再由 `boot_apps.sh` 启动 Agent 守护进程。

```bash
carctl status
carctl version
carctl logs
carctl teleop
carctl web
sudo carctl restart
```

前台整套启动用 `carctl bringup`；后台 Agent 已运行时加 `agent:=false`。
网页和键盘入口用于板端发布目录；源码调试先加载 `install/setup.bash` 再运行 `ros2`。

## carctl 的作用与原理

`carctl` 是本项目在开发板上的统一操作命令，封装服务管理、日志查看、版本查询和
控制程序启动。它本身是 Shell 脚本，不是常驻进程，也不直接控制电机。
`bootstrap.sh` 将仓库中的 `scripts/carctl.sh` 安装为 `/usr/local/bin/carctl`，
因此安装后可以在任意目录执行；不带参数时等同于 `carctl status`。

| 命令 | 实际作用 |
| --- | --- |
| `carctl status` | 用 `systemctl` 查看主服务状态 |
| `carctl version` | 读取 `/work/app/daemon/version.json`，显示版本、架构和提交号 |
| `carctl logs` | 用 `journalctl` 持续显示主服务的更新器、daemon 和 Agent 日志 |
| `sudo carctl start` | 清除主服务失败限流状态，再启动服务 |
| `sudo carctl stop` | 停止主服务及其守护的 Agent |
| `sudo carctl restart` | 重启主服务，启动前检查并安装待更新包 |
| `carctl teleop` | 前台执行 `keyboard_teleop.sh`，启动键盘控制，需要交互终端 |
| `carctl web` | 前台执行 `web_teleop.sh`，启动网页控制 |
| `carctl bringup` | 前台执行 `ros_launch.sh`，通过 ROS launch 编排 Agent 和控制节点 |
| `sudo carctl rollback` | 停止服务，校验并切换上一版本，再启动服务；存在待更新包时拒绝回退 |

后台启动链为：

```text
carctl start/restart
  → systemctl 启动 tb6612-car.service
  → update.py apply：处理 /work/app/tmp/ver/1.ver
  → boot_apps.sh → car_daemon → agent.sh → micro-ROS Agent
```

开机时由 systemd 自动执行同一条启动链，不需要登录后再运行 `carctl`。
手动控制入口会通过 `runtime_env.sh` 加载配置、ROS 和 Agent 环境，无需手动 source。
关闭终端不会停止后台系统服务；前台控制程序用 Ctrl-C 退出。

查看状态、版本和启动前台控制通常不需要 sudo；启停系统服务、回退使用 sudo。
日志是否可见取决于用户的 journal 读取权限，无权限时用 `sudo carctl logs`。
`carctl logs` 只显示主服务日志，网页后台日志单独查看：

```bash
journalctl -u tb6612-car-web.service -f
```

网页后台服务由 `systemctl` 管理，`carctl web` 是另外启动一个前台实例。
已启用网页后台服务时不要重复运行 `carctl web`，否则会占用相同端口。
网页服务配置了对主服务的依赖，主服务停止或重启时会联动已运行的网页服务；
仅启动主服务不等同于启用网页服务。网页开机自启用：

```bash
sudo systemctl enable --now tb6612-car-web.service
```

参数会继续传给对应命令，例如：

```bash
carctl logs -n 100
carctl teleop --ros-args -p key_timeout:=0.8
carctl bringup agent:=false web:=false keyboard:=true
```

最后一条适用于后台 Agent 已运行、希望前台使用键盘的情况；若网页控制也在运行，
应先停止网页服务，避免两种控制同时发布速度指令。回退检查失败时服务保持停止，
可查看 `/work/app/status/update/result` 排查。

## 开发板运行目录

应用程序与启动脚本统一放在 `/work/app/daemon/` 顶层：

```text
/work/app/daemon/
  car_daemon
  keyboard_teleop
  web_teleop
  boot_apps.sh
  agent.sh
  keyboard_teleop.sh
  web_teleop.sh
  ros_launch.sh
  runtime_env.sh
  version.json
  ros/                 ROS 索引和 launch 兼容布局
```

`daemon` 仍是指向当前版本的链接，用于原子切换和回退。后台与手动控制入口直接
执行顶层程序；`ros2 launch` 保留使用 ROS 安装布局。micro-ROS Agent 使用板端已有
安装，由 `agent.sh` 启动。更新器独立位于 `/work/car-bootstrap/`，配置在
`/work/app/cfg/car.conf`，升级投递路径仍为 `/work/app/tmp/ver/1.ver`。
