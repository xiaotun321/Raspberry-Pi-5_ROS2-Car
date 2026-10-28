"""归档校验和版本切换回归测试；不写入 /work，也不操作真实服务。"""

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("car_update", Path(__file__).with_name("update.py"))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def tar_bytes(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:bz2") as archive:
        for name, content, kind in entries:
            entry = tarfile.TarInfo(name)
            entry.type = kind
            entry.size = len(content) if kind == tarfile.REGTYPE else 0
            entry.linkname = "/tmp/escaped"
            archive.addfile(entry, io.BytesIO(content))
    return output.getvalue()


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def extract(self, entries, payload=False):
        with tarfile.open(fileobj=io.BytesIO(tar_bytes(entries)), mode="r:bz2") as archive:
            updater.extract_members(archive, self.root / "out", payload=payload)

    def test_normal_payload(self):
        self.extract([("./work/app/daemon/version.json", b"{}", tarfile.REGTYPE)], True)
        self.assertEqual((self.root / "out/work/app/daemon/version.json").read_bytes(), b"{}")

    def test_unsafe_paths(self):
        for name in ("../escape", "/absolute", "a/../../escape", "C:/escape", "a\\b"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.extract([(name, b"x", tarfile.REGTYPE)])

    def test_links_and_devices(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.FIFOTYPE):
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.extract([("bad", b"", kind)])

    def test_no_system_files(self):
        with self.assertRaises(ValueError):
            self.extract([("etc/passwd", b"bad", tarfile.REGTYPE)], True)

    def test_duplicate(self):
        with self.assertRaises(ValueError):
            self.extract([("file", b"1", tarfile.REGTYPE), ("./file", b"2", tarfile.REGTYPE)])

    def test_size_limit(self):
        with patch.object(updater, "MAX_BYTES", 1), self.assertRaises(ValueError):
            self.extract([("file", b"12", tarfile.REGTYPE)])

    def make_wrapper(self, corrupt=False, extra=False):
        content = b"deb-payload"
        name = "tb6612-car_1.0.0_arm64.deb"
        entries = [(name, content, tarfile.REGTYPE)]
        for algorithm in ("md5", "sha256"):
            checksum = hashlib.new(algorithm, content).hexdigest()
            if corrupt and algorithm == "sha256":
                checksum = "0" * 64
            entries.append((name + "." + algorithm, f"{checksum}  {name}\n".encode(), tarfile.REGTYPE))
        if extra:
            entries.append(("unexpected", b"x", tarfile.REGTYPE))
        package = self.root / "test.ver"
        package.write_bytes(tar_bytes(entries))
        return package

    def test_checksums(self):
        destination = self.root / "wrapper"
        destination.mkdir()
        deb = updater.unpack_wrapper(self.make_wrapper(), destination)
        self.assertEqual(deb.read_bytes(), b"deb-payload")

    def test_corrupt_checksum(self):
        destination = self.root / "wrapper"
        destination.mkdir()
        with self.assertRaises(ValueError):
            updater.unpack_wrapper(self.make_wrapper(corrupt=True), destination)

    def test_extra_files(self):
        destination = self.root / "wrapper"
        destination.mkdir()
        with self.assertRaises(ValueError):
            updater.unpack_wrapper(self.make_wrapper(extra=True), destination)

    def test_manifest(self):
        good = dict(product="tb6612-car", format=1, architecture="arm64",
                    version="1.0.0", ros_distro="jazzy", commit="abc123")
        updater.validate_manifest(good, "arm64", "1.0.0")
        for key, value in (("architecture", "amd64"), ("product", "hs411"),
                           ("version", "2.0.0"), ("ros_distro", "humble")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                updater.validate_manifest(dict(good, **{key: value}), "arm64", "1.0.0")


@unittest.skipUnless(os.name == "posix", "Release symlink/sync tests require POSIX")
class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("releases/old", "releases/new", "status/update", "tmp/ver", ".ver"):
            (self.root / directory).mkdir(parents=True)
        for name in ("old", "new"):
            (self.root / f"releases/{name}/version.json").write_text(json.dumps({"version": name}))

    def test_activate_and_rollback(self):
        updater.activate(self.root, self.root / "releases/old")
        updater.activate(self.root, self.root / "releases/new")
        self.assertEqual(updater.current_release(self.root).name, "new")
        self.assertEqual(updater.current_release(self.root, "previous").name, "old")
        updater.activate(self.root, updater.current_release(self.root, "previous"))
        self.assertEqual(updater.current_release(self.root).name, "old")
        self.assertEqual((self.root / "status/verno").read_text(), "old\n")

    def test_bad_package_preserves_current(self):
        updater.activate(self.root, self.root / "releases/old")
        (self.root / "tmp/ver/1.ver").write_bytes(b"corrupt")
        with self.assertRaises(Exception):
            updater.apply_pending(self.root, "arm64")
        self.assertEqual(updater.current_release(self.root).name, "old")
        self.assertTrue(list((self.root / ".ver").glob("failed-*.ver")))
        self.assertFalse((self.root / "tmp/ver/1.ver").exists())

    def test_recover_claimed_package(self):
        updater.activate(self.root, self.root / "releases/old")
        (self.root / "tmp/ver/.installing.ver").write_bytes(b"interrupted")
        (self.root / "tmp/ver/1.ver").write_bytes(b"next-upload")
        with self.assertRaises(Exception):
            updater.apply_pending(self.root, "arm64")
        self.assertEqual((self.root / "tmp/ver/1.ver").read_bytes(), b"next-upload")

    def test_unmanaged_directory_rejected(self):
        (self.root / "daemon").mkdir()
        with self.assertRaises(ValueError):
            updater.activate(self.root, self.root / "releases/new")


@unittest.skipUnless(os.name == "posix" and shutil.which("dpkg-deb"),
                     "Deb integration tests require Linux dpkg-deb")
class DebIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "app"
        for directory in ("tmp/ver", "status/update", ".ver", "releases", "cfg"):
            (self.root / directory).mkdir(parents=True)
        self.arch = subprocess.check_output(["dpkg", "--print-architecture"], text=True).strip()

    def package(self, version="1.0.0", arch=None):
        arch = arch or self.arch
        stage = self.base / ("stage-" + version)
        (stage / "DEBIAN").mkdir(parents=True)
        (stage / "DEBIAN/control").write_text(
            f"Package: tb6612-car\nVersion: {version}\nArchitecture: {arch}\n"
            "Maintainer: Test <test@example.com>\nDescription: Test fixture\n"
        )
        app = stage / updater.PAYLOAD
        files = ["boot_apps.sh", "runtime_env.sh", "agent.sh", "keyboard_teleop.sh",
                 "ros/tb6612_car_ros2/lib/tb6612_car_ros2/car_daemon",
                 "ros/tb6612_car_ros2/lib/tb6612_car_ros2/keyboard_teleop",
                 "ros/tb6612_car_ros2/share/tb6612_car_ros2/local_setup.bash"]
        for name in files:
            path = app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o755)
        (app / "version.json").write_text(json.dumps(dict(
            product="tb6612-car", format=1, version=version, architecture=arch,
            ros_distro="jazzy", commit="test",
        )))
        deb = self.base / f"tb6612-car_{version}_{arch}.deb"
        subprocess.run(["dpkg-deb", "--root-owner-group", "-Zgzip", "--build", str(stage), str(deb)],
                       check=True, stdout=subprocess.DEVNULL)
        content = deb.read_bytes()
        entries = [(deb.name, content, tarfile.REGTYPE)]
        for algorithm in ("md5", "sha256"):
            checksum = hashlib.new(algorithm, content).hexdigest()
            entries.append((deb.name + "." + algorithm,
                            f"{checksum}  {deb.name}\n".encode(), tarfile.REGTYPE))
        result = self.base / (version + ".ver")
        result.write_bytes(tar_bytes(entries))
        return result

    def install(self, package):
        shutil.copyfile(package, self.root / "tmp/ver/1.ver")
        with patch.object(updater, "preflight"):
            updater.apply_pending(self.root, self.arch)

    def test_install_upgrade_and_reapply(self):
        self.install(self.package("1.0.0"))
        first = updater.current_release(self.root)
        second_package = self.package("1.0.1")
        self.install(second_package)
        second = updater.current_release(self.root)
        self.assertNotEqual(first, second)
        self.assertEqual(updater.current_release(self.root, "previous"), first)
        self.install(second_package)
        self.assertEqual(updater.current_release(self.root, "previous"), first)
        self.assertEqual((self.root / "status/verno").read_text(), "1.0.1\n")

    def test_wrong_architecture_preserves_current(self):
        self.install(self.package())
        first = updater.current_release(self.root)
        wrong_arch = "amd64" if self.arch == "arm64" else "arm64"
        with self.assertRaises(ValueError):
            self.install(self.package("1.0.1", wrong_arch))
        self.assertEqual(updater.current_release(self.root), first)

    def test_preflight_failure_preserves_current(self):
        self.install(self.package())
        first = updater.current_release(self.root)
        shutil.copyfile(self.package("1.0.1"), self.root / "tmp/ver/1.ver")
        with patch.object(updater, "preflight", side_effect=RuntimeError("Missing ROS")):
            with self.assertRaises(RuntimeError):
                updater.apply_pending(self.root, self.arch)
        self.assertEqual(updater.current_release(self.root), first)
        self.assertIn("Missing ROS", (self.root / "status/update/result").read_text())


if __name__ == "__main__":
    unittest.main()
