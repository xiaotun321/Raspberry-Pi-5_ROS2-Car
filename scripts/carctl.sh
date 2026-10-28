#!/usr/bin/env bash
# 安装为 /usr/local/bin/carctl；日常操作不需要手动 source ROS 环境。
# 用法：carctl status/logs/version/teleop；启停和回退通常需要 sudo。
set -e
action="${1:-status}"
shift || true
case "$action" in
  start|restart)
    # 清除连续启动失败的限流状态，允许修复问题后再次启动。
    systemctl reset-failed tb6612-car.service
    exec systemctl "$action" tb6612-car.service "$@"
    ;;
  stop|status)
    exec systemctl "$action" tb6612-car.service "$@"
    ;;
  logs)
    exec journalctl -u tb6612-car.service -f "$@"
    ;;
  version)
    cat /work/app/daemon/version.json
    ;;
  teleop)
    # 后续参数原样传给键盘节点，例如 --ros-args -p key_timeout:=0.8。
    exec /bin/bash /work/app/daemon/keyboard_teleop.sh "$@"
    ;;
  rollback)
    # 先停服务再切换版本；拒绝存在待更新包时回退，避免启动后又被升级。
    [[ "$EUID" == 0 ]] || { echo "Use sudo carctl rollback" >&2; exit 1; }
    if [[ -e /work/app/tmp/ver/1.ver || -e /work/app/tmp/ver/.installing.ver ]]; then
      echo "A pending update exists; move it out of tmp/ver before rollback." >&2
      exit 1
    fi
    systemctl stop tb6612-car.service
    /usr/bin/python3 /work/car-bootstrap/update.py rollback
    systemctl reset-failed tb6612-car.service
    systemctl start tb6612-car.service
    ;;
  *)
    echo "Usage: carctl {start|stop|restart|status|logs|version|teleop|rollback}" >&2
    exit 2
    ;;
esac
