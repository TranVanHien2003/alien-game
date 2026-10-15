# Thiết kế game — Âu Cơ: Con Tàu Thế Hệ

**Thể loại:** Action 2D top-down + quản lý tàu thế hệ có cốt truyện.
**Nền tảng:** Web (GitHub Pages / itch.io), desktop sau.
**Phạm vi bản đầu:** Chương I (25 năm, thế hệ 1) — phát hành itch.io để lấy phản hồi.

## Vòng lặp chính

```
 ┌──────────── HUB (tàu Âu Cơ) ─────────────┐
 │ Sự kiện cốt truyện → lựa chọn              │
 │ Nghiên cứu công nghệ · Chế tạo · Trang bị  │
 │ Huấn luyện kỹ năng công nghệ cao           │
 │ Chọn nhiệm vụ + đội + đội trưởng           │
 └──────┬──────────────────────────┬────────┘
        │ Đổ bộ (action)            │ Gửi tự động (tung xúc xắc theo kỹ năng)
        ▼                           ▼
 ┌──────────── MÀN ACTION ──────────┐   Kết quả sau N năm
 │ Đánh quái · Boss · Khai thác mỏ   │
 │ Vùng nguy hiểm · Mục tiêu         │
 │ Về tàu con thoi = mang đồ về      │
 └──────┬────────────────────────────┘
        ▼
 Loot / nguyên liệu / XP / mất tích → nhiệm vụ Giải cứu
        ▼
 Qua năm: tài nguyên tàu, dân số, tuổi tác, nghiên cứu, sự kiện mới
```

## Hệ thống & file dữ liệu

| Hệ thống | Code | Dữ liệu |
|---|---|---|
| Chỉ số tàu & mô phỏng năm | `systems/simulation.gd` | `config/game.json` (stats, yearly, shortages, failures) |
| Sự kiện & hội thoại | `systems/event_rules.gd`, `event_picker.gd` | `events/`, `dialogues/` |
| Phi hành đoàn, kỹ năng, XP, mất tích | `systems/crew_system.gd` | `characters/`, `skills/` |
| Nghiên cứu | `systems/research_system.gd` | `tech/` |
| Nhiệm vụ & giải cứu | `systems/mission_system.gd` | `missions/`, `locations/` |
| Chỉ số chiến đấu | `systems/combat_stats.gd` | `config.combat_stats`, `config.skill_bonuses` |
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

## Điều khiển (màn action)

WASD di chuyển · chuột trái bắn · Shift/chuột phải lướt · 1/2/lăn chuột đổi vũ khí · Q/R kỹ năng · 3/4 vật phẩm · E tương tác · Esc tạm dừng.

## Lộ trình gợi ý

1. **v0.1 (hiện tại):** Chương I chơi được từ đầu đến cuối, bằng hình khối neon.
2. **v0.2:** Âm thanh (sfxr), hiệu ứng (glow, particle, rung màn hình), cân bằng số liệu, AI quái tìm đường (NavigationAgent2D).
3. **v0.3:** Hub đi lại được trong tàu, thêm quái/boss/vũ khí, chương II.
4. **Phát hành itch.io** → thu phản hồi → mở rộng.
