#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
ICNS_PATH="$ASSETS_DIR/AppIcon.icns"
SOURCE_IMAGE="${1:-}"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
cd "$ROOT_DIR"

if [ -n "$SOURCE_IMAGE" ] && [ ! -f "$SOURCE_IMAGE" ]; then
  echo "❌ 图标源文件不存在: $SOURCE_IMAGE" >&2
  exit 1
fi

if [ -n "$SOURCE_IMAGE" ]; then
  while read -r icon_name icon_size; do
    sips -s format png -z "$icon_size" "$icon_size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/$icon_name" >/dev/null
  done <<'EOF'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
EOF
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
  echo "✅ 已生成图标: $ICNS_PATH"
  exit 0
fi

SOURCE_IMAGE="$SOURCE_IMAGE" python3 <<'PY'
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

root = Path.cwd()
iconset = root / "assets" / "AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)

source_image = os.environ.get("SOURCE_IMAGE", "").strip()

if source_image:
    source_path = Path(source_image).expanduser().resolve()
    with Image.open(source_path) as original:
        original = original.convert("RGBA")
        size = max(original.size)
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        offset = ((size - original.width) // 2, (size - original.height) // 2)
        img.alpha_composite(original, dest=offset)
else:
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Dark gradient background
    top = (12, 16, 28, 255)
    bottom = (8, 10, 18, 255)
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # Rounded mask
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((32, 32, size - 32, size - 32), radius=228, fill=255)
    img.putalpha(mask)

    # Subtle radial glow
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse((120, 120, 930, 930), fill=(56, 116, 255, 60))
    gdraw.ellipse((260, 220, 980, 980), fill=(118, 56, 216, 52))
    glow = glow.filter(ImageFilter.GaussianBlur(44))
    img = Image.alpha_composite(img, glow)

    # Raster texture (noise + scanlines)
    noise = Image.effect_noise((size, size), 24).convert("L")
    noise_alpha = noise.point(lambda v: int(max(0, min(255, (v - 108) * 0.45))))
    noise_layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    noise_layer.putalpha(noise_alpha)
    img = Image.alpha_composite(img, noise_layer)

    scan = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(scan)
    for y in range(0, size, 3):
        sdraw.line([(0, y), (size, y)], fill=(255, 255, 255, 7), width=1)
    img = Image.alpha_composite(img, scan)

    # Rainbow curve dragged by pointer
    curve_points = [(96, 784), (220, 690), (360, 620), (528, 566), (708, 534), (876, 476)]
    rainbow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rdraw = ImageDraw.Draw(rainbow)
    rainbow_colors = [
        (255, 82, 116, 190),
        (255, 153, 78, 190),
        (255, 222, 84, 188),
        (112, 230, 114, 188),
        (84, 198, 255, 188),
        (145, 134, 255, 188),
    ]
    for idx, color in enumerate(rainbow_colors):
        offset = (idx - 2.5) * 8
        shifted = [(x, y + offset) for (x, y) in curve_points]
        rdraw.line(shifted, fill=color, width=24, joint="curve")
    rainbow = rainbow.filter(ImageFilter.GaussianBlur(2.8))
    img = Image.alpha_composite(img, rainbow)

    # White highlight on rainbow center
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(highlight)
    hdraw.line(curve_points, fill=(255, 255, 255, 75), width=9, joint="curve")
    highlight = highlight.filter(ImageFilter.GaussianBlur(1.0))
    img = Image.alpha_composite(img, highlight)

    # Cursor arrow
    arrow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    adraw = ImageDraw.Draw(arrow)
    arrow_points = [
        (458, 228), (778, 488), (632, 516), (732, 764),
        (618, 812), (518, 570), (394, 674)
    ]
    adraw.polygon(arrow_points, fill=(248, 252, 255, 255))
    adraw.line(arrow_points + [arrow_points[0]], fill=(116, 210, 255, 255), width=14, joint="curve")

    # Cursor inner accent
    adraw.polygon(
        [(516, 338), (666, 468), (590, 484), (640, 614), (582, 640), (533, 514), (474, 565)],
        fill=(166, 232, 255, 140)
    )
    img = Image.alpha_composite(img, arrow)

    # Soft drop shadow for cursor
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    shadow_points = [(x + 9, y + 10) for (x, y) in arrow_points]
    sd.polygon(shadow_points, fill=(0, 0, 0, 95))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    img = Image.alpha_composite(shadow, img)

    # Final glossy sheen
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shdraw = ImageDraw.Draw(sheen)
    shdraw.ellipse((96, 78, 650, 372), fill=(255, 255, 255, 28))
    sheen = sheen.filter(ImageFilter.GaussianBlur(26))
    img = Image.alpha_composite(img, sheen)

# Export base and iconset sizes
base_path = iconset / "icon_512x512@2x.png"
img.save(base_path)

sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

for name, px in sizes.items():
    resized = img.resize((px, px), Image.Resampling.LANCZOS)
    resized.save(iconset / name)
PY

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
echo "✅ 已生成图标: $ICNS_PATH"
