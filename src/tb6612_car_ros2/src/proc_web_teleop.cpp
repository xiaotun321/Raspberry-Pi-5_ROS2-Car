#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <exception>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>

#include <geometry_msgs/msg/twist.hpp>
#include <rclcpp/rclcpp.hpp>

#include "build_version.hpp"
#include "http_server.hpp"
#include "teleop_control.hpp"
#include "web_control_page.hpp"

namespace {
volatile std::sig_atomic_t stop_requested = 0;

void request_stop(int) {
  stop_requested = 1;
}

// HTTP 处理线程和 ROS 发布线程共享的状态；用 shared_ptr 保证节点销毁后
// 仍在处理连接的线程不会访问已释放的对象。
struct WebState {
  explicit WebState(double command_timeout) : control(command_timeout) {}

  std::mutex mutex;
  tb6612::TeleopControl control;
  tb6612::Motion motion{};
};

std::string format_number(double value) {
  char buffer[32];
  std::snprintf(buffer, sizeof(buffer), "%.4f", value);
  return buffer;
}

class WebTeleop : public rclcpp::Node {
 public:
  WebTeleop()
      : Node("tb6612_web_teleop"),
        port_(declare_parameter<int>("port", 8080)),
        bind_address_(
            declare_parameter<std::string>("bind_address", "0.0.0.0")),
        token_(declare_parameter<std::string>("token", "")),
        publish_rate_(declare_parameter<int>("publish_rate", 20)) {
    if (port_ < 1 || port_ > 65535) {
      throw std::invalid_argument("port must be in [1, 65535]");
    }
    const double command_timeout =
        declare_parameter<double>("command_timeout", 0.6);
    state_ = std::make_shared<WebState>(command_timeout);

    publisher_ = create_publisher<geometry_msgs::msg::Twist>("cmd_vel", 10);
    const auto period = std::chrono::milliseconds(
        1000 / (publish_rate_ > 0 ? publish_rate_ : 1));
    timer_ = create_wall_timer(period, [this]() { publish_current(); });

    server_ = std::make_unique<tb6612::HttpServer>(
        bind_address_, static_cast<std::uint16_t>(port_),
        [state = state_, token = token_](const tb6612::HttpRequest& request) {
          return handle(state, token, request);
        });
    std::string error;
    if (!server_->start(&error)) {
      throw std::runtime_error("cannot start web server: " + error);
    }
    server_thread_ = std::thread([this]() { server_->run(); });

    RCLCPP_INFO(get_logger(),
                "网页控制已启动：http://<本机 IP>:%d/  (Ctrl-C 退出)", port_);
    if (!token_.empty()) {
      RCLCPP_INFO(get_logger(), "命令需要令牌：?token=%s", token_.c_str());
    }
  }

  ~WebTeleop() override {
    if (server_) {
      server_->stop();
    }
    if (server_thread_.joinable()) {
      server_thread_.join();
    }
  }

  // 退出前发送一次停车指令。
  void stop() {
    {
      std::lock_guard<std::mutex> lock(state_->mutex);
      state_->control.set_motion(0.0, 0.0,
                                 tb6612::TeleopControl::Clock::now());
      state_->motion = {};
    }
    publish_current();
  }

 private:
  void publish_current() {
    tb6612::Motion motion;
    {
      std::lock_guard<std::mutex> lock(state_->mutex);
      state_->motion =
          state_->control.current(tb6612::TeleopControl::Clock::now());
      motion = state_->motion;
    }
    geometry_msgs::msg::Twist message;
    message.linear.x = motion.linear;
    message.angular.z = motion.angular;
    publisher_->publish(message);
  }

  static bool authorized(const std::string& token,
                         const tb6612::HttpRequest& request) {
    if (token.empty()) {
      return true;
    }
    if (request.header("x-car-token") == token) {
      return true;
    }
    const auto params = request.query_params();
    const auto it = params.find("token");
    return it != params.end() && it->second == token;
  }

