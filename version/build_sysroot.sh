#!/usr/bin/env bash
# 在 x86 主机上从 Ubuntu 与 ROS 官方源构建 ARM64 sysroot；开发板无需联网即可交叉编译。
# 产物结构：opt/ros/jazzy、usr/include、usr/lib/aarch64-linux-gnu，与开发板一致。
# 用法：bash version/build_sysroot.sh [发行版] [目标目录]
#   发行版：noble（默认，Ubuntu 24.04）或 jammy（22.04），需与开发板一致。
#   目标目录：默认 $HOME/rpi5-sysroot，与 version/cross.conf 保持一致。
# 只在用户目录读写，不需要 root；下载的 deb 先解到临时目录再整体改名。
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
release="${1:-noble}"
destination="${2:-$HOME/rpi5-sysroot}"
[[ $# -le 2 ]] || exit 2
case "$release" in
  noble|jammy) ;;
  *) echo "Unsupported release: $release (use noble or jammy)" >&2; exit 2 ;;
esac
[[ ! -e "$destination" && ! -L "$destination" ]] || {
  echo "Destination already exists; choose a new directory: $destination" >&2
  exit 2
}
command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required." >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }
work="${CAR_SYSROOT_WORK:-$HOME/.cache/car-arm64-sysroot}"
mkdir -p "$work/lists/partial" "$work/downloads"
# Ubuntu 的 arm64 包在 ports 仓库，ROS 的 arm64 包在官方源；两者按发行版区分。
cat > "$work/sources.list" <<EOF
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $release main universe
deb [arch=arm64] http://packages.ros.org/ros2/ubuntu $release main
EOF
: > "$work/status"
# 用私有目录运行 apt，避免触碰主机的 dpkg 状态和 /var/cache。
apt_opts=(
  -o "Dir::Etc::sourcelist=$work/sources.list"
  -o "Dir::Etc::sourceparts=/dev/null"
  -o "Dir::State::lists=$work/lists"
  -o "Dir::Cache::archives=$work/archives"
  -o "Dir::Cache::pkgcache=$work/pkgcache.bin"
  -o "Dir::Cache::srcpkgcache=$work/srcpkgcache.bin"
  -o "Dir::State::status=$work/status"
  -o "Dir::Etc::trusted=/usr/share/keyrings/ubuntu-archive-keyring.gpg"
  -o "Dir::Etc::trustedparts=/usr/share/keyrings"
  -o "APT::Architecture=arm64"
  -o "APT::Architectures::=arm64"
  -o "Acquire::Languages=none"
)
echo "Resolving ARM64 packages for $release"
apt-get "${apt_opts[@]}" update >/dev/null
# libstdc++-dev 只是虚拟包，实际开发包随发行版的 GCC 主版本命名。
case "$release" in
  noble) stdcxx_dev=libstdc++-13-dev ;;
  jammy) stdcxx_dev=libstdc++-11-dev ;;
esac
# 只取构建需要的包及其依赖。
apt-get "${apt_opts[@]}" install --print-uris -y --no-install-recommends \
  libc6 libc6-dev libstdc++6 "$stdcxx_dev" libgcc-s1 linux-libc-dev \
  ros-jazzy-rclcpp ros-jazzy-geometry-msgs ros-jazzy-ament-cmake \
  | sed -n "s/^'\([^']*\)'.*/\1/p" > "$work/urls.txt"
[[ -s "$work/urls.txt" ]] || { echo "No ARM64 packages resolved." >&2; exit 1; }
echo "Downloading $(wc -l < "$work/urls.txt") packages"
while read -r url; do printf '%s\0%s\0' "$url" "${url##*/}"; done < "$work/urls.txt" \
  | xargs -0 -P 8 -n 2 bash -c 'curl -fsSL --retry 3 -o "$0/$2" "$1"' "$work/downloads"
stage="$(mktemp -d "$work/sysroot.XXXXXX")"
for package in "$work/downloads"/*.deb; do
  dpkg-deb -x "$package" "$stage"
done
# Debian 包里仍带 /lib、/bin 等旧路径；按 usrmerge 布局并入 usr/ 再改成符号链接，
# 与开发板实际的 /lib -> usr/lib 一致，链接脚本里的绝对路径才能在 sysroot 内解析。
for legacy in lib bin sbin; do
  if [[ -d "$stage/$legacy" && ! -L "$stage/$legacy" ]]; then
    mkdir -p "$stage/usr/$legacy"
    cp -a "$stage/$legacy/." "$stage/usr/$legacy/"
    rm -rf "$stage/$legacy"
    ln -s "usr/$legacy" "$stage/$legacy"
  fi
done
ln -sfn usr/lib "$stage/lib"
python3 "$repo/version/tools/relativize_sysroot.py" "$stage"
# 与 check_cross.sh 相同的必检项，避免把残缺 sysroot 交给交叉构建。
for path in usr/include/stdio.h usr/include/aarch64-linux-gnu/bits/wordsize.h \
  usr/lib/aarch64-linux-gnu/crt1.o usr/lib/aarch64-linux-gnu/libc.so \
  usr/lib/aarch64-linux-gnu/libstdc++.so.6 \
  opt/ros/jazzy/share/ament_cmake/cmake/ament_cmakeConfig.cmake \
  opt/ros/jazzy/share/rclcpp/cmake/rclcppConfig.cmake \
  opt/ros/jazzy/share/geometry_msgs/cmake/geometry_msgsConfig.cmake \
  opt/ros/jazzy/lib/librclcpp.so; do
  [[ -f "$stage/$path" ]] || {
    echo "Incomplete sysroot, missing: $path" >&2
    exit 1
  }
done
python3 - "$stage/opt/ros/jazzy/lib/librclcpp.so" <<'PY'
from pathlib import Path
import sys
header = Path(sys.argv[1]).open('rb').read(20)
if header[:6] != b'\x7fELF\x02\x01' or int.from_bytes(header[18:20], 'little') != 183:
    raise SystemExit('sysroot librclcpp.so is not an ARM64 ELF library')
PY
destination="$(realpath -m "$destination")"
mv -T "$stage" "$destination"
printf 'Sysroot ready: %s\n' "$destination"
printf 'Set CAR_SYSROOT in version/cross.conf if you used a custom directory.\n'
