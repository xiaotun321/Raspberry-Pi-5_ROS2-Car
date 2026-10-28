#!/usr/bin/env bash
# 在正式构建前检查工具链/sysroot，并实际编译链接一个 ARM64 C++ 小程序。
# 仅运行主机编译器，不运行生成的 ARM 程序；失败日志保留在指定目录。
set -e
output="${1:?Usage: check_cross.sh OUTPUT_DIRECTORY}"
[[ -n "${CAR_SYSROOT:-}" && -d "$CAR_SYSROOT" ]] || {
  echo "Set CAR_SYSROOT to the board sysroot directory in version/cross.conf." >&2
  exit 2
}
[[ "$CAR_SYSROOT" != / && "$CAR_SYSROOT" != *[[:space:]]* ]] || {
  echo "CAR_SYSROOT must not be / or contain whitespace." >&2
  exit 2
}
[[ -n "${CAR_TARGET_GCC_LIBDIR:-}" && -f "$CAR_TARGET_GCC_LIBDIR/libstdc++.so" ]] || {
  echo "Missing target GCC development library directory." >&2
  exit 2
}
[[ "$CAR_CROSS_PREFIX" != *[[:space:]]* ]] || {
  echo "Toolchain prefix must not contain whitespace." >&2
  exit 2
}
for tool in gcc g++ ar ranlib strip ld; do
  [[ -x "${CAR_CROSS_PREFIX}${tool}" ]] || {
    echo "Missing cross tool: ${CAR_CROSS_PREFIX}${tool}" >&2
    exit 2
  }
done
[[ "$("${CAR_CROSS_PREFIX}g++" -dumpmachine)" == aarch64*linux* ]] || {
  echo "The compiler must target AArch64 Linux." >&2
  exit 2
}
for path in usr/include/stdio.h usr/include/aarch64-linux-gnu/bits/wordsize.h \
  usr/lib/aarch64-linux-gnu/crt1.o usr/lib/aarch64-linux-gnu/libc.so \
  usr/lib/aarch64-linux-gnu/libstdc++.so.6 \
  opt/ros/jazzy/share/ament_cmake/cmake/ament_cmakeConfig.cmake \
  opt/ros/jazzy/share/rclcpp/cmake/rclcppConfig.cmake \
  opt/ros/jazzy/share/geometry_msgs/cmake/geometry_msgsConfig.cmake \
  opt/ros/jazzy/lib/librclcpp.so; do
  [[ -f "$CAR_SYSROOT/$path" ]] || {
    echo "Incomplete sysroot or broken absolute symlink: $CAR_SYSROOT/$path" >&2
    exit 2
  }
  resolved="$(realpath -e "$CAR_SYSROOT/$path")"
  [[ "$resolved" == "$CAR_SYSROOT/"* ]] || {
    echo "Sysroot symlink points outside the sysroot: $path -> $resolved" >&2
    exit 2
  }
done
resolved="$(realpath -e "$CAR_TARGET_GCC_LIBDIR/libstdc++.so")"
[[ "$resolved" == "$CAR_SYSROOT/"* ]] || {
  echo "Target libstdc++.so points outside sysroot: $resolved" >&2
  exit 2
}
python3 - "$CAR_SYSROOT/opt/ros/jazzy/lib/librclcpp.so" <<'PY'
from pathlib import Path
import sys
header = Path(sys.argv[1]).open('rb').read(20)
if header[:6] != b'\x7fELF\x02\x01' or int.from_bytes(header[18:20], 'little') != 183:
    raise SystemExit('sysroot librclcpp.so is not an ARM64 ELF library')
PY
mkdir -p "$output"
cat > "$output/probe.cpp" <<'CPP'
#include <chrono>
#include <iostream>
#include <thread>
int main() {
  std::thread worker([] { std::this_thread::sleep_for(std::chrono::milliseconds(1)); });
  worker.join();
  std::cout << "toolchain link check\n";
}
CPP
multiarch="$CAR_SYSROOT/usr/lib/aarch64-linux-gnu"
if ! "${CAR_CROSS_PREFIX}g++" --sysroot="$CAR_SYSROOT" -std=c++17 \
  -isystem "$CAR_SYSROOT/usr/include/aarch64-linux-gnu" -B"$multiarch/" \
  -L"$CAR_TARGET_GCC_LIBDIR" -L"$multiarch" -L"$CAR_SYSROOT/lib/aarch64-linux-gnu" \
  -Wl,-rpath-link,"$multiarch" \
  -Wl,-rpath-link,"$CAR_SYSROOT/lib/aarch64-linux-gnu" \
  -pthread "$output/probe.cpp" \
  -o "$output/probe" > "$output/link.log" 2>&1; then
  cat "$output/link.log" >&2
  echo "Toolchain/sysroot cannot link. Check glibc, libstdc++ and linker compatibility." >&2
  echo "For a GCC 13/Jazzy sysroot, a matching newer AArch64 toolchain may be required." >&2
  exit 1
fi
echo "Cross toolchain link check passed: $("${CAR_CROSS_PREFIX}g++" -dumpfullversion)"
