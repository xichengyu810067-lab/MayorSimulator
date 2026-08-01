#!/usr/bin/env python3
"""Build the Storybook V2 UI icon set from ImageGen chroma-key sources."""

from __future__ import annotations

import argparse
import csv
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


EXPECTED_FILENAMES = (
    "blueprint.png",
    "blueprint_decoration.png",
    "blueprint_floors.png",
    "blueprint_material.png",
    "blueprint_size.png",
    "blueprint_workers.png",
    "building_civic.png",
    "building_community.png",
    "building_economy.png",
    "building_housing.png",
    "building_mobility.png",
    "building_utilities.png",
    "buildings.png",
    "city_data.png",
    "city_hall.png",
    "city_level.png",
    "complaint.png",
    "customize.png",
    "demolish.png",
    "education.png",
    "environment.png",
    "exit.png",
    "fallback.png",
    "governance.png",
    "healthcare.png",
    "justice.png",
    "oversight.png",
    "population.png",
    "public_affairs.png",
    "report.png",
    "score.png",
    "settings.png",
    "theme.png",
    "time.png",
    "treasury.png",
    "trust.png",
    "wellbeing.png",
)

CANVAS_SIZE = 256
MAX_SUBJECT_AXIS = 224
ALPHA_THRESHOLD = 8


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--alpha-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--chroma-helper", type=Path, required=True)
    parser.add_argument(
        "--force-chroma",
        action="store_true",
        help="Rebuild alpha intermediates even when they are newer than their raw sources.",
    )
    return parser.parse_args()


def remove_chroma(source: Path, destination: Path, helper: Path, force: bool = False) -> None:
    if not force and destination.is_file() and destination.stat().st_mtime_ns >= source.stat().st_mtime_ns:
        return
    subprocess.run(
        [
            sys.executable,
            str(helper),
            "--input",
            str(source),
            "--out",
            str(destination),
            "--auto-key",
            "border",
            "--soft-matte",
            "--transparent-threshold",
            "12",
            "--opaque-threshold",
            "220",
            "--despill",
            "--force",
        ],
        check=True,
    )


def normalize(source: Path, destination: Path) -> dict[str, object]:
    image = Image.open(source).convert("RGBA")
    alpha = image.getchannel("A")
    bounds = alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()
    if bounds is None:
        raise RuntimeError(f"No visible pixels in {source}")
    cropped = image.crop(bounds)
    scale = min(MAX_SUBJECT_AXIS / cropped.width, MAX_SUBJECT_AXIS / cropped.height)
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    offset = ((CANVAS_SIZE - resized.width) // 2, (CANVAS_SIZE - resized.height) // 2)
    canvas.alpha_composite(resized, offset)
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, optimize=True)

    final_alpha = canvas.getchannel("A")
    final_bounds = final_alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()
    assert final_bounds is not None
    magenta = 0
    partial = 0
    visible = 0
    pixel_data = canvas.get_flattened_data() if hasattr(canvas, "get_flattened_data") else canvas.getdata()
    for red, green, blue, opacity in pixel_data:
        if opacity > ALPHA_THRESHOLD:
            visible += 1
            if red > 220 and blue > 220 and green < 76:
                magenta += 1
        if 0 < opacity < 255:
            partial += 1
    margins = (
        final_bounds[0],
        final_bounds[1],
        CANVAS_SIZE - final_bounds[2],
        CANVAS_SIZE - final_bounds[3],
    )
    if min(margins) < 12:
        raise RuntimeError(f"Unsafe edge margin for {destination.name}: {margins}")
    if magenta:
        raise RuntimeError(f"Visible magenta pixels remain in {destination.name}: {magenta}")
    return {
        "filename": destination.name,
        "source_width": image.width,
        "source_height": image.height,
        "bbox_width": final_bounds[2] - final_bounds[0],
        "bbox_height": final_bounds[3] - final_bounds[1],
        "margin_left": margins[0],
        "margin_top": margins[1],
        "margin_right": margins[2],
        "margin_bottom": margins[3],
        "visible_pixels": visible,
        "partial_alpha_pixels": partial,
        "magenta_pixels": magenta,
        "output_bytes": destination.stat().st_size,
    }


