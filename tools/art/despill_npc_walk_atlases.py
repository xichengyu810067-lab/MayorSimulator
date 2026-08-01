#!/usr/bin/env python3
"""Remove chroma-key magenta fringe and rebuild final NPC walk atlases."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image


ROLES = (
    "resident",
    "student",
    "merchant",
    "elderly",
    "worker",
    "civil-servant",
    "council-member",
    "resident-florist",
)
DIRECTIONS = ("down", "left", "right", "up")


def _magenta_distance(red: int, green: int, blue: int) -> float:
    return math.sqrt((red - 255) ** 2 + green**2 + (blue - 255) ** 2)


def _has_transparent_neighbor(alpha, x: int, y: int, radius: int = 2) -> bool:
    width, height = alpha.size
    for sample_y in range(max(0, y - radius), min(height, y + radius + 1)):
        for sample_x in range(max(0, x - radius), min(width, x + radius + 1)):
            if alpha.getpixel((sample_x, sample_y)) <= 4:
                return True
    return x < radius or y < radius or x >= width - radius or y >= height - radius


def _nearby_foreground_color(image: Image.Image, x: int, y: int, radius: int = 4):
    width, height = image.size
    candidates: list[tuple[int, int, int, int]] = []
    for sample_y in range(max(0, y - radius), min(height, y + radius + 1)):
        for sample_x in range(max(0, x - radius), min(width, x + radius + 1)):
            red, green, blue, alpha = image.getpixel((sample_x, sample_y))
            dominance = min(red, blue) - green
            if alpha >= 96 and not (red >= 160 and blue >= 160 and dominance >= 45):
                candidates.append((red, green, blue, alpha))
    if not candidates:
        return None
    weight = sum(item[3] for item in candidates)
    return tuple(round(sum(item[channel] * item[3] for item in candidates) / weight) for channel in range(3))


def despill(image: Image.Image) -> tuple[Image.Image, int, int]:
    source = image.convert("RGBA")
    alpha = source.getchannel("A")
    output = source.copy()
    removed = 0
    recovered = 0
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, opacity = source.getpixel((x, y))
            if opacity <= 0:
                continue
            distance = _magenta_distance(red, green, blue)
            dominance = min(red, blue) - green
            if (
                red >= 170
                and blue >= 170
                and green <= 105
                and dominance >= 70
                and _has_transparent_neighbor(alpha, x, y)
            ):
                output.putpixel((x, y), (0, 0, 0, 0))
                removed += 1
                continue
            if distance <= 112.0:
                output.putpixel((x, y), (0, 0, 0, 0))
                removed += 1
                continue
            if not _has_transparent_neighbor(alpha, x, y):
                continue
            if red < 145 or blue < 145 or dominance < 42 or distance >= 218.0:
                continue
            replacement = _nearby_foreground_color(source, x, y)
            if replacement is None:
                output.putpixel((x, y), (0, 0, 0, 0))
                removed += 1
                continue
            edge_factor = max(0.0, min(1.0, (distance - 112.0) / 106.0))
            corrected_alpha = min(opacity, round(255.0 * edge_factor))
            if corrected_alpha <= 4:
                output.putpixel((x, y), (0, 0, 0, 0))
                removed += 1
            else:
                output.putpixel((x, y), (*replacement, corrected_alpha))
                recovered += 1
    return output, removed, recovered


def _save_gif(frames: list[Image.Image], output: Path, duration: int) -> None:
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=duration,
        loop=0,
        disposal=2,
    )


def rebuild_role(folder: Path) -> dict[str, int]:
    frames: list[Image.Image] = []
    total_removed = 0
    total_recovered = 0
    for index in range(16):
        frame_path = folder / f"npc_walk-{index + 1}.png"
        cleaned, removed, recovered = despill(Image.open(frame_path))
        cleaned.save(frame_path)
        frames.append(cleaned)
        total_removed += removed
        total_recovered += recovered

    cell_size = frames[0].width
    atlas = Image.new("RGBA", (cell_size * 4, cell_size * 4), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, 4)
        atlas.alpha_composite(frame, (col * cell_size, row * cell_size))
    atlas.save(folder / "sheet-transparent.png")

    duration = 120
    metadata_path = folder / "pipeline-meta.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    duration = int(metadata.get("duration", duration))
    for row, direction in enumerate(DIRECTIONS):
        row_frames = frames[row * 4 : row * 4 + 4]
        strip = Image.new("RGBA", (cell_size * 4, cell_size), (0, 0, 0, 0))
        for col, frame in enumerate(row_frames):
            strip.alpha_composite(frame, (col * cell_size, 0))
        strip.save(folder / f"{direction}-strip.png")
        _save_gif(row_frames, folder / f"{direction}.gif", duration)

    metadata["despill"] = {
        "removed_pixels": total_removed,
        "recovered_edge_pixels": total_recovered,
        "algorithm": "transparent-neighbor magenta recovery v1",
    }
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"removed": total_removed, "recovered": total_recovered}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    for role in ROLES:
        folder = args.root / role
        result = rebuild_role(folder)
        print(f"{role}: removed={result['removed']} recovered={result['recovered']}")


if __name__ == "__main__":
    main()
