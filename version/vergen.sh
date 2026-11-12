#!/usr/bin/env bash
# 版本包外层沿用 hs411 的 tar.bz2 + deb + md5，另加 SHA-256 校验；
# 同时生成一份加 1024 字节头信息的 .bivi。
# 通常由 autogen.sh 调用，参数依次为：版本号、架构、已安装包目录、提交号。
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?Usage: vergen.sh VERSION ARCH INSTALLED_PACKAGE COMMIT}"
arch="${2:?}"
prefix="${3:?}"
commit="${4:?}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~][A-Za-z0-9.]+)?$ ]] || exit 2
[[ "$arch" == arm64 || "$arch" == amd64 ]] || exit 2
[[ "$commit" =~ ^[A-Za-z0-9._-]+$ ]] || exit 2
# 静态核对架构与嵌入版本，允许在 x86 主机打包 ARM 程序。
for executable in keyboard_teleop car_daemon web_teleop; do
  python3 "$repo/version/tools/verify_binary.py" \
    "$prefix/lib/tb6612_car_ros2/$executable" "$arch" "$version" "$commit"
done
mkdir -p "$repo/target" "$repo/version/out"
touch "$repo/target/COLCON_IGNORE"
# 打包暂存树固定放在 version/tmp/<产品名>，与产线工程 version/tmp/SpiderHunter 一致；
# 每次构建前重建，保留下来便于排查包内容。
stage="$repo/version/tmp/tb6612-car"
rm -rf "$stage"
# 暂存树里带着安装好的 package.xml，colcon 会当成重复包，这里按 target/ 的做法屏蔽。
touch "$repo/version/tmp/COLCON_IGNORE"
root="$stage/root"
app="$root/work/app/daemon"
mkdir -p "$root/DEBIAN" "$app/ros"
# 解引用安装目录的链接，发布包不能依赖构建机的源码路径。
cp -aL "$prefix" "$app/ros/tb6612_car_ros2"
for script in runtime_env.sh agent.sh boot_apps.sh keyboard_teleop.sh web_teleop.sh ros_launch.sh; do
  install -m 755 "$repo/scripts/$script" "$app/$script"
done
# 版本清单供 carctl version 显示，并由升级器核对产品、架构和版本。
python3 - "$app/version.json" "$version" "$arch" "$commit" <<'PY'
import datetime, json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "product": "tb6612-car", "version": sys.argv[2], "architecture": sys.argv[3],
    "commit": sys.argv[4], "ros_distro": "jazzy", "format": 1,
    "built_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}, indent=2) + "\n", encoding="utf-8")
PY
# 生成 deb 元数据；此包作为应用载荷，不包含系统安装维护脚本。
cat > "$root/DEBIAN/control" <<EOF
Package: tb6612-car
Version: $version
Architecture: $arch
Maintainer: shuaijie <202649427@qq.com>
Description: Raspberry Pi ROS 2 car application payload
EOF
deb="tb6612-car_${version}_${arch}.deb"
dpkg-deb --root-owner-group -Zgzip --build "$root" "$stage/$deb"
cd "$stage"
# 为载荷生成校验文件，再用临时文件名打包，完成后改为正式 .bin 文件。
md5sum "$deb" > "$deb.md5"
sha256sum "$deb" > "$deb.sha256"
archive="$repo/version/out/tb6612-car_${version}_${arch}.bin"
tar -cjf "$archive.partial" "$deb" "$deb.md5" "$deb.sha256"
mv -f "$archive.partial" "$archive"
# 同一份载荷再生成带 1024 字节头信息的版本包：头部含 magic、版本、构建时间、
# 长度和 CRC32，与产线 tools_ver_maker 的输出格式一致。
# 带头的版本包放在 version/ 下，与产线工程 version/bivi_*.bivi 的位置一致。
magic="${CAR_VER_MAGIC:-DEAD5409}"
headered="$repo/version/tb6612-car_${version}_${arch}.bivi"
python3 "$repo/version/tools/make_ver_header.py" "$magic" "$version" "$archive" "$headered"
# 首次初始化只需这个小包；后续只传版本包，无需再次安装服务。
tar -czf "$repo/version/out/tb6612-car-bootstrap.tar.gz" -C "$repo" \
  scripts/bootstrap.sh scripts/vinstall.sh scripts/vmonitor.sh \
  scripts/carctl.sh scripts/car.conf scripts/tb6612-car.service \
  scripts/install_agent.sh version/update.py version/ver_header.py
echo "Release: $archive"
echo "Release with header: $headered"
