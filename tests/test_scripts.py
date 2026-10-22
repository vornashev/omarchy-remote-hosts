"""Script tests use private temporary files and fake SSH/terminal processes only."""
import io
import json
import stat
import sys
import unittest
from unittest.mock import Mock, patch

from test_helper import Isolated, ID
import helper as h


class ScriptTests(Isolated):
    def setUp(self):
        super().setUp()
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.home_patch = patch.object(h, "user_home", return_value=self.home)
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)

    def save(self, **overrides):
        return self.call(**{"op": "saveScript", "id": ID, "scriptId": "", "name": "Deploy",
                            "body": "#!/bin/sh\nprintf 'ok\\n'\n", **overrides})

    def test_save_list_edit_delete_without_exposing_body(self):
        reply = self.save()
        self.assertEqual(reply["scripts"][ID][0]["name"], "Deploy")
        self.assertNotIn("body", str(reply))
        entry_id = reply["scripts"][ID][0]["id"]
        self.assertEqual(self.call(op="list")["scripts"][ID], reply["scripts"][ID])
        edited = self.call(op="saveScript", id=ID, scriptId=entry_id, name="Release")
        self.assertEqual(edited["scripts"][ID][0]["name"], "Release")
        self.assertEqual(self.store.load_scripts()[0]["body"], "#!/bin/sh\nprintf 'ok\\n'\n")
        self.assertEqual(stat.S_IMODE(self.store.scripts_path.stat().st_mode), 0o600)
        self.assertEqual(self.call(op="deleteScript", id=ID, scriptId=entry_id)["scripts"][ID], [])

    def test_listing_shows_only_first_command_as_summary(self):
        reply = self.save(body="#!/bin/sh\n# deploy\n\n  docker compose up -d\x1b[31m\nrm -rf /tmp/x\n")
        entry = reply["scripts"][ID][0]
        self.assertEqual(entry["summary"], "docker compose up -d [31m")
        self.assertNotIn("rm -rf", str(reply))

    def test_rejects_invalid_body_duplicate_names_and_extra_fields(self):
        entry_id = self.save()["scripts"][ID][0]["id"]
        for body in ("", "\x00", "x" * (h.MAX_SCRIPT_BYTES + 1)):
            with self.subTest(body=body[:4]), self.assertRaises(h.Error):
                self.call(op="saveScript", id=ID, scriptId="", name="Other", body=body)
        with self.assertRaises(h.Error):
            self.save(body="echo duplicate")
        with self.assertRaises(h.Error):
            self.call(op="saveScript", id=ID, scriptId=entry_id, name="Release", body="echo ok", unexpected="x")

    def test_endpoint_changes_revoke_access_and_host_delete_removes_scripts(self):
        entry_id = self.save()["scripts"][ID][0]["id"]
        changed = self.store.load()
        changed["devices"][0]["host"] = "other.example.test"
        self.store.save(changed)
        self.assertEqual(self.call(op="list")["scripts"][ID], [])
        with self.assertRaises(h.Error):
            self.call(op="launchScript", id=ID, scriptId=entry_id)
        self.call(op="deleteDevice", id=ID)
        self.assertEqual(self.store.load_scripts(), [])

    def test_file_browser_rejects_symlinks_traversal_non_executable_and_large_files(self):
        folder = self.home / "scripts"
        folder.mkdir()
        valid = folder / "deploy.sh"
        valid.write_text("#!/bin/sh\necho ready\n")
        valid.chmod(0o700)
        (folder / "shortcut.sh").symlink_to(valid)
        invalid = folder / "disabled.sh"
        invalid.write_text("echo skip")
        browser = self.call(op="browseScripts", folder=str(folder))["browser"]
        self.assertEqual([item["name"] for item in browser["files"]], ["deploy.sh", "disabled.sh"])
        self.assertTrue(browser["files"][0]["selectable"])
        self.assertFalse(browser["files"][1]["selectable"])
        self.assertEqual(h.script_file(str(valid)), valid.read_text())
        for path in (folder / "shortcut.sh", invalid, self.home / ".." / "outside.sh"):
            with self.subTest(path=path), self.assertRaises((h.Error, OSError)):
                h.script_file(str(path))
        valid.write_text("x" * (h.MAX_SCRIPT_BYTES + 1))
        with self.assertRaises(h.Error):
            h.script_file(str(valid))

    def test_file_picker_remembers_folder_across_sessions_and_handles_removed_folder(self):
        folder = self.home / "projects" / "scripts"
        folder.mkdir(parents=True)
        selected = self.call(op="browseScripts", folder=str(folder))["browser"]
        self.assertEqual(selected["folder"], str(folder))
        self.assertEqual(stat.S_IMODE(self.store.script_browser_path.stat().st_mode), 0o600)
        reopened = h.dispatch({"op": "browseScripts", "folder": ""}, h.Store(self.store.root))["browser"]
        self.assertEqual(reopened["folder"], str(folder))
        folder.rmdir()
        fallback = self.call(op="browseScripts", folder="")["browser"]
        self.assertEqual(fallback["folder"], str(self.home))
        self.assertEqual(self.store.load_script_folder(), str(self.home))

    def test_unsafe_browser_state_fails_closed_and_failed_navigation_keeps_last_folder(self):
        folder = self.home / "scripts"
        folder.mkdir()
        self.call(op="browseScripts", folder=str(folder))
        outside = self.root / "outside"
        outside.mkdir()
        with self.assertRaises(h.Error):
            self.call(op="browseScripts", folder=str(outside))
        self.assertEqual(self.store.load_script_folder(), str(folder))
        self.store.script_browser_path.unlink()
        self.store.script_browser_path.symlink_to(self.root / "missing")
        with self.assertRaises(h.Error):
            self.call(op="browseScripts", folder="")

    def test_file_is_copied_not_re_read_at_launch_and_not_in_argv(self):
        source = self.home / "task.sh"
        source.write_text("#!/bin/sh\necho first\n")
        source.chmod(0o700)
        reply = self.call(op="saveScript", id=ID, scriptId="", name="Task", path=str(source))
        entry_id = reply["scripts"][ID][0]["id"]
        self.assertEqual(reply["scripts"][ID][0]["sourcePath"], str(source))
        source.write_text("#!/bin/sh\necho changed\n")
        with patch.object(h, "Store", return_value=self.store):
            self.assertEqual(h.script_preview({"id": ID, "scriptId": entry_id}), "#!/bin/sh\necho first\n")
        renamed = self.call(op="saveScript", id=ID, scriptId=entry_id, name="Renamed")
        self.assertEqual(renamed["scripts"][ID][0]["sourcePath"], str(source))
        with patch.object(h, "Store", return_value=self.store), \
             patch.object(h, "has_known_host_entry", return_value=True), \
             patch.object(h, "ssh_environment", return_value={}), \
             patch.object(h.shutil, "which", return_value="/usr/bin/ssh"):
            run = Mock(return_value=Mock(returncode=0))
            with patch.object(h.subprocess, "run", run):
                self.assertEqual(h.terminal_script(ID, entry_id), 0)
        args = run.call_args.args[0]
        self.assertEqual(args[:3], ["ssh", "-F", "/dev/null"])
        self.assertIn("StrictHostKeyChecking=yes", args)
        self.assertIn("-T", args)
        self.assertEqual(args[-4:], ["--", "example.test", "sh", "-s"])
        self.assertEqual(run.call_args.kwargs["input"], b"#!/bin/sh\necho first\n")
        self.assertNotIn("first", str(args) + str(run.call_args.kwargs["env"]))

    def test_file_preview_uses_validated_copy_and_raw_pipe_not_json(self):
        source = self.home / "preview.sh"
        source.write_text("#!/bin/sh\necho visible\n")
        source.chmod(0o700)
        self.assertEqual(h.script_preview({"path": str(source)}), source.read_text())
        with self.assertRaises(h.Error):
            h.script_preview({"path": str(source), "body": "extra"})
        saved = self.call(op="saveScript", id=ID, scriptId="", name="Preview", path=str(source))
        entry_id = saved["scripts"][ID][0]["id"]
        source.unlink()
        stdout = io.StringIO()
        request = io.TextIOWrapper(io.BytesIO((json.dumps({"id": ID, "scriptId": entry_id}) + "\n").encode()))
        with patch.object(h, "Store", return_value=self.store), \
             patch.object(sys, "argv", ["helper.py", "--script-preview"]), \
             patch.object(sys, "stdin", request), patch.object(sys, "stdout", stdout):
            h.main()
        self.assertEqual(stdout.getvalue(), "#!/bin/sh\necho visible\n")
        self.assertNotIn("body", str(saved))

    def test_old_scripts_without_source_path_still_load(self):
        reply = self.save()
        entry_id = reply["scripts"][ID][0]["id"]
        path = self.store.scripts_path
        rows = json.loads(path.read_text())
        rows[0].pop("sourcePath")
        path.write_text(json.dumps(rows))
        self.assertEqual(self.call(op="list")["scripts"][ID][0]["sourcePath"], "")
        with patch.object(h, "Store", return_value=self.store):
            self.assertEqual(h.script_preview({"id": ID, "scriptId": entry_id}), rows[0]["body"])

    def test_symlinked_directory_and_unsafe_permissions_are_rejected(self):
        folder = self.home / "scripts"
        folder.mkdir()
        source = folder / "task.sh"
        source.write_text("echo ok")
        source.chmod(0o700)
        (self.home / "alias").symlink_to(folder, target_is_directory=True)
        with self.assertRaises((h.Error, OSError)):
            h.script_file(str(self.home / "alias" / "task.sh"))
        source.chmod(0o722)
        with self.assertRaises(h.Error):
            h.script_file(str(source))

    def test_corrupt_storage_and_linked_storage_fail_closed(self):
        self.save()
        target = self.store.scripts_path
        raw = target.read_text()
        target.unlink()
        target.symlink_to(self.root / "missing")
        with self.assertRaises(h.Error):
            self.call(op="list")
        target.unlink()
        target.write_text(raw.replace('"endpoint":', '"unexpected": 1, "endpoint":'))
        target.chmod(0o600)
        with self.assertRaises(h.Error):
            self.call(op="list")

    def test_bash_shebang_uses_bash_without_interpreting_shell_fragments(self):
        reply = self.call(op="saveScript", id=ID, scriptId="", name="Bash",
                          body="#!/usr/bin/env bash\necho ready\n")
        entry_id = reply["scripts"][ID][0]["id"]
        with patch.object(h, "Store", return_value=self.store), \
             patch.object(h, "has_known_host_entry", return_value=True), \
             patch.object(h, "ssh_environment", return_value={}), \
             patch.object(h.shutil, "which", return_value="/usr/bin/ssh"):
            run = Mock(return_value=Mock(returncode=0))
            with patch.object(h.subprocess, "run", run):
                h.terminal_script(ID, entry_id)
        self.assertEqual(run.call_args.args[0][-2:], ["bash", "-s"])
        with self.assertRaises(h.Error):
            self.call(op="saveScript", id=ID, scriptId="", name="Other",
                      body="#!/usr/bin/env python3\nprint('no')\n")

    def test_launch_requires_verified_key_before_spawning_terminal(self):
        entry_id = self.save()["scripts"][ID][0]["id"]
        with patch.object(h, "has_known_host_entry", return_value=False), \
             patch.object(h, "host_key_preview", return_value={"hostKeys": {}}):
            self.assertIn("hostKeys", self.call(op="launchScript", id=ID, scriptId=entry_id))
        with patch.object(h, "has_known_host_entry", return_value=True), \
             patch.object(h.shutil, "which", return_value="/usr/bin/fake"), \
             patch.object(h.subprocess, "Popen", return_value=Mock()) as popen:
            self.call(op="launchScript", id=ID, scriptId=entry_id)
        self.assertEqual(popen.call_args.args[0][-3:], ["--terminal-script", ID, entry_id])
        self.assertNotIn("body", str(popen.call_args))


if __name__ == "__main__":
    unittest.main()
