"""No real connections, clients, key reads or Secret Service access. Temp data only."""
import base64
import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import helper as h

ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
REAL_POPEN = subprocess.Popen


def public_key(algorithm="ssh-ed25519", material=b"synthetic-public-key"):
    def ssh_string(value):
        return len(value).to_bytes(4, "big") + value
    name = algorithm.encode("ascii")
    if algorithm == "ssh-ed25519":
        body = ssh_string(hashlib.sha256(material).digest())
    elif algorithm == "ssh-rsa":
        body = ssh_string(b"\x01\x00\x01") + ssh_string(b"\x00\x80" + hashlib.sha512(material).digest())
    else:
        curve = algorithm.removeprefix("ecdsa-sha2-").encode("ascii")
        size = {b"nistp256": 65, b"nistp384": 97, b"nistp521": 133}[curve]
        body = ssh_string(curve) + ssh_string(b"\x04" + (hashlib.sha512(material).digest() * 3)[:size - 1])
    blob = ssh_string(name) + body
    encoded = base64.b64encode(blob).decode("ascii")
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(blob).digest()).decode("ascii").rstrip("=")
    return encoded, fingerprint


def profile(**changes):
    return {"id": ID, "name": "Сервер", "host": "example.test", "port": 2222,
            "login": "tema", "group": h.DEFAULT_GROUP, "note": "private note",
            "auth": "agent", "keyPath": "", "client": "ghostty", "remoteFolder": "",
            "launchMode": "shell", "customExecutable": "", "agents": [], "agentFolder": "", **changes}


