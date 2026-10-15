SHELL := /bin/bash
# Mọi thao tác thường ngày đều có lệnh make. Chạy `make help` để xem danh sách.
GODOT   := tools/godot.sh
VERSION := $(shell cat .godot-version)
PORT    ?= 8000

.PHONY: help assets setup setup-templates edit run run-mission test validate export-web serve itch-zip screenshots clean

help: ## Hiện danh sách lệnh
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Tải Godot $(VERSION) + cấu hình VS Code làm editor ngoài
	@bash tools/setup.sh

setup-templates: ## Tải thêm export templates (cần để export Web ở máy)
	@bash tools/setup.sh --templates

assets: ## Tải asset CC0 (Kenney) + sinh atlas/quái ghép + dựng TileSet (cần Python + Pillow)
	@python3 tools/import_assets.py
	@$(GODOT) --headless --import >/dev/null 2>&1 || true
	@$(GODOT) --headless --script res://tools/build_tileset.gd
	@$(GODOT) --headless --import >/dev/null 2>&1 || true

edit: ## Mở Godot editor
	@$(GODOT) --editor &

run: ## Chạy game
	@$(GODOT)

run-mission: ## Chạy thẳng một màn action (debug)
	@$(GODOT) res://scenes/mission/mission_level.tscn

test: ## Chạy toàn bộ test headless (nội dung, save, gameplay, màn action, UI)
	@mkdir -p build
	@$(GODOT) --headless --import >/dev/null 2>&1 || true
	@$(GODOT) --headless res://tests/test_runner.tscn 2>&1 | tee build/test.log; test $${PIPESTATUS[0]:-0} -eq 0
	@if grep -q "SCRIPT ERROR" build/test.log; then echo "✘ Có SCRIPT ERROR trong lúc chạy test (xem build/test.log)"; exit 1; fi

validate: test ## Alias của test (kiểm tra nội dung JSON)

export-web: ## Export bản Web vào build/web
	@mkdir -p build/web && touch build/.gdignore && rm -f build/web/*.import
	@$(GODOT) --headless --import >/dev/null 2>&1 || true
	@$(GODOT) --headless --export-release "Web" build/web/index.html
	@touch build/web/.nojekyll
	@python3 tools/cache_bust.py build/web
	@echo "✓ build/web sẵn sàng. Chạy thử: make serve"

serve: ## Chạy server tĩnh cho build/web tại http://localhost:$(PORT)
	@cd build/web && python3 -m http.server $(PORT)

itch-zip: export-web ## Đóng gói build/web thành zip để upload lên itch.io
	@cd build/web && rm -f ../au-co-web.zip && zip -qr ../au-co-web.zip . -x ".nojekyll"
	@echo "✓ build/au-co-web.zip"

screenshots: ## Chụp ảnh các màn hình chính vào build/shots (mở cửa sổ vài giây)
	@for s in title/title hub/hub mission/mission_level; do \
		$(GODOT) res://tools/screenshot.tscn -- --scene=res://scenes/$$s.tscn --out=build/shots/$$(basename $$s).png; \
	done

clean: ## Xóa build và cache import
	rm -rf build .godot
