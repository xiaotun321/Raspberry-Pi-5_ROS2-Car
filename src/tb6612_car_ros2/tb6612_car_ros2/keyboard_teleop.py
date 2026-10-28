#!/usr/bin/env python3
import select
import sys
import termios
import tty
import time
import math

import rclpy
from geometry_msgs.msg import Twist  # 几何消息包 geometry_msgs 中的标准速度消息类型 TWist
from rclpy.node import Node


HELP = '''
ESP32-S3 TB6612 小车键盘控制
-----------------------------
        w：前进
  a：左转  s：停止  d：右转
        x：后退

  q/e：增加/减小线速度
  z/c：增加/减小角速度
  空格：停止
  Ctrl-C：退出
  按住方向键移动；最后一次方向按键后 0.6 秒自动停车。
  以 10 Hz 刷新命令；s/空格立即发停止。
'''


class KeyboardTeleop(Node):
    def __init__(self):
        super().__init__('tb6612_keyboard_teleop')  # 调用父类 Node 的构造函数，创建 ROS2 节点 tb6612_keyboard_teleop
        self.publisher = self.create_publisher(Twist, 'cmd_vel', 10) # 创建 /cmd_vel 发布者对象（消息类型、话题名、队列长度(用作缓存)）
                                                                     # 节点之间通过消息传输数据 Twist 就是数据类型
        self.linear_speed = 0.15    # 线速度
        self.angular_speed = 0.8    # 开环指令值，不是实测速度
        self.key_timeout = float(self.declare_parameter('key_timeout', 0.6).value)
        if not math.isfinite(self.key_timeout) or not 0 < self.key_timeout <= 5:
            raise ValueError('key_timeout must be >0 and <=5 seconds')
        self.target = (0.0, 0.0)
        self.last_motion_key = time.monotonic()
        self.timer = self.create_timer(0.1, self.publish_current)

    def publish(self, linear=0.0, angular=0.0):
        msg = Twist()
        msg.linear.x = float(linear)
        msg.angular.z = float(angular)
        self.publisher.publish(msg)     # 发布话题消息

    def set_motion(self, linear=0.0, angular=0.0):
        self.target = (linear, angular)
        self.last_motion_key = time.monotonic()
        self.publish(*self.target)

    def publish_current(self):
        if time.monotonic() - self.last_motion_key >= self.key_timeout:
            self.target = (0.0, 0.0)
        self.publish(*self.target)

    # 将按键转换成开环运动指令
    '''
    方向键更新运动目标，定时器以 10 Hz 刷新；没有新的方向按键时超时清零。
    '''
    def handle_key(self, key):
        if key == 'w':
            self.set_motion(self.linear_speed, 0.0)
        elif key == 'x':
            self.set_motion(-self.linear_speed, 0.0)
        elif key == 'a':
            self.set_motion(0.0, self.angular_speed)
        elif key == 'd':
            self.set_motion(0.0, -self.angular_speed)
        elif key in ('s', ' '):
            self.set_motion()
        elif key == 'q':
            self.linear_speed = min(0.50, self.linear_speed + 0.02)
        elif key == 'e':
            self.linear_speed = max(0.02, self.linear_speed - 0.02)
        elif key == 'z':
            self.angular_speed = min(2.5, self.angular_speed + 0.1)
        elif key == 'c':
            self.angular_speed = max(0.1, self.angular_speed - 0.1)
        print(
            f'\r线速度={self.linear_speed:.2f} m/s  '
            f'角速度={self.angular_speed:.2f} rad/s   ',
            end='', flush=True)


# 非阻塞读取按键 默认最多等待 0.05s
def read_key(timeout=0.05):
    readable, _, _ = select.select([sys.stdin], [], [], timeout)
    return sys.stdin.read(1) if readable else ''


def main(args=None):
    # 该程序需要实时读取键盘，所以标准输入必须是终端。
    if not sys.stdin.isatty(): 
        raise RuntimeError('keyboard_teleop 必须在交互式终端运行')

    rclpy.init(args=args)
    node = KeyboardTeleop() # 创建键盘控制节点
    old_settings = termios.tcgetattr(sys.stdin)
    print(HELP)

    try:
        tty.setraw(sys.stdin.fileno())
        while rclpy.ok():
            rclpy.spin_once(node, timeout_sec=0.0)  # 处理一次与该节点相关的 ROS2 事件。timeout_sec=0.0 表示不等待，有事件就处理，没有事件就立即返回
            key = read_key()
            if key == '\x03':
                break
            if key:
                node.handle_key(key)  # 处理普通按键 有字符调用此函数
    finally:
        node.publish()
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        print('\n已停车并退出。')
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()

