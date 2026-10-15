#!/usr/bin/env python3
"""Pipeline asset: tải các gói CC0 của Kenney, chọn đúng file cần, chuẩn hóa tên, và sinh asset ghép.

    python3 tools/import_assets.py            # tải (có cache trong build/asset_cache) + sinh assets/
    python3 tools/import_assets.py --offline  # chỉ dùng cache đã tải

Kết quả (được commit vào repo để CI không cần tải lại):
    assets/characters/<id>_<pose>.png   nhân vật (nhìn từ trên xuống, hướng sang phải)
    assets/enemies/<id>.png             quái / boss (một số được ghép từ Monster Builder)
    assets/tiles/<biome>.png            atlas autotile 64px: hàng 0 = sàn, các hàng sau = 47 biến thể tường
    assets/props/*.png                  mỏ tài nguyên, trang trí, tàu con thoi
    assets/items/<item_id>.png          icon vật phẩm
    assets/fx/*.png                     đạn, hiệu ứng, mặt nạ ánh sáng
    assets/audio/*.ogg                  âm thanh
    assets/CREDITS.md                   nguồn + giấy phép
Cần Pillow (pip install pillow).
"""
import io
import json
import re
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "asset_cache"
OUT = ROOT / "assets"
TILE = 64

PACKS = {
    "top-down-shooter": "Topdown Shooter",
    "sci-fi-rts": "Sci-Fi RTS",
    "space-shooter-remastered": "Space Shooter Remastered",
    "tower-defense-top-down": "Tower Defense (Top-Down)",
    "generic-items": "Generic Items",
    "monster-builder-pack": "Monster Builder Pack",
    "particle-pack": "Particle Pack",
    "sci-fi-sounds": "Sci-Fi Sounds",
    "impact-sounds": "Impact Sounds",
}


# --- Tải ---------------------------------------------------------------------------

def pack_zip(slug: str, offline: bool) -> zipfile.ZipFile:
    path = CACHE / f"{slug}.zip"
    if not path.exists():
        if offline:
            sys.exit(f"Thiếu cache {path}. Chạy lại không có --offline.")
        page = urllib.request.urlopen(f"https://kenney.nl/assets/{slug}", timeout=30).read().decode("utf-8", "ignore")
        match = re.search(r'https://kenney\.nl/media/pages/assets/[^"]+\.zip', page)
        if not match:
            sys.exit(f"Không tìm thấy link tải cho {slug}")
        print(f"↓ {slug}")
        CACHE.mkdir(parents=True, exist_ok=True)
        path.write_bytes(urllib.request.urlopen(match.group(0), timeout=120).read())
    return zipfile.ZipFile(path)


class Packs:
    def __init__(self, offline: bool):
        self.zips = {slug: pack_zip(slug, offline) for slug in PACKS}

    def _find(self, slug: str, suffix: str) -> str:
        names = [n for n in self.zips[slug].namelist() if n.replace("\\", "/").endswith(suffix)]
        if not names:
            sys.exit(f"Không thấy '{suffix}' trong gói {slug}")
        return sorted(names, key=len)[0]

    def image(self, slug: str, suffix: str) -> Image.Image:
        with self.zips[slug].open(self._find(slug, suffix)) as f:
            return Image.open(io.BytesIO(f.read())).convert("RGBA")

    def raw(self, slug: str, suffix: str) -> bytes:
        with self.zips[slug].open(self._find(slug, suffix)) as f:
            return f.read()


def save(img: Image.Image, rel: str) -> None:
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)


# --- Nhân vật ----------------------------------------------------------------------

