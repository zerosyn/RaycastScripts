# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit>=0.13,<1"]
# ///
"""Raycast account list generation and Codex account switching."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import tomlkit


def merge_config(current: str, extra: str | None) -> str:
    config = tomlkit.parse(current)
    config.pop("model_provider", None)
    providers = config.get("model_providers")
    if providers is not None:
        providers.pop("custom", None)
    if extra is not None:
        addition = tomlkit.parse(extra)
        if "model_provider" in addition:
            config.add("model_provider", addition["model_provider"])
        custom = addition.get("model_providers", {}).get("custom")
        if custom is not None:
            if providers is None:
                config.add("model_providers", tomlkit.table())
            config["model_providers"].add("custom", custom)
    result = tomlkit.dumps(config)
    tomlkit.parse(result)
    return result


def write_atomic(path: Path, data: bytes, mode: int = 0o600) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            os.fchmod(output.fileno(), mode)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def switch_account(home: Path, account: str) -> None:
    if account in ("", ".", "..") or Path(account).name != account:
        raise ValueError("无效的账号名称")
    source = home / "providers" / account
    with (home / ".account-switch.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current_auth = home / "auth.json"
        if current_auth.exists():
            active_auth = current_auth.read_bytes()
            if json.loads(active_auth).get("auth_mode") == "chatgpt":
                origin = home / "providers" / "origin"
                origin.mkdir(parents=True, exist_ok=True)
                write_atomic(origin / "auth.json", active_auth)
        # Read the target after backup, including when switching to origin.
        if not source.is_dir():
            raise ValueError("账号目录不存在，请刷新账号列表")
        auth_path = source / "auth.json"
        auth = auth_path.read_bytes() if auth_path.exists() else None
        if auth is not None:
            json.loads(auth)
        env = (source / ".env").read_bytes() if (source / ".env").exists() else None
        plus = source / "config.toml.plus"
        paths = [home / name for name in (".env", "auth.json", "config.toml")]
        before = {p: (p.read_bytes(), p.stat().st_mode & 0o777) if p.exists()
                  else None for p in paths}
        original = before[paths[2]]
        updated = merge_config(
            original[0].decode("utf-8") if original else "",
            plus.read_text(encoding="utf-8") if plus.exists() else None,
        ).encode("utf-8")
        try:
            paths[0].unlink(missing_ok=True)
            if env is not None:
                write_atomic(paths[0], env)
            if auth is not None:
                write_atomic(paths[1], auth)
            write_atomic(paths[2], updated, original[1] if original else 0o600)
        except OSError:
            for path, snapshot in before.items():
                if snapshot is None:
                    path.unlink(missing_ok=True)
                else:
                    write_atomic(path, *snapshot)
            raise


def refresh_accounts(home: Path, destination: Path) -> None:
    accounts = sorted(p.name for p in (home / "providers").iterdir() if p.is_dir())
    if not accounts:
        raise ValueError("providers 目录下没有账号子目录")
    argument = json.dumps({"type": "dropdown", "placeholder": "选择账号",
                           "data": [{"title": name, "value": name} for name in accounts]},
                          ensure_ascii=False)
    script = '''#!/bin/bash
# @metadata.schemaVersion 1
# @metadata.title Switch Codex Account
# @metadata.mode compact
# @metadata.icon 🔄
# @metadata.packageName Codex
# @metadata.argument1 ARGUMENT

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
script_dir="$(cd "$(dirname "$0")" && pwd)"
exec uv run --quiet --script "$script_dir/codex-account.py" switch "$1"
'''.replace("@metadata.", "@raycast.").replace("ARGUMENT", argument)
    write_atomic(destination / "switch-codex-account.sh", script.encode("utf-8"), 0o755)
    print(f"已刷新 {len(accounts)} 个账号；Raycast 会重新读取命令选项。")


def prompt_restart() -> bool:
    result = subprocess.run(["/usr/bin/osascript", "-e", '''
        set answer to display dialog "重新启动Codex桌面应用" with title "Codex 账号已切换" buttons {"稍后", "确认"} default button "确认"
        return button returned of answer
    '''], capture_output=True, text=True)
    return result.returncode == 0 and result.stdout.strip() == "确认"


def restart_codex() -> None:
    result = subprocess.run(["/usr/bin/osascript", "-e", '''
        if application "Codex" is running then
            tell application "Codex" to quit
            repeat 150 times
                if application "Codex" is not running then exit repeat
                delay 0.2
            end repeat
            if application "Codex" is running then error "Codex 未能退出，请手动重启"
        end if
    '''], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("账号已切换，但 Codex 未能退出，请手动重启")
    subprocess.run(["/usr/bin/open", "-a", "Codex"], check=True, capture_output=True)


def main() -> None:
    home = Path.home() / ".codex"
    if len(sys.argv) == 2 and sys.argv[1] == "refresh":
        refresh_accounts(home, Path(__file__).resolve().parent)
    elif len(sys.argv) == 3 and sys.argv[1] == "switch":
        switch_account(home, sys.argv[2])
        print(f"已切换到 {sys.argv[2]}", flush=True)
        if prompt_restart():
            restart_codex()
    else:
        raise ValueError("用法：codex-account.py refresh | switch <账号名>")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Parser errors can contain secret values; never print their details.
        message = str(error) if isinstance(error, (RuntimeError, ValueError)) and not isinstance(error, json.JSONDecodeError) else "请检查账号文件、TOML 格式、文件权限及 Codex 安装状态"
        if isinstance(error, tomlkit.exceptions.ParseError):
            message = "TOML 格式无效，未执行切换"
        print(f"操作失败：{message}", file=sys.stderr)
        sys.exit(1)
