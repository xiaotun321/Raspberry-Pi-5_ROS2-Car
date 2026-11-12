#!/usr/bin/env bash
# 生成不带版本号的交叉工具入口；Ubuntu 交叉包只提供 gcc-13 之类的带版本号文件，
# 而 check_cross.sh 与 toolchain_aarch64.cmake 都按 aarch64-linux-gnu- 前缀查找。
# 两种做法二选一：
#   1) 安装元包，自带未版本化入口（推荐）：
#        sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
#   2) 用本脚本在用户目录建软链接，不需要 root：
#        bash version/link_cross_tools.sh
# 用法：bash version/link_cross_tools.sh [目标目录]，默认 $HOME/bin
set -euo pipefail
destination="${1:-$HOME/bin}"
prefix="aarch64-linux-gnu-"
mkdir -p "$destination"
# 带版本号的编译器入口来自 gcc-13-aarch64-linux-gnu / g++-13-aarch64-linux-gnu。
for tool in gcc g++ cpp gcov; do
  for candidate in /usr/bin/$prefix$tool-13 /usr/bin/$prefix$tool-12; do
    if [[ -x "$candidate" ]]; then
      ln -sfn "$candidate" "$destination/$prefix$tool"
      break
    fi
  done
done
# binutils 直接提供未版本化入口。
for tool in ar ranlib strip ld nm; do
  [[ -x "/usr/bin/$prefix$tool" ]] && ln -sfn "/usr/bin/$prefix$tool" "$destination/$prefix$tool"
done
for tool in gcc g++ ar ranlib strip ld; do
  [[ -x "$destination/$prefix$tool" ]] || {
    echo "Missing cross tool: $prefix$tool" >&2
    echo "Install gcc-13-aarch64-linux-gnu g++-13-aarch64-linux-gnu first." >&2
    exit 1
  }
done
printf 'Cross tool links ready: %s/%s\n' "${destination%/}" "$prefix"