class Isolated(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = h.Store(self.root / "data")
        with self.store.locked():
            self.data = self.store.load()
        self.data["devices"] = [profile()]
        with self.store.locked():
            self.store.save(self.data)
        # Any accidental external side effect fails the suite, not the real session.
        self.process = patch.object(h.subprocess, "run", side_effect=AssertionError("Unmocked subprocess"))
        self.process.start()
        self.addCleanup(self.process.stop)
        self.popen = patch.object(h.subprocess, "Popen", side_effect=AssertionError("Unmocked client"))
        self.popen.start()
        self.addCleanup(self.popen.stop)
        self.network = patch.object(h.socket, "getaddrinfo", side_effect=AssertionError("Unmocked DNS"))
        self.network.start()
        self.addCleanup(self.network.stop)

    def call(self, **req):
        return h.dispatch(req, self.store)


class ValidationTests(Isolated):
    def test_ipv4_ipv6_domain_canonicalization(self):
        for value, expected in [("192.0.2.1", "192.0.2.1"), ("2001:0db8::1", "2001:db8::1"), ("EXAMPLE.test.", "example.test"), ("xn--e1afmkfd.xn--p1ai", "xn--e1afmkfd.xn--p1ai")]:
            self.assertEqual(h.host_value(value), expected)

    def test_host_injections_and_unsupported_forms(self):
        for value in ["-oProxyCommand=id", "$(id)", "x;id", "x\ny", "x y", "user@host", "host/path", "[::1]", "::1%eth0", "999.1.1.1", "*", "a..b", "a_", "é.test", "a\x00b"]:
            with self.subTest(value=value), self.assertRaises(h.Error):
                h.host_value(value)

    def test_login_injection(self):
        for value in ["-root", "a b", "root@x", "a\nProxyCommand id", "$(id)", "a;id", ""]:
            with self.subTest(value=value), self.assertRaises(h.Error):
                h.device(profile(login=value))

    def test_ports_strict_integer_range(self):
        for value in [True, "22", 0, -1, 65536, 22.0, None]:
            with self.subTest(value=value), self.assertRaises(h.Error):
                h.device(profile(port=value))
        for value in [1, 65535]:
            self.assertEqual(h.device(profile(port=value))["port"], value)

    def test_path_policy_prevents_shell_and_config_expansion(self):
        for value in ["relative", "~/key", "/a/../key", "/tmp/$(id)", "/tmp/a;id", "/tmp/%h", "/tmp/\"key\"", "/tmp/back\\slash", "/tmp/a\nb", "/tmp/`id`", "/tmp/$HOME"]:
            with self.subTest(value=value), self.assertRaises(h.Error):
                h.safe_path(value, "path")
        self.assertEqual(h.safe_path("/home/tema/My Key", "path"), "/home/tema/My Key")

    def test_unknown_fields_secret_material_and_duplicate_json_rejected(self):
        for field in ["password", "privateKey", "secretId", "proxyCommand"]:
            with self.subTest(field=field), self.assertRaises(h.Error):
                h.device(profile(**{field: "do not accept"}))
        with self.assertRaises(h.Error):
            h.decode('{"version":1,"version":1}')
        with self.assertRaises(h.Error):
            h.decode("x" * (h.MAX_BYTES + 1))

    def test_agent_selection_validation_and_legacy_migration(self):
        old = profile()
        old.pop("agents")
        old.pop("agentFolder")
        old["launchMode"] = "opencode"
        migrated = h.device(old)
        self.assertEqual(migrated["agents"], ["opencode"])
        self.assertEqual(migrated["agentFolder"], "")
        for agents in [["pi", "pi"], ["unknown-agent"], ["goose session"], ["opencode;id"], ["custom"], "pi", [1]]:
            with self.subTest(agents=agents), self.assertRaises(h.Error):
                h.device(profile(agents=agents))
        for folder in ["relative", "/tmp/$(id)", "/tmp/a;id"]:
            with self.subTest(folder=folder), self.assertRaises(h.Error):
                h.device(profile(agentFolder=folder))

    def test_notes_controls_and_limits(self):
        self.assertEqual(h.device(profile(note="line1\nline2"))["note"], "line1\nline2")
        for changes in [{"name": "\x1b[0m"}, {"note": "secret\x00"}, {"note": "a" * 4001}, {"id": "../../x"}, {"auth": "password", "keyPath": "/tmp/key"}]:
            with self.assertRaises(h.Error):
                h.device(profile(**changes))

    def test_document_duplicates_group_and_limit(self):
        bad = copy.deepcopy(self.data)
        bad["devices"].append(profile(id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))
        with self.assertRaises(h.Error):
            h.document(bad)
        bad = copy.deepcopy(self.data)
        bad["devices"][0]["group"] = ID
        with self.assertRaises(h.Error):
            h.document(bad)
        bad = copy.deepcopy(self.data)
        bad["groups"][0]["collapsed"] = "yes"
        with self.assertRaises(h.Error):
            h.document(bad)


class PersistenceTests(Isolated):
    def test_oversized_crud_rejected_before_secrets_or_write(self):
        original = self.store.path.read_bytes()
        with patch.object(h, "MAX_BYTES", len(original)), patch.object(h, "secret") as secret:
            with self.assertRaises(h.Error):
                self.call(op="saveDevice", device=profile(auth="password", note="界" * 4000), password="synthetic")
            secret.assert_not_called()
            self.assertEqual(self.store.path.read_bytes(), original)
            self.assertEqual(self.store.load(), self.data)
        oversized = copy.deepcopy(self.data)
        oversized["devices"][0]["note"] = "界" * 4000
        with patch.object(h, "MAX_BYTES", len(original)), self.assertRaises(h.Error):
            self.store.save(oversized)
        self.assertEqual(self.store.path.read_bytes(), original)
        self.assertFalse(list(self.store.root.glob(".remote-devices-*")))

    def test_permissions_private_atomic_and_no_secret_fields(self):
        self.assertEqual(stat.S_IMODE(self.store.root.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.store.path.stat().st_mode), 0o600)
        inode = self.store.path.stat().st_ino
        self.call(op="saveDevice", device=profile(name="renamed"))
        self.assertNotEqual(inode, self.store.path.stat().st_ino)
        self.assertEqual(self.store.load()["devices"][0]["name"], "renamed")
        self.assertFalse(list(self.store.root.glob(".remote-devices-*")))

    def test_atomic_failure_preserves_original_and_cleans_temp(self):
        original = self.store.path.read_bytes()
        with patch.object(h.os, "replace", side_effect=OSError("disk full")), self.assertRaises(OSError):
            self.call(op="saveDevice", device=profile(name="new"))
        self.assertEqual(original, self.store.path.read_bytes())
        self.assertFalse(list(self.store.root.glob(".remote-devices-*")))

    def test_public_permissions_and_symlink_fail_closed(self):
        self.store.path.chmod(0o644)
        with self.assertRaises(h.Error):
            self.store.load()
        self.store.path.chmod(0o600)
        other = self.root / "other"
        self.store.path.rename(other)
        self.store.path.symlink_to(other)
        with self.assertRaises(h.Error):
            self.store.load()
        bad_root = self.root / "symlink"
        bad_root.symlink_to(self.store.root)
        with self.assertRaises(h.Error), h.Store(bad_root).locked():
            pass

    def test_public_directory_rejected(self):
        self.store.root.chmod(0o755)
        with self.assertRaises(h.Error), self.store.locked():
            pass

    def test_group_crud_collapse_constraints(self):
        result = self.call(op="saveGroup", name="Работа")["data"]
        g = result["groups"][-1]
        result = self.call(op="saveGroup", id=g["id"], name="Work", collapsed=True)["data"]
        self.assertTrue(result["groups"][-1]["collapsed"])
        with self.assertRaises(h.Error):
            self.call(op="deleteGroup", id=h.DEFAULT_GROUP)
        self.call(op="deleteGroup", id=g["id"])
        self.call(op="deleteDevice", id=ID)
        with self.assertRaises(h.Error):
            self.call(op="deleteGroup", id=h.DEFAULT_GROUP)

    def test_new_device_uuid_and_empty_state(self):
        self.call(op="deleteDevice", id=ID)
        self.assertEqual(self.call(op="list")["data"]["devices"], [])
        d = profile(id="")
        result = self.call(op="saveDevice", device=d)["data"]["devices"][0]
        self.assertNotEqual(result["id"], ID)
        h.identifier(result["id"])


class TransferTests(Isolated):
    def test_merged_import_exceeding_byte_limit_rejected(self):
        def catalog(start):
            data = copy.deepcopy(self.data)
            data["devices"] = [profile(id=str(h.uuid.UUID(int=i + 1)), host=f"host{i}.test", note="界" * 4000)
                               for i in range(start, start + 50)]
            return data
        current, incoming = catalog(0), catalog(50)
        self.store.save(current)
        original = self.store.path.read_bytes()
        raw = h.encoded_document(incoming).decode("utf-8")
        path = self.root / "large-import.json"
        path.write_text(raw, encoding="utf-8")
        for op in ("previewImport", "import"):
            with self.subTest(op=op), self.assertRaises(h.Error):
                self.call(op=op, path=str(path), policy="skip", token="unused")
            self.assertEqual(self.store.path.read_bytes(), original)
            self.assertEqual(self.store.load(), current)

    def test_redaction_and_opt_in_paths_notes(self):
        self.data["devices"] = [profile(auth="password", remoteFolder="/home/tema/project",
                                        launchMode="custom", customExecutable="my-agent")]
        result = h.export_document(self.data)
        self.assertEqual(result["devices"][0]["auth"], "agent")
        self.assertEqual(result["devices"][0]["note"], "")
        self.assertEqual(result["devices"][0]["remoteFolder"], "")
        self.assertEqual(result["devices"][0]["launchMode"], "custom")
        self.assertEqual(result["devices"][0]["customExecutable"], "my-agent")
        result = h.export_document(self.data, notes=True, paths=True)
        self.assertEqual(result["devices"][0]["note"], "private note")
        self.assertEqual(result["devices"][0]["remoteFolder"], "/home/tema/project")
        self.assertNotIn("password", json.dumps(result))
        self.data["devices"] = [profile(keyPath="/home/tema/key")]
        self.assertEqual(h.export_document(self.data)["devices"][0]["keyPath"], "")
        self.assertEqual(h.export_document(self.data, paths=True)["devices"][0]["keyPath"], "/home/tema/key")

    def test_export_no_clobber_and_permissions(self):
        dest = self.root / "export.json"
        self.call(op="export", path=str(dest))
        self.assertEqual(stat.S_IMODE(dest.stat().st_mode), 0o600)
        with self.assertRaises(h.Error):
            self.call(op="export", path=str(dest))
        with self.assertRaises(h.Error):
            self.call(op="export", path=str(self.store.path))

    def test_import_preview_skip_replace_keeps_local_auth(self):
        self.data["devices"] = [profile(auth="password")]
        incoming = copy.deepcopy(self.data)
        incoming["devices"][0].update(name="Imported", auth="agent", keyPath="/tmp/not-local",
                                      launchMode="codex", remoteFolder="/home/tema/imported")
        result, summary = h.import_preview(self.data, json.dumps(incoming), "skip")
        self.assertEqual(summary["skipped"], 1)
        self.assertEqual(result["devices"][0]["name"], "Сервер")
        result, summary = h.import_preview(self.data, json.dumps(incoming), "replace")
        self.assertEqual(summary["replaced"], 1)
        self.assertEqual(result["devices"][0]["name"], "Imported")
        self.assertEqual(result["devices"][0]["auth"], "password")
        self.assertEqual(result["devices"][0]["keyPath"], "")
        self.assertEqual(result["devices"][0]["launchMode"], "codex")
        self.assertEqual(result["devices"][0]["remoteFolder"], "/home/tema/imported")

    def test_import_new_id_reset_auth_and_group_mapping(self):
        incoming = copy.deepcopy(self.data)
        incoming["devices"][0].update(host="other.test", auth="password")
        result, summary = h.import_preview(self.data, json.dumps(incoming), "skip")
        self.assertEqual(summary["added"], 1)
        self.assertNotEqual(result["devices"][1]["id"], ID)
        self.assertEqual(result["devices"][1]["auth"], "agent")
        self.assertEqual(len(result["groups"]), 1)

    def test_preview_no_write_and_stale_confirmation_rejected(self):
        dest = self.root / "input.json"
        incoming = copy.deepcopy(self.data)
        incoming["devices"][0]["host"] = "other.test"
        dest.write_text(json.dumps(incoming))
        original = self.store.path.read_bytes()
        preview = self.call(op="previewImport", path=str(dest), policy="skip")
        self.assertEqual(original, self.store.path.read_bytes())
        with self.assertRaises(h.Error):
            self.call(op="import", path=str(dest), policy="skip", token="wrong")
        result = self.call(op="import", path=str(dest), policy="skip", token=preview["token"])
        self.assertEqual(len(result["data"]["devices"]), 2)
        with self.assertRaises(h.Error):
            self.call(op="import", path=str(dest), policy="skip", token=preview["token"])

    def test_import_file_changed_after_preview(self):
        dest = self.root / "input.json"
        dest.write_text(json.dumps(self.data))
        preview = self.call(op="previewImport", path=str(dest))
        dest.write_text(json.dumps(self.data) + " ")
        with self.assertRaises(h.Error):
            self.call(op="import", path=str(dest), token=preview["token"])


class SecretTests(Isolated):
    def test_store_stdin_only_and_fixed_label(self):
        sentinel = "VerySensitive!987"
        with patch.object(h.shutil, "which", return_value="/usr/bin/secret-tool"), patch.object(h.subprocess, "run", return_value=Mock(returncode=0)) as run:
            h.secret("store", profile(auth="password"), sentinel)
        args, kwargs = run.call_args
        self.assertNotIn(sentinel, repr(args))
        self.assertNotIn(sentinel, repr({k: v for k, v in kwargs.items() if k != "input"}))
        self.assertEqual(kwargs["input"], sentinel)
        self.assertEqual(args[0][:3], ["secret-tool", "store", "--label=Omarchy remote device"])
        self.assertNotIn("shell", kwargs)

    def test_secret_missing_failure_timeout_redacted(self):
        sentinel = "NEVER_EXPOSE_ME"
        with patch.object(h.shutil, "which", return_value=None), self.assertRaises(h.Error):
            h.secret("store", profile(), sentinel)
        for failure in [Mock(returncode=1, stdout=sentinel, stderr=sentinel), subprocess.TimeoutExpired([sentinel], 20, output=sentinel), OSError(sentinel)]:
            with patch.object(h.shutil, "which", return_value="secret-tool"):
                target: dict[str, Any] = {"side_effect": failure} if isinstance(failure, Exception) else {"return_value": failure}
                with patch.object(h.subprocess, "run", **target), self.assertRaises(h.Error) as raised:
                    h.secret("store", profile(), sentinel)
                self.assertNotIn(sentinel, str(raised.exception))

    def test_password_never_persisted_returned_and_failure_no_profile(self):
        original = self.store.path.read_bytes()
        with patch.object(h, "secret", side_effect=h.Error("unavailable")), self.assertRaises(h.Error):
            self.call(op="saveDevice", device=profile(auth="password"), password="sentinel")
        self.assertEqual(self.store.path.read_bytes(), original)
        with patch.object(h, "secret") as secret:
            result = self.call(op="saveDevice", device=profile(auth="password"), password="sentinel")
        self.assertEqual(secret.call_args.args[0], "store")
        self.assertNotIn("sentinel", json.dumps(result))
        self.assertNotIn(b"sentinel", self.store.path.read_bytes())

    def test_endpoint_change_requires_password_and_binds_secret_attributes(self):
        old = profile(auth="password")
        self.data["devices"] = [old]
        with self.store.locked():
            self.store.save(self.data)
        with self.assertRaises(h.Error):
            self.call(op="saveDevice", device=profile(auth="password", host="other.test"))
        self.assertNotEqual(h.secret_args(old), h.secret_args(profile(host="other.test")))
        with patch.object(h, "secret") as secret:
            self.call(op="saveDevice", device=profile(auth="password", host="other.test"), password="new")
        self.assertEqual([c.args[0] for c in secret.call_args_list], ["store", "clear"])

    def test_endpoint_change_save_failure_never_clears_working_old_secret(self):
        old = profile(auth="password")
        self.data["devices"] = [old]
        with self.store.locked():
            self.store.save(self.data)
        changed = profile(auth="password", host="new.example.test")
        with patch.object(self.store, "save", side_effect=OSError("disk full")), \
             patch.object(h, "secret") as secret, self.assertRaises(OSError):
            self.call(op="saveDevice", device=changed, password="new-password")
        calls = [(call.args[0], call.args[1]["host"]) for call in secret.call_args_list]
        self.assertEqual(calls, [("store", "new.example.test"), ("clear", "new.example.test")])
        self.assertNotIn(("clear", "example.test"), calls)
        self.assertEqual(self.store.load()["devices"][0]["host"], "example.test")

    def test_delete_secret_failure_preserves_profile(self):
        self.data["devices"] = [profile(auth="password")]
        with self.store.locked():
            self.store.save(self.data)
        with patch.object(h, "secret", side_effect=h.Error("locked")), self.assertRaises(h.Error):
            self.call(op="deleteDevice", id=ID)
        self.assertEqual(len(self.store.load()["devices"]), 1)
        with patch.object(h, "secret") as secret:
            self.call(op="deleteDevice", id=ID)
        self.assertEqual(secret.call_args.args[0], "clear")

    def test_askpass_exact_prompt_only_and_endpoint_binding(self):
        self.data["devices"] = [profile(auth="password")]
        with self.store.locked():
            self.store.save(self.data)
        env = {"REMOTE_DEVICES_PROFILE": ID, "REMOTE_DEVICES_ENDPOINT": h.revision(list(h.endpoint(profile())))}
        expected = "tema@example.test's password: "
        with patch.object(h, "secret", return_value="secret") as secret:
            self.assertEqual(h.askpass(expected, env, self.store), "secret")
            secret.assert_called_once()
        for prompt in ["Are you sure you want to continue connecting (yes/no)?", "Enter passphrase for key '/tmp/key': ", "Password:", "root@example.test's password: ", expected.rstrip(), expected + "x", "tema@evil.test's password: "]:
            with self.subTest(prompt=prompt), patch.object(h, "secret") as secret, self.assertRaises(h.Error):
                h.askpass(prompt, env, self.store)
            secret.assert_not_called()
        for addition in [{"SSH_ASKPASS_PROMPT": "confirm"}, {"SSH_ASKPASS_PROMPT": "none"}, {"SSH_ASKPASS_PROMPT": "unexpected"}, {"REMOTE_DEVICES_ENDPOINT": "wrong"}]:
            with patch.object(h, "secret") as secret, self.assertRaises(h.Error):
                h.askpass(expected, {**env, **addition}, self.store)
            secret.assert_not_called()

    def test_generic_exception_json_never_echoes_request(self):
        inp = Mock(buffer=io.BytesIO(b'{"op":"list","password":"sensitive"}\n'))
        out = io.StringIO()
        with patch.object(sys, "argv", ["helper.py"]), patch.object(sys, "stdin", inp), contextlib.redirect_stdout(out), patch.object(h, "dispatch", side_effect=RuntimeError("sensitive")):
            h.main()
        result = json.loads(out.getvalue())
        self.assertFalse(result["ok"])
        self.assertNotIn("sensitive", out.getvalue())


class SettingsTests(Isolated):
    def test_export_cannot_create_settings_file(self):
        with self.assertRaises(h.Error):
            self.call(op="export", path=str(self.store.settings_path))
        self.assertFalse(self.store.settings_path.exists())

    def save_terminal(self, terminal):
        with patch.object(h.shutil, "which", return_value="/synthetic/terminal"):
            return self.call(op="saveSettings", settings={"version": 1, "defaultTerminal": terminal})

    def test_settings_survive_new_store_without_changing_profiles_or_export(self):
        before = self.store.path.read_bytes()
        self.save_terminal("kitty")
        other = h.Store(self.store.root)
        with patch.object(h.shutil, "which", side_effect=lambda name: "/synthetic/kitty" if name == "kitty" else None):
            result = h.dispatch({"op": "getSettings"}, other)
        self.assertEqual(result["globalSettings"]["defaultTerminal"], "kitty")
        self.assertEqual([t["value"] for t in result["terminals"] if t["available"]], ["kitty"])
        self.assertEqual(self.store.path.read_bytes(), before)
        self.assertEqual(stat.S_IMODE(self.store.settings_path.stat().st_mode), 0o600)
        with other.locked():
            self.assertNotIn("defaultTerminal", h.export_document(other.load()))

    def test_invalid_or_secret_settings_do_not_replace_saved_selection(self):
        self.save_terminal("kitty")
        before = self.store.settings_path.read_bytes()
        for settings in [
            {"version": 1, "defaultTerminal": "/tmp/terminal"},
            {"version": 1, "defaultTerminal": ["kitty"]},
            {"version": True, "defaultTerminal": "kitty"},
            {"version": 2, "defaultTerminal": "kitty"},
            {"version": 1, "defaultTerminal": "kitty", "password": "synthetic"},
        ]:
            with self.subTest(settings=settings), self.assertRaises(h.Error):
                self.call(op="saveSettings", settings=settings)
        with self.assertRaises(h.Error):
            self.call(op="saveSettings", settings={"version": 1, "defaultTerminal": "kitty"}, command="anything")
        self.assertEqual(self.store.settings_path.read_bytes(), before)

    def test_unavailable_terminal_cannot_replace_settings_or_fall_back_on_launch(self):
        self.save_terminal("kitty")
        before = self.store.settings_path.read_bytes()
        with patch.object(h.shutil, "which", side_effect=lambda name: "/synthetic/ghostty" if name == "ghostty" else None):
            with self.assertRaises(h.Error):
                self.call(op="saveSettings", settings={"version": 1, "defaultTerminal": "foot"})
            with patch.object(h, "has_known_host_entry", return_value=True), self.assertRaises(h.Error):
                self.call(op="launch", id=ID)
        self.assertEqual(self.store.settings_path.read_bytes(), before)

    def test_settings_file_rejects_symlink_unsafe_permissions_and_oversize(self):
        outside = self.root / "outside.json"
        outside.write_text('{"version":1,"defaultTerminal":"kitty"}')
        self.store.settings_path.symlink_to(outside)
        for op in ("getSettings", "saveSettings"):
            request = {"op": op}
            if op == "saveSettings":
                request["settings"] = {"version": 1, "defaultTerminal": "foot"}
            with patch.object(h.shutil, "which", return_value="/synthetic/foot"), self.assertRaises(h.Error):
                self.call(**request)
        self.assertEqual(json.loads(outside.read_text())["defaultTerminal"], "kitty")
        self.store.settings_path.unlink()
        self.save_terminal("kitty")
        self.store.settings_path.chmod(0o644)
        with self.assertRaises(h.Error):
            self.call(op="getSettings")
        self.store.settings_path.chmod(0o600)
        self.store.settings_path.write_bytes(b" " * (h.MAX_BYTES + 1))
        with self.assertRaises(h.Error):
            self.call(op="getSettings")

    def test_global_terminal_controls_ssh_and_ai_not_legacy_profile_client(self):
        self.data["devices"] = [profile(client="vscode", agents=["codex"])]
        with self.store.locked():
            self.store.save(self.data)
        self.save_terminal("alacritty")
        with patch.object(h, "has_known_host_entry", return_value=True), \
             patch.object(h.shutil, "which", return_value="/synthetic/alacritty"), \
             patch.object(h.subprocess, "Popen") as spawn:
            self.call(op="launch", id=ID)
            ssh_command = spawn.call_args.args[0]
            self.call(op="launchAgent", id=ID, agent="codex")
            ai_command = spawn.call_args.args[0]
        self.assertEqual(ssh_command[:3], ["alacritty", "--hold", "-e"])
        self.assertEqual(ssh_command[-2:], ["--terminal", ID])
        self.assertEqual(ai_command, ssh_command + ["--agent", "codex"])

    def test_new_default_terminal_still_requires_host_key_confirmation(self):
        self.save_terminal("foot")
        preview = {"hostKeys": {"state": "new", "deviceId": ID}}
        with patch.object(h, "has_known_host_entry", return_value=False), \
             patch.object(h, "host_key_preview", return_value=preview), \
             patch.object(h.subprocess, "Popen") as spawn:
            self.assertEqual(self.call(op="launch", id=ID), preview)
        spawn.assert_not_called()


class ClientTests(Isolated):
    def test_unknown_ghostty_host_returns_preview_without_launch(self):
        preview = {"hostKeys": {"state": "new", "deviceId": ID}}
        with patch.object(h, "has_known_host_entry", return_value=False) as known, \
             patch.object(h, "host_key_preview", return_value=preview) as scan, \
             patch.object(h, "launch") as launch:
            result = self.call(op="launch", id=ID)
        self.assertEqual(result, preview)
        known.assert_called_once_with(self.data["devices"][0])
        scan.assert_called_once_with(self.data["devices"][0])
        launch.assert_not_called()

    def test_known_ghostty_host_launches_after_preflight(self):
        with patch.object(h, "has_known_host_entry", return_value=True) as known, \
             patch.object(h, "host_key_preview") as scan, \
             patch.object(h, "launch", return_value="Клиент запущен") as launch:
            result = self.call(op="launch", id=ID, client="ghostty")
        self.assertEqual(result, {"message": "Клиент запущен"})
        known.assert_called_once_with(self.data["devices"][0])
        scan.assert_not_called()
        launch.assert_called_once_with(self.data["devices"][0], "ghostty", None)

    def test_selected_agent_dispatch_and_terminal_argv(self):
        self.data["devices"] = [profile(agents=["pi", "codex"], agentFolder="/srv/My Project")]
        with self.store.locked():
            self.store.save(self.data)
        with patch.object(h, "has_known_host_entry", return_value=True), \
             patch.object(h, "launch", return_value="Клиент запущен") as launch:
            result = self.call(op="launchAgent", id=ID, agent="codex")
        self.assertEqual(result, {"message": "Клиент запущен"})
        launch.assert_called_once_with(h.device(self.data["devices"][0]), "ghostty", "codex")
        args = h.launch_argv(h.device(self.data["devices"][0]), "ghostty", "pi")
        self.assertEqual(args[-2:], ["--agent", "pi"])
        with patch.object(h, "has_known_host_entry", return_value=True), self.assertRaises(h.Error):
            self.call(op="launchAgent", id=ID, agent="claude")
        with self.assertRaises(h.Error):
            self.call(op="launchAgent", id=ID, agent="codex", extra="bad")

    def test_sftp_launch_uses_openssh_host_preflight(self):
        preview = {"hostKeys": {"state": "new", "deviceId": ID}}
        with patch.object(h, "has_known_host_entry", return_value=False) as known, \
             patch.object(h, "host_key_preview", return_value=preview) as scan, \
             patch.object(h, "launch") as launch:
            self.assertEqual(self.call(op="launch", id=ID, client="sftp"), preview)
        known.assert_called_once_with(self.data["devices"][0])
        scan.assert_called_once_with(self.data["devices"][0])
        launch.assert_not_called()

        state = {"endpoint": ["example.test", 2222, "tema", ""], "state": "mounted"}
        with patch.object(h, "has_known_host_entry", return_value=True), \
             patch.object(h, "host_key_preview") as scan, \
             patch.object(h, "launch", return_value="SFTP открыт") as launch, \
             patch.object(h, "sftp_state", return_value=state):
            result = self.call(op="launch", id=ID, client="sftp")
        self.assertEqual(result, {"message": "SFTP открыт", "sftpStates": {ID: state}})
        scan.assert_not_called()
        launch.assert_called_once_with(self.data["devices"][0], "sftp", None)

    def test_ssh_safe_argv_hostkey_and_config_isolation(self):
        args = h.ssh_argv(profile(keyPath="/home/tema/My Key"))
        self.assertEqual(args[-2:], ["--", "example.test"])
        self.assertEqual(args[1:3], ["-F", "/dev/null"])
        self.assertIn("StrictHostKeyChecking=ask", args)
        self.assertIn("/home/tema/My Key", args)
        self.assertIn("2222", args)
        self.assertIn("PermitLocalCommand=no", args)
        self.assertIn("ClearAllForwardings=yes", args)
        args = h.ssh_argv(profile(auth="password"))
        for option in ["StrictHostKeyChecking=yes", "PreferredAuthentications=password", "KbdInteractiveAuthentication=no", "PubkeyAuthentication=no", "NumberOfPasswordPrompts=1"]:
            self.assertIn(option, args)
        self.assertNotIn("StrictHostKeyChecking=no", args)

    def test_remote_agent_and_working_directory_argv(self):
        args = h.ssh_argv(profile(agents=["codex"]), "codex")
        self.assertIn("-t", args)
        self.assertEqual(args[-3:], ["--", "example.test", 'exec "${SHELL:-/bin/sh}" -lic \'exec codex\''])
        args = h.ssh_argv(profile(agents=["claude"], agentFolder="/home/tema/My Project"), "claude")
        inner = "cd -- '/home/tema/My Project' && exec claude"
        self.assertEqual(args[-1], f'exec "${{SHELL:-/bin/sh}}" -lic {h.shlex.quote(inner)}')
        self.assertEqual(args.count("-t"), 1)
        self.assertNotIn("-t", h.ssh_argv(profile(agents=["pi"])))
        for agent in ("gemini", "pi"):
            with self.subTest(agent=agent), self.assertRaises(h.Error):
                h.ssh_argv(profile(agents=[]), agent)

    def test_goose_starts_interactive_session_in_project_directory(self):
        project = self.root / "My Project"
        project.mkdir()
        binary = self.root / "goose"
        binary.write_text("#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$#\" \"$@\"\n")
        binary.chmod(0o700)
        command = h.ssh_remote_command(h.device(profile(agents=["goose"], agentFolder=str(project))), "goose")
        # Run only the inner command: no SSH and no real login-shell startup files.
        inner = h.shlex.split(command)[-1]
        with REAL_POPEN(["/bin/sh", "-c", inner], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, env={"PATH": str(self.root), "HOME": str(self.root)}) as process:
            stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertEqual(stdout.splitlines(), [str(project), "1", "session"])

    def test_sshfs_safe_argv_password_key_and_ipv6(self):
        mountpoint = self.root / "mount"
        args = h.sshfs_argv(profile(auth="password", host="2001:db8::1"), mountpoint)
        ssh_command = next(value for value in args if value.startswith("ssh_command="))
        self.assertIn("-F /dev/null", ssh_command)
        self.assertIn("StrictHostKeyChecking=yes", ssh_command)
        self.assertIn("password_stdin", args)
        self.assertIn("KbdInteractiveAuthentication=no", ssh_command)
        self.assertEqual(args[-2:], ["tema@[2001:db8::1]:", str(mountpoint)])
        self.assertNotIn("SYNTHETIC-sftp-password", " ".join(args))
        args = h.sshfs_argv(profile(keyPath="/home/tema/My Key", remoteFolder="/srv/data"), mountpoint)
        ssh_command = next(value for value in args if value.startswith("ssh_command="))
        self.assertIn("'/home/tema/My Key'", ssh_command)
        self.assertIn("IdentitiesOnly=yes", ssh_command)
        self.assertEqual(args[-2], "tema@example.test:/srv/data")

    def test_mount_sftp_password_stdin_and_existing_mount_reuse(self):
        password = "SYNTHETIC-sftp-password"
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}), \
             patch.object(h.shutil, "which", return_value="/usr/bin/tool"), \
             patch.object(h, "sftp_mount_kind", side_effect=["unmounted", "mounted"]), \
             patch.object(h, "secret", return_value=password) as secret, \
             patch.object(h.subprocess, "run", return_value=Mock(returncode=0)) as run, \
             patch.object(h.subprocess, "Popen") as proc:
            message = h.mount_sftp(profile(auth="password"))
        self.assertIn("SSHFS", message)
        secret.assert_called_once_with("lookup", h.device(profile(auth="password")))
        self.assertEqual(run.call_args.kwargs["input"], password + "\n")
        self.assertNotIn(password, json.dumps(run.call_args.args[0]))
        self.assertEqual(proc.call_args.args[0][0], "nautilus")
        self.assertTrue(proc.call_args.args[0][1].startswith("file://"))

        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}), \
             patch.object(h.shutil, "which", return_value="/usr/bin/tool"), \
             patch.object(h, "sftp_mount_kind", return_value="mounted"), \
             patch.object(h, "secret") as secret, patch.object(h.subprocess, "run") as run, \
             patch.object(h.subprocess, "Popen"):
            h.mount_sftp(profile(auth="password"))
        secret.assert_not_called()
        run.assert_not_called()

    def test_mountinfo_state_and_unmount_are_exact_and_safe(self):
        info = self.root / "mountinfo"
        info.write_text("42 1 0:9 / /run/user/1000/tema\\040remote rw - fuse.sshfs host rw\n"
                        "43 1 0:10 / /foreign rw - ext4 disk rw\n")
        self.assertEqual(h.mountinfo(info)["/run/user/1000/tema remote"],
                         {"filesystem": "fuse.sshfs", "source": "host"})
        d = profile()
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}):
            point = h.sftp_mountpoint(d)
            expected = {str(point): {"filesystem": "fuse.sshfs", "source": h.sftp_source(d)}}
            foreign = {str(point): {"filesystem": "fuse.sshfs", "source": "other@host:"}}
            h.atomic_write(h.sftp_marker(d), h.sftp_binding(d))
            self.assertEqual(h.sftp_mount_kind(d, expected), "mounted")
            self.assertEqual(h.sftp_mount_kind(d, foreign), "foreign")
            wrong_port = h.sftp_binding(d)
            wrong_port["endpoint"][1] = 22
            h.atomic_write(h.sftp_marker(d), wrong_port)
            self.assertEqual(h.sftp_mount_kind(d, expected), "foreign")
            h.atomic_write(h.sftp_marker(d), h.sftp_binding(d))
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}):
            mountpoint = h.sftp_mountpoint(d)
            mountpoint.mkdir(mode=0o700)
            with patch.object(h, "sftp_mount_kind", side_effect=["mounted", "unmounted"]), \
                 patch.object(h.shutil, "which", return_value="/usr/bin/fusermount3"), \
                 patch.object(h.subprocess, "run", return_value=Mock(returncode=0)) as run:
                self.assertEqual(h.unmount_sftp(d), "SFTP отключён")
        self.assertEqual(run.call_args.args[0], ["fusermount3", "-u", "--", str(mountpoint)])
        self.assertFalse(mountpoint.exists())

    def test_sftp_cleanup_only_empty_owned_plugin_directories(self):
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}):
            root = h.sftp_runtime_root()
            stale = root / (ID + "-" + "a" * 16)
            stale.mkdir(mode=0o700)
            stale_marker = Path(str(stale) + ".mount.json")
            h.atomic_write(stale_marker, {"version": 1, "endpoint": []})
            nonempty = root / (ID + "-" + "b" * 16)
            nonempty.mkdir(mode=0o700)
            (nonempty / "keep").write_text("x")
            link = root / (ID + "-" + "c" * 16)
            link.symlink_to(stale)
            with patch.object(h, "mountinfo", return_value={}):
                h.cleanup_sftp_runtime()
        self.assertFalse(stale.exists())
        self.assertFalse(stale_marker.exists())
        self.assertTrue(nonempty.exists())
        self.assertTrue(link.is_symlink())

    def test_foreign_sftp_mount_is_never_unmounted(self):
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}), \
             patch.object(h, "sftp_mount_kind", return_value="foreign"), \
             patch.object(h.subprocess, "run") as run, self.assertRaisesRegex(h.Error, "посторонним"):
            h.unmount_sftp(profile())
        run.assert_not_called()

    def test_sftp_runtime_falls_back_without_environment(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(h.sftp_runtime_root(create=False), Path(f"/run/user/{os.getuid()}/{h.APP}"))

    def test_mounted_sftp_blocks_profile_move_delete_and_import(self):
        changed = profile(remoteFolder="/srv/new")
        incoming = copy.deepcopy(self.data)
        incoming["devices"][0]["remoteFolder"] = "/srv/imported"
        source = self.root / "mounted-import.json"
        source.write_text(json.dumps(incoming))
        preview = self.call(op="previewImport", path=str(source), policy="replace")
        with patch.object(h, "sftp_mount_kind", return_value="mounted") as state, \
             patch.dict(os.environ, {}, clear=True), patch.object(h, "secret") as secret:
            with self.assertRaisesRegex(h.Error, "отключите SFTP"):
                self.call(op="saveDevice", device=changed, password="")
            with self.assertRaisesRegex(h.Error, "отключите SFTP"):
                self.call(op="deleteDevice", id=ID)
            with self.assertRaisesRegex(h.Error, "отключите SFTP"):
                self.call(op="import", path=str(source), policy="replace", token=preview["token"])
        self.assertGreaterEqual(state.call_count, 3)
        secret.assert_not_called()

    def test_unknown_vscode_host_preflights_before_runtime_files(self):
        preview = {"hostKeys": {"state": "new", "deviceId": ID}}
        with patch.object(h, "has_known_host_entry", return_value=False), \
             patch.object(h, "host_key_preview", return_value=preview), \
             patch.object(h, "launch") as launch:
            result = self.call(op="launch", id=ID, client="vscode")
        self.assertEqual(result, preview)
        launch.assert_not_called()

    def test_vscode_runtime_config_is_private_and_profile_isolated(self):
        d = profile(client="vscode", keyPath="/home/tema/My Key", remoteFolder="/srv/project")
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}), \
             patch.object(h, "vscode_extension_available"):
            args = h.vscode_argv(d)
        self.assertEqual(args[0:2], ["code", "--new-window"])
        self.assertIn("--user-data-dir", args)
        self.assertEqual(args[-3:], ["--remote", "ssh-remote+remote-device-" + ID, "/srv/project"])
        runtime = Path(args[args.index("--user-data-dir") + 1])
        config = runtime / "ssh_config"
        settings = runtime / "User" / "settings.json"
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
        self.assertEqual(json.loads(settings.read_text()), {"remote.SSH.configFile": str(config)})
        text = config.read_text()
        for expected in ["HostName example.test", "User tema", "Port 2222", "StrictHostKeyChecking yes",
                         'IdentityFile "/home/tema/My Key"', "ForwardAgent no"]:
            self.assertIn(expected, text)
        self.assertNotIn("ClearAllForwardings", text)
        self.assertFalse((self.root / ".ssh").exists())

    def test_vscode_extension_detection_and_password_rejection(self):
        with patch.object(h.shutil, "which", return_value="/usr/bin/code"), \
             patch.object(h.subprocess, "run", return_value=Mock(
                 returncode=0, stdout="publisher.other\nMS-VSCODE-REMOTE.REMOTE-SSH\n")):
            h.vscode_extension_available()
        with patch.object(h.shutil, "which", return_value="/usr/bin/code"), \
             patch.object(h.subprocess, "run", return_value=Mock(returncode=0, stdout="publisher.other\n")), \
             self.assertRaisesRegex(h.Error, "официальное расширение"):
            h.vscode_extension_available()
        with patch.object(h, "vscode_extension_available") as extension, self.assertRaisesRegex(h.Error, "ключ или SSH-agent"):
            h.vscode_argv(profile(auth="password"))
        extension.assert_not_called()

    def test_launch_argv_ghostty_and_unknown_client(self):
        args = h.launch_argv(profile(), "ghostty")
        self.assertEqual(args[:3], ["ghostty", "--wait-after-command=true", "-e"])
        self.assertEqual(args[-2:], ["--terminal", ID])
        with self.assertRaises(h.Error):
            h.launch_argv(profile(), "sftp")
        with patch.object(h.shutil, "which", return_value=None), self.assertRaises(h.Error):
            h.launch(profile(), "ghostty")

    def test_launch_detached_no_shell_and_stdio_closed(self):
        with patch.object(h.shutil, "which", return_value="ghostty"), patch.object(h.subprocess, "Popen") as proc:
            h.launch(profile(), "ghostty")
        self.assertEqual(proc.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(proc.call_args.kwargs["stderr"], subprocess.DEVNULL)
        self.assertTrue(proc.call_args.kwargs["start_new_session"])
        self.assertNotIn("shell", proc.call_args.kwargs)

    def test_terminal_environment_has_no_secret_and_only_trusted_askpass(self):
        self.data["devices"] = [profile(auth="password")]
        with self.store.locked():
            self.store.save(self.data)
        with patch.object(h, "Store", return_value=self.store), patch.object(h.shutil, "which", return_value="ssh"), patch.object(h.os, "execvpe") as execute, patch.dict(os.environ, {"SSH_ASKPASS": "/evil", "SSH_ASKPASS_PROMPT": "confirm"}), patch.object(h, "secret") as secret:
            h.terminal(ID)
        secret.assert_not_called()
        executable, args, env = execute.call_args.args
        self.assertEqual(executable, "ssh")
        self.assertEqual(env["SSH_ASKPASS"], str(h.HERE / "askpass.py"))
        self.assertEqual(env["SSH_ASKPASS_REQUIRE"], "force")
        self.assertNotIn("SSH_ASKPASS_PROMPT", env)
        self.assertEqual(env["LC_ALL"], "C")
        self.assertEqual(env["TERM"], "xterm-256color")
        self.assertIn("StrictHostKeyChecking=yes", args)

    def test_copy_uses_stdin(self):
        with patch.object(h.shutil, "which", return_value="wl-copy"), patch.object(h.subprocess, "run", return_value=Mock(returncode=0)) as run:
            self.call(op="copy", id=ID)
        self.assertEqual(run.call_args.args[0], ["wl-copy"])
        self.assertEqual(run.call_args.kwargs["input"], "example.test")


class HostKeyTests(Isolated):
    def test_bounded_keyscan_kills_oversized_output(self):
        marker = self.root / "producer-finished"
        code = ("import sys,time,pathlib; "
                f"sys.stdout.buffer.write(b'x'*{h.MAX_KEYSCAN_BYTES + 1}); sys.stdout.flush(); "
                f"time.sleep(2); pathlib.Path({str(marker)!r}).write_text('bad')")
        with patch.object(h.subprocess, "Popen", REAL_POPEN), self.assertRaises(h.Error) as raised:
            h.bounded_keyscan([sys.executable, "-c", code])
        self.assertIn("слишком велик", str(raised.exception))
        self.assertFalse(marker.exists(), "oversized producer must be killed before completing")

    def scan_result(self, d=None, algorithm="ssh-ed25519", material=b"synthetic-public-key"):
        d = d or profile()
        key, fingerprint = public_key(algorithm, material)
        line = f"{h.known_host_token(d)} {algorithm} {key}\n"
        return Mock(returncode=0, stdout=line, stderr=""), key, fingerprint

    def test_scan_safe_argv_preview_fingerprint_and_no_write(self):
        d = profile(host="2001:db8::1")
        result, key, fingerprint = self.scan_result(d)
        before = set(self.root.rglob("*"))
        with patch.object(h.shutil, "which", return_value="/usr/bin/tool"), \
             patch.object(h, "bounded_keyscan", return_value=result.stdout) as run:
            preview = h.host_key_preview(d, self.root / "home")["hostKeys"]
        self.assertEqual(preview["endpoint"], "[2001:db8::1]:2222")
        self.assertEqual(preview["state"], "new")
        self.assertEqual(preview["keys"], [{"algorithm": "ssh-ed25519", "key": key, "fingerprint": fingerprint}])
        argv = run.call_args.args[0]
        self.assertEqual(argv, ["ssh-keyscan", "-T", "5", "-p", "2222", "-t", h.KEYSCAN_TYPES, "--", "2001:db8::1"])
        self.assertEqual(run.call_args.kwargs, {})
        self.assertEqual(set(self.root.rglob("*")), before)

    def test_scan_rejects_wrong_token_malformed_key_and_failure(self):
        d = profile()
        key, _ = public_key()
        bad_outputs = [
            f"evil.test ssh-ed25519 {key}\n",
            "example.test ssh-ed25519 !!!\n",
            f"[example.test]:2222 ssh-dss {key}\n",
            "# banner only\n",
            f"[example.test]:2222 ssh-ed25519 {base64.b64encode(b'\\0\\0\\0\\7ssh-rsaX').decode()}\n",
        ]
        for output in bad_outputs:
            with self.subTest(output=output), self.assertRaises(h.Error):
                h.parse_keyscan_output(output, d)
        with patch.object(h.shutil, "which", return_value="ssh-keyscan"), \
             patch.object(h, "bounded_keyscan", side_effect=h.Error("ssh-keyscan не получил ключи")), \
             self.assertRaises(h.Error) as raised:
            h.keyscan(d)
        self.assertNotIn("secret", str(raised.exception))

    def test_trust_rescans_exact_match_and_appends_once_with_safe_modes(self):
        d = profile(host="192.0.2.10")
        scan, key, fingerprint = self.scan_result(d)
        keys = [{"algorithm": "ssh-ed25519", "key": key, "fingerprint": fingerprint}]
        token = h.revision({"endpoint": list(h.endpoint(d)), "hostToken": h.known_host_token(d),
                            "keys": [["ssh-ed25519", key]]})
        calls = []
        def run(argv, **kwargs):
            calls.append(argv)
            self.assertEqual(argv[0], "ssh-keygen")
            return Mock(returncode=1, stdout="", stderr="")
        home = self.root / "home"
        home.mkdir()
        with patch.object(h.shutil, "which", return_value="/usr/bin/tool"), \
             patch.object(h, "bounded_keyscan", return_value=scan.stdout) as keyscan_run, \
             patch.object(h.subprocess, "run", side_effect=run):
            result = h.trust_host_keys(d, keys, token, home)
        known = home / ".ssh/known_hosts"
        self.assertIn("строгий вход", result["message"])
        self.assertEqual(known.read_text(), f"[192.0.2.10]:2222 ssh-ed25519 {key}\n")
        self.assertEqual(stat.S_IMODE((home / ".ssh").stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(known.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((home / ".ssh/.tema.remote-devices-known-hosts.lock").stat().st_mode), 0o600)
        keyscan_run.assert_called_once()

    def test_existing_safe_permissions_are_preserved_not_chmodded(self):
        d = profile()
        scan, key, fingerprint = self.scan_result(d)
        keys = [{"algorithm": "ssh-ed25519", "key": key, "fingerprint": fingerprint}]
        token = h.revision({"endpoint": list(h.endpoint(d)), "hostToken": h.known_host_token(d),
                            "keys": [["ssh-ed25519", key]]})
        home = self.root / "home"
        ssh_dir = home / ".ssh"
        ssh_dir.mkdir(parents=True, mode=0o755)
        known = ssh_dir / "known_hosts"
        known.write_text("")
        known.chmod(0o644)
        with patch.object(h.shutil, "which", return_value="tool"), \
             patch.object(h, "bounded_keyscan", return_value=scan.stdout), \
             patch.object(h.subprocess, "run", return_value=Mock(returncode=1, stdout="", stderr="")):
            h.trust_host_keys(d, keys, token, home)
        self.assertEqual(stat.S_IMODE(ssh_dir.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE(known.stat().st_mode), 0o644)

    def test_trust_rejects_changed_rescan_and_tampered_preview_without_files(self):
        d = profile()
        _, key, fingerprint = self.scan_result(d)
        keys = [{"algorithm": "ssh-ed25519", "key": key, "fingerprint": fingerprint}]
        token = h.revision({"endpoint": list(h.endpoint(d)), "hostToken": h.known_host_token(d),
                            "keys": [["ssh-ed25519", key]]})
        changed, _, _ = self.scan_result(d, material=b"changed")
        home = self.root / "home"
        home.mkdir()
        with patch.object(h.shutil, "which", return_value="tool"), \
             patch.object(h, "bounded_keyscan", return_value=changed.stdout), self.assertRaises(h.Error):
            h.trust_host_keys(d, keys, token, home)
        self.assertFalse((home / ".ssh").exists())
        tampered = copy.deepcopy(keys)
        tampered[0]["fingerprint"] = "SHA256:wrong"
        with self.assertRaises(h.Error):
            h.trust_host_keys(d, tampered, token, home)

    def test_existing_matching_conflicting_and_special_records_are_never_changed(self):
        d = profile()
        scan, key, fingerprint = self.scan_result(d)
        other_key, _ = public_key(material=b"other")
        home = self.root / "home"
        ssh_dir = home / ".ssh"
        ssh_dir.mkdir(parents=True, mode=0o700)
        known = ssh_dir / "known_hosts"
        cases = [(f"[example.test]:2222 ssh-ed25519 {key}\n", "known"),
                 (f"[example.test]:2222 ssh-ed25519 {other_key}\n", "conflict"),
                 (f"@revoked [example.test]:2222 ssh-ed25519 {key}\n", "special")]
        for line, state in cases:
            with self.subTest(state=state):
                known.write_text(line)
                known.chmod(0o600)
                def run(argv, **kwargs):
                    return Mock(returncode=0, stdout="# Host found\n" + line, stderr="")
                with patch.object(h.shutil, "which", return_value="tool"), \
                     patch.object(h, "bounded_keyscan", return_value=scan.stdout), \
                     patch.object(h.subprocess, "run", side_effect=run):
                    preview = h.host_key_preview(d, home)["hostKeys"]
                    self.assertEqual(preview["state"], state)
                    with self.assertRaises(h.Error):
                        h.trust_host_keys(d, preview["keys"], preview["token"], home)
                self.assertEqual(known.read_text(), line)

    def test_existing_permissions_and_symlinks_fail_without_chmod(self):
        d = profile()
        scan, _, _ = self.scan_result(d)
        home = self.root / "home"
        ssh_dir = home / ".ssh"
        ssh_dir.mkdir(parents=True)
        ssh_dir.chmod(0o777)
        with patch.object(h.shutil, "which", return_value="tool"), \
             patch.object(h, "bounded_keyscan", return_value=scan.stdout), self.assertRaises(h.Error):
            h.host_key_preview(d, home)
        self.assertEqual(stat.S_IMODE(ssh_dir.stat().st_mode), 0o777)
        ssh_dir.chmod(0o700)
        target = home / "target"
        target.write_text("untouched")
        (ssh_dir / "known_hosts").symlink_to(target)
        with patch.object(h.shutil, "which", return_value="tool"), \
             patch.object(h, "bounded_keyscan", return_value=scan.stdout), self.assertRaises(h.Error):
            h.host_key_preview(d, home)
        self.assertEqual(target.read_text(), "untouched")
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o644)

    def test_supported_key_blobs_are_fully_parsed(self):
        for algorithm in sorted(h.KEY_ALGORITHMS):
            with self.subTest(algorithm=algorithm):
                key, fingerprint = public_key(algorithm)
                self.assertEqual(h.parse_public_key(algorithm, key, h.KEY_ALGORITHMS), fingerprint)
        algorithm = "ssh-ed25519"
        name = algorithm.encode()
        truncated = base64.b64encode(len(name).to_bytes(4, "big") + name + b"garbage").decode()
        with self.assertRaises(h.Error):
            h.parse_public_key(algorithm, truncated, h.KEY_ALGORITHMS)

    def test_plugin_concurrency_appends_only_once(self):
        d = profile()
        scan, key, fingerprint = self.scan_result(d)
        keys = [{"algorithm": "ssh-ed25519", "key": key, "fingerprint": fingerprint}]
        token = h.revision({"endpoint": list(h.endpoint(d)), "hostToken": h.known_host_token(d),
                            "keys": [["ssh-ed25519", key]]})
        home = self.root / "home"
        home.mkdir()
        def inspect(device, paths):
            known = home / ".ssh/known_hosts"
            if not known.exists() or not known.read_text():
                return []
            return [{"marker": "", "algorithm": "ssh-ed25519", "key": key, "fingerprint": fingerprint}]
        def enroll():
            try:
                h.trust_host_keys(d, keys, token, home)
                return "written"
            except h.Error:
                return "already"
        with patch.object(h.shutil, "which", return_value="tool"), \
             patch.object(h, "bounded_keyscan", return_value=scan.stdout), patch.object(h, "known_entries", side_effect=inspect):
            with h.concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda _: enroll(), range(2)))
        self.assertEqual(sorted(results), ["already", "written"])
        self.assertEqual((home / ".ssh/known_hosts").read_text(),
                         f"[example.test]:2222 ssh-ed25519 {key}\n")

    def test_default_port_token_has_no_brackets(self):
        self.assertEqual(h.known_host_token(profile(host="2001:db8::1", port=22)), "2001:db8::1")
        self.assertEqual(h.known_host_token(profile(host="example.test", port=22)), "example.test")


class StatusTests(Isolated):
    def test_unsaved_endpoint_check_sends_only_host_and_port(self):
        status = {"ping": "ok", "ms": 3.5, "ssh": "open", "checkedAt": "now", "endpoint": []}
        with patch.object(h, "bounded_probe", return_value=("probe", status)) as probe:
            result = self.call(op="checkEndpoint", host="EXAMPLE.test.", port=2222)
        sent = probe.call_args.args[0]
        self.assertEqual((sent["host"], sent["port"]), ("example.test", 2222))
        self.assertEqual(result["draftStatus"]["endpoint"], ["example.test", 2222])
        for forbidden in ("password", "note", "keyPath", "remoteFolder"):
            self.assertNotIn(forbidden, {"host": sent["host"], "port": sent["port"]})
        with self.assertRaises(h.Error):
            self.call(op="checkEndpoint", host="example.test", port=22, password="secret")

    def test_ping_and_tcp_independent(self):
        sock = Mock()
        sock.__enter__ = Mock(return_value=sock)
        sock.__exit__ = Mock(return_value=False)
        with patch.object(h.subprocess, "run", return_value=Mock(returncode=1, stdout="")), patch.object(h.socket, "getaddrinfo", return_value=[(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("192.0.2.1", 2222))]), patch.object(h.socket, "socket", return_value=sock):
            result = h.probe(profile())
        self.assertEqual(result, {"ping": "unreachable", "ms": None, "ssh": "open"})

    def test_ping_ms_and_dns_failure(self):
        with patch.object(h.subprocess, "run", return_value=Mock(returncode=0, stdout="64 bytes time=1.25 ms")) as run, patch.object(h.socket, "getaddrinfo", side_effect=socket.gaierror()):
            result = h.probe(profile())
        self.assertEqual(result, {"ping": "ok", "ms": 1.25, "ssh": "dns-error"})
        self.assertEqual(run.call_args.args[0][-2:], ["--", "example.test"])
        self.assertEqual(run.call_args.kwargs["timeout"], 2)

    def test_ping_missing_timeout_error_and_tcp_timeout(self):
        sock = Mock()
        sock.__enter__ = Mock(return_value=sock)
        sock.__exit__ = Mock(return_value=False)
        sock.connect.side_effect = TimeoutError()
        for failure, expected in [(FileNotFoundError(), "unavailable"), (subprocess.TimeoutExpired("ping", 2), "timeout")]:
            with patch.object(h.subprocess, "run", side_effect=failure), patch.object(h.socket, "getaddrinfo", return_value=[(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("192.0.2.1", 22))]), patch.object(h.socket, "socket", return_value=sock):
                result = h.probe(profile())
            self.assertEqual(result["ping"], expected)
            self.assertEqual(result["ssh"], "timeout")

    def test_child_timeout_failure_malformed_output_and_timestamp(self):
        for output in [subprocess.TimeoutExpired("probe", 6), OSError(), Mock(returncode=1), Mock(returncode=0, stdout="bad"), Mock(returncode=0, stdout="{}")]:
            kwargs: dict[str, Any] = {"side_effect": output} if isinstance(output, Exception) else {"return_value": output}
            with patch.object(h.subprocess, "run", **kwargs):
                id_, status = h.bounded_probe(profile())
            self.assertEqual(id_, ID)
            self.assertIn(status["ssh"], ["error", "timeout"])
            self.assertIn("checkedAt", status)
            self.assertEqual(status["endpoint"], ["example.test", 2222, "tema"])

    def test_bounded_async_pool_no_persistence(self):
        before = self.store.path.read_bytes()
        with patch.object(h, "bounded_probe", return_value=(ID, {"ping": "ok", "ssh": "open"})) as probe:
            result = self.call(op="check")
        probe.assert_called_once()
        self.assertEqual(result["statuses"][ID]["ssh"], "open")
        self.assertEqual(before, self.store.path.read_bytes())

    def test_check_device_probes_only_selected_host(self):
        before = self.store.path.read_bytes()
        status = {"ping": "ok", "ms": 4.2, "ssh": "open"}
        with patch.object(h, "bounded_probe", return_value=(ID, status)) as probe:
            result = self.call(op="checkDevice", id=ID)
        probe.assert_called_once()
        self.assertEqual(probe.call_args.args[0]["id"], ID)
        self.assertEqual(result, {"statuses": {ID: status}})
        self.assertEqual(before, self.store.path.read_bytes())

        for request in ({"op": "checkDevice", "id": "not-a-uuid"},
                        {"op": "checkDevice", "id": ID, "password": "secret"}):
            with self.assertRaises(h.Error), patch.object(h, "bounded_probe") as rejected_probe:
                h.dispatch(request, self.store)
            rejected_probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
