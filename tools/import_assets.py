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
    "planets": "Planets",
    "game-icons": "Game Icons",
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


# Asset ngoài Kenney (OpenGameArt) — tải trực tiếp theo URL, lưu cache theo tên file
EXTERNAL = {
    "vegastrike.zip": "https://opengameart.org/sites/default/files/vegastrike-portraits-640x480.zip",
    "nichol_portraits.zip": "https://opengameart.org/sites/default/files/png.zip",
    "survivor.zip": "https://opengameart.org/sites/default/files/Top_Down_Survivor_2.zip",
    "ship_interior_1.jpg": "https://opengameart.org/sites/default/files/interior_of_a_fictional_spaceship_1.jpg",
    "ship_interior_2.jpg": "https://opengameart.org/sites/default/files/interior_of_a_fictional_spaceship_2.jpg",
    "scifi_bulkhead.jpg": "https://opengameart.org/sites/default/files/sci_fi_bg1.jpg",
}


def external(name: str, offline: bool) -> Path:
    path = CACHE / name
    if not path.exists():
        if offline:
            sys.exit(f"Thiếu cache {path}. Chạy lại không có --offline.")
        print(f"↓ {name}")
        CACHE.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(EXTERNAL[name], headers={"User-Agent": "Mozilla/5.0 (asset pipeline)"})
        path.write_bytes(urllib.request.urlopen(req, timeout=180).read())
    return path


def zip_image(path: Path, suffix: str) -> Image.Image:
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if "__MACOSX" not in n and (n == suffix or n.endswith("/" + suffix.lstrip("/")))]
        if not names:
            sys.exit(f"Không thấy {suffix} trong {path.name}")
        with z.open(sorted(names, key=len)[0]) as f:
            return Image.open(io.BytesIO(f.read())).convert("RGBA")


class Packs:
    def __init__(self, offline: bool):
        self.offline = offline
        self.zips = {slug: pack_zip(slug, offline) for slug in PACKS}

    def ext(self, name: str) -> Path:
        return external(name, self.offline)

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


# --- Chân dung (dẫn truyện) ------------------------------------------------------------

PORTRAITS = ["male17", "male15", "male14", "male13", "male10", "women28", "women6", "asian", "women45", "women16", "women24", "women26", "male16", "male20", "women3", "male6", "male2", "male3", "male7", "male8", "male19", "women2", "women9", "women14", "women17", "women27", "women36"]
PORTRAIT_H = 480


def bust(img: Image.Image, height: int = PORTRAIT_H) -> Image.Image:
    img = img.crop(img.getbbox())
    scale = height / img.height
    return img.resize((int(img.width * scale), height), Image.LANCZOS)


def hologram(img: Image.Image) -> Image.Image:
    """Hiệu ứng hologram cho LẠC: đơn sắc xanh + vạch quét + viền sáng."""
    from PIL import ImageChops, ImageFilter
    gray = img.convert("L")
    alpha = img.getchannel("A")
    r = gray.point(lambda v: int(v * 0.35))
    g = gray.point(lambda v: min(255, int(v * 0.95 + 20)))
    b = gray.point(lambda v: min(255, int(v * 1.05 + 40)))
    lines = Image.new("L", img.size, 255)
    d = ImageDraw.Draw(lines)
    for y in range(0, img.height, 4):
        d.line([(0, y), (img.width, y)], fill=150)
    alpha = ImageChops.multiply(alpha, lines).point(lambda v: int(v * 0.88))
    out = Image.merge("RGBA", (r, g, b, alpha))
    glow = out.filter(ImageFilter.GaussianBlur(6))
    base = Image.new("RGBA", img.size)
    base.alpha_composite(glow)
    base.alpha_composite(out)
    return base


def build_portraits(p: Packs) -> None:
    vs = p.ext("vegastrike.zip")
    for name in PORTRAITS:
        save(bust(zip_image(vs, f"{name}.png")), f"portraits/vs_{name}.png")
    husk = zip_image(p.ext("nichol_portraits.zip"), "Husk.png")
    save(hologram(bust(husk)), "portraits/lac.png")


