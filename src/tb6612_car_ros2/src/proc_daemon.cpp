#include <fcntl.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <thread>

#include "build_version.hpp"

namespace {
volatile std::sig_atomic_t stopping = 0;

void request_stop(int) {
  stopping = 1;
}

void pause_for(std::chrono::milliseconds duration) {
  const auto end = std::chrono::steady_clock::now() + duration;
  while (!stopping && std::chrono::steady_clock::now() < end) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
}

// 停止整个子进程组，避免脚本启动的后代进程在重启后继续占用端口。
void stop_child(pid_t child) {
  kill(-child, SIGTERM);
  int status = 0;
  for (int retry = 0; retry < 50; ++retry) {
    const auto result = waitpid(child, &status, WNOHANG);
    if (result == child || (result < 0 && errno == ECHILD)) {
      kill(-child, SIGKILL);
      return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  kill(-child, SIGKILL);
  while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
  }
}
}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    std::printf("car_daemon %s (%s)\n", tb6612::kVersion, tb6612::kGitCommit);
    std::puts(tb6612::kBuildIdentity);
    return 0;
  }
  if (argc < 5 || std::strcmp(argv[1], "--lock") != 0 ||
      std::strcmp(argv[3], "--") != 0 || argv[4][0] != '/') {
    std::fprintf(stderr,
                 "Usage: car_daemon --lock PATH -- /program [args...]\n");
    return 2;
  }

  // 与 spx-lib daemon 相同，使用单实例锁和 fork/exec/waitpid 守护模型。
  const int lock_fd = open(argv[2], O_CREAT | O_RDWR | O_CLOEXEC, 0644);
  if (lock_fd < 0 || flock(lock_fd, LOCK_EX | LOCK_NB) != 0) {
    std::fprintf(stderr, "Cannot lock %s: %s\n", argv[2], std::strerror(errno));
    if (lock_fd >= 0) {
      close(lock_fd);
    }
    return 1;
  }
  std::setvbuf(stdout, nullptr, _IOLBF, 0);
  std::signal(SIGINT, request_stop);
  std::signal(SIGTERM, request_stop);
  int delay_seconds = 2;
  int result = 0;

  while (!stopping) {
    const auto started = std::chrono::steady_clock::now();
    const pid_t parent = getpid();
    const pid_t child = fork();
    if (child < 0) {
      std::perror("fork");
      result = 1;
      break;
    }
    if (child == 0) {
      std::signal(SIGINT, SIG_DFL);
      std::signal(SIGTERM, SIG_DFL);
      // 父进程意外退出时停止被守护进程；systemd 还会清理服务 cgroup。
      if (setpgid(0, 0) != 0 || prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 ||
          getppid() != parent) {
        _exit(126);
      }
      close(lock_fd);
      execv(argv[4], argv + 4);
      std::perror("execv");
      _exit(127);
    }
    // 子进程也调用 setpgid，覆盖父子进程调度先后差异。
    setpgid(child, child);
    std::printf("Started pid=%ld command=%s\n", static_cast<long>(child),
                argv[4]);
    int status = 0;
    while (!stopping) {
      const pid_t waited = waitpid(child, &status, WNOHANG);
      if (waited == child) {
        break;
      }
      if (waited < 0 && errno != EINTR) {
        std::perror("waitpid");
        stopping = 1;
        result = 1;
        break;
      }
      pause_for(std::chrono::milliseconds(100));
    }
    if (stopping) {
      stop_child(child);
      break;
    }
    kill(-child, SIGKILL);
    if (std::chrono::steady_clock::now() - started >=
        std::chrono::seconds(30)) {
      delay_seconds = 2;
    }
    std::printf("Child exited status=%d; restart in %d seconds\n", status,
                delay_seconds);
    pause_for(std::chrono::seconds(delay_seconds));
    delay_seconds = std::min(delay_seconds * 2, 30);
  }
  close(lock_fd);
  return result;
}
