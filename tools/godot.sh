#!/usr/bin/env bash
# Wrapper tìm đúng binary Godot cho project (theo .godot-version).
# Thứ tự ưu tiên: biến GODOT -> ~/.local/share/godot-bin/<ver>/godot -> godot4/godot trong PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.godot-version")"
CANDIDATES=("${GODOT:-}" "$HOME/.local/share/godot-bin/$VERSION/godot" "$(command -v godot4 || true)" "$(command -v godot || true)")
for bin in "${CANDIDATES[@]}"; do
	if [[ -n "$bin" && -x "$bin" ]]; then
		exec "$bin" --path "$ROOT" "$@"
	fi
done
echo "Không tìm thấy Godot $VERSION. Chạy: make setup" >&2
exit 1