  static std::string state_json(const std::shared_ptr<WebState>& state) {
    tb6612::Motion motion;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      motion = state->motion;
    }
    const bool active = motion.linear != 0.0 || motion.angular != 0.0;
    std::string json = "{\"linear\":";
    json += format_number(motion.linear);
    json += ",\"angular\":";
    json += format_number(motion.angular);
    json += ",\"active\":";
    json += active ? "true" : "false";
    json += "}";
    return json;
  }

  static tb6612::HttpResponse handle(const std::shared_ptr<WebState>& state,
                                     const std::string& token,
                                     const tb6612::HttpRequest& request) {
    if (request.method == "OPTIONS") {
      return tb6612::HttpResponse{204, "text/plain; charset=utf-8", ""};
    }
    if (request.path == "/" && request.method == "GET") {
      return tb6612::HttpResponse{200, "text/html; charset=utf-8",
                                   tb6612::kWebControlPage};
    }
    if (!authorized(token, request)) {
      return tb6612::HttpResponse{403, "text/plain; charset=utf-8",
                                  "forbidden"};
    }
    if (request.path == "/state" && request.method == "GET") {
      return tb6612::HttpResponse{200, "application/json", state_json(state)};
    }
    if (request.path == "/cmd" &&
        (request.method == "POST" || request.method == "GET")) {
      std::string payload = request.body;
      if (payload.empty()) {
        payload = "linear=" + request.query_value("linear") +
                  "&angular=" + request.query_value("angular");
      }
      double linear = 0.0;
      double angular = 0.0;
      if (!tb6612::parse_command_values(payload, &linear, &angular)) {
        return tb6612::HttpResponse{400, "text/plain; charset=utf-8",
                                    "invalid command"};
      }
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (!state->control.set_motion(linear, angular,
                                       tb6612::TeleopControl::Clock::now())) {
          return tb6612::HttpResponse{400, "text/plain; charset=utf-8",
                                      "invalid command"};
        }
        state->motion =
            state->control.current(tb6612::TeleopControl::Clock::now());
      }
      return tb6612::HttpResponse{200, "application/json", state_json(state)};
    }
    if (request.path == "/stop" && request.method == "POST") {
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        state->control.set_motion(0.0, 0.0,
                                  tb6612::TeleopControl::Clock::now());
        state->motion =
            state->control.current(tb6612::TeleopControl::Clock::now());
      }
      return tb6612::HttpResponse{200, "application/json", state_json(state)};
    }
    return tb6612::HttpResponse{404, "text/plain; charset=utf-8", "not found"};
  }

  std::shared_ptr<WebState> state_;
  int port_;
  std::string bind_address_;
  std::string token_;
  int publish_rate_;
  rclcpp::Publisher<geometry_msgs::msg::Twist>::SharedPtr publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
  std::unique_ptr<tb6612::HttpServer> server_;
  std::thread server_thread_;
};

}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    std::printf("web_teleop %s (%s)\n", tb6612::kVersion, tb6612::kGitCommit);
    std::puts(tb6612::kBuildIdentity);
    return 0;
  }
  std::shared_ptr<WebTeleop> node;
  int result = 0;

  try {
    rclcpp::init(argc, argv, rclcpp::InitOptions(),
                 rclcpp::SignalHandlerOptions::None);
    std::signal(SIGINT, request_stop);
    std::signal(SIGTERM, request_stop);
    node = std::make_shared<WebTeleop>();
    rclcpp::executors::SingleThreadedExecutor executor;
    executor.add_node(node);
    while (rclcpp::ok() && !stop_requested) {
      executor.spin_some();
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
  } catch (const std::exception& error) {
    std::fprintf(stderr, "web_teleop: %s\n", error.what());
    result = 1;
  }

  if (node && rclcpp::ok()) {
    try {
      node->stop();
      RCLCPP_INFO(node->get_logger(), "已发送停车命令并退出。");
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
