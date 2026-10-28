#!/usr/bin/env bash
# 与 hs411 一样：编译 -> 收集安装产物 -> vergen.sh 生成版本包。
# 用法：bash version/autogen.sh 1.0.0 [arm64|amd64]，默认 arm64。
# 在 x86_64 上生成 arm64 包时，自动读取 cross.conf 并启用交叉编译。
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?Usage: bash version/autogen.sh VERSION [arm64|amd64]}"
arch="${2:-arm64}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~][A-Za-z0-9.]+)?$ ]] || {
  echo "Version must look like 1.0.0 or 1.0.0+build1" >&2; exit 2;
}
[[ "$arch" == arm64 || "$arch" == amd64 ]] || exit 2
host_arch="$(dpkg --print-architecture)"
cross=false
if [[ "$host_arch" != "$arch" ]]; then
  [[ "$host_arch" == amd64 && "$arch" == arm64 ]] || {
    echo "Unsupported cross build: $host_arch -> $arch" >&2
    exit 2
  }
  cross=true
  source "$repo/version/cross.conf"
  if [[ ! -d "$CAR_SYSROOT/opt/ros/jazzy" ]]; then
    echo "Missing ARM64 sysroot: $CAR_SYSROOT" >&2
    echo "/opt/ros/jazzy alone is not a sysroot. Run version/sync_sysroot.sh USER@BOARD first." >&2
    exit 2
  fi
  CAR_SYSROOT="$(realpath -e "$CAR_SYSROOT")"
  # Ubuntu 的 libstdc++.so 开发链接通常位于目标 GCC 目录，而非 multiarch 根目录。
  CAR_TARGET_GCC_LIBDIR="$(find "$CAR_SYSROOT/usr/lib/gcc/aarch64-linux-gnu" \
    -name libstdc++.so -print 2>/dev/null | sort -V | tail -n 1)"
  if [[ -z "$CAR_TARGET_GCC_LIBDIR" ]]; then
    echo "Missing target libstdc++.so. Install g++ on the board and resync its /usr." >&2
    exit 2
  fi
  CAR_TARGET_GCC_LIBDIR="$(dirname -- "$CAR_TARGET_GCC_LIBDIR")"
  export CAR_SYSROOT CAR_CROSS_PREFIX CAR_TARGET_GCC_LIBDIR
fi
# 主机 ROS 只提供 ament/Python 构建工具；交叉构建的库由 toolchain 指向 sysroot。
source /opt/ros/jazzy/setup.bash
# 将提交号写入程序；有未提交修改时追加 dirty 标记，便于追溯版本。
commit="$(git -C "$repo" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
if ! git -C "$repo" diff --quiet 2>/dev/null || \
   [[ -n "$(git -C "$repo" ls-files --others --exclude-standard)" ]]; then
  commit="$commit-dirty"
fi
# 每次使用独立目录，避免把 symlink-install 或旧版本文件打进发布包。
mkdir -p "$repo/target"
touch "$repo/target/COLCON_IGNORE"
stage="$(mktemp -d "$repo/target/release.XXXXXX")"
cmake_args=(-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
  "-DCAR_VERSION=$version" "-DCAR_GIT_COMMIT=$commit")
if [[ "$cross" == true ]]; then
  bash "$repo/version/check_cross.sh" "$stage/probe"
  # 用主机编译器运行可移植逻辑/更新器/daemon 测试，不执行 ARM 二进制。
  cmake -S "$repo/src/tb6612_car_ros2/test" -B "$stage/host-tests" \
    -DCMAKE_CXX_COMPILER=/usr/bin/g++ -DCMAKE_BUILD_TYPE=Release
  cmake --build "$stage/host-tests" --parallel
  ctest --test-dir "$stage/host-tests" --output-on-failure
  cmake_args+=(-DBUILD_TESTING=OFF
    "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchain_aarch64.cmake")
  export AMENT_PREFIX_PATH="$CAR_SYSROOT/opt/ros/jazzy"
  export CMAKE_PREFIX_PATH="$CAR_SYSROOT/opt/ros/jazzy"
  unset AMENT_CURRENT_PREFIX
fi
cd "$repo"
colcon --log-base "$stage/log" build \
  --base-paths "$repo/src/tb6612_car_ros2" \
  --packages-select tb6612_car_ros2 \
  --build-base "$stage/build" --install-base "$stage/install" \
  --cmake-args "${cmake_args[@]}"
# 测试通过后才打包，任何一步失败都会停止后续发布步骤。
if [[ "$cross" == false ]]; then
  ctest --test-dir "$stage/build/tb6612_car_ros2" --output-on-failure
fi
bash "$repo/version/vergen.sh" "$version" "$arch" "$stage/install/tb6612_car_ros2" "$commit"
echo "Build tree retained for diagnosis: $stage"
