# Hướng dẫn modding

Toàn bộ nội dung game là JSON trong `data/`. Mod là một thư mục có **cùng cấu trúc** đặt ở:

| Nền tảng | Thư mục mod |
|---|---|
| Mọi nền tảng | Thư mục `mods/` bên trong thư mục dữ liệu người dùng — trong Godot editor: **Project → Open User Data Folder** |

Ví dụ `mods/them-sung/items/my_weapons.json`. Entry trùng `id` với nội dung gốc sẽ **ghi đè** nó; `id` mới sẽ được **thêm vào**. Khi game khởi động, mọi lỗi tham chiếu được báo ở màn hình tiêu đề.

## Danh mục

`config, chapters, characters, events, dialogues, items, endings, skills, tech, locations, missions, levels, enemies, abilities, loot, recipes, resource_nodes`

Mỗi file (trừ `config`) là một **mảng object có `id`**.

## Điều kiện (`conditions`) — dùng trong sự kiện, lựa chọn, nhiệm vụ

```json
{ "year_min": 5, "year_max": 20, "generation": 1, "chance": 0.5,
  "flags_all": ["a"], "flags_none": ["b"],
  "stats_min": { "food": 30 }, "stats_max": { "morale": 80 },
  "items_all": ["linh_kien_du_phong"], "characters_alive": ["khang"],
  "characters_missing": ["huy"], "tech_all": ["deep_scanner"], "locations_known": ["loc_comet"] }
```

## Hiệu ứng (`effects`, `success`, `failure`, `result` của công thức)

```json
{ "stats": { "food": -10 }, "flags_set": ["x"], "flags_clear": ["y"],
  "items_add": { "medkit": 2 }, "items_remove": { "kim_loai": 1 },
  "characters_add": ["an"], "characters_remove": ["khang"],
  "research_points": 10, "techs_unlock": ["eva_suits"],
  "locations_discover": ["loc_derelict"], "discover_random_location": true,
  "loot": "lt_crate", "log": "Dòng ghi vào nhật ký", "next_event": "ev_khac" }
```

## Ví dụ: thêm một vũ khí và công thức chế tạo

`mods/sung-moi/items/weapons.json`
```json
[{ "id": "w_ion_lance", "category": "weapon", "name": "Giáo ion", "description": "Xuyên 5 mục tiêu.",
   "weapon": { "damage": 25, "fire_interval": 0.6, "projectile_speed": 1200, "pierce": 5, "range": 900, "color": "#9FE8FF" } }]
```
`mods/sung-moi/recipes/ion.json`
```json
[{ "id": "r_ion_lance", "name": "Giáo ion", "materials": { "tinh_the": 5, "kim_loai": 5 },
   "requires_tech": "weapon_lab", "result": { "items_add": { "w_ion_lance": 1 } } }]
```

## Ví dụ: boss mới

```json
{ "id": "boss_x", "name": "...", "boss": true, "hp": 800, "speed": 80, "damage": 20, "radius": 36,
  "loot": "lt_boss_warden", "summon": "crawler", "projectile_speed": 320,
  "phases": [ { "hp_above": 0.5, "patterns": ["aimed_burst", "radial"], "interval": 1.5 },
              { "hp_above": 0.0, "patterns": ["charge", "summon", "radial"], "interval": 1.0 } ] }
```
Đòn đánh có sẵn: `aimed_burst`, `radial`, `charge`, `summon`. Dùng boss trong nhiệm vụ: `"objective": { "type": "boss", "boss": "boss_x", "label": "..." }`.

Loại mục tiêu nhiệm vụ: `collect` (nhặt N vật), `interact` (giữ E ở N điểm), `rescue` (đưa người mất tích về), `mine` (khai thác N nguyên liệu `item`), `boss`.

## Sprite & bản đồ

Đặt ảnh PNG vào thư mục `assets/` tương ứng rồi trỏ tên (không có đuôi) trong JSON. Tên sai sẽ bị báo lỗi lúc khởi động.

