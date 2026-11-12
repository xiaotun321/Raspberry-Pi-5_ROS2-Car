"""一键拉起 Agent、键盘控制和网页控制。

用法：

    # 默认：Agent（UDP）+ 网页控制
    ros2 launch tb6612_car_ros2 car_bringup.launch.py transport:=udp4 udp_port:=8888

    # 串口 Agent + 键盘控制（键盘节点需要控制终端，网页控制默认关闭）
    ros2 launch tb6612_car_ros2 car_bringup.launch.py transport:=serial keyboard:=true

    # 网页控制改端口并加令牌
    ros2 launch tb6612_car_ros2 car_bringup.launch.py web_port:=8081 web_token:=secret

    # Agent 不在本机时只起控制节点
    ros2 launch tb6612_car_ros2 car_bringup.launch.py agent:=false keyboard:=true

键盘控制和网页控制发布的是同一个 /cmd_vel，同时打开会互相覆盖指令，
所以默认只开网页控制，需要键盘时用 keyboard:=true 并关掉网页控制。
"""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration, PythonExpression
from launch_ros.actions import Node


def _web_node(context):
    """按需拼出网页控制的参数：令牌为空时不能传 token:=，rcl 会解析失败。"""
    port = LaunchConfiguration('web_port').perform(context)
    bind = LaunchConfiguration('web_bind').perform(context)
    token = LaunchConfiguration('web_token').perform(context)
    arguments = ['--ros-args', '-p', 'port:=' + port, '-p', 'bind_address:=' + bind]
    if token:
        arguments += ['-p', 'token:=' + token]
    return [Node(
        package='tb6612_car_ros2',
        executable='web_teleop',
        name='tb6612_web_teleop',
        output='screen',
        arguments=arguments,
    )]


def generate_launch_description():
    transport = LaunchConfiguration('transport')
    agent = LaunchConfiguration('agent')
    keyboard = LaunchConfiguration('keyboard')
    web = LaunchConfiguration('web')

    return LaunchDescription([
        # 启动参数
        DeclareLaunchArgument(
            'agent', default_value='true',
            description='是否启动 micro-ROS Agent（Agent 不在本机时关掉）'),
        DeclareLaunchArgument(
            'transport', default_value='udp4',
            description='micro-ROS Agent 传输方式：udp4 走 Wi-Fi，serial 走 USB 串口'),
        DeclareLaunchArgument(
            'serial_port', default_value='/dev/ttyACM0',
            description='ESP32-S3 micro-ROS 串口设备'),
        DeclareLaunchArgument(
            'baudrate', default_value='921600',
            description='micro-ROS 串口波特率'),
        DeclareLaunchArgument(
            'udp_port', default_value='8888',
            description='micro-ROS Agent 的 UDP 端口'),
        DeclareLaunchArgument(
            'keyboard', default_value='false',
            description='是否启动键盘控制（需要控制终端）'),
        DeclareLaunchArgument(
            'key_timeout', default_value='0.6',
            description='最后一次方向按键后自动停车的秒数'),
        DeclareLaunchArgument(
            'web', default_value='true',
            description='是否启动网页控制'),
        DeclareLaunchArgument(
            'web_port', default_value='8080',
            description='网页控制监听端口'),
        DeclareLaunchArgument(
            'web_bind', default_value='0.0.0.0',
            description='网页控制监听地址'),
        DeclareLaunchArgument(
            'web_token', default_value='',
            description='网页控制令牌，非空时命令需要携带 ?token='),

        # Agent：串口和 UDP 两种方式，按 transport 二选一启动。
        Node(
            package='micro_ros_agent',
            executable='micro_ros_agent',
            name='micro_ros_agent',
            output='screen',
            condition=IfCondition(PythonExpression([
                "'", agent, "' == 'true' and '", transport, "' == 'serial'"])),
            arguments=['serial', '--dev', LaunchConfiguration('serial_port'),
                       '--baudrate', LaunchConfiguration('baudrate')],
        ),
        Node(
            package='micro_ros_agent',
            executable='micro_ros_agent',
            name='micro_ros_agent',
            output='screen',
            condition=IfCondition(PythonExpression([
                "'", agent, "' == 'true' and '", transport, "' == 'udp4'"])),
            arguments=['udp4', '--port', LaunchConfiguration('udp_port')],
        ),

        # 键盘控制：从控制终端读按键，需要 ros2 launch 在终端里执行。
        Node(
            package='tb6612_car_ros2',
            executable='keyboard_teleop',
            name='tb6612_keyboard_teleop',
            output='screen',
            condition=IfCondition(keyboard),
            arguments=['--ros-args', '-p',
                       ['key_timeout:=', LaunchConfiguration('key_timeout')]],
        ),

        # 网页控制：浏览器访问 http://<本机IP>:<端口>/ 即可下发指令。
        OpaqueFunction(function=_web_node, condition=IfCondition(web)),
    ])
