"""Run the installed launcher against a local Codex stub; no model calls."""

import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "offload.sh"
STUB = r'''
import json, os, signal, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["STUB_CALLS"], "a") as f:
    f.write(json.dumps(args) + "\n")
sys.stdin.read()
def event(name):
    with open(os.environ[name], "w") as f:
        f.write(str(os.getpid()))
def stop(signum, frame):
    event("STUB_STOPPED")
    with open(os.environ["STUB_STOP_GATE"], "rb") as f:
        f.read(1)
    os._exit(143)
if "STUB_READY" in os.environ:
    signal.signal(signal.SIGTERM, stop)
    event("STUB_READY")
    with open(os.environ["STUB_GATE"], "rb") as f:
        f.read(1)
mode = os.environ.get("STUB_MODE", "ok")
if mode != "no-session":
    print('{"thread_id":"fixture-session"}', flush=True)
if mode == "fail":
    sys.exit(9)
if mode != "missing":
    report = "" if mode == "empty" else " \n\t" if mode == "blank" else "fixture report\n"
    Path(args[args.index("-o") + 1]).write_text(report)
'''


class LauncherTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="offload-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.stub = self.root / "codex"
        self.stub.write_text(f"#!{sys.executable}\n" + STUB)
        self.stub.chmod(0o700)
        self.task = self.root / "task.md"
        self.task.write_text("Fixture task: no external actions.\n")
        self.correction = self.root / "correction.md"
        self.correction.write_text("Address this fixture finding.\n")
        self.calls = self.root / "calls.jsonl"
        self.out = self.root / "runs"
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("OFFLOAD_", "STUB_"))}
        self.env.update(OFFLOAD_CODEX=str(self.stub), HOME=str(self.root),
                        STUB_CALLS=str(self.calls), OFFLOAD_OUT_DIR=str(self.out))

    def start(self):
        return ["start", "--task", str(self.task), "--cd", str(self.root)]

    def resume(self, run):
        return ["resume", "--run", str(run), "--input", str(self.correction)]

    def command(self, args):
        return ["bash", str(SCRIPT)] + args

    def run_script(self, args=None, **env):
        return subprocess.run(self.command(self.start() if args is None else args),
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=10)

    def recorded_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def runs(self):
        return set(self.out.glob("*/cwd"))

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))
        self.assertIn("OFFLOAD_DONE ", result.stdout)
        self.assertNotIn("OFFLOAD_FAILED", result.stdout)

    def assert_unlocked(self):
        self.assertEqual(list((self.out / ".locks").iterdir()), [])

    def blocked(self, args):
        folder = Path(tempfile.mkdtemp(dir=self.root, prefix="gate-"))
        fds, env = {}, {}
        for name in ("READY", "GATE", "STOPPED", "STOP_GATE"):
            fifo = folder / name
            os.mkfifo(fifo)
            fds[name] = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
            self.addCleanup(os.close, fds[name])
            env["STUB_" + name] = str(fifo)
        process = subprocess.Popen(self.command(args), env=dict(self.env, **env),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   start_new_session=True)

        def cleanup():
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate(timeout=5)

        self.addCleanup(cleanup)
        child = int(self.event(fds["READY"]))
        return process, child, fds

    def event(self, fd):
        self.assertTrue(select.select([fd], [], [], 5)[0], "stub event timed out")
        return os.read(fd, 4096).decode()

    def test_start_resume_preserve_model_effort_and_session(self):
        contract = (SCRIPT.parents[1] / "prompts" / "build.md").read_text().rstrip("\n")
        self.assertTrue(contract)
        for override in (False, True):
            with self.subTest(override=override):
                before = self.runs()
                env = {"OFFLOAD_MODEL": "explicit-model", "OFFLOAD_EFFORT": "high"} if override else {}
                self.assert_success(self.run_script(**env))
                run = (self.runs() - before).pop().parent
                model, effort = ("explicit-model", "high") if override else ("gpt-6.1-sol", "xhigh")
                self.assertEqual((run / "model").read_text().strip(), model)
                self.assertEqual((run / "effort").read_text().strip(), effort)
                self.assertEqual((run / "session_id").read_text().strip(), "fixture-session")
                self.assertEqual((run / "task.md").read_text(), self.task.read_text())
                self.assert_success(self.run_script(self.resume(run)))
                first, second = self.recorded_calls()[-2:]
                self.assertEqual(first[0], "exec")
                self.assertEqual(second[:3], ["exec", "resume", "fixture-session"])
                for args in (first, second):
                    self.assertEqual(args[args.index("-m") + 1], model)
                    self.assertIn("model_reasoning_effort=" + effort, args)
                start_input = (run / "round-1/input.md").read_text()
                resume_input = (run / "round-2/input.md").read_text()
                for prompt in (start_input, resume_input):
                    self.assertEqual(prompt.count(contract), 1)
                    self.assertEqual(prompt.count("Never print secret values."), 1)
                self.assertIn(f"Task: {(run / 'task.md').resolve()}", start_input)
                self.assertIn("Read the task file first.", start_input)
                self.assertIn(self.correction.read_text(), resume_input)
                self.assertTrue((run / "round-2/report.md").is_file())
                self.assert_unlocked()

    def test_start_and_resume_share_duplicate_ownership(self):
        self.assert_success(self.run_script())
        run = self.runs().pop().parent
        for owner_args in (self.resume(run), self.start()):
            with self.subTest(owner=owner_args[0]):
                before_calls = len(self.recorded_calls())
                process, _, fds = self.blocked(owner_args)
                rounds = set(run.glob("round-*"))
                for duplicate_args in (self.resume(run), self.start()):
                    duplicate = self.run_script(duplicate_args)
                    self.assertEqual(duplicate.returncode, 75, duplicate.stderr)
                    self.assertIn("already owned", duplicate.stderr)
                    self.assertIn(f"pid={process.pid}", duplicate.stderr)
                self.assertEqual(set(run.glob("round-*")), rounds)
                self.assertEqual(len(self.recorded_calls()), before_calls + 1)
                os.write(fds["GATE"], b"x")
                stdout, stderr = process.communicate(timeout=10)
                self.assertEqual(process.returncode, 0, (stdout, stderr))
                self.assert_unlocked()
        self.assert_success(self.run_script(self.resume(run)))

    def test_failed_or_missing_reports_and_session_allow_retry(self):
        for mode, code in (("fail", 9), ("missing", 1), ("empty", 1), ("blank", 1), ("no-session", 1)):
            with self.subTest(mode=mode):
                result = self.run_script(STUB_MODE=mode)
                self.assertEqual(result.returncode, code, (result.stdout, result.stderr))
                self.assertIn("OFFLOAD_FAILED", result.stdout)
                self.assertNotIn("OFFLOAD_DONE", result.stdout)
                self.assert_unlocked()
                self.assert_success(self.run_script())

    def test_failed_resume_can_resume_same_session_again(self):
        self.assert_success(self.run_script())
        run = self.runs().pop().parent
        failed = self.run_script(self.resume(run), STUB_MODE="fail")
        self.assertEqual(failed.returncode, 9, (failed.stdout, failed.stderr))
        self.assertIn("OFFLOAD_FAILED", failed.stdout)
        self.assertNotIn("OFFLOAD_DONE", failed.stdout)
        self.assert_unlocked()
        self.assert_success(self.run_script(self.resume(run)))
        self.assertTrue((run / "round-3/report.md").is_file())
        self.assertEqual(self.recorded_calls()[-1][:3], ["exec", "resume", "fixture-session"])

    def test_resume_without_session_fails_before_launch(self):
        self.assert_success(self.run_script())
        run = self.runs().pop().parent
        log = run / "round-1/codex.jsonl"
        original = log.read_text()
        log.write_text("")
        result = self.run_script(self.resume(run))
        self.assertEqual(result.returncode, 2, (result.stdout, result.stderr))
        self.assertIn("Run has no session to resume", result.stderr)
        self.assertEqual(len(self.recorded_calls()), 1)
        self.assertFalse((run / "round-2").exists())
        self.assert_unlocked()
        log.write_text(original)
        self.assert_success(self.run_script(self.resume(run)))

    def test_basic_argument_errors_do_not_launch(self):
        missing = str(self.root / "missing")
        for args in ([], ["unknown"], ["start", "--unknown", "x"], ["start", "--task"],
                     ["start", "--task", missing, "--cd", str(self.root)],
                     ["start", "--task", str(self.task), "--cd", missing],
                     ["resume", "--run", missing, "--input", str(self.correction)]):
            with self.subTest(args=args):
                result = self.run_script(args)
                self.assertEqual(result.returncode, 2, (result.stdout, result.stderr))
                self.assertIn("OFFLOAD_FAILED", result.stdout)
                self.assertNotIn("OFFLOAD_DONE", result.stdout)
                self.assertEqual(self.recorded_calls(), [])

    def test_cancellation_holds_lock_until_own_child_stops(self):
        process, child, fds = self.blocked(self.start())
        process.send_signal(signal.SIGTERM)
        self.assertEqual(int(self.event(fds["STOPPED"])), child)
        os.kill(child, 0)
        duplicate = self.run_script()
        self.assertEqual(duplicate.returncode, 75, duplicate.stderr)
        self.assertEqual(len(self.recorded_calls()), 1)
        os.write(fds["STOP_GATE"], b"x")
        stdout, stderr = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 143, (stdout, stderr))
        self.assertIn("OFFLOAD_FAILED", stdout)
        self.assertNotIn("OFFLOAD_DONE", stdout)
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)
        self.assert_unlocked()
        self.assert_success(self.run_script())


if __name__ == "__main__":
    unittest.main(verbosity=2)
