#!/usr/bin/env bash
set -eo pipefail
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo "用法: bash version/autogen.sh VERSION [arm64|amd64]"
  exit 0
fi
[[ $# -ge 1 && $# -le 2 ]] || { echo "用法: bash version/autogen.sh VERSION [arm64|amd64]" >&2; exit 2; }
version="$1"
arch="${2:-arm64}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~][A-Za-z0-9.]+)?$ && ${#version} -lt 32 ]] || {
  echo "无效版本号（示例 1.0.0，最多 31 字符）: $version" >&2; exit 2;
}
[[ "$arch" == arm64 || "$arch" == amd64 ]] || { echo "架构只能是 arm64 或 amd64" >&2; exit 2; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
source /opt/ros/jazzy/setup.bash
commit="$(git rev-parse --short=12 HEAD)"
if ! git diff --quiet HEAD -- || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  commit="$commit-dirty"
fi
strip_tool=strip
cmake_args=(-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
  "-DCAR_VERSION=$version" "-DCAR_GIT_COMMIT=$commit")
host_arch="$(dpkg --print-architecture)"
if [[ "$host_arch" != "$arch" ]]; then
  [[ "$host_arch" == amd64 && "$arch" == arm64 ]] || {
    echo "仅支持本机编译或 amd64 -> arm64 交叉编译" >&2; exit 2;
  }
  source "$repo/version/cross.conf"
  CAR_SYSROOT="$(realpath -e "$CAR_SYSROOT")"
  target_library="$(find "$CAR_SYSROOT/usr/lib/gcc/aarch64-linux-gnu" -name libstdc++.so | sort -V | tail -n 1)"
  [[ -n "$target_library" && -d "$CAR_SYSROOT/opt/ros/jazzy" ]] || {
    echo "sysroot 缺少 GCC 开发库或 ROS Jazzy: $CAR_SYSROOT" >&2; exit 1;
  }
  CAR_TARGET_GCC_LIBDIR="$(dirname -- "$target_library")"
  export CAR_SYSROOT CAR_CROSS_PREFIX CAR_TARGET_GCC_LIBDIR
  export AMENT_PREFIX_PATH="$CAR_SYSROOT/opt/ros/jazzy" CMAKE_PREFIX_PATH="$CAR_SYSROOT/opt/ros/jazzy"
  unset AMENT_CURRENT_PREFIX
  cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchain_aarch64.cmake")
  strip_tool="${CAR_CROSS_PREFIX}strip"
fi
command -v "$strip_tool" >/dev/null
mkdir -p version/tmp target
touch version/tmp/COLCON_IGNORE target/COLCON_IGNORE
stage="$(mktemp -d "$repo/version/tmp/build.XXXXXX")"
trap 'echo "构建失败，日志目录: $stage" >&2' ERR

echo "[1/3] 测试"
cmake -S src/tb6612_car_ros2/test -B "$stage/tests" -DCMAKE_CXX_COMPILER=/usr/bin/g++ -DCMAKE_BUILD_TYPE=Release
cmake --build "$stage/tests" --parallel
ctest --test-dir "$stage/tests" --output-on-failure

echo "[2/3] 编译 $version / $arch"
colcon --log-base "$stage/log" build --base-paths src/tb6612_car_ros2 \
  --packages-select tb6612_car_ros2 --build-base "$stage/build" --install-base "$stage/install" \
  --cmake-args "${cmake_args[@]}"
for executable in car_daemon keyboard_teleop web_teleop; do
  "$strip_tool" "$stage/install/tb6612_car_ros2/lib/tb6612_car_ros2/$executable"
done
rm -rf "$repo/target/tb6612_car_ros2"
cp -aL "$stage/install/tb6612_car_ros2" "$repo/target/tb6612_car_ros2"
python3 - "$repo/target/version.json" "$version" "$arch" "$commit" <<'PY'
import datetime, json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "product": "tb6612-car", "version": sys.argv[2], "architecture": sys.argv[3],
    "commit": sys.argv[4], "ros_distro": "jazzy", "format": 1,
    "built_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}, indent=2) + "\n", encoding="utf-8")
PY

echo "[3/3] 打包"
bash "$repo/version/vergen.sh"
echo "构建日志: $stage"
