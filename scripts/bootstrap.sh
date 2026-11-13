#!/usr/bin/env bash
set -e
[[ "$EUID" == 0 ]] || { echo "Run with sudo" >&2; exit 1; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
agent_setup="${1:-}"
[[ $# -le 1 ]] || { echo "Usage: bootstrap.sh [AGENT_SETUP_PATH]" >&2; exit 2; }
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
if systemctl is-active --quiet tb6612-car.service; then
  echo "Stop tb6612-car.service before reinstalling bootstrap files" >&2
  exit 1
fi
install -m 755 "$repo/version/update.py" /work/car-bootstrap/update.py
install -m 755 "$repo/version/ver_header.py" /work/car-bootstrap/ver_header.py
install -m 755 "$repo/scripts/carctl.sh" /usr/local/bin/carctl
if [[ ! -f /work/app/cfg/car.conf ]]; then
  install -m 644 "$repo/scripts/car.conf" /work/app/cfg/car.conf
fi
if [[ -n "$agent_setup" ]]; then
  printf '\nMICRO_ROS_AGENT_SETUP=%q\n' "$agent_setup" >> /work/app/cfg/car.conf
fi
install -m 644 "$repo/scripts/tb6612-car.service" /etc/systemd/system/tb6612-car.service
install -m 644 "$repo/scripts/tb6612-car-web.service" /etc/systemd/system/tb6612-car-web.service
systemctl daemon-reload
systemctl enable tb6612-car.service
echo "Bootstrap installed. Stage a release at /work/app/tmp/ver/1.ver, then reboot."
echo "Web control (opt-in): systemctl enable --now tb6612-car-web.service"
