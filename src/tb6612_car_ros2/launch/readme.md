# 启动文件

`car_bringup.launch.py` 一次拉起 micro-ROS Agent、键盘控制和网页控制：

```bash
# 默认：Agent（UDP）+ 网页控制
ros2 launch tb6612_car_ros2 car_bringup.launch.py transport:=udp4 udp_port:=8888

# 串口 Agent + 键盘控制
ros2 launch tb6612_car_ros2 car_bringup.launch.py transport:=serial keyboard:=true

# 网页控制改端口并加令牌
ros2 launch tb6612_car_ros2 car_bringup.launch.py web_port:=8081 web_token:=secret

# Agent 不在本机时只起控制节点
ros2 launch tb6612_car_ros2 car_bringup.launch.py agent:=false keyboard:=true
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `agent` | `true` | 是否在本机启动 micro-ROS Agent |
| `transport` | `udp4` | Agent 传输方式：`udp4` 或 `serial` |
| `serial_port` | `/dev/ttyACM0` | ESP32-S3 串口设备 |
| `baudrate` | `921600` | 串口波特率 |
| `udp_port` | `8888` | Agent 的 UDP 端口 |
| `keyboard` | `false` | 是否启动键盘控制，需要控制终端 |
| `key_timeout` | `0.6` | 最后一次方向按键后自动停车的秒数 |
| `web` | `true` | 是否启动网页控制 |
| `web_port` | `8080` | 网页控制监听端口 |
| `web_bind` | `0.0.0.0` | 网页控制监听地址 |
| `web_token` | 空 | 非空时命令需要携带 `?token=` |

键盘控制和网页控制发布同一个 `/cmd_vel`，同时打开会互相覆盖指令，按需二选一。
键盘控制从控制终端（`/dev/tty`）读按键，因此在 `ros2 launch` 下也能用。
