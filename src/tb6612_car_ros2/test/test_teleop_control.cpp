#include <cstdlib>
#include <iostream>
#include <limits>

#include "teleop_control.hpp"

void check(bool value) {
  if (!value) {
    std::cerr << "Control check failed\n";
    std::exit(1);
  }
}

void expect(tb6612::Motion motion, double linear, double angular) {
  check(std::abs(motion.linear - linear) < 1e-9 &&
        std::abs(motion.angular - angular) < 1e-9);
}

int main() {
  using namespace std::chrono_literals;
  using tb6612::TeleopControl;
  const auto start = TeleopControl::TimePoint{} + 10s;
  TeleopControl control;
  expect(control.current(start), 0, 0);
  check(control.handle_key('w', start));
  expect(control.current(start + 599ms), 0.15, 0);
  expect(control.current(start + 600ms), 0, 0);

  control.handle_key('x', start);
  expect(control.current(start), -0.15, 0);

  control.handle_key('a', start);
  expect(control.current(start), 0, 0.8);

  control.handle_key('d', start);
  expect(control.current(start), 0, -0.8);

  for (char key : {'s', ' '}) {
    control.handle_key('w', start);
    check(control.handle_key(key, start + 1ms));
    expect(control.current(start + 1ms), 0, 0);
  }

  control.handle_key('w', start);

  control.handle_key('w', start + 500ms);
  expect(control.current(start + 1099ms), 0.15, 0);
  expect(control.current(start + 1100ms), 0, 0);

  control.handle_key('w', start);
  check(!control.handle_key('q', start + 500ms));
  check(!control.handle_key('?', start + 550ms));
  expect(control.current(start + 599ms), 0.15, 0);
  expect(control.current(start + 600ms), 0, 0);

  control.handle_key('w', start + 700ms);
  expect(control.current(start + 700ms), 0.17, 0);

  for (int i = 0; i < 200; ++i) {
    control.handle_key('q', start);

    control.handle_key('z', start);
  }
  check(control.linear_speed() == 0.50 && control.angular_speed() == 2.5);

  for (int i = 0; i < 200; ++i) {
    control.handle_key('e', start);

    control.handle_key('c', start);
  }
  check(control.linear_speed() == 0.02 && control.angular_speed() == 0.1);

  TeleopControl custom(0.8);
  custom.handle_key('w', start);
  expect(custom.current(start + 799ms), 0.15, 0);
  expect(custom.current(start + 800ms), 0, 0);

  for (double timeout :
       {0.0, -1.0, 5.1, std::numeric_limits<double>::infinity(),
        std::numeric_limits<double>::quiet_NaN()}) {
    bool rejected = false;
    try {
      TeleopControl invalid(timeout);
    } catch (const std::invalid_argument&) {
      rejected = true;
    }
    check(rejected);
  }

  TeleopControl maximum(5.0);
  maximum.handle_key('w', start);
  expect(maximum.current(start + 4999ms), 0.15, 0);
  expect(maximum.current(start + 5s), 0, 0);
  std::cout << "All teleop control checks passed\n";
}
