#!/usr/bin/env python3
"""打包前静态核对 ELF 架构与嵌入版本信息，不执行目标程序。"""
from pathlib import Path
import sys


def verify(path, architecture, version, commit):
    data = path.read_bytes()
    machines = {"arm64": 183, "amd64": 62}
    if len(data) < 64 or data[:6] != b"\x7fELF\x02\x01":
        raise ValueError(f"Not a little-endian ELF64 executable: {path}")
    if int.from_bytes(data[16:18], "little") not in (2, 3):
        raise ValueError(f"Not an executable/PIE: {path}")
    if int.from_bytes(data[18:20], "little") != machines[architecture]:
        raise ValueError(f"ELF architecture is not {architecture}: {path}")
    identity = f"TB6612_BUILD:{version}:{commit}\0".encode("ascii")
    if identity not in data:
        raise ValueError(f"Embedded version/commit mismatch: {path}")


if __name__ == "__main__":
    verify(Path(sys.argv[1]), *sys.argv[2:5])
    print(f"Verified {sys.argv[1]}")
