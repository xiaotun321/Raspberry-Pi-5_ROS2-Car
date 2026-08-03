from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch.substitutions import PythonExpression
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        # 声明启动参数
        DeclareLaunchArgument(
            'transport', default_value='udp4',  # 参数名称transport, 不传参时使用默认值udp4 
            description='micro-ROS Agent transport: udp4 for WiFi, serial for USB'),  # 帮助说明 执行ros2 launch 你的功能包 文件名.launch.py --show-args 可以查看到
        DeclareLaunchArgument(
            'serial_port', default_value='/dev/ttyACM0',
            description='ESP32-S3 micro-ROS serial device'),
        DeclareLaunchArgument(
            'baudrate', default_value='921600',
            description='micro-ROS serial baudrate'),
        DeclareLaunchArgument(
            'udp_port', default_value='8888',
            description='micro-ROS Agent UDP port for WiFi transport'),
        Node(
            package='micro_ros_agent',          # 功能包名
            executable='micro_ros_agent',       # 可执行程序名
            name='micro_ros_agent',             # 节点名称
            output='screen',                    # 打印日志到终端
            condition=IfCondition(PythonExpression([   # 条件启动，只有当 transport 参数等于字符串 serial 时，才启动这个节点。
                "'", LaunchConfiguration('transport'), "' == 'serial'"  # 此时 LaunchConfiguration('transport') 替换成 serial,最终Python表达式等价为 'serial' == 'serial' 结果为 True
            ])),
            arguments=[                                # 命令行启动参数，传递给 micro_ros_agent 可执行程序的命令行参数。
                'serial',
                '--dev', LaunchConfiguration('serial_port'),
                '--baudrate', LaunchConfiguration('baudrate'),
            ],
        ),
        Node(
            package='micro_ros_agent',
            executable='micro_ros_agent',
            name='micro_ros_agent',
            output='screen',
            condition=IfCondition(PythonExpression([
                "'", LaunchConfiguration('transport'), "' == 'udp4'"
            ])),
            arguments=[
                'udp4',
                '--port', LaunchConfiguration('udp_port'),
            ],
        ),
    ])

'''
arguments 等价于终端直接敲命令：
# 串口模式
ros2 run micro_ros_agent micro_ros_agent serial --dev /dev/ttyACM0 --baudrate 921600


# UDP wifi模式
ros2 run micro_ros_agent micro_ros_agent udp4 --port 8888
'''



'''
ros2 launch your_package xxx.launch.py transport:=serial
'''