| Dữ liệu | Trường | File |
|---|---|---|
| `characters` | `sprite`, `tint` | `assets/characters/<sprite>_<pose>.png` (pose: gun, hold, machine, reload, silencer, stand) |
| `items` (vũ khí) | `weapon.pose`, `weapon.projectile`, `weapon.sound` | tư thế nhân vật, `assets/fx/<projectile>.png`, `assets/audio/<sound>.ogg` |
| `items` | `icon` (mặc định = id) | `assets/items/<icon>.png` |
| `enemies` | `sprite`, `sprite_scale`, `tint`, `projectile` | `assets/enemies/<sprite>.png` (mặt hướng sang phải) |
| `resource_nodes` | `sprite`, `sprite_scale`, `radius` | `assets/props/<sprite>.png` |
| `levels` | `tileset` (ship/derelict/debris/comet/moon), `ambient`, `lamp_color`, `lamps`, `decor` | `decor`: `{tên prop: số lượng}` trong `assets/props/` |

## Vai trò, công cụ, nhiệm vụ

- `roles/*.json`: `{id, name, color, modifiers: {chỉ_số: +n}, weapon_types: [...], tool_types: [...], abilities: [...], default_weapon, default_tool}`.
- Nhân vật: `"role": "<id vai trò>"`, `"title"` là chức danh hiển thị.
- Vũ khí: `weapon.type` (pistol, rifle, smg, shotgun, sniper, heavy...). Công cụ: `"category": "tool"`, `tool: {type: drill|repair|turret|med|scanner, power, range}`.
- Kỹ năng (`abilities`): `type` ∈ heal, heal_allies, aoe, buff, slow_enemies, time_slow, turret, mining_blast, flare, scan.
- Nhiệm vụ: `team_size: [min, max]`, `time_limit` (giây), `recommended_roles: {vai: số}`, `tier` (cộng thêm độ khó).
- Bản đồ (`levels`): `grid`, `rooms`, `enemies`, `resource_nodes`, `caches` (tủ tiếp tế), `waves: {first, interval, enemies, growth}`.

## Dẫn truyện

- `dialogues/*.json`: `{id, bg: "<tên nền>", lines: [{speaker: "<id nhân vật>" | "" (lời dẫn), text, side?: "left"|"right", bg?: "<đổi nền>"}]}`.
- `events/*.json`: `dialogue` (đoạn hội thoại phát trước lựa chọn), `background`.
- `chapters`: `intro_dialogue`, `outro_dialogue`. `endings`: `background`.
- Nhân vật: `portrait` = tên file trong `assets/portraits/` (không có đuôi).
- Nền: `assets/backgrounds/<tên>.jpg` (1280×720). Có sẵn: corridor, bridge, hydroponics, alarm, medbay, deck7, derelict, space, jupiter, van_lang, moon, comet.

## Bản đồ ngoài trời

`levels[]`: `"layout": "terrain"` + `grid`, `rooms` (số điểm khám phá), `palette {ground, rough, forest, path, water, cliff}`,
`trees`, `rocks` (tên prop), `tree_density`, `terrain {height_freq, moisture_freq, river_freq, cliff, forest, river}`, `pack_size` (quái theo bầy).
`"layout": "interior"` = kiểu phòng/hành lang trong tàu.

## Nhân vật: thuộc tính, vai trò, tài năng, vòng đời

- `config.attributes`: 6 thuộc tính; `config.attribute_bonuses`: (thuộc tính − 30) × hệ số cộng vào chỉ số chiến đấu.
- `roles[].attribute_weights`: trọng số tính thành thạo (0..100); hiệu quả vai = 0.6 + thành thạo/100 × 0.8.
  `assign_min`: thành thạo tối thiểu để chỉ huy giao vai; `auto_unlock`: tự mở vai khi vượt ngưỡng.
- Nhân vật: `attributes {…}`, `gender` (male/female), `role` (vai ban đầu), `child: true` (chưa có vai).
- `talents/*.json`: `{id, role, name, tier, cost, requires[], modifiers{}, attributes{}, grants_ability}`; `rare: true` = chỉ qua kỳ ngộ.
- `encounters/*.json`: `kind` = `coming_of_age` (kèm `role`, `talent`, `attributes`), `adult` (kỳ ngộ ngẫu nhiên trên tàu), `relic` (cổ vật trong màn); `lines` dùng `{name}`.
- `config.nutrition`: lương thực/năm theo tuổi, giới tính, vai. `config.lifecycle`: sinh con, tuổi trưởng thành, tỉ lệ kỳ ngộ, tăng trưởng.
- `config.growth`: hành động trong màn (kills, mined, worked, revived, healed, distance) -> thuộc tính. `levels[].relics`, `levels[].strangers`.
- Module có thể cộng thuộc tính: `items[].attributes`.
