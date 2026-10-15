# Thiết kế game — Âu Cơ: Con Tàu Thế Hệ

**Thể loại:** Action 2D top-down + quản lý tàu thế hệ có cốt truyện.
**Nền tảng:** Web (GitHub Pages / itch.io), desktop sau.
**Phạm vi bản đầu:** Chương I (25 năm, thế hệ 1) — phát hành itch.io để lấy phản hồi.

## Vòng lặp chính

Người chơi là **chỉ huy** của tàu Âu Cơ. Không trực tiếp cầm súng — mà chọn đội, trang bị theo vai trò và ra lệnh cho từng người trên bản đồ khai phá.

```
 ┌──────────────── HUB (tàu Âu Cơ) ────────────────┐
 │ Sự kiện cốt truyện · Nghiên cứu · Chế tạo         │
 │ Trang bị từng thành viên theo vai trò              │
 │ Chọn nhiệm vụ: độ khó ★, thời gian, vai đề cử ✔/✘ │
 └──────┬───────────────────────────────┬──────────┘
        │ Đổ bộ (chỉ huy trên bản đồ)    │ Gửi tự động (tung xúc xắc)
        ▼                                ▼
 ┌──────────── MÀN KHAI PHÁ (2–6 người) ────────────┐
 │ Khám phá bản đồ lớn trong bóng tối                 │
 │ Chiến đấu: quái tại chỗ + đợt quái mạnh dần        │
 │ Khai thác: thợ mỏ khoan, người khác bắn mỏ         │
 │ Tủ tiếp tế, mục tiêu, boss                         │
 │ ⏱ Hết giờ -> buộc rút lui về tàu con thoi          │
 └──────┬─────────────────────────────────────────────┘
        ▼
 Về tàu: loot, nguyên liệu, XP, điểm nghiên cứu · Bỏ lại: mất tích -> Giải cứu
```

## Nhân vật

- **Thuộc tính** (Sức mạnh, Nhanh nhẹn, Trí tuệ, Bền bỉ, Tinh mắt, Ý chí) quyết định độ **thành thạo** từng vai -> hiệu quả ×0.6..×1.4.
- Một người có **nhiều vai** (tự mở khi đủ giỏi hoặc chỉ huy giao), chọn 1 vai chính khi ra trận.
- Tăng trưởng: huấn luyện theo năm · hành động trong màn · cây tài năng (XP -> cấp -> điểm) · trang bị · **kỳ ngộ** (cổ vật trong màn, sự kiện ngẫu nhiên).
- **Lương thực**: mỗi người ăn khác nhau theo tuổi, giới tính, vai; đói làm giảm sức chiến đấu và dừng huấn luyện.
- **Vòng đời**: trẻ sinh ra trên tàu thừa hưởng thuộc tính cha mẹ, lớn dần; 16 tuổi chọn vai trong Lễ trưởng thành — đôi khi gặp kỳ ngộ cho tài năng hiếm.
- **Giải cứu trong màn**: người mất tích được tìm thấy gia nhập đội ngay trên bản đồ; người sống sót lạ có thể được thu nhận sau màn.

## Tự động chơi màn

- Mỗi thành viên có nút AUTO (mặc định bật). AI chỉ biết những gì đội **đã nhìn thấy**, chọn việc theo ưu tiên vai trò
  (chiến binh săn quái/hộ tống, thợ mỏ khai thác, kỹ sư làm trạm/tủ/cổ vật, y sĩ cứu & theo người bị thương,
  trinh sát thăm dò/đón người, nhà khoa học cổ vật/trạm), tự dùng kỹ năng, tự lùi khi yếu, tự rút khi xong mục tiêu.
- Trí tuệ + Tinh mắt + thành thạo -> phản ứng nhanh & chọn việc chuẩn; màn càng khó AI càng chậm, dễ sai.
- Lệnh tay của chỉ huy được ưu tiên làm xong trước (★), người khác vẫn tự động; "Dừng" giữ yên 8 giây.

## Vai trò

| Vai | Điểm mạnh | Vũ khí | Công cụ | Kỹ năng |
|---|---|---|---|---|
| Chiến binh | +40 máu, +10 giáp, +15% sát thương | súng ngắn, trường, tán xạ, súng máy | — | Lựu đạn, Áp chế |
| Kỹ sư | tương tác ×2 | súng ngắn, tiểu liên | sửa chữa, tháp pháo | Dựng tháp pháo, Quá tải |
| Thợ mỏ | +150% khai thác, hút đồ xa | súng ngắn, tán xạ | máy khoan | Mìn địa chấn |
| Y sĩ | hồi máu ×2, cứu nhanh | súng ngắn, tiểu liên | tia hồi phục (tự động) | Xung hồi phục, Sơ cứu |
| Trinh sát | +60 tốc độ, tầm nhìn xa, chí mạng | súng ngắn, tiểu liên, bắn tỉa | máy quét | Pháo sáng, Chạy nước rút |
| Nhà khoa học | năng lượng lớn | súng ngắn | máy quét, tia hồi phục | Quét địa hình, Pheromone |

## Độ khó (đồng đều cho mọi màn)

`độ khó = 1 + khoảng_cách × 0.6 + năm × 0.06 + số_lần_đã_làm × 0.25 + tier`

Mỗi điểm độ khó: +18% máu quái, +12% sát thương, +20% số quái, +25% quái mỗi đợt, +12% phần thưởng (mỏ, tủ, loot). Hệ số ở `config.difficulty`.

