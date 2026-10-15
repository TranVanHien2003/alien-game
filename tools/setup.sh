#!/usr/bin/env bash
# Tải Godot editor (và tùy chọn export templates) đúng phiên bản trong .godot-version.
#   tools/setup.sh              -> chỉ editor (~75 MB)
#   tools/setup.sh --templates  -> editor + export templates (~1.3 GB, cần để export Web ở máy)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.godot-version")"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
BIN_DIR="$HOME/.local/share/godot-bin/$VERSION"
TPL_DIR="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$(uname -m)" in
	x86_64) ARCH="x86_64" ;;
	aarch64|arm64) ARCH="arm64" ;;
	*) echo "Kiến trúc không hỗ trợ: $(uname -m)" >&2; exit 1 ;;
esac

if [[ -x "$BIN_DIR/godot" ]]; then
	echo "✓ Godot $VERSION đã có tại $BIN_DIR/godot"
else
	echo "→ Tải Godot $VERSION editor..."
	ZIP="Godot_v${VERSION}-stable_linux.${ARCH}.zip"
	curl -fL --progress-bar -o "$TMP/$ZIP" "$BASE_URL/$ZIP"
	mkdir -p "$BIN_DIR"
	unzip -q "$TMP/$ZIP" -d "$TMP/editor"
	mv "$TMP"/editor/Godot_v${VERSION}-stable_linux.${ARCH} "$BIN_DIR/godot"
	chmod +x "$BIN_DIR/godot"
	echo "✓ Đã cài $BIN_DIR/godot"
fi

if [[ "${1:-}" == "--templates" ]]; then
	if [[ -f "$TPL_DIR/web_nothreads_release.zip" ]]; then
		echo "✓ Export templates $VERSION đã có"
	else
		echo "→ Tải export templates $VERSION (file lớn, chờ chút)..."
		TPZ="Godot_v${VERSION}-stable_export_templates.tpz"
		curl -fL --progress-bar -o "$TMP/$TPZ" "$BASE_URL/$TPZ"
		mkdir -p "$TPL_DIR"
		# Chỉ giải nén template Web để tiết kiệm dung lượng
		unzip -q -j "$TMP/$TPZ" 'templates/web_*' 'templates/version.txt' -d "$TPL_DIR"
		echo "✓ Đã cài template Web vào $TPL_DIR"
	fi
fi

# Cấu hình Godot dùng VS Code làm external editor
python3 "$ROOT/tools/configure_editor.py" "$VERSION" || echo "! Bỏ qua cấu hình external editor"

# Import lần đầu để sinh cache .godot/ (class_name, uid...)
"$ROOT/tools/godot.sh" --headless --import >/dev/null 2>&1 || true
echo "✓ Xong. Thử: make run"
