#!/usr/bin/env python3
"""版本安装工具：校验归档、准备独立版本目录并切换当前版本。

apply：处理待更新包；rollback：切换到上一版本；check FILE.ver：仅检查归档。
默认管理 /work/app，apply/rollback 由启动脚本或 carctl 以 root 权限调用。
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

PRODUCT = "tb6612-car"
VERSION_RE = r"[0-9]+\.[0-9]+\.[0-9]+([.+~][A-Za-z0-9.]+)?"
PAYLOAD = "work/app/daemon"
MAX_BYTES = 1024 * 1024 * 1024


def digest(path, algorithm="sha256"):
    """分块计算文件校验值，避免把整个版本包读入内存。"""
    result = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def extract_members(archive, destination, payload=False):
    """只提取普通文件/目录，禁止绝对路径、越界路径、链接与设备节点。"""
    total = 0
    seen = set()
    for member in archive:
        name = member.name
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
            raise ValueError(f"Unsafe archive path: {name}")
        name = path.as_posix()
        if name in seen:
            raise ValueError(f"Duplicate archive entry: {name}")
        seen.add(name)
        if len(seen) > 10000:
            raise ValueError("Too many archive entries")
        if not member.isfile() and not member.isdir():
            raise ValueError(f"Links/special files are not allowed: {name}")
        if payload:
            parents = {".", "work", "work/app", PAYLOAD}
            if not name.startswith(PAYLOAD + "/"):
                if name not in parents or not member.isdir():
                    raise ValueError(f"Unexpected payload path: {name}")
        elif len(path.parts) != 1 or not member.isfile():
            raise ValueError("Version wrapper must contain only flat files")
        total += member.size
        if member.size < 0 or total > MAX_BYTES:
            raise ValueError("Version package is too large")
        target = destination / name
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o755 if member.mode & 0o111 else 0o644)


def unpack_wrapper(package, directory):
    """解开 .ver 外层，确认仅含一个 deb 及其两种校验文件。"""
    with tarfile.open(package, "r:bz2") as archive:
        extract_members(archive, directory)
    debs = list(directory.glob("*.deb"))
    if len(debs) != 1:
        raise ValueError("Expected exactly one deb payload")
    deb = debs[0]
    expected = {deb.name, deb.name + ".md5", deb.name + ".sha256"}
    if {entry.name for entry in directory.iterdir()} != expected:
        raise ValueError("Unexpected or missing checksum files")
    for algorithm in ("md5", "sha256"):
        tokens = (directory / (deb.name + "." + algorithm)).read_text().split()
        if len(tokens) != 2 or tokens[1] != deb.name or tokens[0] != digest(deb, algorithm):
            raise ValueError(f"{algorithm} checksum mismatch")
    return deb


def read_field(deb, field):
    return subprocess.check_output(
        ["dpkg-deb", "--field", str(deb), field], text=True
    ).strip()


def validate_manifest(manifest, architecture, version):
    """核对载荷清单与开发板架构、deb 版本是否一致。"""
    if manifest.get("product") != PRODUCT or manifest.get("format") != 1:
        raise ValueError("Wrong product or package format")
    if manifest.get("architecture") != architecture:
        raise ValueError("Wrong CPU architecture")
    if manifest.get("ros_distro") != "jazzy":
        raise ValueError("This updater requires a Jazzy release")
    if manifest.get("version") != version or not re.fullmatch(VERSION_RE, version):
        raise ValueError("Version metadata mismatch")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", manifest.get("commit", "")):
        raise ValueError("Invalid source commit")


def unpack_deb(deb, destination, architecture):
    if read_field(deb, "Package") != PRODUCT:
        raise ValueError("Wrong Debian package name")
    if read_field(deb, "Architecture") != architecture:
        raise ValueError("Release CPU architecture does not match this board")
    version = read_field(deb, "Version")
    # 使用 dpkg-deb 读取数据区，不以 dpkg -i 修改系统，也不执行维护脚本。
    process = subprocess.Popen(
        ["dpkg-deb", "--fsys-tarfile", str(deb)], stdout=subprocess.PIPE
    )
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            extract_members(archive, destination, payload=True)
        # 消费 tar 尾部填充，避免提前关闭管道让 dpkg-deb 收到 SIGPIPE。
        while process.stdout.read(1024 * 1024):
            pass
        process.stdout.close()
        if process.wait() != 0:
            raise ValueError("Cannot decode deb payload")
    except BaseException:
        process.kill()
        process.wait()
        raise
    release = destination / PAYLOAD
    manifest = json.loads((release / "version.json").read_text(encoding="utf-8"))
    validate_manifest(manifest, architecture, version)
    required = [
        "boot_apps.sh", "runtime_env.sh", "agent.sh", "keyboard_teleop.sh",
        "ros/tb6612_car_ros2/lib/tb6612_car_ros2/car_daemon",
        "ros/tb6612_car_ros2/lib/tb6612_car_ros2/keyboard_teleop",
        "ros/tb6612_car_ros2/share/tb6612_car_ros2/local_setup.bash",
    ]
    for name in required:
        if not (release / name).is_file():
            raise ValueError(f"Missing release file: {name}")
    return release, manifest


def atomic_text(path, text):
    """先写临时文件再替换，避免状态文件只写入一部分。"""
    temporary = path.with_name(path.name + ".new")
    with temporary.open("w", encoding="utf-8") as stream:
        stream.write(text)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def atomic_link(link, target):
    """原子替换版本链接，切换时不会出现先删除后创建的空档。"""
    temporary = link.with_name(link.name + ".new")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(os.path.relpath(target, link.parent), target_is_directory=True)
    os.replace(temporary, link)


def current_release(root, name="daemon"):
    link = root / name
    if not link.is_symlink():
        if link.exists():
            raise ValueError(f"Refusing to replace unmanaged directory: {link}")
        return None
    target = link.resolve(strict=True)
    if target.parent != (root / "releases").resolve():
        raise ValueError(f"Release link escapes releases directory: {link}")
    return target


def record_version(root):
    current = current_release(root)
    if current:
        manifest = json.loads((current / "version.json").read_text(encoding="utf-8"))
        atomic_text(root / "status/verno", manifest["version"] + "\n")


def activate(root, release):
    """保留上一版本链接，再切换当前版本并记录版本号。"""
    previous = current_release(root)
    if previous and previous != release:
        atomic_link(root / "previous", previous)
        os.sync()
    atomic_link(root / "daemon", release)
    os.sync()
    record_version(root)


def preflight(root, release):
    """激活前检查本地程序和依赖，不启动 Agent 或发送运动指令。"""
    environment = os.environ.copy()
    environment["CAR_CONFIG"] = str(root / "cfg/car.conf")
    subprocess.run(
        ["/bin/bash", str(release / "boot_apps.sh"), "--check"],
        env=environment, check=True, timeout=60,
    )


def apply_pending(root, architecture):
    inbox = root / "tmp/ver"
    pending = inbox / ".installing.ver"
    incoming = inbox / "1.ver"
    # 上传必须使用 .partial -> 1.ver 原子重命名；断电后优先重试已认领的包。
    if not pending.exists() and incoming.exists():
        os.replace(incoming, pending)
        os.sync()
    if not pending.exists():
        record_version(root)
        return
    try:
        with tempfile.TemporaryDirectory(prefix="update-", dir=root / "tmp") as temp:
            staging = Path(temp)
            wrapper = staging / "wrapper"
            wrapper.mkdir()
            deb = unpack_wrapper(pending, wrapper)
            release, manifest = unpack_deb(deb, staging / "payload", architecture)
            identity = f"{manifest['version']}-{architecture}-{digest(deb)[:12]}"
            destination = root / "releases" / identity
            if not destination.exists():
                os.replace(release, destination)
            preflight(root, destination)
            os.sync()
            activate(root, destination)
            # 包留作审计/恢复，不重复处理；当前和 previous 版本目录也保留。
            os.replace(pending, root / ".ver" / (identity + ".ver"))
            atomic_text(root / "status/update/result", f"OK {identity}\n")
            os.sync()
            print(f"Activated {identity}", flush=True)
    except Exception as error:
        if pending.exists():
            os.replace(pending, root / ".ver" / f"failed-{time.time_ns()}.ver")
        atomic_text(root / "status/update/result", f"FAILED {error}\n")
        os.sync()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["apply", "rollback", "check"])
    parser.add_argument("package", nargs="?")
    parser.add_argument("--root", type=Path, default=Path("/work/app"))
    args = parser.parse_args()
    architecture = subprocess.check_output(["dpkg", "--print-architecture"], text=True).strip()
    if args.action == "check":
        if not args.package:
            parser.error("check requires a .ver file")
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / "wrapper").mkdir()
            deb = unpack_wrapper(Path(args.package), base / "wrapper")
            _, manifest = unpack_deb(deb, base / "payload", architecture)
            print(json.dumps(manifest, indent=2))
        return 0
    if os.geteuid() != 0:
        parser.error("apply/rollback require root")
    # fcntl 仅在 Linux 更新入口使用，归档验证函数可在开发机测试。
    import fcntl
    root = args.root.resolve()
    for directory in ("tmp/ver", "releases", ".ver", "status/update", "cfg"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    with (root / ".update.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            if args.action == "rollback":
                previous = current_release(root, "previous")
                if previous is None:
                    raise ValueError("No previous release")
                preflight(root, previous)
                activate(root, previous)
                atomic_text(root / "status/update/result", "ROLLBACK OK\n")
                os.sync()
            else:
                apply_pending(root, architecture)
            return 0
        except Exception as error:
            print(f"Update failed: {error}", file=sys.stderr)
            # 无效升级包不阻止原版本启动；首次安装失败则阻止服务启动。
            if args.action == "apply" and current_release(root) is not None:
                print("Keeping current release", file=sys.stderr)
                return 0
            return 1


if __name__ == "__main__":
    sys.exit(main())