## Hệ thống & file dữ liệu

| Hệ thống | Code | Dữ liệu |
|---|---|---|
| Chỉ số tàu & mô phỏng năm | `systems/simulation.gd` | `config/game.json` (stats, yearly, shortages, failures) |
| Sự kiện & hội thoại | `systems/event_rules.gd`, `event_picker.gd` | `events/`, `dialogues/` |
| Phi hành đoàn, kỹ năng, XP, mất tích | `systems/crew_system.gd` | `characters/`, `skills/` |
| Nghiên cứu | `systems/research_system.gd` | `tech/` |
| Nhiệm vụ & giải cứu | `systems/mission_system.gd` | `missions/`, `locations/` |
| Chỉ số chiến đấu | `systems/combat_stats.gd` | `config.combat_stats`, `config.skill_bonuses`, `roles[].modifiers` |
| Vai trò | `systems/roles.gd` | `roles/` |
| Độ khó | `systems/difficulty.gd` | `config.difficulty`, `missions[].tier` |
| Đội trên bản đồ | `actors/unit.gd`, `mission/squad_controller.gd` | `config.squad` |
| Vũ khí, module, vật phẩm | `systems/inventory.gd` | `items/` (category: weapon/module/consumable/material/key) |
| Kỹ năng chủ động | `systems/abilities.gd`, `actors/player.gd` | `abilities/` |
| Loot (quái, boss, mỏ, nhiệm vụ, sự kiện) | `systems/loot.gd` | `loot/` |
| Chế tạo | `systems/crafting.gd` | `recipes/` |
| Quái & boss | `actors/enemy.gd` | `enemies/` (boss có `phases`) |
| Bản đồ thủ tục | `mission/level_generator.gd` | `levels/` |
| Mỏ tài nguyên | `actors/resource_node.gd` | `resource_nodes/` |

## Chỉ số chiến đấu

`max_hp, armor, damage_mult, crit_chance, crit_mult, fire_rate_mult, move_speed, max_energy, energy_regen, mining_power, pickup_radius, dash_cooldown`

Nguồn cộng dồn: base → kỹ năng đội trưởng (100%) → kỹ năng thành viên khác (25%) → module → công nghệ → buff tạm thời (thuốc, kỹ năng).
Giáp giảm sát thương theo `100 / (100 + giáp)`.

## Nguồn vật phẩm

| Nguồn | Ví dụ |
|---|---|
| Quái thường | `lt_crawler`, `lt_sentinel` |
| Boss | `lt_boss_warden` (luôn rơi Súng trường ray) |
| Khai thác mỏ | quặng → kim loại, băng → lõi băng, tinh thể, túi sinh học |
| Thùng hàng | `lt_crate` (có tỉ lệ ra module) |
| Thưởng nhiệm vụ | `success.loot`, `success.items_add` |
| Sự kiện cốt truyện | `effects.items_add` / `effects.loot` |
| Chế tạo | `recipes/` |
| Khởi đầu chương | `chapters[].starting_items` |

## Nhịp độ màn khai phá

- Bản đồ ngoài trời lớn (150–160 × 100–110 ô), camera nhìn xa kiểu bàn cờ chiến thuật, có zoom và minimap.
- Quái đứng theo bầy ở các điểm khám phá, đợt quái đầu sau 2,5 phút và cách nhau 2 phút.
- Thời gian màn 8–17 phút; có thể chạy ×½ để chỉ huy kỹ hoặc ×2 khi di chuyển đường dài.

## Phong cách hình ảnh

- Top-down 2.5D phẳng kiểu Kenney: nhân vật nhìn từ trên đầu, hướng mặt theo tầm ngắm.
- Mỗi biome có bảng màu riêng (viền tường, ánh sáng môi trường, màu đèn) để người chơi nhận ra ngay mình đang ở đâu.
- Ánh sáng là gameplay: phòng xa tối, đèn pin chỉ chiếu phía trước — quái có thể ẩn trong bóng tối.
- Hiệu ứng (đạn, nổ, chớp nòng) dùng vật liệu "unshaded + add" để luôn sáng rực.

## Điều khiển (màn khai phá)

- Chuột trái: chọn / kéo khung (Shift thêm) · 1–6 chọn từng người · Ctrl+A cả đội · bấm thẻ thành viên ở HUD.
- Chuột phải: lệnh theo ngữ cảnh — sàn: di chuyển theo đội hình · quái: tấn công · mỏ: khai thác · trạm/tủ: tương tác · đồng đội gục: cứu.
- Q/E/R: kỹ năng của người được chọn đầu tiên (nhắm theo con trỏ) · Z/X: vật phẩm nhanh.
- H dừng · G giữ vị trí · B rút lui · Space về camera · WASD / mép màn hình / lăn chuột: camera · minimap bấm để nhảy.

## Lộ trình gợi ý

1. **v0.1 (hiện tại):** Chương I chơi được từ đầu đến cuối, bằng hình khối neon.
2. **v0.2:** Âm thanh (sfxr), hiệu ứng (glow, particle, rung màn hình), cân bằng số liệu, AI quái tìm đường (NavigationAgent2D).
3. **v0.3:** Hub đi lại được trong tàu, thêm quái/boss/vũ khí, chương II.
4. **Phát hành itch.io** → thu phản hồi → mở rộng.
