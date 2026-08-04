```bash
# micro_ros_agent 是运行在 Linux/ROS 2 主机上的通信桥梁，让资源受限的微控制器能够加入 ROS 2 网络 —— ROS2 分布式通信
# ros2 run <ROS功能包名> <可执行程序名> <Agent参数>
ros2 run micro_ros_agent micro_ros_agent udp4 --port 8888

# 通过 launch 启动
ros2 launch tb6612_car_ros2 car_bringup.launch.py transport:=udp4 udp_port:=8888
```

```text
ESP32-S3
micro-ROS Client
     │
     │ UDP / 串口
     ▼
micro_ros_agent
     │
     │ DDS
     ▼
ROS 2 节点、话题、服务、动作
它的主要作用：
     1.接收 ESP32 micro-ROS Client 发来的 Micro XRCE-DDS 数据。
     2.将数据转换并发布到标准 ROS 2 DDS 网络。
     3.把 ROS 2 主机发送的消息转发给 ESP32。
     4.管理 ESP32 创建的话题、服务、订阅器和发布器。
```