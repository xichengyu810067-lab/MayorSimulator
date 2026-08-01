#!/usr/bin/env python3
"""Validate delivered NPC directional walk atlases and print compact QC data."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


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


def opaque_bbox(image: Image.Image):
    return image.getchannel("A").getbbox()


def bright_magenta_count(image: Image.Image) -> int:
    count = 0
    rgba = image.convert("RGBA")
    alpha_channel = rgba.getchannel("A")
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = rgba.getpixel((x, y))
            if not (alpha > 4 and red >= 170 and blue >= 170 and green <= 105 and min(red, blue) - green >= 70):
                continue
            near_transparency = False
            for sample_y in range(max(0, y - 2), min(rgba.height, y + 3)):
                for sample_x in range(max(0, x - 2), min(rgba.width, x + 3)):
                    if alpha_channel.getpixel((sample_x, sample_y)) <= 4:
                        near_transparency = True
                        break
                if near_transparency:
                    break
            if near_transparency:
                count += 1
    return count


def alpha_touches_edge(image: Image.Image) -> bool:
    alpha = image.getchannel("A")
    width, height = image.size
    return any(
        alpha.getpixel((x, 0)) > 4 or alpha.getpixel((x, height - 1)) > 4
        for x in range(width)
    ) or any(
        alpha.getpixel((0, y)) > 4 or alpha.getpixel((width - 1, y)) > 4
        for y in range(height)
    )


def frame_difference(first: Image.Image, second: Image.Image) -> float:
    diff = ImageChops.difference(first.convert("RGBA"), second.convert("RGBA"))
    return sum(ImageStat.Stat(diff).mean) / 4.0


def validate_role(folder: Path) -> tuple[list[str], dict[str, object]]:
    errors: list[str] = []
    metadata_path = folder / "pipeline-meta.json"
    if not metadata_path.exists():
        return ["missing pipeline-meta.json"], {}
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("edge_touch_frames"):
        errors.append(f"metadata edge touch: {metadata['edge_touch_frames']}")

    atlas_path = folder / "sheet-transparent.png"
    if not atlas_path.exists():
        return errors + ["missing sheet-transparent.png"], {}
    atlas = Image.open(atlas_path).convert("RGBA")
    if atlas.size != (768, 768):
        errors.append(f"atlas size is {atlas.size}, expected 768x768")

    frame_hashes: set[str] = set()
    heights: list[int] = []
    feet_y: list[int] = []
    direction_min_differences: list[float] = []
    magenta_pixels = 0
    frames: list[Image.Image] = []
    for index in range(16):
        path = folder / f"npc_walk-{index + 1}.png"
        if not path.exists():
            errors.append(f"missing frame {index + 1}")
            continue
        frame = Image.open(path).convert("RGBA")
        frames.append(frame)
        if frame.size != (192, 192):
            errors.append(f"frame {index + 1} size is {frame.size}")
        if alpha_touches_edge(frame):
            errors.append(f"frame {index + 1} alpha touches edge")
        bbox = opaque_bbox(frame)
        if bbox is None:
            errors.append(f"frame {index + 1} is empty")
            continue
        heights.append(bbox[3] - bbox[1])
        feet_y.append(bbox[3])
        magenta_pixels += bright_magenta_count(frame)
        frame_hashes.add(hashlib.sha256(frame.tobytes()).hexdigest())

    if len(frame_hashes) != 16:
        errors.append(f"only {len(frame_hashes)} unique frame images")
    if heights and min(heights) < max(heights) * 0.84:
        errors.append(f"body-height drift exceeds 16%: {min(heights)}..{max(heights)}")
    if feet_y and max(feet_y) - min(feet_y) > 2:
        errors.append(f"feet anchor drift exceeds 2px: {min(feet_y)}..{max(feet_y)}")
    if magenta_pixels > 0:
        errors.append(f"visible bright-magenta pixels: {magenta_pixels}")

    if len(frames) == 16:
        for row in range(4):
            row_frames = frames[row * 4 : row * 4 + 4]
            differences = [
                frame_difference(row_frames[index], row_frames[(index + 1) % 4])
                for index in range(4)
            ]
            direction_min_differences.append(min(differences))
            if min(differences) < 0.45:
                errors.append(f"direction row {row} contains near-identical adjacent poses")

    return errors, {
        "unique_frames": len(frame_hashes),
        "height_range": [min(heights), max(heights)] if heights else [],
        "feet_y_range": [min(feet_y), max(feet_y)] if feet_y else [],
        "bright_magenta": magenta_pixels,
        "min_pose_difference": round(min(direction_min_differences), 3) if direction_min_differences else 0,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    report: dict[str, object] = {"roles": {}, "checks": 0, "failures": []}
    for role in ROLES:
        errors, metrics = validate_role(args.root / role)
        report["roles"][role] = {"metrics": metrics, "errors": errors}
        report["checks"] += 1
        if errors:
            report["failures"].append({"role": role, "errors": errors})
        print(f"{role}: {'PASS' if not errors else 'FAIL'} {metrics}")
        for error in errors:
            print(f"  - {error}")

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    if report["failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
