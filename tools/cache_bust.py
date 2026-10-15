#!/usr/bin/env python3
"""Chống cache trình duyệt cho bản Web: đổi index.pck -> index.<hash>.pck và trỏ GODOT_CONFIG.mainPack tới đó.
Mỗi bản build có tên gói khác nhau nên người chơi luôn tải bản mới nhất (GitHub Pages cache 10 phút).
    python3 tools/cache_bust.py build/web
"""
import hashlib
import json
import re
import sys
from pathlib import Path

web = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
html_path = web / "index.html"
pck = web / "index.pck"
if not pck.exists():
    sys.exit("Không thấy index.pck (đã cache-bust rồi?)")

digest = hashlib.sha256(pck.read_bytes()).hexdigest()[:10]
for old in web.glob("index.*.pck"):
    old.unlink()
new_name = f"index.{digest}.pck"
pck.rename(web / new_name)

html = html_path.read_text(encoding="utf-8")
match = re.search(r"const GODOT_CONFIG = (\{.*?\});", html)
if not match:
    sys.exit("Không thấy GODOT_CONFIG trong index.html")
config = json.loads(match.group(1))
sizes = config.get("fileSizes", {})
if "index.pck" in sizes:
    sizes[new_name] = sizes.pop("index.pck")
config["mainPack"] = new_name
html = html.replace(match.group(0), "const GODOT_CONFIG = " + json.dumps(config, separators=(",", ":")) + ";")
html_path.write_text(html, encoding="utf-8")
print(f"✓ Gói dữ liệu: {new_name}")
