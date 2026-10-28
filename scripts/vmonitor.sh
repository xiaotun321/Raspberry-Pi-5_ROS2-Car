#!/usr/bin/env bash
# systemd 的启动前入口，每次服务启动时执行一次，并非常驻轮询进程。
# 等待 vinstall.sh 完成后，systemd 才继续启动 boot_apps.sh。
set -e
bootstrap="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec /bin/bash "$bootstrap/vinstall.sh"
