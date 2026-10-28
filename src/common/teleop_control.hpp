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
        linear_speed_ = std::min(0.50, linear_speed_ + 0.02);
        return false;
      case 'e':
        linear_speed_ = std::max(0.02, linear_speed_ - 0.02);
        return false;
      case 'z':
        angular_speed_ = std::min(2.5, angular_speed_ + 0.1);
        return false;
      case 'c':
        angular_speed_ = std::max(0.1, angular_speed_ - 0.1);
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
  double linear_speed_ = 0.15;
  double angular_speed_ = 0.8;
};

}  // namespace tb6612
