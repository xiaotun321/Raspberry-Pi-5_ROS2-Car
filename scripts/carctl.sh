#!/usr/bin/env bash
set -e
action="${1:-status}"
shift || true
case "$action" in
  start|restart)
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
    exec /bin/bash /work/app/daemon/keyboard_teleop.sh "$@"
    ;;
  web)
    exec /bin/bash /work/app/daemon/web_teleop.sh "$@"
    ;;
  bringup)
    exec /bin/bash /work/app/daemon/ros_launch.sh "$@"
    ;;
  rollback)
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
    echo "Usage: carctl {start|stop|restart|status|logs|version|teleop|web|bringup|rollback}" >&2
    exit 2
    ;;
esac
