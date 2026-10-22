"""Executable askpass integration with a synthetic secret-tool, never real DBus."""
import json
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import helper as h


class AskpassProcessTests(unittest.TestCase):
    def test_executable_pipe_and_fail_closed_prompts(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            store = h.Store(base / h.APP)
            d = {"id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "Synthetic test",
                 "host": "2001:db8::1", "port": 2222, "login": "tema", "group": h.DEFAULT_GROUP,
                 "auth": "password", "client": "ghostty", "note": "", "keyPath": "", "remoteFolder": ""}
            with store.locked():
                data = store.load()
                data["devices"] = [d]
                store.save(data)
            shim = base / "secret-tool"
            marker = base / "lookup.json"
            shim.write_text("#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n"
                            f"Path({str(marker)!r}).write_text(json.dumps(sys.argv[1:]))\n"
                            "assert sys.argv[1] == 'lookup'\nprint('SYNTHETIC-password-42')\n")
            shim.chmod(0o700)
            # Only our fake binary is discoverable. Shebang uses absolute Python.
            plugin = base / "plugin"
            plugin.mkdir()
            for filename in ("askpass.py", "helper.py"):
                shutil.copy2(h.HERE / filename, plugin / filename)
            initial_files = sorted(p.name for p in plugin.iterdir())
            env = {"PATH": str(base), "XDG_DATA_HOME": str(base),
                   "REMOTE_HOSTS_PROFILE": d["id"], "REMOTE_HOSTS_ENDPOINT": h.revision(list(h.endpoint(d)))}
            command = [str(plugin / "askpass.py"), "tema@2001:db8::1's password: "]
            p = subprocess.run(command, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(p.returncode, 0)
            self.assertEqual(p.stdout, "SYNTHETIC-password-42\n")
            self.assertEqual(p.stderr, "")
            self.assertEqual(json.loads(marker.read_text()), ["lookup"] + h.secret_args(d))
            self.assertNotIn("SYNTHETIC-password", marker.read_text())
            self.assertEqual(sorted(p.name for p in plugin.iterdir()), initial_files)
            self.assertFalse(list(plugin.rglob("*.pyc")))
            marker.unlink()
            for prompt, changes in [("Enter passphrase for key '/tmp/key': ", {}),
                                    ("Are you sure you want to continue connecting (yes/no)?", {}),
                                    (command[1], {"SSH_ASKPASS_PROMPT": "confirm"}),
                                    ("tema@other.test's password: ", {}),
                                    (command[1], {"REMOTE_HOSTS_ENDPOINT": "changed"})]:
                p = subprocess.run([command[0], prompt], env={**env, **changes}, capture_output=True, text=True, timeout=5)
                self.assertEqual(p.returncode, 1)
                self.assertEqual(p.stdout + p.stderr, "")
                self.assertFalse(marker.exists(), "Rejected prompts must not even query a secret")
            # Missing Secret Service CLI must not fall back to plaintext or another helper.
            shim.unlink()
            p = subprocess.run(command, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(p.returncode, 1)
            self.assertEqual(p.stdout + p.stderr, "")

    def test_key_passphrase_pipe_is_exactly_bound_and_silent_on_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            store = h.Store(base / h.APP)
            key_path = "/tmp/synthetic encrypted key"
            d = {"id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "Synthetic test",
                 "host": "2001:db8::1", "port": 2222, "login": "tema",
                 "group": h.DEFAULT_GROUP, "auth": "agent", "client": "ghostty",
                 "note": "", "keyPath": key_path, "saveKeyPassphrase": True,
                 "remoteFolder": ""}
            with store.locked():
                data = store.load()
                data["devices"] = [d]
                store.save(data)
            shim = base / "secret-tool"
            marker = base / "lookup.json"
            shim.write_text(
                "#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n"
                f"Path({str(marker)!r}).write_text(json.dumps(sys.argv[1:]))\n"
                "assert sys.argv[1] == 'lookup'\nprint('SYNTHETIC-key-passphrase-42')\n")
            shim.chmod(0o700)
            plugin = base / "plugin"
            plugin.mkdir()
            for filename in ("askpass.py", "helper.py"):
                shutil.copy2(h.HERE / filename, plugin / filename)
            env = {
                "PATH": str(base),
                "XDG_DATA_HOME": str(base),
                "REMOTE_HOSTS_PROFILE": d["id"],
                "REMOTE_HOSTS_ENDPOINT": h.revision(list(h.endpoint(d))),
                "REMOTE_HOSTS_KEY": h.revision(key_path),
            }
            prompt = f"Enter passphrase for key '{key_path}': "
            command = [str(plugin / "askpass.py"), prompt]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "SYNTHETIC-key-passphrase-42\n")
            self.assertEqual(result.stderr, "")
            self.assertEqual(json.loads(marker.read_text()),
                             ["lookup"] + h.secret_args(d, kind="key-passphrase"))
            self.assertNotIn("SYNTHETIC-key-passphrase", marker.read_text())
            marker.unlink()
            rejected = [
                ("Enter passphrase for key '/tmp/other-key': ", {}),
                ("tema@2001:db8::1's password: ", {}),
                ("Are you sure you want to continue connecting (yes/no)?", {}),
                (prompt, {"SSH_ASKPASS_PROMPT": "confirm"}),
                (prompt, {"REMOTE_HOSTS_ENDPOINT": "old"}),
                (prompt, {"REMOTE_HOSTS_KEY": "old"}),
            ]
            for rejected_prompt, changes in rejected:
                result = subprocess.run(
                    [command[0], rejected_prompt], env={**env, **changes},
                    capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout + result.stderr, "")
                self.assertFalse(marker.exists(), "Rejected prompts must not query a secret")
            d["saveKeyPassphrase"] = False
            with store.locked():
                data["devices"] = [d]
                store.save(data)
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout + result.stderr, "")
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
