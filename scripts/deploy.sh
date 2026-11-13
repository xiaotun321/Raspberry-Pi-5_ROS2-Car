#!/usr/bin/env bash
set -eo pipefail
usage() {
  echo "用法: bash scripts/deploy.sh FILE USER@BOARD [--reboot]"
}
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then usage; exit 0; fi
[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }
package="$1"
board="$2"
action="${3:-}"
[[ -z "$action" || "$action" == --reboot ]] || { usage >&2; exit 2; }
[[ -f "$package" && ( "$package" == *.bin || "$package" == *.bivi || "$package" == *.ver ) ]] || {
  echo "请提供已生成的 .bin、.bivi 或旧格式 .ver 文件: $package" >&2; exit 2;
}
[[ "$board" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
  echo "开发板地址格式应为 USER@HOST，例如 pi@192.168.1.10" >&2; exit 2;
}
remote="$(ssh "$board" 'mktemp /tmp/tb6612-upload.XXXXXXXX.ver')"
[[ "$remote" =~ ^/tmp/tb6612-upload\.[A-Za-z0-9]+\.ver$ ]] || exit 1
scp -- "$package" "$board:$remote"
ssh -t "$board" "sudo bash -c '
set -e
test -d /work/app/tmp/ver
exec 9>/work/app/.upload.lock
flock -n 9
test ! -e /work/app/tmp/ver/1.ver
install -m 600 $remote /work/app/tmp/ver/1.ver.partial
sync
mv /work/app/tmp/ver/1.ver.partial /work/app/tmp/ver/1.ver
sync
'"
ssh "$board" "rm -f -- $remote"
echo "Staged /work/app/tmp/ver/1.ver on $board"
if [[ "$action" == --reboot ]]; then
  ssh -t "$board" 'sudo reboot'
fi
