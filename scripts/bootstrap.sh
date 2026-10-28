#!/usr/bin/env bash
# 开发板首次初始化：只安装更新器/服务/默认配置，不替换现有第三方 /work 脚本。
# 用法：sudo bash scripts/bootstrap.sh [Agent 环境脚本的绝对路径]
set -e
[[ "$EUID" == 0 ]] || { echo "Run with sudo" >&2; exit 1; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
agent_setup="${1:-}"
[[ $# -le 1 ]] || { echo "Usage: bootstrap.sh [AGENT_SETUP_PATH]" >&2; exit 2; }
# 安装前检查工具和已有目录，避免覆盖其他应用的运行目录。
for command in python3 dpkg dpkg-deb systemctl; do
  command -v "$command" >/dev/null || { echo "Missing $command" >&2; exit 1; }
done
[[ -f /opt/ros/jazzy/setup.bash ]] || { echo "Install ROS 2 Jazzy first" >&2; exit 1; }
if [[ -n "$agent_setup" ]]; then
  agent_setup="$(realpath -e "$agent_setup")"
fi
if [[ -e /work/app/daemon && ! -L /work/app/daemon ]]; then
  echo "Existing /work/app/daemon is not managed by this updater; migrate it first." >&2
  exit 1
fi
install -d -m 755 /work/car-bootstrap /work/app/cfg /work/app/tmp/ver \
  /work/app/status/update /work/app/.ver /work/app/releases /work/data/log/ros
# 避免重新初始化时替换正在执行中的更新脚本。
if systemctl is-active --quiet tb6612-car.service; then
  echo "Stop tb6612-car.service before reinstalling bootstrap files" >&2
  exit 1
fi
install -m 755 "$repo/version/update.py" /work/car-bootstrap/update.py
install -m 755 "$repo/scripts/vinstall.sh" /work/car-bootstrap/vinstall.sh
install -m 755 "$repo/scripts/vmonitor.sh" /work/car-bootstrap/vmonitor.sh
install -m 755 "$repo/scripts/carctl.sh" /usr/local/bin/carctl
# 默认配置仅首次写入，保留开发板已经调整的参数。
if [[ ! -f /work/app/cfg/car.conf ]]; then
  install -m 644 "$repo/scripts/car.conf" /work/app/cfg/car.conf
fi
if [[ -n "$agent_setup" ]]; then
  # printf %q 生成 Bash 安全引用，支持路径中有空格。
  printf '\nMICRO_ROS_AGENT_SETUP=%q\n' "$agent_setup" >> /work/app/cfg/car.conf
fi
install -m 644 "$repo/scripts/tb6612-car.service" /etc/systemd/system/tb6612-car.service
systemctl daemon-reload
# 只设置开机自启；应用版本包投递并重启后才开始运行。
systemctl enable tb6612-car.service
echo "Bootstrap installed. Stage a release at /work/app/tmp/ver/1.ver, then reboot."