# --- Nền dẫn truyện ----------------------------------------------------------------------

BG_SIZE = (1280, 720)


def cover(img: Image.Image, size=BG_SIZE, focus_y: float = 0.5) -> Image.Image:
    img = img.convert("RGB")
    scale = max(size[0] / img.width, size[1] / img.height)
    img = img.resize((int(img.width * scale) + 1, int(img.height * scale) + 1), Image.LANCZOS)
    x = (img.width - size[0]) // 2
    y = int((img.height - size[1]) * focus_y)
    return img.crop((x, y, x + size[0], y + size[1]))


def grade(img: Image.Image, tint: tuple, amount: float, dark: float = 1.0) -> Image.Image:
    overlay = Image.new("RGB", img.size, tint)
    out = Image.blend(img, overlay, amount)
    return out.point(lambda v: int(v * dark))


def starfield(seed: int, planet: Image.Image | None, planet_scale: float, pos: tuple) -> Image.Image:
    import random
    rnd = random.Random(seed)
    img = Image.new("RGB", BG_SIZE, (6, 8, 18))
    d = ImageDraw.Draw(img)
    # Tinh vân: vài đốm màu mờ lớn
    from PIL import ImageFilter
    neb = Image.new("RGB", BG_SIZE, (0, 0, 0))
    nd = ImageDraw.Draw(neb)
    for _ in range(9):
        c = rnd.choice([(60, 20, 90), (10, 50, 90), (90, 30, 60), (20, 70, 80)])
        x, y, r = rnd.randint(0, 1280), rnd.randint(0, 720), rnd.randint(120, 360)
        nd.ellipse([x - r, y - r, x + r, y + r], fill=c)
    img = Image.blend(img, neb.filter(ImageFilter.GaussianBlur(90)), 0.55)
    d = ImageDraw.Draw(img)
    for _ in range(900):
        x, y = rnd.randint(0, 1279), rnd.randint(0, 719)
        v = rnd.randint(90, 255)
        d.point((x, y), fill=(v, v, min(255, v + 20)))
    for _ in range(40):
        x, y, r = rnd.randint(0, 1279), rnd.randint(0, 719), rnd.choice([1, 1, 2])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255))
    if planet is not None:
        pl = planet.copy()
        pl = pl.resize((int(pl.width * planet_scale), int(pl.height * planet_scale)), Image.LANCZOS)
        img = img.convert("RGBA")
        img.alpha_composite(pl, (pos[0] - pl.width // 2, pos[1] - pl.height // 2))
    return img.convert("RGB")


def build_backgrounds(p: Packs) -> None:
    corridor = cover(Image.open(p.ext("ship_interior_1.jpg")))
    corridor2 = cover(Image.open(p.ext("ship_interior_2.jpg")).transpose(Image.FLIP_LEFT_RIGHT))
    bulkhead = cover(Image.open(p.ext("scifi_bulkhead.jpg")))
    backgrounds = {
        "corridor": corridor,
        "bridge": grade(corridor2, (20, 60, 120), 0.25, 0.9),
        "hydroponics": grade(corridor, (40, 140, 60), 0.3, 0.95),
        "alarm": grade(corridor2, (180, 20, 20), 0.35, 0.75),
        "medbay": grade(bulkhead, (220, 240, 255), 0.15, 1.0),
        "deck7": grade(bulkhead, (10, 20, 40), 0.55, 0.6),
        "derelict": grade(corridor2, (30, 40, 30), 0.45, 0.45),
        "space": starfield(1, p.image("planets", "Planets/planet09.png"), 0.9, (980, 560)),
        "jupiter": starfield(2, p.image("planets", "Planets/planet03.png"), 0.95, (1060, 560)),
        "van_lang": starfield(3, p.image("planets", "Planets/planet00.png"), 0.45, (330, 220)),
        "moon": starfield(4, p.image("planets", "Planets/planet06.png"), 1.6, (240, 700)),
        "comet": starfield(5, p.image("planets", "Planets/planet08.png"), 0.7, (1050, 200)),
    }
    for name, img in backgrounds.items():
        path = OUT / "backgrounds" / f"{name}.jpg"
        path.parent.mkdir(parents=True, exist_ok=True)
        img.convert("RGB").save(path, quality=86)


# --- Sprite đội có hoạt ảnh (theo vai trò) ------------------------------------------------

ROLE_TINTS = {
    # vai trò: (hue mục tiêu 0..1 hoặc None = giữ nguyên, hệ số bão hòa, hệ số sáng)
    "soldier": (None, 1.0, 1.0),
    "engineer": (0.07, 1.6, 1.15),
    "miner": (0.12, 1.2, 1.0),
    "medic": (0.55, 0.15, 1.9),
    "scout": (0.6, 1.2, 0.85),
    "scientist": (0.8, 1.1, 1.05),
}
WEAPON_KINDS = {"rifle": "rifle", "shotgun": "shotgun", "handgun": "handgun"}
UNIT_ANIMS = {"idle": 2, "move": 2, "shoot": 1}  # bước lấy mẫu frame
UNIT_SCALE = 0.22


def recolor(img: Image.Image, hue, sat_mul: float, val_mul: float) -> Image.Image:
    """Đổi màu riêng phần quân phục (dải màu xanh/olive), giữ nguyên da, súng."""
    if hue is None:
        return img
    import colorsys
    px = img.load()
    out = img.copy()
    po = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s_, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if 0.08 <= h <= 0.5 and s_ > 0.07 and v > 0.12:
                nr, ng, nb = colorsys.hsv_to_rgb(hue, min(1.0, s_ * sat_mul), min(1.0, v * val_mul))
                po[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return out


def strip(frames: list) -> Image.Image:
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    out = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        out.alpha_composite(f, (i * w + (w - f.width) // 2, (h - f.height) // 2))
    return out


def build_units(p: Packs) -> None:
    zpath = p.ext("survivor.zip")
    meta = {"scale": UNIT_SCALE, "anims": {}}
    with zipfile.ZipFile(zpath) as z:
        names = [n for n in z.namelist() if n.endswith(".png") and "__MACOSX" not in n]

        def frames(prefix: str, step: int) -> list:
            picked = sorted((n for n in names if f"/{prefix}/" in n), key=lambda n: int(re.findall(r"_(\d+)\.png$", n)[0]))
            out = []
            for n in picked[::step]:
                with z.open(n) as f:
                    im = Image.open(io.BytesIO(f.read())).convert("RGBA")
                out.append(im.resize((int(im.width * UNIT_SCALE), int(im.height * UNIT_SCALE)), Image.LANCZOS))
            return out

        base = {}
        for kind in WEAPON_KINDS:
            for anim, step in UNIT_ANIMS.items():
                base[(kind, anim)] = frames(f"{kind}/{anim}", step)
        for anim in ["walk", "idle"]:
            fr = frames(f"feet/{anim}", 2)
            save(strip(fr), f"units/feet_{anim}.png")
            meta["anims"][f"feet_{anim}"] = len(fr)
        for role, (hue, sat, val) in ROLE_TINTS.items():
            for (kind, anim), fr in base.items():
                save(strip([recolor(f, hue, sat, val) for f in fr]), f"units/{role}_{kind}_{anim}.png")
                meta["anims"][f"{kind}_{anim}"] = len(fr)
    (OUT / "units" / "units.json").write_text(json.dumps(meta, indent="\t") + "\n")


# --- Icon giao diện & texture địa hình --------------------------------------------------------

UI_ICONS = ["pause", "right", "fastForward", "zoomIn", "zoomOut", "target", "exitLeft", "home", "gear", "save",
            "information", "menuList", "star", "warning", "wrench", "multiplayer", "singleplayer", "door", "barsHorizontal",
            "barsVertical", "arrowUp", "arrowDown", "stop", "locked", "checkmark", "cross", "next", "return", "trophy",
            "leaderboardsComplex", "signal3", "medal1", "basket", "massiveMultiplayer", "power", "question", "rewind", "previous"]


def build_ui(p: Packs) -> None:
    names = p.zips["game-icons"].namelist()
    for name in UI_ICONS:
        for size in ("2x", "1x"):
            if any(n.endswith(f"PNG/White/{size}/{name}.png") for n in names):
                save(p.image("game-icons", f"PNG/White/{size}/{name}.png"), f"ui/icons/{name}.png")
                break
        else:
            print(f"! bỏ qua icon {name}")


def build_terrain(p: Packs) -> None:
    for i, n in enumerate(["noise00", "noise08", "noise13"]):
        save(p.image("planets", f"Parts/{n}.png").convert("L").convert("RGBA"), f"terrain/noise_{i}.png")
    details = {
        "debris": ("sci-fi-rts", "PNG/Default size/Tile/scifiTile_41.png"),
        "comet": ("sci-fi-rts", "PNG/Default size/Tile/scifiTile_13.png"),
        "moon": ("sci-fi-rts", "PNG/Default size/Tile/scifiTile_42.png"),
    }
    for biome, (slug, path) in details.items():
        save(p.image(slug, path).resize((128, 128), Image.LANCZOS), f"terrain/{biome}_detail.png")


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
    lines += [
        "",
        "## Ngoài Kenney (OpenGameArt) — giữ nguyên giấy phép gốc khi chia sẻ lại các file này",
        "",
        "| Asset | Tác giả | Giấy phép | Dùng cho |",
        "|---|---|---|---|",
        "| [VegaStrike Portraits](https://opengameart.org/content/vegastrike-portraits) | Grumbel | CC-BY-SA 3.0 / GPL | assets/portraits/vs_*.png (đã cắt, thu nhỏ) |",
        "| [Justin Nichol's sci-fi portraits](https://opengameart.org/content/justin-nichols-sci-fi-portraits-png-psd-transparency) (Husk) | Justin Nichol (tách nền: soreCactus) | CC-BY-SA 3.0 | assets/portraits/lac.png (hiệu ứng hologram) |",
        "| [Animated Top Down Survivor Player](https://opengameart.org/content/animated-top-down-survivor-player) | rileygombart | CC-BY 3.0 | assets/units/* (thu nhỏ, đổi màu theo vai trò) |",
        "| [Spaceship Interior](https://opengameart.org/content/spaceship-interior) | Pixabay | CC0 | assets/backgrounds/ (nội thất tàu, đã chỉnh màu) |",
        "| [Sci-Fi Background](https://opengameart.org/content/sci-fi-background) | ask4asset | CC0 | assets/backgrounds/medbay, deck7 |",
        "",
        "Nền vũ trụ (space, jupiter, van_lang, moon, comet) được tự sinh + hành tinh từ Kenney Planets.",
        "",
        "Font: Be Vietnam Pro — SIL Open Font License (assets/fonts/OFL.txt).",
    ]
    (OUT / "CREDITS.md").write_text("\n".join(lines) + "\n")


def main() -> None:
    p = Packs("--offline" in sys.argv)
    for sub in ("characters", "enemies", "props", "items", "fx", "audio", "portraits", "backgrounds", "units", "ui", "terrain"):
        shutil.rmtree(OUT / sub, ignore_errors=True)
    build_characters(p)
    build_enemies(p)
    build_tiles(p)
    build_misc(p)
    build_portraits(p)
    build_backgrounds(p)
    build_units(p)
    build_ui(p)
    build_terrain(p)
    build_lights()
    write_credits()
    print(f"✓ Asset đã sinh vào {OUT}")


if __name__ == "__main__":
    main()