def make_contact_sheet(output_dir: Path, destination: Path, background: tuple[int, int, int]) -> None:
    columns = 6
    cell_width = 230
    cell_height = 264
    rows = (len(EXPECTED_FILENAMES) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell_width, rows * cell_height), background)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=16)
    text_color = (244, 238, 221) if sum(background) < 240 else (48, 39, 31)
    for index, filename in enumerate(EXPECTED_FILENAMES):
        icon = Image.open(output_dir / filename).convert("RGBA").resize((192, 192), Image.Resampling.LANCZOS)
        x = (index % columns) * cell_width
        y = (index // columns) * cell_height
        tile = Image.new("RGBA", (cell_width, 224), background + (255,))
        tile.alpha_composite(icon, ((cell_width - 192) // 2, 10))
        sheet.paste(tile.convert("RGB"), (x, y))
        label = Path(filename).stem
        box = draw.textbbox((0, 0), label, font=font)
        draw.text((x + (cell_width - (box[2] - box[0])) / 2, y + 228), label, fill=text_color, font=font)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, optimize=True)


def make_runtime_sheet(output_dir: Path, destination: Path, background: tuple[int, int, int]) -> None:
    sizes = (27, 44, 82, 150)
    columns = 3
    cell_width = 460
    cell_height = 230
    rows = (len(EXPECTED_FILENAMES) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell_width, rows * cell_height), background)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=16)
    text_color = (244, 238, 221) if sum(background) < 240 else (48, 39, 31)
    for index, filename in enumerate(EXPECTED_FILENAMES):
        source = Image.open(output_dir / filename).convert("RGBA")
        x = (index % columns) * cell_width
        y = (index // columns) * cell_height
        draw.text((x + 12, y + 10), Path(filename).stem, fill=text_color, font=font)
        cursor_x = x + 12
        for size in sizes:
            icon = source.resize((size, size), Image.Resampling.LANCZOS)
            top = y + 48 + (150 - size)
            tile = Image.new("RGBA", (size, size), background + (255,))
            tile.alpha_composite(icon)
            sheet.paste(tile.convert("RGB"), (cursor_x, top))
            draw.text((cursor_x, y + 204), f"{size}px", fill=text_color, font=font)
            cursor_x += size + 24
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, optimize=True)


def main() -> int:
    args = parse_args()
    for directory in (args.alpha_dir, args.output_dir, args.evidence_dir):
        directory.mkdir(parents=True, exist_ok=True)
    missing = [filename for filename in EXPECTED_FILENAMES if not (args.raw_dir / filename).is_file()]
    if missing:
        raise RuntimeError("Missing raw ImageGen files: " + ", ".join(missing))

    metrics: list[dict[str, object]] = []
    for filename in EXPECTED_FILENAMES:
        raw_path = args.raw_dir / filename
        alpha_path = args.alpha_dir / filename
        output_path = args.output_dir / filename
        remove_chroma(raw_path, alpha_path, args.chroma_helper, args.force_chroma)
        metrics.append(normalize(alpha_path, output_path))

    metrics_path = args.evidence_dir / "storybook-v2-icon-metrics.tsv"
    with metrics_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(metrics[0]), delimiter="\t")
        writer.writeheader()
        writer.writerows(metrics)

    make_contact_sheet(args.output_dir, args.evidence_dir / "storybook-v2-icons-light.png", (246, 232, 199))
    make_contact_sheet(args.output_dir, args.evidence_dir / "storybook-v2-icons-dark.png", (18, 43, 62))
    make_runtime_sheet(args.output_dir, args.evidence_dir / "storybook-v2-runtime-sizes-light.png", (246, 232, 199))
    make_runtime_sheet(args.output_dir, args.evidence_dir / "storybook-v2-runtime-sizes-dark.png", (18, 43, 62))
    print(f"Built {len(EXPECTED_FILENAMES)} Storybook V2 icons.")
    print(metrics_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
