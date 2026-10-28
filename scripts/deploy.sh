#!/usr/bin/env bash
# 原子投递升级包；默认只上传，显式 --reboot 才重启开发板。
# 用法：bash scripts/deploy.sh 本地版本.ver 用户名@开发板IP [--reboot]
# 前提：开发板已完成 bootstrap，远端用户可使用 sudo。
set -e
package="${1:?Usage: deploy.sh FILE.ver USER@BOARD [--reboot]}"
board="${2:?}"
action="${3:-}"
[[ $# -le 3 && ( -z "$action" || "$action" == --reboot ) ]] || exit 2
[[ -f "$package" && "$package" == *.ver ]] || exit 2
# 限定 SSH 目标格式，避免把参数误解释为选项或远端命令。
[[ "$board" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || exit 2
# 先传到普通用户可写的临时文件，避免更新器读取尚未传完的包。
remote="$(ssh "$board" 'mktemp /tmp/tb6612-upload.XXXXXXXX.ver')"
[[ "$remote" =~ ^/tmp/tb6612-upload\.[A-Za-z0-9]+\.ver$ ]] || exit 1
scp -- "$package" "$board:$remote"
# sudo 在远端终端提示密码；完整复制并 sync 后才公开 1.ver。
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
