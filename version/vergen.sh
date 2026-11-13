#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo "用法: bash version/vergen.sh（重新打包 target/ 中最近一次构建）"
  exit 0
fi
[[ $# == 0 ]] || { echo "无需参数；版本和架构从 target/version.json 读取。" >&2; exit 2; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$repo/target/version.json" ]] || { echo "请先运行 version/autogen.sh" >&2; exit 1; }
read -r version arch commit < <(python3 - "$repo/target/version.json" "$repo/version" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
from update import validate_manifest
info = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
validate_manifest(info, info["architecture"], info["version"])
if info["architecture"] not in ("arm64", "amd64") or len(info["version"]) > 31:
    raise SystemExit("Invalid build metadata")
print(info["version"], info["architecture"], info["commit"])
PY
)
prefix="$repo/target/tb6612_car_ros2"
for executable in keyboard_teleop car_daemon web_teleop; do
  python3 "$repo/version/tools/verify_binary.py" "$prefix/lib/tb6612_car_ros2/$executable" "$arch" "$version" "$commit"
done
[[ -f "$prefix/share/tb6612_car_ros2/local_setup.bash" ]]
stage="$repo/version/tmp/tb6612-car"
rm -rf "$stage"
app="$stage/root/work/app/daemon"
mkdir -p "$stage/root/DEBIAN" "$app/ros" "$repo/version/out"
touch "$repo/version/tmp/COLCON_IGNORE"
cp -aL "$prefix" "$app/ros/tb6612_car_ros2"
for executable in car_daemon keyboard_teleop web_teleop; do
  install -m 755 "$prefix/lib/tb6612_car_ros2/$executable" "$app/$executable"
done
cp "$repo/target/version.json" "$app/version.json"
for script in runtime_env.sh agent.sh boot_apps.sh keyboard_teleop.sh web_teleop.sh ros_launch.sh; do
  install -m 755 "$repo/scripts/$script" "$app/$script"
done
cat > "$stage/root/DEBIAN/control" <<EOF
Package: tb6612-car
Version: $version
Architecture: $arch
Maintainer: shuaijie <202649427@qq.com>
Description: Raspberry Pi ROS 2 car application payload
EOF
cd "$stage"
name="tb6612-car_${version}_${arch}"
dpkg-deb --root-owner-group -Zgzip --build root "$name.deb"
md5sum "$name.deb" > "$name.deb.md5"
sha256sum "$name.deb" > "$name.deb.sha256"
tar -cjf "$name.bin" "$name.deb" "$name.deb.md5" "$name.deb.sha256"
python3 "$repo/version/tools/make_ver_header.py" DEAD5409 "$version" "$name.bin" "$name.bivi"
tar -czf tb6612-car-bootstrap.tar.gz -C "$repo" \
  scripts/bootstrap.sh scripts/carctl.sh scripts/car.conf scripts/install_agent.sh \
  scripts/tb6612-car.service scripts/tb6612-car-web.service version/update.py version/ver_header.py
rm -rf -- "$repo/version/out"
mkdir -p "$repo/version/out"
for file in "$name.bin" "$name.bivi" tb6612-car-bootstrap.tar.gz; do
  cp "$file" "$repo/version/out/$file.partial"
  mv -f "$repo/version/out/$file.partial" "$repo/version/out/$file"
  echo "$repo/version/out/$file"
done
