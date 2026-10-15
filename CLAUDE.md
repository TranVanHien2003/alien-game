# Ghi chú cho AI / người đóng góp

- Godot 4.7.2 (xem `.godot-version`), GDScript, renderer Compatibility, export Web không thread.
- Chạy test: `make test` (headless, scene `tests/test_runner.tscn`; mọi file `tests/test_*.gd`, hàm `test_*(t)`). Luôn chạy sau khi sửa code hoặc data.
- Nội dung nằm trong `data/*/*.json`. Thêm khóa mới cho điều kiện/hiệu ứng → sửa `scripts/systems/event_rules.gd`, thêm kiểm tra vào `Content.validate()` (`scripts/autoload/content_db.gd`) và cập nhật `MODDING.md`.
- Đổi cấu trúc dữ liệu save (`Game.to_dict`) → tăng `SaveManager.SAVE_VERSION`, thêm migration và test trong `tests/test_save.gd`.
- Hệ thống trong `scripts/systems/` là static, nhận `game` (autoload `Game`) làm tham số — giữ chúng không phụ thuộc scene để test được.
- Biến có giá trị lấy từ `game.xxx` (kiểu Node không định kiểu) phải khai báo kiểu tường minh (`var x: float = ...`), không dùng `:=`.
- UI hub và HUD được dựng bằng code (`scripts/ui/ui.gd` có helper).
- Lore và bí mật: `design/story_bible.md`. Thiết kế: `design/game_design.md`.
- Văn bản trong game bằng tiếng Việt.
- Asset: `make assets` = `tools/import_assets.py` (tải Kenney CC0, chọn file, sinh atlas tường/quái ghép/ánh sáng) + `tools/build_tileset.gd` (dựng `assets/tiles/world_tileset.tres`). Asset sinh ra được commit; `build/asset_cache` thì không.
- Bit lân cận autotile trong `import_assets.py` và `scripts/mission/level_map.gd` phải khớp nhau (test `test_autotile_covers_all_masks`).
- Xem nhanh hình ảnh: `tools/godot.sh res://tools/screenshot.tscn -- --scene=res://scenes/mission/mission_level.tscn --mission=msn_derelict --out=build/shots/x.png` (mở cửa sổ vài giây).
