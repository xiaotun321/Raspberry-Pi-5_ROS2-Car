#pragma once

#include <algorithm>
#include <chrono>
#include <cmath>
#include <stdexcept>

namespace tb6612 {

struct Motion {
  double linear = 0.0;
  double angular = 0.0;
};

// Pure control logic, independent of ROS and terminal input.
class TeleopControl {
 public:
  using Clock = std::chrono::steady_clock;
  using TimePoint = Clock::time_point;

  // 指令限幅：键盘调速和网页绝对速度共用同一上限，避免越界指令。
  static constexpr double kMaxLinearSpeed = 0.50;
  static constexpr double kMaxAngularSpeed = 2.5;
  static constexpr double kMinLinearSpeed = 0.02;
  static constexpr double kMinAngularSpeed = 0.1;
  static constexpr double kDefaultLinearSpeed = 0.15;
  static constexpr double kDefaultAngularSpeed = 0.8;

  explicit TeleopControl(double key_timeout = 0.6) : timeout_(key_timeout) {
    if (!std::isfinite(key_timeout) || key_timeout <= 0.0 ||
        key_timeout > 5.0) {
      throw std::invalid_argument("key_timeout must be >0 and <=5 seconds");
    }
  }

  // Returns true when the new command must be published immediately.
  bool handle_key(char key, TimePoint now) {
    switch (key) {
      case 'w':
        target_ = {linear_speed_, 0.0};
        break;
      case 'x':
        target_ = {-linear_speed_, 0.0};
        break;
      case 'a':
        target_ = {0.0, angular_speed_};
        break;
      case 'd':
        target_ = {0.0, -angular_speed_};
        break;
      case 's':
      case ' ':
        target_ = {};
        break;
      case 'q':
        linear_speed_ = std::min(kMaxLinearSpeed, linear_speed_ + 0.02);
        return false;
      case 'e':
        linear_speed_ = std::max(kMinLinearSpeed, linear_speed_ - 0.02);
        return false;
      case 'z':
        angular_speed_ = std::min(kMaxAngularSpeed, angular_speed_ + 0.1);
        return false;
      case 'c':
        angular_speed_ = std::max(kMinAngularSpeed, angular_speed_ - 0.1);
        return false;
      default:
        return false;
    }

    last_motion_ = now;
    return true;
  }

  Motion current(TimePoint now) {
    if (now - last_motion_ >= timeout_) {
      target_ = {};
    }
    return target_;
  }

  // 网页/遥控直接下发绝对速度：按同一限幅裁剪后生效，并刷新运动超时。
  // 非有限数值（NaN、Inf）视为无效指令，返回 false 且不改变当前状态。
  bool set_motion(double linear, double angular, TimePoint now) {
    if (!std::isfinite(linear) || !std::isfinite(angular)) {
      return false;
    }
    target_ = {std::clamp(linear, -kMaxLinearSpeed, kMaxLinearSpeed),
               std::clamp(angular, -kMaxAngularSpeed, kMaxAngularSpeed)};
    last_motion_ = now;
    return true;
  }

  double linear_speed() const {
    return linear_speed_;
  }

  double angular_speed() const {
    return angular_speed_;
  }

 private:
  std::chrono::duration<double> timeout_;
  TimePoint last_motion_{};
  Motion target_{};
  double linear_speed_ = kDefaultLinearSpeed;
  double angular_speed_ = kDefaultAngularSpeed;
};

}  // namespace tb6612
