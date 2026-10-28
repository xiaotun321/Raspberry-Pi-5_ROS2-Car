"""Linux 子进程集成测试：退出重启、单实例锁与停止清理。"""

from pathlib import Path
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest

DAEMON = str(Path(sys.argv.pop(1)).resolve())


def wait_for(predicate, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for process state")


def running(pid):
    try:
        return Path(f"/proc/{pid}/stat").read_text().split(")", 1)[1].split()[0] != "Z"
    except FileNotFoundError:
        return False


class DaemonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lock = self.root / "daemon.lock"

    def start(self, code):
        process = subprocess.Popen(
            [DAEMON, "--lock", str(self.lock), "--", sys.executable, "-c", code],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

        def cleanup():
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

        self.addCleanup(cleanup)
        return process

    def test_restart(self):
        record = self.root / "starts"
        process = self.start(f"from pathlib import Path; p=Path({str(record)!r}); "
                             "p.open('a').write('start\\n')")
        wait_for(lambda: record.exists() and len(record.read_text().splitlines()) >= 2)
        self.assertIsNone(process.poll())

    def test_singleton(self):
        marker = self.root / "ready"
        first = self.start(f"from pathlib import Path; import time; "
                           f"Path({str(marker)!r}).touch(); time.sleep(60)")
        wait_for(marker.exists)
        second = self.start("raise SystemExit(0)")
        self.assertEqual(second.wait(timeout=3), 1)
        self.assertIsNone(first.poll())

    def test_stop_cleans_child(self):
        marker = self.root / "pid"
        process = self.start(f"from pathlib import Path; import os,time; "
                             f"Path({str(marker)!r}).write_text(str(os.getpid())); time.sleep(60)")
        wait_for(lambda: marker.exists() and marker.stat().st_size > 0)
        child = int(marker.read_text())
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=8), 0)
        wait_for(lambda: not running(child))

    def test_parent_death_stops_child(self):
        marker = self.root / "pid"
        process = self.start(f"from pathlib import Path; import os,time; "
                             f"Path({str(marker)!r}).write_text(str(os.getpid())); time.sleep(60)")
        wait_for(lambda: marker.exists() and marker.stat().st_size > 0)
        child = int(marker.read_text())
        process.kill()
        process.wait(timeout=3)
        wait_for(lambda: not running(child))


if __name__ == "__main__":
    unittest.main()
