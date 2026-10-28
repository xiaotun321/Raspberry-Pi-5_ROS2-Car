"""无需运行目标程序的打包检查，覆盖交叉编译的架构和版本错误。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "verify_binary", Path(__file__).with_name("verify_binary.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BinaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.binary = Path(self.temp.name) / "program"

    def write_elf(self, machine=183, kind=3, version="1.0.0.0t", commit="abc123"):
        # 这里只测试元数据解析，不把这个头部样本当成可运行的 ELF 程序。
        data = bytearray(64)
        data[:6] = b"\x7fELF\x02\x01"
        data[16:18] = kind.to_bytes(2, "little")
        data[18:20] = machine.to_bytes(2, "little")
        data.extend(f"TB6612_BUILD:{version}:{commit}\0".encode())
        self.binary.write_bytes(data)

    def test_arm64_version(self):
        self.write_elf()
        module.verify(self.binary, "arm64", "1.0.0.0t", "abc123")

    def test_amd64_version(self):
        self.write_elf(machine=62)
        module.verify(self.binary, "amd64", "1.0.0.0t", "abc123")

    def test_wrong_architecture(self):
        self.write_elf(machine=62)
        with self.assertRaises(ValueError):
            module.verify(self.binary, "arm64", "1.0.0.0t", "abc123")

    def test_wrong_metadata(self):
        self.write_elf()
        for version, commit in (("1.0.0", "abc123"), ("1.0.0.0t", "other")):
            with self.subTest(version=version, commit=commit), self.assertRaises(ValueError):
                module.verify(self.binary, "arm64", version, commit)

    def test_object_file(self):
        self.write_elf(kind=1)
        with self.assertRaises(ValueError):
            module.verify(self.binary, "arm64", "1.0.0.0t", "abc123")

    def test_non_elf(self):
        self.binary.write_bytes(b"#!/bin/sh\n")
        with self.assertRaises(ValueError):
            module.verify(self.binary, "arm64", "1.0.0.0t", "abc123")


if __name__ == "__main__":
    unittest.main()
