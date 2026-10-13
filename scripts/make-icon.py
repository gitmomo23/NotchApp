#!/usr/bin/env python3
"""Draw the Notchling app icon into the asset catalog."""

from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "Notchling" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"


def draw(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (17, 18, 22, 255))
    pen = ImageDraw.Draw(image)
    island_w = size * 0.68
    island_h = max(3.0, size * 0.16)
    origin_x = (size - island_w) / 2
    origin_y = size * 0.31
    pen.rounded_rectangle(
        [origin_x, origin_y, origin_x + island_w, origin_y + island_h],
        radius=island_h / 2,
        fill=(246, 247, 249, 255),
    )
    dot = max(1.2, size * 0.028)
    dot_x = size * 0.63
    dot_y = origin_y + island_h / 2
    pen.ellipse([dot_x - dot, dot_y - dot, dot_x + dot, dot_y + dot], fill=(78, 88, 104, 255))

    bar_h = max(2.0, size * 0.038)
    bar_y = origin_y + island_h + size * 0.09
    widths = (0.18, 0.28, 0.14)
    gap = size * 0.025
    group = size * sum(widths) + gap * (len(widths) - 1)
    cursor = (size - group) / 2
    colors = ((126, 198, 255, 255), (226, 229, 234, 255), (126, 198, 255, 190))
    for width, color in zip(widths, colors):
        bar_w = size * width
        pen.rounded_rectangle(
            [cursor, bar_y, cursor + bar_w, bar_y + bar_h],
            radius=bar_h / 2,
            fill=color,
        )
        cursor += bar_w + gap
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, size in {
        "icon_16.png": 16,
        "icon_32.png": 32,
        "icon_64.png": 64,
        "icon_128.png": 128,
        "icon_256.png": 256,
        "icon_512.png": 512,
        "icon_1024.png": 1024,
    }.items():
        draw(size).save(OUT / name)


if __name__ == "__main__":
    main()
