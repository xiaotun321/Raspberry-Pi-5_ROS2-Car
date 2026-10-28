#!/usr/bin/env bash
# 与 hs411 一样：编译 -> 收集安装产物 -> vergen.sh 生成版本包。
# 用法：bash version/autogen.sh 1.0.0 [arm64|amd64]，默认 arm64。
# 需在匹配目标架构的 Linux/Jazzy 环境执行，产物位于 version/out。
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?Usage: bash version/autogen.sh VERSION [arm64|amd64]}"
arch="${2:-arm64}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~][A-Za-z0-9.]+)?$ ]] || {
  echo "Version must look like 1.0.0 or 1.0.0+build1" >&2; exit 2;
}
[[ "$(dpkg --print-architecture)" == "$arch" ]] || {
  echo "Build host architecture differs from $arch. Build on the board or a matching Linux environment." >&2
  exit 2
}
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
cd "$repo"
colcon --log-base "$stage/log" build \
  --base-paths "$repo/src/tb6612_car_ros2" \
  --packages-select tb6612_car_ros2 \
  --build-base "$stage/build" --install-base "$stage/install" \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
  "-DCAR_VERSION=$version" "-DCAR_GIT_COMMIT=$commit"
# 测试通过后才打包，任何一步失败都会停止后续发布步骤。
ctest --test-dir "$stage/build/tb6612_car_ros2" --output-on-failure
bash "$repo/version/vergen.sh" "$version" "$arch" "$stage/install/tb6612_car_ros2" "$commit"
echo "Build tree retained for diagnosis: $stage"
