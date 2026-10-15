#!/usr/bin/env python3
"""Bật VS Code làm external editor cho Godot (sửa editor_settings-<major.minor>.tres)."""
import os
import re
import shutil
import sys
from pathlib import Path

version = sys.argv[1] if len(sys.argv) > 1 else "4.7"
major_minor = ".".join(version.split(".")[:2])
config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
settings_file = config_home / "godot" / f"editor_settings-{major_minor}.tres"

code = shutil.which("code") or "/usr/bin/code"
wanted = {
    "text_editor/external/use_external_editor": "true",
    "text_editor/external/exec_path": f'"{code}"',
    "text_editor/external/exec_flags": '"{project} --goto {file}:{line}:{col}"',
}

if settings_file.exists():
    text = settings_file.read_text(encoding="utf-8")
else:
    settings_file.parent.mkdir(parents=True, exist_ok=True)
    text = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'

for key, value in wanted.items():
    line = f"{key} = {value}"
    pattern = re.compile(rf"^{re.escape(key)} = .*$", re.M)
    if pattern.search(text):
        text = pattern.sub(lambda _: line, text)
    else:
        text = text.rstrip("\n") + "\n" + line + "\n"

settings_file.write_text(text, encoding="utf-8")
print(f"✓ External editor = {code} ({settings_file})")
