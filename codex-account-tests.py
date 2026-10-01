import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import tomlkit

spec = importlib.util.spec_from_file_location("account", Path(__file__).with_name("codex-account.py"))
account = importlib.util.module_from_spec(spec)
spec.loader.exec_module(account)


class AccountTests(unittest.TestCase):
    def test_provider_without_auth_file(self):
        for active in (None, b'{"auth_mode":"chatgpt","token":"fresh"}', b'{"auth_mode":"apikey"}'):
            with self.subTest(active=active), tempfile.TemporaryDirectory() as temporary:
                home = Path(temporary)
                source = home / "providers" / "custom"
                source.mkdir(parents=True)
                plus = 'model_provider="custom"\n[model_providers.custom]\nname="example"\nexperimental_bearer_token="fake-secret"\n[model_providers.custom.http_headers]\nAuthorization="Bearer fake"\n'
                (source / "config.toml.plus").write_text(plus)
                (home / ".env").write_text("OLD=fake")
                if active is not None:
                    (home / "auth.json").write_bytes(active)
                account.switch_account(home, "custom")
                self.assertFalse((home / ".env").exists())
                self.assertEqual(tomlkit.parse((home / "config.toml").read_text()), tomlkit.parse(plus))
                if active is None:
                    self.assertFalse((home / "auth.json").exists())
                else:
                    self.assertEqual((home / "auth.json").read_bytes(), active)
                    if json.loads(active)["auth_mode"] == "chatgpt":
                        self.assertEqual((home / "providers/origin/auth.json").read_bytes(), active)
                        account.switch_account(home, "origin")
                        self.assertEqual((home / "auth.json").read_bytes(), active)
                        self.assertNotIn("custom", tomlkit.parse((home / "config.toml").read_text()).get("model_providers", {}))

    def test_backup_chatgpt_before_reading_target(self):
        for target in ("custom", "origin"):
            for existing_origin in (False, True):
                with self.subTest(target=target, existing_origin=existing_origin), tempfile.TemporaryDirectory() as temporary:
                    home = Path(temporary)
                    origin = home / "providers" / "origin"
                    custom = home / "providers" / "custom"
                    custom.mkdir(parents=True)
                    custom_auth = b'{"auth_mode":"apikey"}'
                    (custom / "auth.json").write_bytes(custom_auth)
                    if existing_origin:
                        origin.mkdir()
                        (origin / "auth.json").write_text('{"token":"stale"}')
                    active = b'{"auth_mode": "chatgpt", "token": "fresh"}\n'
                    (home / "auth.json").write_bytes(active)
                    account.switch_account(home, target)
                    self.assertEqual((origin / "auth.json").read_bytes(), active)
                    self.assertEqual((origin / "auth.json").stat().st_mode & 0o777, 0o600)
                    self.assertEqual((home / "auth.json").read_bytes(), active if target == "origin" else custom_auth)

    def test_non_chatgpt_does_not_replace_origin(self):
        for active in (b'{"auth_mode":"apikey"}', b'{}', None):
            with self.subTest(active=active), tempfile.TemporaryDirectory() as temporary:
                home = Path(temporary)
                origin = home / "providers" / "origin"
                origin.mkdir(parents=True)
                saved = b'{"auth_mode":"chatgpt","token":"saved"}'
                (origin / "auth.json").write_bytes(saved)
                if active is not None:
                    (home / "auth.json").write_bytes(active)
                account.switch_account(home, "origin")
                self.assertEqual((origin / "auth.json").read_bytes(), saved)
                self.assertEqual((home / "auth.json").read_bytes(), saved)

    def test_backup_failure_stops_switch(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            target = home / "providers" / "custom"
            target.mkdir(parents=True)
            (target / "auth.json").write_text('{}')
            active = b'{"auth_mode":"chatgpt"}'
            (home / "auth.json").write_bytes(active)
            (home / ".env").write_text("KEEP=fake")
            with patch.object(account, "write_atomic", side_effect=OSError("backup failed")):
                with self.assertRaises(OSError):
                    account.switch_account(home, "custom")
            self.assertEqual((home / "auth.json").read_bytes(), active)
            self.assertEqual((home / ".env").read_text(), "KEEP=fake")

    def test_merge_preserves_hierarchy_and_unrelated_content(self):
        original = '''# keep this comment
model = "example"
model_provider = "old"
[projects."/tmp/work"]
trust_level = "trusted"
[model_providers.custom]
name = "old"
[model_providers.custom.http_headers]
old = "header"
[model_providers.other]
name = "keep"
'''
        plus = '''model_provider = "custom"
ignored = true
[model_providers.custom]
name = "new"
description = """line one
[not_a_table]
line three"""
[model_providers.custom.http_headers]
new = "header"
'''
        result = account.merge_config(original, plus)
        parsed = tomlkit.parse(result)
        self.assertEqual(parsed["model_provider"], "custom")
        self.assertEqual(parsed["projects"]["/tmp/work"]["trust_level"], "trusted")
        self.assertEqual(parsed["model_providers"]["custom"]["http_headers"], {"new": "header"})
        self.assertEqual(parsed["model_providers"]["other"]["name"], "keep")
        self.assertNotIn("ignored", parsed)
        self.assertIn("# keep this comment", result)
        self.assertEqual(tomlkit.parse(account.merge_config(result, plus)), parsed)
        cleared = tomlkit.parse(account.merge_config(result, None))
        self.assertNotIn("model_provider", cleared)
        self.assertNotIn("custom", cleared["model_providers"])

    def test_switch_and_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            source = home / "providers" / "测试 account"
            source.mkdir(parents=True)
            (source / "auth.json").write_text('{"token":"fake"}')
            (home / ".env").write_text("OLD=fake")
            (home / "config.toml").write_text('model_provider="old"\n[other]\nx=1\n')
            account.switch_account(home, source.name)
            self.assertFalse((home / ".env").exists())
            self.assertEqual(json.loads((home / "auth.json").read_text()), {"token": "fake"})
            self.assertEqual((home / "auth.json").stat().st_mode & 0o777, 0o600)
            (source / ".env").write_text("NEW=fake")
            (source / "config.toml.plus").write_text('model_provider="custom"\n[model_providers.custom]\nname="new"\n')
            account.switch_account(home, source.name)
            self.assertEqual((home / ".env").read_text(), "NEW=fake")
            before = {p.name: p.read_bytes() for p in home.iterdir() if p.is_file()}
            (source / "config.toml.plus").write_text("invalid = [")
            with self.assertRaises(Exception):
                account.switch_account(home, source.name)
            self.assertEqual(before, {p.name: p.read_bytes() for p in home.iterdir() if p.is_file()})
            with self.assertRaises(ValueError):
                account.switch_account(home, "../outside")

    def test_rollback_on_write_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            source = home / "providers" / "test"
            source.mkdir(parents=True)
            (source / "auth.json").write_text("{}")
            (home / ".env").write_text("OLD=fake")
            real_write = account.write_atomic
            failed = False

            def failing_write(path, *args):
                nonlocal failed
                if path.name == "config.toml" and not failed:
                    failed = True
                    raise OSError("simulated write failure")
                return real_write(path, *args)

            with patch.object(account, "write_atomic", side_effect=failing_write):
                with self.assertRaises(OSError):
                    account.switch_account(home, "test")
            self.assertEqual((home / ".env").read_text(), "OLD=fake")
            self.assertFalse((home / "auth.json").exists())
            self.assertFalse((home / "config.toml").exists())

    def test_refresh_dropdown(self):
        # Raycast also scans helper source files for command metadata.
        helper = Path(account.__file__).read_text()
        self.assertFalse(any(line.startswith("# @raycast.") for line in helper.splitlines()))
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            for name in ['中文账号', 'quoted " account']:
                (home / "providers" / name).mkdir(parents=True)
            account.refresh_accounts(home, home)
            script = (home / "switch-codex-account.sh").read_text()
            line = next(line for line in script.splitlines() if line.startswith("# @raycast.argument1 "))
            options = json.loads(line.removeprefix("# @raycast.argument1 "))
            self.assertEqual({item["value"] for item in options["data"]}, {'中文账号', 'quoted " account'})


if __name__ == "__main__":
    unittest.main()
