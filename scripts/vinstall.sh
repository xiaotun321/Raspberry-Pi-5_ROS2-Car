#!/usr/bin/env bash
# 稳定更新入口位于 /work/car-bootstrap，应用版本更新不覆盖它。
# 由 vmonitor.sh 调用：检查 /work/app/tmp/ver/1.ver 并执行校验、安装和切换。
# 更新失败但仍有当前版本时，更新器允许服务继续启动当前版本。
set -e
bootstrap="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec /usr/bin/python3 "$bootstrap/update.py" apply
