#!/usr/bin/env python3
"""版本包头部格式：与产线工具 tools_ver_maker 的输出一致。

带头的版本包 = 1024 字节头部 + 原始载荷，载荷字节与未加头的 .bin 完全相同。
头部字段：

    0x00 uint32 magic         大端 0xDEAD5409
    0x04 char   version[32]   NUL 结尾
    0x24 char   buildtime[20] "YYYY/MM/DD HH:MM:SS"
    0x38 char   reserved[12]
    0x44 uint32 size          大端，载荷字节数
    0x48 uint32 crc32         大端，zlib.crc32(载荷)
    0x4C uint32 type          小端，1
    0x50 零填充至 1024

构建端用 build() 生成头部，板端用 strip() 剥离并核对长度与 CRC32。
"""

import datetime
import shutil
import struct
import zlib

MAGIC = 0xDEAD5409
HEADER_SIZE = 1024
OFFSET_MAGIC = 0x00
OFFSET_VERSION = 0x04
OFFSET_TIME = 0x24
OFFSET_RESERVED = 0x38
OFFSET_SIZE = 0x44
OFFSET_CRC32 = 0x48
OFFSET_TYPE = 0x4C
VERSION_SIZE = 32
TIME_SIZE = 20
RESERVED_SIZE = 12
PACKAGE_TYPE = 1


class HeaderError(ValueError):
    """头部字段非法，或载荷与头部记录的长度/校验值不符。"""


def build(version, payload, magic=MAGIC, when=None):
    """根据版本号和载荷生成 1024 字节头部。"""
    encoded = version.encode()
    if not encoded or len(encoded) >= VERSION_SIZE:
        raise HeaderError("Version does not fit in the header field")
    stamp = (when or datetime.datetime.now()).strftime("%Y/%m/%d %H:%M:%S")
    if len(stamp.encode()) >= TIME_SIZE:
        raise HeaderError("Build time does not fit in the header field")
    header = bytearray(HEADER_SIZE)
    struct.pack_into(">I", header, OFFSET_MAGIC, magic)
    header[OFFSET_VERSION:OFFSET_VERSION + len(encoded)] = encoded
    header[OFFSET_TIME:OFFSET_TIME + len(stamp)] = stamp.encode()
    struct.pack_into(">I", header, OFFSET_SIZE, len(payload))
    struct.pack_into(">I", header, OFFSET_CRC32, zlib.crc32(payload))
    struct.pack_into("<I", header, OFFSET_TYPE, PACKAGE_TYPE)
    return bytes(header)


def parse(header, magic=MAGIC):
    """解析头部字段；没有头部或 magic 不符时返回 None。"""
    if len(header) < HEADER_SIZE:
        return None
    if struct.unpack_from(">I", header, OFFSET_MAGIC)[0] != magic:
        return None
    version = header[OFFSET_VERSION:OFFSET_VERSION + VERSION_SIZE]
    stamp = header[OFFSET_TIME:OFFSET_TIME + TIME_SIZE]
    size, checksum = struct.unpack_from(">II", header, OFFSET_SIZE)
    package_type = struct.unpack_from("<I", header, OFFSET_TYPE)[0]
    return {
        "version": version.split(b"\0")[0].decode(errors="replace"),
        "build_time": stamp.split(b"\0")[0].decode(errors="replace"),
        "size": size,
        "crc32": checksum,
        "type": package_type,
    }


def strip(source, destination, magic=MAGIC):
    """把版本包的载荷写到 destination，返回头信息；没有头部时返回 None。

    带头的包会先核对头部记录的长度与 CRC32，不一致即报错，避免安装被篡改的载荷。
    """
    with open(source, "rb") as stream:
        info = parse(stream.read(HEADER_SIZE), magic)
        if info is None:
            stream.seek(0)
            with open(destination, "wb") as output:
                shutil.copyfileobj(stream, output)
            return None
        remaining = info["size"]
        checksum = 0
        with open(destination, "wb") as output:
            while remaining > 0:
                block = stream.read(min(1024 * 1024, remaining))
                if not block:
                    raise HeaderError("Package is shorter than the size in the header")
                checksum = zlib.crc32(block, checksum)
                output.write(block)
                remaining -= len(block)
        if checksum != info["crc32"]:
            raise HeaderError("Payload checksum does not match the header")
    return info
