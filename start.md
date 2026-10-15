# Hướng dẫn làm game Godot 4, code bằng VS Code, deploy miễn phí lên GitHub Pages

Tài liệu này hướng dẫn từ đầu đến cuối cách làm một game 2D đơn giản theo đúng mô hình của [Neon Harbor](https://quzkhanh.github.io/neon-harbor-web/): game làm bằng **Godot 4**, export ra **Web (HTML5 + WebAssembly)** và chạy trên **GitHub Pages**. Khác với Neon Harbor (repo chỉ chứa bản build), hướng dẫn này lưu **cả source code lẫn bản build** trên GitHub.

---

## Mục lục

1. [Phân tích cách Neon Harbor được làm](#1-phân-tích-cách-neon-harbor-được-làm)
2. [Chuẩn bị công cụ](#2-chuẩn-bị-công-cụ)
3. [Kết nối Godot với VS Code](#3-kết-nối-godot-với-vs-code)
4. [Tạo project và cấu trúc thư mục](#4-tạo-project-và-cấu-trúc-thư-mục)
5. [Thiết lập Git và GitHub](#5-thiết-lập-git-và-github)
6. [Game mẫu: Breakout neon](#6-game-mẫu-breakout-neon)
7. [Export ra Web](#7-export-ra-web)
8. [Deploy lên GitHub Pages](#8-deploy-lên-github-pages)
9. [Tự động deploy bằng GitHub Actions (tùy chọn)](#9-tự-động-deploy-bằng-github-actions-tùy-chọn)
10. [Ý tưởng game tiếp theo](#10-ý-tưởng-game-tiếp-theo)
11. [Xử lý lỗi thường gặp](#11-xử-lý-lỗi-thường-gặp)
12. [Checklist tổng](#12-checklist-tổng)
13. [Tài nguyên hữu ích](#13-tài-nguyên-hữu-ích)

---

## 1. Phân tích cách Neon Harbor được làm

Đọc file `index.html` trong repo `quzkhanh/neon-harbor-web` có thể thấy:

| Dấu hiệu | Ý nghĩa |
|---|---|
| `const engine = new Engine(GODOT_CONFIG);` | Đây là bản export Web của **Godot 4** |
| `index.wasm` (~39 MB) và `index.pck` (~3 MB) | `.wasm` là engine Godot, `.pck` chứa scene, script, hình ảnh, âm thanh của game |
| `GODOT_THREADS_ENABLED = false` | Export với **Thread Support tắt** để chạy được trên GitHub Pages |
| File `.nojekyll` ở gốc repo | Tắt Jekyll để GitHub Pages phục vụ nguyên trạng các file build |
| Không có `project.godot` hay file `.gd` | Repo chỉ chứa bản build, source được giữ ở nơi khác |

**Vì sao phải tắt Thread Support?** Bản export có thread cần trình duyệt bật `SharedArrayBuffer`, điều này đòi hỏi server gửi header `Cross-Origin-Opener-Policy` và `Cross-Origin-Embedder-Policy`. GitHub Pages không cho cấu hình header, nên cách đơn giản nhất là export bản single-threaded (hỗ trợ từ Godot 4.3 trở lên).

---

## 2. Chuẩn bị công cụ

| Công cụ | Ghi chú |
|---|---|
| **Godot 4.x Standard** (4.3 trở lên) | Tải tại https://godotengine.org/download. Chọn bản **Standard** (GDScript). Bản .NET/C# hiện chưa export Web được. |
| **Export Templates** | Trong Godot: `Editor → Manage Export Templates → Download and Install`. Phải cùng phiên bản với editor. |
| **VS Code** | https://code.visualstudio.com |
| **Git** | https://git-scm.com |
| **Tài khoản GitHub** | https://github.com |

> Godot là file chạy trực tiếp, không cần cài đặt. Nên đặt vào một thư mục cố định (ví dụ `C:\Tools\Godot\` hoặc `~/Applications/`) để VS Code trỏ tới được.

---

## 3. Kết nối Godot với VS Code

### 3.1. Cài extension

Trong VS Code, mở tab Extensions và cài **godot-tools** (tác giả: Godot Engine). Extension này cung cấp tô màu cú pháp, autocomplete, đi tới định nghĩa và debug GDScript.

### 3.2. Cấu hình Godot dùng VS Code làm editor ngoài

Trong Godot: `Editor → Editor Settings → Text Editor → External`

- Bật **Use External Editor**
- **Exec Path**: đường dẫn tới VS Code
  - Windows: `C:\Users\<tên>\AppData\Local\Programs\Microsoft VS Code\Code.exe`
  - macOS: `/Applications/Visual Studio Code.app/Contents/MacOS/Electron`
  - Linux: `/usr/bin/code`
- **Exec Flags**: `{project} --goto {file}:{line}:{col}`

Từ giờ, double-click vào script trong Godot sẽ mở thẳng VS Code.

### 3.3. Cấu hình VS Code biết Godot ở đâu

Trong VS Code, mở Settings, tìm `godotTools.editorPath.godot4` và điền đường dẫn tới file Godot. Khi Godot editor đang mở project, extension sẽ kết nối qua Language Server (cổng mặc định 6005) để có autocomplete.

### 3.4. Workflow hằng ngày

- **Godot editor**: dựng scene, kéo thả node, chỉnh hình, collision, animation.
- **VS Code**: viết và sửa toàn bộ GDScript, quản lý Git.
- Nhấn **F5** trong Godot để chạy thử game.

---

## 4. Tạo project và cấu trúc thư mục

### 4.1. Tạo project

Mở Godot → **New Project**, đặt tên (ví dụ `neon-breakout`), chọn thư mục.

**Quan trọng:** ở mục **Renderer**, chọn **Compatibility**. Bản Web của Godot 4 chạy trên WebGL 2, chỉ hỗ trợ renderer Compatibility. Nếu đã tạo project với Forward+, đổi lại tại `Project → Project Settings → Rendering → Renderer`.

### 4.2. Cấu trúc thư mục đề xuất

```
neon-breakout/
├── .github/
│   └── workflows/
│       └── deploy.yml        # (tùy chọn) tự động build & deploy
├── assets/
│   ├── sprites/
│   ├── sounds/
│   └── fonts/
├── scenes/
│   ├── main.tscn
│   ├── paddle.tscn
│   ├── ball.tscn
│   └── brick.tscn
├── scripts/
│   ├── main.gd
│   ├── paddle.gd
│   ├── ball.gd
│   └── brick.gd
├── docs/                     # bản build Web (nếu deploy thủ công)
│   ├── index.html
│   ├── index.js
│   ├── index.wasm
│   ├── index.pck
│   └── .nojekyll
├── .gitignore
├── export_presets.cfg        # cấu hình export, NÊN commit
├── icon.svg
├── project.godot
└── README.md
```

> Đặt tên file và thư mục bằng **chữ thường, không dấu, không khoảng trắng**. Máy Windows không phân biệt hoa thường nhưng web server thì có, sai một chữ là game lỗi khi deploy.

### 4.3. Cài đặt màn hình cho web

`Project → Project Settings → Display → Window`:

- **Viewport Width / Height**: ví dụ `1280 × 720`
- **Stretch → Mode**: `canvas_items`
- **Stretch → Aspect**: `keep`

Như vậy game tự co giãn theo cửa sổ trình duyệt mà không bị méo.

---

## 5. Thiết lập Git và GitHub

### 5.1. File `.gitignore`

Tạo file `.gitignore` ở gốc project:

```gitignore
# Thư mục cache của Godot 4 (tự sinh lại được)
.godot/

# Build tạm (nếu dùng GitHub Actions thì không commit build)
build/

# File hệ điều hành
.DS_Store
Thumbs.db

# VS Code (giữ lại nếu muốn chia sẻ cấu hình)
.vscode/*
!.vscode/settings.json
```

> Không cho `docs/` vào `.gitignore` nếu bạn dùng cách deploy thủ công ở mục 8. Nếu dùng GitHub Actions (mục 9) thì không cần thư mục `docs/`.

### 5.2. Đưa project lên GitHub

Tạo repo mới trên GitHub (ví dụ `neon-breakout`, để **Public** vì GitHub Pages miễn phí yêu cầu repo public với tài khoản Free). Sau đó trong terminal của VS Code:

```bash
git init
git add .
git commit -m "Khởi tạo project Godot"
git branch -M main
git remote add origin https://github.com/<username>/neon-breakout.git
git push -u origin main
```

---

## 6. Game mẫu: Breakout neon

Một game Breakout tối giản để làm quen toàn bộ quy trình. Chưa cần hình ảnh: dùng node `ColorRect` làm hình chữ nhật màu neon.

### 6.1. Scene `paddle.tscn`

```
Paddle (CharacterBody2D)        ← gắn scripts/paddle.gd
├── ColorRect                   size 120×20, position (-60, -10), màu #00E5FF
└── CollisionShape2D            RectangleShape2D size 120×20
```

Trong Inspector của `Paddle`, đặt **Motion Mode = Floating**.

`scripts/paddle.gd`:

```gdscript
extends CharacterBody2D

@export var speed := 600.0
@export var half_width := 60.0

func _physics_process(_delta: float) -> void:
	var dir := Input.get_axis("ui_left", "ui_right")
	velocity = Vector2(dir * speed, 0)
	move_and_slide()

	var screen_w := get_viewport_rect().size.x
	position.x = clamp(position.x, half_width, screen_w - half_width)
```

### 6.2. Scene `ball.tscn`

```
Ball (CharacterBody2D)          ← gắn scripts/ball.gd
├── ColorRect                   size 16×16, position (-8, -8), màu #FF2BD6
└── CollisionShape2D            CircleShape2D radius 8
```

`scripts/ball.gd`:

```gdscript
extends CharacterBody2D

signal ball_lost

@export var speed := 400.0
@export var speed_step := 10.0

var dir := Vector2(0.5, -1).normalized()

func _physics_process(delta: float) -> void:
	var collision := move_and_collide(dir * speed * delta)
	if collision:
		dir = dir.bounce(collision.get_normal())
		var other = collision.get_collider()
		if other.is_in_group("bricks"):
			other.queue_free()
			speed += speed_step

	# Rơi khỏi đáy màn hình là thua
	if position.y > get_viewport_rect().size.y + 20:
		ball_lost.emit()
		queue_free()
```

### 6.3. Scene `brick.tscn`

```
Brick (StaticBody2D)            ← gắn scripts/brick.gd
├── ColorRect                   size 80×24, position (-40, -12), màu #B4FF39
└── CollisionShape2D            RectangleShape2D size 80×24
```

`scripts/brick.gd`:

```gdscript
extends StaticBody2D

func _ready() -> void:
	add_to_group("bricks")
```

### 6.4. Scene `main.tscn`

```
Main (Node2D)                   ← gắn scripts/main.gd
├── Background (ColorRect)      full màn hình, màu #0D0F19
├── Walls (StaticBody2D)
│   ├── Left  (CollisionShape2D)   tường trái
│   ├── Right (CollisionShape2D)   tường phải
│   └── Top   (CollisionShape2D)   tường trên
├── Paddle (instance paddle.tscn)  position (640, 680)
└── Ball   (instance ball.tscn)    position (640, 600)
```

Ba bức tường dùng `RectangleShape2D` mỏng đặt sát mép màn hình (không làm tường dưới, vì bóng rơi xuống là thua).

`scripts/main.gd`:

```gdscript
extends Node2D

const BRICK := preload("res://scenes/brick.tscn")

@export var rows := 5
@export var cols := 12

func _ready() -> void:
	_spawn_bricks()
	$Ball.ball_lost.connect(_on_ball_lost)

func _spawn_bricks() -> void:
	var start := Vector2(100, 80)
	var gap := Vector2(98, 36)
	for row in rows:
		for col in cols:
			var brick := BRICK.instantiate()
			brick.position = start + Vector2(col * gap.x, row * gap.y)
			add_child(brick)

func _process(_delta: float) -> void:
	if get_tree().get_nodes_in_group("bricks").is_empty():
		print("Thắng!")
		get_tree().reload_current_scene()

func _on_ball_lost() -> void:
	get_tree().reload_current_scene()
```

Đặt `main.tscn` làm scene chính: `Project → Project Settings → Application → Run → Main Scene`.

### 6.5. Thêm cảm giác "neon"

Khi game đã chạy được, thử thêm:

- **Glow**: thêm node `WorldEnvironment`, tạo `Environment`, đặt **Background Mode = Canvas** và bật **Glow**. Sau đó cho màu các `ColorRect` vượt quá 1.0 (ví dụ `Color(0, 2.5, 3)`, bật chế độ HDR trong color picker) để chúng phát sáng. Kiểm tra trên bản Web vì mức hỗ trợ hiệu ứng của renderer Compatibility có thể khác bản desktop.
- **Particle**: `CPUParticles2D` khi gạch vỡ (dùng CPU particles để tương thích web tốt hơn).
- **Screen shake**: rung `Camera2D` một chút mỗi lần bóng chạm gạch.
- **Âm thanh**: `AudioStreamPlayer` với tiếng "bíp" ngắn. Lưu ý trình duyệt chỉ cho phát âm thanh sau khi người chơi tương tác (click/nhấn phím) lần đầu.

---

## 7. Export ra Web

### 7.1. Tạo export preset

`Project → Export… → Add… → Web`

| Tùy chọn | Giá trị |
|---|---|
| **Variant → Thread Support** | **Tắt** (bắt buộc cho GitHub Pages) |
| **Variant → Extensions Support** | Tắt |
| **HTML → Canvas Resize Policy** | Adaptive |
| **HTML → Focus Canvas on Start** | Bật |
| **Progressive Web App → Enabled** | Tắt (bật sau nếu muốn) |
| **Export Path** | `docs/index.html` |

Tên file **phải là `index.html`** để GitHub Pages tự mở khi vào link.

### 7.2. Export

Nhấn **Export Project**, bỏ chọn **Export With Debug** cho bản phát hành. Godot sẽ sinh ra trong `docs/`:

```
index.html  index.js  index.wasm  index.pck  index.png  index.icon.png  index.apple-touch-icon.png  index.audio.worklet.js
```

Tạo thêm file rỗng `docs/.nojekyll`:

```bash
# macOS / Linux / Git Bash
touch docs/.nojekyll

# Windows PowerShell
New-Item docs/.nojekyll -ItemType File
```

### 7.3. Chạy thử trên máy

Không mở `index.html` bằng double-click được (trình duyệt chặn tải `.wasm` từ `file://`). Có hai cách:

- Trong Godot, nhấn nút **Remote Debug / Run in Browser** (biểu tượng HTML5 ở góc trên bên phải).
- Hoặc chạy server tĩnh:

```bash
cd docs
python -m http.server 8000
# mở http://localhost:8000
```

---

## 8. Deploy lên GitHub Pages

Cách thủ công, giống Neon Harbor nhưng giữ cả source:

```bash
git add docs/ .
git commit -m "Build web bản đầu tiên"
git push
```

Trên GitHub, vào repo → **Settings → Pages**:

- **Source**: `Deploy from a branch`
- **Branch**: `main`, thư mục `/docs`
- Nhấn **Save**

Sau 1–2 phút, game có tại:

```
https://<username>.github.io/neon-breakout/
```

Mỗi lần cập nhật: sửa game → export lại vào `docs/` → commit → push.

---

## 9. Tự động deploy bằng GitHub Actions (tùy chọn)

Khi đã quen, bạn có thể để GitHub tự export và deploy mỗi lần push, không cần commit thư mục build.

**Bước 1:** Đảm bảo `export_presets.cfg` đã được commit và preset Web tên chính xác là `Web`.

**Bước 2:** Trong **Settings → Pages**, đổi **Source** thành `GitHub Actions`.

**Bước 3:** Tạo file `.github/workflows/deploy.yml`:

```yaml
name: Build & Deploy Godot Web

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

env:
  # Đổi cho khớp đúng phiên bản Godot bạn đang dùng
  GODOT_VERSION: "4.3"

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Tải Godot và export templates
        run: |
          wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
          wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz
          unzip -q Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
          mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 godot
          mkdir -p ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable
          unzip -q Godot_v${GODOT_VERSION}-stable_export_templates.tpz
          mv templates/* ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable/

      - name: Export Web
        run: |
          mkdir -p build/web
          ./godot --headless --import || true
          ./godot --headless --export-release "Web" build/web/index.html
          touch build/web/.nojekyll

      - uses: actions/upload-pages-artifact@v3
        with:
          path: build/web

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

Từ giờ chỉ cần `git push`, xem tiến trình ở tab **Actions** của repo. Khi dùng cách này, có thể xóa thư mục `docs/` và thêm `build/` vào `.gitignore`.

> Nếu bước export báo lỗi không tìm thấy template, kiểm tra lại `GODOT_VERSION` có khớp chính xác tên release trên trang https://github.com/godotengine/godot/releases không (ví dụ `4.3`, `4.4.1`).

---

## 10. Ý tưởng game tiếp theo

Sau Breakout, đây là các ý tưởng tận dụng tốt Godot, xếp theo độ khó tăng dần:

| Ý tưởng | Mô tả | Học được gì |
|---|---|---|
| **Gravity Flip Runner** | Kiểu Flappy, nhấn phím để đảo trọng lực giữa trần và sàn | Input, spawn chướng ngại, điểm số |
| **Snake Roguelike** | Rắn săn mồi, đủ 10 mồi thì chọn 1 trong 3 nâng cấp | Grid, UI chọn nâng cấp, Resource |
| **Neon Shooter** | Bắn tàu vũ trụ màn hình tối, hiệu ứng glow và particle | Particle, shader đơn giản, âm thanh |
| **Typing Defense** | Từ rơi xuống, gõ đúng để bắn hạ (có thể dùng từ vựng tiếng Anh) | Xử lý bàn phím, Label, độ khó tăng dần |
| **Physics Puzzle** | Đặt vật thể để dẫn bóng vào đích | RigidBody2D, thiết kế level |
| **Survivor Mini** | Né đám đông quái, tự động tấn công, lên cấp chọn kỹ năng | Quản lý nhiều đối tượng, cân bằng game |

**Nguyên tắc chọn:** ưu tiên game hoàn thành được trong **1–2 tuần**. Làm bản "xấu nhưng chơi được" bằng hình khối trước, deploy ngay, rồi mới thêm đồ họa và âm thanh.

---

## 11. Xử lý lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| Thông báo cần `SharedArrayBuffer` / Cross-Origin Isolation | Export với Thread Support bật | Tắt **Thread Support** trong preset Web, export lại |
| Màn hình đen, console báo lỗi WebGL hoặc renderer | Project dùng Forward+ / Mobile | Đổi Renderer sang **Compatibility** |
| Trang GitHub Pages báo 404 | Chưa bật Pages, sai thư mục, hoặc file không tên `index.html` | Kiểm tra Settings → Pages và tên file |
| Game chạy trên máy nhưng lỗi khi deploy | Sai hoa/thường trong đường dẫn file | Đổi toàn bộ tên file sang chữ thường |
| Không có âm thanh | Trình duyệt chặn audio trước khi người dùng tương tác | Thêm màn hình "Nhấn để bắt đầu" |
| Mở `index.html` trực tiếp không chạy | Trình duyệt chặn `file://` | Dùng `python -m http.server` hoặc nút Run in Browser |
| Push bị GitHub từ chối vì file quá lớn | File vượt 100 MB | Nén/giảm asset; `index.wasm` (~40 MB) vẫn dưới giới hạn |
| Thay đổi không hiện sau khi deploy | Trình duyệt cache bản cũ | `Ctrl + Shift + R` hoặc mở tab ẩn danh |
| Phím bấm không ăn | Canvas chưa có focus | Bật **Focus Canvas on Start**, hoặc click vào game |

Mở **DevTools (F12) → Console** trên trình duyệt để xem lỗi chi tiết của bản Web.

---

## 12. Checklist tổng

**Thiết lập**
- [ ] Cài Godot 4.3+ bản Standard và Export Templates cùng phiên bản
- [ ] Cài VS Code + extension godot-tools, cấu hình External Editor
- [ ] Tạo project với renderer **Compatibility**
- [ ] Tạo `.gitignore`, push project lên repo GitHub public

**Phát triển**
- [ ] Dựng scene trong Godot, viết script trong VS Code
- [ ] Đặt Main Scene, cấu hình Stretch Mode cho web
- [ ] Chạy thử bằng F5 và bằng "Run in Browser"

**Phát hành**
- [ ] Preset Web: **Thread Support tắt**, xuất ra `index.html`
- [ ] Có file `.nojekyll` trong thư mục build
- [ ] Bật GitHub Pages (thư mục `/docs` hoặc GitHub Actions)
- [ ] Mở link `https://<username>.github.io/<repo>/` kiểm tra trên Chrome, Firefox và điện thoại
- [ ] Viết README có link chơi game và ảnh chụp màn hình

---

## 13. Tài nguyên hữu ích

- Tài liệu Godot (có bản tiếng Việt một phần): https://docs.godotengine.org
- Hướng dẫn export Web chính thức: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- Hướng dẫn "Your first 2D game" trong tài liệu Godot (rất nên làm theo trước)
- Asset miễn phí: https://kenney.nl và https://opengameart.org
- Âm thanh miễn phí: https://sfxr.me (tạo tiếng kiểu retro)
- Font miễn phí: https://fonts.google.com
- Đăng game cho cộng đồng: https://itch.io (upload chính thư mục build Web)

> Lưu ý: tên menu và tùy chọn có thể khác đôi chút giữa các phiên bản Godot 4.x. Nếu không tìm thấy một tùy chọn, hãy tra tài liệu đúng phiên bản bạn đang dùng.