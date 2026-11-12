#!/usr/bin/env python3
"""将同步副本中的绝对符号链接改为 sysroot 内的相对链接。"""
import os
from pathlib import Path
import posixpath
import sys


def convert(root):
    root = root.resolve(strict=True)
    if root == Path("/") or not (root / "opt/ros/jazzy").is_dir():
        raise ValueError("Expected a copied sysroot containing opt/ros/jazzy")
    if root == Path("/opt/ros/jazzy") or root == Path("/usr"):
        raise ValueError("Refusing to modify a host installation")
    count = 0
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in folders + files:
            link = Path(directory) / name
            if link.is_symlink():
                target = os.readlink(link)
                if target.startswith("/"):
                    # 按目标 Linux 根目录归一化 /../，不能让链接越过副本根目录。
                    target = posixpath.normpath(target).lstrip("/")
                    replacement = os.path.relpath(root / target, link.parent)
                    link.unlink()
                    link.symlink_to(replacement)
                    count += 1
    return count


if __name__ == "__main__":
    print(f"Converted {convert(Path(sys.argv[1]))} absolute symlinks")
