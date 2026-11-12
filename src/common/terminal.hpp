#pragma once

#include <fcntl.h>
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
    // 优先读 /dev/tty：ros2 launch 下子进程的 stdin 不是终端，但控制终端还在，
    // 直接打开控制终端才能在 launch 里继续用键盘。
    fd_ = ::open("/dev/tty", O_RDONLY | O_NOCTTY);
    owned_ = fd_ >= 0;
    if (!owned_) {
      fd_ = STDIN_FILENO;
    }
    if (!isatty(fd_)) {
      close_fd();
      throw std::runtime_error(
          "keyboard_teleop must run in an interactive terminal");
    }
    if (tcgetattr(fd_, &saved_) == -1) {
      close_fd();
      throw std::system_error(errno, std::generic_category(), "tcgetattr");
    }

    auto settings = saved_;
    settings.c_lflag &= static_cast<tcflag_t>(~(ICANON | ECHO | ISIG | IEXTEN));
    settings.c_iflag &= static_cast<tcflag_t>(~(IXON | ICRNL | INLCR | IGNCR));
    settings.c_cc[VMIN] = 1;
    settings.c_cc[VTIME] = 0;
    if (tcsetattr(fd_, TCSANOW, &settings) == -1) {
      close_fd();
      throw std::system_error(errno, std::generic_category(), "tcsetattr");
    }
  }

  ~Terminal() {
    if (fd_ >= 0) {
      tcsetattr(fd_, TCSANOW, &saved_);
      close_fd();
    }
  }
  Terminal(const Terminal&) = delete;
  Terminal& operator=(const Terminal&) = delete;

  // 0: timeout/interrupted; -1: EOF; otherwise unsigned input byte.
  int read_key(int timeout_ms = 50) const {
    pollfd input{fd_, POLLIN, 0};
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
    const auto count = read(fd_, &key, 1);
    if (count < 0) {
      if (errno == EINTR) {
        return 0;
      }
      throw std::system_error(errno, std::generic_category(), "read");
    }
    return count == 0 ? -1 : key;
  }

 private:
  void close_fd() {
    if (owned_ && fd_ >= 0) {
      ::close(fd_);
    }
    fd_ = -1;
  }

  int fd_ = -1;
  bool owned_ = false;
  termios saved_{};
};

}  // namespace tb6612