CHARACTERS = {
    # id sprite trong game -> thư mục/tiền tố trong gói Topdown Shooter
    "man_blue": ("Man Blue/manBlue", "Khang"),
    "man_brown": ("Man Brown/manBrown", "Bảo"),
    "man_old": ("Man Old/manOld", ""),
    "woman_green": ("Woman Green/womanGreen", "Thu Hà, Lan Anh, Mai"),
    "soldier": ("Soldier 1/soldier1", "Tuấn"),
    "hitman": ("Hitman 1/hitman1", "Huy"),
    "survivor": ("Survivor 1/survivor1", "An"),
    "robot": ("Robot 1/robot1", "LẠC, Người Gác"),
    "zombie": ("Zombie 1/zoimbie1", "người nhiễm nấm"),
}
POSES = ["gun", "hold", "machine", "reload", "silencer", "stand"]


def build_characters(p: Packs) -> None:
    for cid, (prefix, _) in CHARACTERS.items():
        for pose in POSES:
            save(p.image("top-down-shooter", f"PNG/{prefix}_{pose}.png"), f"characters/{cid}_{pose}.png")


# --- Quái / boss ---------------------------------------------------------------------

def paste_center(base: Image.Image, part: Image.Image, dx: int, dy: int, scale: float = 1.0, angle: float = 0.0) -> None:
    if scale != 1.0:
        part = part.resize((max(1, int(part.width * scale)), max(1, int(part.height * scale))), Image.LANCZOS)
    if angle:
        part = part.rotate(angle, expand=True, resample=Image.BICUBIC)
    x = base.width // 2 + dx - part.width // 2
    y = base.height // 2 + dy - part.height // 2
    base.alpha_composite(part, (x, y))


def monster(p: Packs, body: str, eyes: list, mouth: str, horns: str | None, arms: str | None, size: int, out_px: int) -> Image.Image:
    """Ghép quái nhìn từ trên xuống, mặt hướng sang phải (+x) như nhân vật."""
    mb = "monster-builder-pack"
    canvas = Image.new("RGBA", (size, size))
    b = p.image(mb, f"PNG/Default/{body}.png")
    if arms:
        arm = p.image(mb, f"PNG/Default/{arms}.png")
        paste_center(canvas, arm, -int(b.width * 0.35), -int(b.height * 0.25), 0.9, 30)
        paste_center(canvas, arm.transpose(Image.FLIP_LEFT_RIGHT), int(b.width * 0.35), -int(b.height * 0.25), 0.9, -30)
    if horns:
        h = p.image(mb, f"PNG/Default/{horns}.png")
        paste_center(canvas, h, -int(b.width * 0.28), -int(b.height * 0.48), 1.0, 15)
        paste_center(canvas, h.transpose(Image.FLIP_LEFT_RIGHT), int(b.width * 0.28), -int(b.height * 0.48), 1.0, -15)
    paste_center(canvas, b, 0, 0)
    for i, eye in enumerate(eyes):
        e = p.image(mb, f"PNG/Default/{eye}.png")
        spread = (i - (len(eyes) - 1) / 2) * e.width * 1.05
        paste_center(canvas, e, int(spread), -int(b.height * 0.12), 0.95)
    paste_center(canvas, p.image(mb, f"PNG/Default/{mouth}.png"), 0, int(b.height * 0.22))
    canvas = canvas.crop(canvas.getbbox())
    # Bản gốc nhìn chính diện, phần "đầu" ở trên -> xoay để đầu hướng sang phải
    canvas = canvas.rotate(-90, expand=True)
    canvas.thumbnail((out_px, out_px), Image.LANCZOS)
    return canvas


