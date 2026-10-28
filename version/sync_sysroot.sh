#!/usr/bin/env bash
# 从 ARM64 开发板只读同步编译环境；不修改板上的库或配置。
# 用法：bash version/sync_sysroot.sh 用户名@开发板IP [本地新目录]
# 两端需要 rsync，开发板需已安装 Jazzy 及其开发头文件。
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
board="${1:?Usage: sync_sysroot.sh USER@BOARD [NEW_SYSROOT_DIRECTORY]}"
destination="${2:-$HOME/rpi5-sysroot}"
[[ $# -le 2 ]] || exit 2
[[ "$board" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || exit 2
[[ ! -e "$destination" && ! -L "$destination" ]] || {
  echo "Destination already exists; choose a new directory: $destination" >&2
  exit 2
}
[[ "$(ssh "$board" 'dpkg --print-architecture')" == arm64 ]] || {
  echo "The remote machine must be the ARM64 development board." >&2
  exit 2
}
ssh "$board" 'test -f /opt/ros/jazzy/lib/librclcpp.so && command -v rsync >/dev/null'
command -v rsync >/dev/null
mkdir -p "$(dirname -- "$destination")"
destination="$(realpath -m "$destination")"
stage="$(mktemp -d "$(dirname -- "$destination")/sysroot-sync.XXXXXX")"
mkdir -p "$stage/usr" "$stage/opt/ros" "$stage/etc"
echo "Copying board sysroot to $stage (may take several minutes)"
rsync -a --no-owner --no-group "$board:/usr/" "$stage/usr/"
rsync -a --no-owner --no-group "$board:/opt/ros/jazzy" "$stage/opt/ros/"
rsync -a --no-owner --no-group "$board:/lib" "$stage/"
if ssh "$board" 'test -e /lib64'; then
  rsync -a --no-owner --no-group "$board:/lib64" "$stage/"
fi
rsync -aL --no-owner --no-group "$board:/etc/os-release" "$stage/etc/"
# 只修改副本中的绝对符号链接，防止它们指向编译主机的 /usr 或 /lib。
python3 "$repo/version/relativize_sysroot.py" "$stage"
mv -T "$stage" "$destination"
printf 'Sysroot ready: %s\n' "$destination"
printf 'Set CAR_SYSROOT in version/cross.conf if you used a custom directory.\n'
