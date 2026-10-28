#pragma once

#include <poll.h>
#include <termios.h>
#include <unistd.h>

#include <cerrno>
#include <stdexcept>
#include <system_error>

namespace tb6612 {

// Restore the terminal on normal exit and exception unwinding.
class Terminal {
 public:
  Terminal() {
    if (!isatty(STDIN_FILENO)) {
      throw std::runtime_error(
          "keyboard_teleop must run in an interactive terminal");
    }
    if (tcgetattr(STDIN_FILENO, &saved_) == -1) {
      throw std::system_error(errno, std::generic_category(), "tcgetattr");
    }

    auto settings = saved_;
    settings.c_lflag &= static_cast<tcflag_t>(~(ICANON | ECHO | ISIG | IEXTEN));
    settings.c_iflag &= static_cast<tcflag_t>(~(IXON | ICRNL | INLCR | IGNCR));
    settings.c_cc[VMIN] = 1;
    settings.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &settings) == -1) {
      throw std::system_error(errno, std::generic_category(), "tcsetattr");
    }
  }

  ~Terminal() {
    tcsetattr(STDIN_FILENO, TCSANOW, &saved_);
  }
  Terminal(const Terminal&) = delete;
  Terminal& operator=(const Terminal&) = delete;

  // 0: timeout/interrupted; -1: EOF; otherwise unsigned input byte.
  int read_key(int timeout_ms = 50) const {
    pollfd input{STDIN_FILENO, POLLIN, 0};
    const int ready = poll(&input, 1, timeout_ms);
    if (ready < 0) {
      if (errno == EINTR) {
        return 0;
      }
      throw std::system_error(errno, std::generic_category(), "poll");
    }
    if (ready == 0) {
      return 0;
    }
    if (input.revents & (POLLERR | POLLHUP | POLLNVAL)) {
      return -1;
    }
    if (!(input.revents & POLLIN)) {
      return 0;
    }

    unsigned char key = 0;
    const auto count = read(STDIN_FILENO, &key, 1);
    if (count < 0) {
      if (errno == EINTR) {
        return 0;
      }
      throw std::system_error(errno, std::generic_category(), "read");
    }
    return count == 0 ? -1 : key;
  }

 private:
  termios saved_{};
};

}  // namespace tb6612
