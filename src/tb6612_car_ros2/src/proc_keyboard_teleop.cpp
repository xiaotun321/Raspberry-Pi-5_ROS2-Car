#include <csignal>
#include <cstdio>
#include <cstring>
#include <geometry_msgs/msg/twist.hpp>
#include <memory>
#include <rclcpp/rclcpp.hpp>

#include "build_version.hpp"
#include "teleop_control.hpp"
#include "terminal.hpp"

namespace {
volatile std::sig_atomic_t stop_requested = 0;

void request_stop(int) {
  stop_requested = 1;
}

class KeyboardTeleop : public rclcpp::Node {
 public:
  KeyboardTeleop()
      : Node("tb6612_keyboard_teleop"),
        control_(declare_parameter<double>("key_timeout", 0.6)) {
    publisher_ = create_publisher<geometry_msgs::msg::Twist>("cmd_vel", 10);
    timer_ = create_wall_timer(std::chrono::milliseconds(100), [this]() {
      publish(control_.current(tb6612::TeleopControl::Clock::now()));
    });
  }

  void handle_key(char key) {
    const auto now = tb6612::TeleopControl::Clock::now();
    if (control_.handle_key(key, now)) {
      publish(control_.current(now));
    }
    std::printf("\r线速度指令=%.2f  角速度指令=%.2f   ",
                control_.linear_speed(), control_.angular_speed());
    std::fflush(stdout);
  }

  void stop() {
    timer_->cancel();
    publish({});
  }

 private:
  void publish(const tb6612::Motion& motion) {
    geometry_msgs::msg::Twist message;
    message.linear.x = motion.linear;
    message.angular.z = motion.angular;
    publisher_->publish(message);
  }

  tb6612::TeleopControl control_;
  rclcpp::Publisher<geometry_msgs::msg::Twist>::SharedPtr publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
};
}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    std::printf("keyboard_teleop %s (%s)\n", tb6612::kVersion,
                tb6612::kGitCommit);
    return 0;
  }
  std::shared_ptr<KeyboardTeleop> node;
  int result = 0;

  try {
    // Keep the ROS context alive until the final zero command has been sent.
    rclcpp::init(argc, argv, rclcpp::InitOptions(),
                 rclcpp::SignalHandlerOptions::None);
    std::signal(SIGINT, request_stop);
    std::signal(SIGTERM, request_stop);
    tb6612::Terminal terminal;
    node = std::make_shared<KeyboardTeleop>();
    std::puts(
        "ESP32-S3 TB6612 小车键盘控制\n"
        "w 前进 / x 后退 / a 左转 / d 右转 / s 或空格 停止\n"
        "q/e 增加/减小线速度，z/c 增加/减小角速度，Ctrl-C 退出\n"
        "10 Hz 刷新；最后一次方向按键后默认 0.6 秒停车。\n"
        "速度是开环指令值；调速后再次按方向键生效。");
    rclcpp::executors::SingleThreadedExecutor executor;
    executor.add_node(node);
    while (rclcpp::ok() && !stop_requested) {
      executor.spin_some();
      const int key = terminal.read_key();
      if (stop_requested || key == 3 || key == -1) {
        break;
      }
      if (key != 0) {
        node->handle_key(static_cast<char>(key));
      }
    }
  } catch (const std::exception& error) {
    std::fprintf(stderr, "keyboard_teleop: %s\n", error.what());
    result = 1;
  }

  if (node && rclcpp::ok()) {
    try {
      node->stop();
      std::puts("\n已发送停车命令并退出。");
    } catch (const std::exception& error) {
      std::fprintf(stderr, "Failed to send stop command: %s\n", error.what());
      result = 1;
    }
  }

  node.reset();
  if (rclcpp::ok()) {
    rclcpp::shutdown();
  }
  return result;
}
