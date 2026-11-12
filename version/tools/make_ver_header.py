#!/usr/bin/env python3
"""给版本包加头部信息，用法与产线工具 tools_ver_maker 一致。

用法：python3 version/tools/make_ver_header.py MAGIC 版本号 输入文件 输出文件
      python3 version/tools/make_ver_header.py --verify 版本包
MAGIC 支持 DEAD5409 这样的十六进制写法；--verify 只读校验已有包的头信息。
"""

import argparse
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import ver_header  # noqa: E402  头部格式定义在上一层的 version/ 里


def parse_magic(text):
    try:
        return int(text, 16)
    except ValueError:
        raise SystemExit(f"Invalid magic: {text}")


def verify(package):
    with tempfile.TemporaryDirectory(prefix="verify-") as temp:
        payload = Path(temp) / "payload"
        try:
            info = ver_header.strip(package, payload)
        except ver_header.HeaderError as error:
            print(f"FAILED {error}", file=sys.stderr)
            return 1
        if info is None:
            print("No version header found")
            return 1
        print(f"magic     0x{ver_header.MAGIC:08X}")
        print(f"version   {info['version']}")
        print(f"built     {info['build_time']}")
        print(f"size      {info['size']}")
        print(f"crc32     0x{info['crc32']:08X}")
        print("OK")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("magic", nargs="?", help="头部 magic，十六进制，如 DEAD5409")
    parser.add_argument("version", nargs="?", help="版本号")
    parser.add_argument("source", nargs="?", type=Path, help="未加头的版本包")
    parser.add_argument("destination", nargs="?", type=Path, help="加头后的输出文件")
    parser.add_argument("--verify", type=Path, help="只校验已有版本包的头信息")
    args = parser.parse_args()

    if args.verify:
        return verify(args.verify)
    if not (args.magic and args.version and args.source and args.destination):
        parser.error("magic, version, source and destination are required")
    magic = parse_magic(args.magic)
    payload = args.source.read_bytes()
    header = ver_header.build(args.version, payload, magic)
    args.destination.write_bytes(header + payload)
    print(f"Wrote {args.destination} ({len(header) + len(payload)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