def turret(p: Packs) -> Image.Image:
    td = "tower-defense-top-down"
    base = p.image(td, "towerDefense_tile181.png")
    gun = p.image(td, "towerDefense_tile250.png").rotate(-90, expand=True)
    base.alpha_composite(gun, ((base.width - gun.width) // 2 + 10, (base.height - gun.height) // 2))
    return base


def build_enemies(p: Packs) -> None:
    save(monster(p, "body_greenD", ["eye_angry_green", "eye_angry_green"], "mouthB", "detail_green_horn_small", None, 400, 44), "enemies/crawler.png")
    save(monster(p, "body_darkE", ["eye_psycho_light"], "mouth_closed_fangs", "detail_dark_antenna_large", None, 400, 40), "enemies/spore.png")
    save(turret(p), "enemies/sentinel.png")
    save(p.image("top-down-shooter", "PNG/Zombie 1/zoimbie1_hold.png"), "enemies/infected.png")
    warden = p.image("top-down-shooter", "PNG/Robot 1/robot1_machine.png")
    save(warden.resize((warden.width * 2, warden.height * 2), Image.LANCZOS), "enemies/boss_warden.png")
    save(monster(p, "body_redF", ["eye_red", "eye_psycho_dark", "eye_red"], "mouthF", "detail_red_horn_large", "arm_redC", 600, 120), "enemies/boss_queen.png")


# --- Tile & autotile -----------------------------------------------------------------

BIOMES = {
    # floor: các tile sàn (gói, đường dẫn), wall: màu mặt trên / viền / mặt trước (2.5D)
    "ship": {
        "floor": [("top-down-shooter", f"PNG/Tiles/tile_{n:02d}.png") for n in (7, 8, 9, 10)],
        "wall": {"top": (63, 63, 63), "edge": (232, 106, 23), "face": (44, 44, 48)},
    },
    "derelict": {
        "floor": [("top-down-shooter", f"PNG/Tiles/tile_{n}.png") for n in (298, 299, 300, 301)],
        "wall": {"top": (52, 56, 60), "edge": (148, 178, 185), "face": (36, 38, 42)},
    },
    "debris": {
        "floor": [("sci-fi-rts", f"PNG/Default size/Tile/scifiTile_{n:02d}.png") for n in (41, 42, 41, 42)],
        "wall": {"top": (92, 64, 51), "edge": (182, 120, 82), "face": (66, 45, 37)},
    },
    "comet": {
        "floor": [("sci-fi-rts", f"PNG/Default size/Tile/scifiTile_{n:02d}.png") for n in (13, 14, 13, 14)],
        "wall": {"top": (70, 96, 120), "edge": (170, 220, 240), "face": (48, 66, 86)},
    },
    "moon": {
        "floor": [("sci-fi-rts", f"PNG/Default size/Tile/scifiTile_{n:02d}.png") for n in (41, 42, 41, 1)],
        "wall": {"top": (40, 62, 56), "edge": (160, 90, 200), "face": (28, 44, 40)},
    },
}
EDGE = 10   # độ dày viền (giống tile gốc của Kenney)
FACE = 18   # chiều cao mặt trước tường (tạo cảm giác 2.5D)

# Bit lân cận: N, E, S, W, NE, SE, SW, NW — bit = 1 nghĩa là ô đó là TƯỜNG
N, E, S, W, NE, SE, SW, NW = 1, 2, 4, 8, 16, 32, 64, 128


def canonical(mask: int) -> int:
    """Góc chỉ có ý nghĩa khi cả hai cạnh kề cũng là tường (blob 47)."""
    for corner, a, b in ((NE, N, E), (SE, S, E), (SW, S, W), (NW, N, W)):
        if mask & corner and not (mask & a and mask & b):
            mask &= ~corner
    return mask


BLOB_MASKS = sorted({canonical(m) for m in range(256)})
assert len(BLOB_MASKS) == 47


def wall_tile(mask: int, colors: dict) -> Image.Image:
    img = Image.new("RGBA", (TILE, TILE), colors["top"] + (255,))
    d = ImageDraw.Draw(img)
    t, e = TILE - 1, EDGE
    edge = colors["edge"] + (255,)
    # Mặt trước khi bên dưới là sàn: dải tối + viền ở mép dưới -> tường có "chiều cao"
    if not mask & S:
        d.rectangle([0, TILE - FACE, t, t], fill=colors["face"] + (255,))
        d.rectangle([0, TILE - FACE - e // 2, t, TILE - FACE], fill=edge)
    if not mask & N:
        d.rectangle([0, 0, t, e - 1], fill=edge)
    if not mask & E:
        d.rectangle([TILE - e, 0, t, t], fill=edge)
    if not mask & W:
        d.rectangle([0, 0, e - 1, t], fill=edge)
    # Góc trong: sàn ở chéo nhưng hai cạnh kề đều là tường
    for corner, a, b, box in (
        (NE, N, E, [TILE - e, 0, t, e - 1]),
        (SE, S, E, [TILE - e, TILE - e, t, t]),
        (SW, S, W, [0, TILE - e, e - 1, t]),
        (NW, N, W, [0, 0, e - 1, e - 1]),
    ):
        if mask & a and mask & b and not mask & corner:
            d.rectangle(box, fill=edge)
    # Vân nhẹ cho mặt trên đỡ phẳng
    d.rectangle([e + 6, e + 6, TILE - e - 7, TILE - e - 7], outline=tuple(min(255, c + 8) for c in colors["top"]) + (255,), width=2)
    return img


def build_tiles(p: Packs) -> dict:
    cols = 8
    rows = 1 + (len(BLOB_MASKS) + cols - 1) // cols
    meta = {"tile_size": TILE, "columns": cols, "biomes": list(BIOMES), "floor_row": 0, "floor_variants": 4, "wall_masks": BLOB_MASKS}
    for biome, spec in BIOMES.items():
        atlas = Image.new("RGBA", (cols * TILE, rows * TILE))
        for i, (slug, path) in enumerate(spec["floor"]):
            atlas.alpha_composite(p.image(slug, path).resize((TILE, TILE)), (i * TILE, 0))
        for i, mask in enumerate(BLOB_MASKS):
            atlas.alpha_composite(wall_tile(mask, spec["wall"]), ((i % cols) * TILE, (1 + i // cols) * TILE))
        save(atlas, f"tiles/{biome}.png")
    (OUT / "tiles" / "atlas.json").write_text(json.dumps(meta, indent="\t") + "\n")
    return meta


# --- Đạo cụ, vật phẩm, hiệu ứng, âm thanh -------------------------------------------

PROPS = {
    "ore_metal": ("sci-fi-rts", "scifiEnvironment_01.png"),
    "ore_metal_b": ("space-shooter-remastered", "Meteors/meteorBrown_big1.png"),
    "ice_chunk": ("sci-fi-rts", "scifiEnvironment_06.png"),
    "crystal_vein": ("top-down-shooter", "PNG/Tiles/tile_264.png"),
    "xeno_pod": ("sci-fi-rts", "scifiEnvironment_14.png"),
    "salvage_crate": ("top-down-shooter", "PNG/Tiles/tile_129.png"),
    "shuttle": ("space-shooter-remastered", "playerShip1_blue.png"),
    "terminal": ("top-down-shooter", "PNG/Tiles/tile_296.png"),
    "survivor_pod": ("sci-fi-rts", "scifiStructure_11.png"),
    "deco_plant_a": ("sci-fi-rts", "scifiEnvironment_12.png"),
    "deco_plant_b": ("sci-fi-rts", "scifiEnvironment_13.png"),
    "deco_cactus": ("sci-fi-rts", "scifiEnvironment_10.png"),
    "deco_rock_a": ("sci-fi-rts", "scifiEnvironment_04.png"),
    "deco_rock_b": ("sci-fi-rts", "scifiEnvironment_18.png"),
    "deco_meteor": ("space-shooter-remastered", "Meteors/meteorGrey_med1.png"),
    "deco_crate_small": ("top-down-shooter", "PNG/Tiles/tile_130.png"),
    "deco_barrel": ("top-down-shooter", "PNG/Tiles/tile_198.png"),
    "deco_debris": ("top-down-shooter", "PNG/Tiles/tile_292.png"),
    "deco_glass": ("top-down-shooter", "PNG/Tiles/tile_293.png"),
}

ITEM_ICONS = {
    "kim_loai": ("space-shooter-remastered", "Meteors/meteorGrey_small1.png"),
    "bang": ("sci-fi-rts", "scifiEnvironment_05.png"),
    "tinh_the": ("top-down-shooter", "PNG/Tiles/tile_264.png"),
    "mau_vat_la": ("generic-items", "Colored/genericItem_color_108.png"),
    "linh_kien_du_phong": ("generic-items", "Colored/genericItem_color_075.png"),
    "medkit": ("generic-items", "Colored/genericItem_color_102.png"),
    "energy_cell": ("space-shooter-remastered", "Power-ups/powerupBlue_bolt.png"),
    "stim": ("generic-items", "Colored/genericItem_color_093.png"),
    "armor_plate": ("space-shooter-remastered", "Power-ups/shield_silver.png"),
    "servo_legs": ("generic-items", "Colored/genericItem_color_080.png"),
    "targeting_chip": ("generic-items", "Colored/genericItem_color_077.png"),
    "capacitor": ("generic-items", "Colored/genericItem_color_076.png"),
    "drill_head": ("generic-items", "Colored/genericItem_color_001.png"),
    "shock_launcher": ("generic-items", "Colored/genericItem_color_091.png"),
    "w_pulse_pistol": ("top-down-shooter", "PNG/weapon_gun.png"),
    "w_scatter": ("tower-defense-top-down", "towerDefense_tile292.png"),
    "w_rail_rifle": ("top-down-shooter", "PNG/weapon_machine.png"),
    "w_plasma_cutter": ("top-down-shooter", "PNG/weapon_silencer.png"),
    "hat_giong_lua": ("generic-items", "Colored/genericItem_color_146.png"),
    "nhat_ky_thuyen_truong": ("generic-items", "Colored/genericItem_color_035.png"),
    "ban_ghi_tin_hieu": ("generic-items", "Colored/genericItem_color_085.png"),
    "loi_ai_tien_phong": ("generic-items", "Colored/genericItem_color_054.png"),
}

FX = {
    "laser_blue": ("space-shooter-remastered", "Lasers/laserBlue01.png"),
    "laser_red": ("space-shooter-remastered", "Lasers/laserRed01.png"),
    "laser_green": ("space-shooter-remastered", "Lasers/laserGreen11.png"),
    "laser_yellow": ("space-shooter-remastered", "Lasers/laserBlue07.png"),
    "hit_blue": ("space-shooter-remastered", "Lasers/laserBlue08.png"),
    "hit_red": ("space-shooter-remastered", "Lasers/laserRed08.png"),
    "muzzle": ("particle-pack", "PNG (Transparent)/muzzle_01.png"),
    "explosion": ("particle-pack", "PNG (Transparent)/circle_05.png"),
    "spark": ("particle-pack", "PNG (Transparent)/spark_05.png"),
    "smoke": ("particle-pack", "PNG (Transparent)/smoke_04.png"),
    "scorch": ("particle-pack", "PNG (Transparent)/scorch_02.png"),
}
FX_MAX = {"muzzle": 96, "explosion": 256, "spark": 128, "smoke": 192, "scorch": 160}

AUDIO = {
    "shoot": ("sci-fi-sounds", "laserSmall_000.ogg"),
    "shoot_heavy": ("sci-fi-sounds", "laserLarge_000.ogg"),
    "shoot_enemy": ("sci-fi-sounds", "laserRetro_002.ogg"),
    "hit": ("impact-sounds", "impactMetal_light_000.ogg"),
    "mine": ("impact-sounds", "impactPlate_light_001.ogg"),
    "explosion": ("sci-fi-sounds", "explosionCrunch_000.ogg"),
    "boss_explosion": ("sci-fi-sounds", "lowFrequency_explosion_000.ogg"),
    "pickup": ("sci-fi-sounds", "forceField_000.ogg"),
    "hurt": ("impact-sounds", "impactPunch_heavy_000.ogg"),
    "dash": ("sci-fi-sounds", "thrusterFire_000.ogg"),
    "ability": ("sci-fi-sounds", "forceField_002.ogg"),
    "door": ("sci-fi-sounds", "doorOpen_000.ogg"),
    "ui_click": ("sci-fi-sounds", "computerNoise_000.ogg"),
    "slime": ("sci-fi-sounds", "slime_000.ogg"),
}


def fit(img: Image.Image, max_px: int) -> Image.Image:
    img = img.copy()
    img.thumbnail((max_px, max_px), Image.LANCZOS)
    return img


def build_misc(p: Packs) -> None:
    for name, (slug, path) in PROPS.items():
        save(p.image(slug, path), f"props/{name}.png")
    for name, (slug, path) in ITEM_ICONS.items():
        save(fit(p.image(slug, path), 64), f"items/{name}.png")
    for name, (slug, path) in FX.items():
        save(fit(p.image(slug, path), FX_MAX.get(name, 512)), f"fx/{name}.png")
    (OUT / "audio").mkdir(parents=True, exist_ok=True)
    for name, (slug, path) in AUDIO.items():
        (OUT / "audio" / f"{name}.ogg").write_bytes(p.raw(slug, path))


def build_lights() -> None:
    """Texture ánh sáng tự sinh: suy giảm bậc hai (mềm, không cháy sáng khi chồng đèn)."""
    import math
    size = 256
    radial = Image.new("L", (size, size))
    cone = Image.new("L", (size, size))
    c = size / 2
    for y in range(size):
        for x in range(size):
            dx, dy = (x - c) / c, (y - c) / c
            r = math.hypot(dx, dy)
            fall = max(0.0, 1.0 - r) ** 2
            radial.putpixel((x, y), int(255 * fall))
            # Nón 60° hướng sang phải (+x) + quầng nhỏ quanh người cầm đèn
            angle = abs(math.atan2(dy, dx))
            beam = max(0.0, 1.0 - angle / math.radians(32)) ** 0.6 if dx > 0 else 0.0
            halo = max(0.0, 1.0 - r * 5.0)
            cone.putpixel((x, y), int(255 * min(1.0, max(beam * fall * 1.6, halo * 0.3))))
    for name, img in (("light", radial), ("light_cone", cone)):
        save(Image.merge("RGBA", (img, img, img, Image.new("L", img.size, 255))), f"fx/{name}.png")


def write_credits() -> None:
    lines = [
        "# Nguồn asset",
        "",
        "Toàn bộ asset đồ họa và âm thanh lấy từ [Kenney](https://kenney.nl) — giấy phép **CC0 1.0** (public domain).",
        "Không bắt buộc ghi công, nhưng chúng tôi vẫn ghi để cảm ơn tác giả.",
        "Asset được sinh lại bằng `make assets` (tools/import_assets.py). Atlas tường và quái ghép được tạo từ các gói này.",
        "",
        "| Gói | Link |",
        "|---|---|",
    ]
    lines += [f"| {name} | https://kenney.nl/assets/{slug} |" for slug, name in PACKS.items()]
    lines += ["", "Font: Be Vietnam Pro — SIL Open Font License (assets/fonts/OFL.txt)."]
    (OUT / "CREDITS.md").write_text("\n".join(lines) + "\n")


def main() -> None:
    p = Packs("--offline" in sys.argv)
    for sub in ("characters", "enemies", "tiles", "props", "items", "fx", "audio"):
        shutil.rmtree(OUT / sub, ignore_errors=True)
    build_characters(p)
    build_enemies(p)
    build_tiles(p)
    build_misc(p)
    build_lights()
    write_credits()
    print(f"✓ Asset đã sinh vào {OUT}")


if __name__ == "__main__":
    main()
