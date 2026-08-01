#!/usr/bin/env python3
"""Deterministically assemble a 4-direction NPC walk atlas from QC'd frames."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image


DIRECTIONS = ("down", "left", "right", "up")


def _frame_path(folder: Path, index: int) -> Path:
    return folder / f"npc_walk-{index + 1}.png"


def _save_gif(frames: list[Image.Image], output: Path, duration: int) -> None:
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=duration,
        loop=0,
        disposal=2,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-dir", type=Path, required=True)
    parser.add_argument("--replacement-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--replace-row", type=int, default=3)
    parser.add_argument("--cell-size", type=int, default=192)
    parser.add_argument("--duration", type=int, default=120)
    args = parser.parse_args()

    if args.replace_row not in range(4):
        raise ValueError("replace-row must be between 0 and 3")

    base_meta = json.loads((args.base_dir / "pipeline-meta.json").read_text(encoding="utf-8"))
    replacement_meta = json.loads(
        (args.replacement_dir / "pipeline-meta.json").read_text(encoding="utf-8")
    )
    replacement_edges = replacement_meta.get("edge_touch_frames", [])
    if replacement_edges:
        raise ValueError(f"Replacement frames failed edge QC: {replacement_edges}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    frame_sources: list[str] = []
    replacement_start = args.replace_row * 4
    for index in range(16):
        if replacement_start <= index < replacement_start + 4:
            source = _frame_path(args.replacement_dir, index - replacement_start)
        else:
            source = _frame_path(args.base_dir, index)
        image = Image.open(source).convert("RGBA")
        if image.size != (args.cell_size, args.cell_size):
            raise ValueError(f"Unexpected frame size {image.size}: {source}")
        destination = _frame_path(args.output_dir, index)
        image.save(destination)
        frames.append(image)
        frame_sources.append(str(source))

    atlas = Image.new(
        "RGBA",
        (args.cell_size * 4, args.cell_size * 4),
        (0, 0, 0, 0),
    )
    for index, frame in enumerate(frames):
        row, col = divmod(index, 4)
        atlas.alpha_composite(frame, (col * args.cell_size, row * args.cell_size))
    atlas.save(args.output_dir / "sheet-transparent.png")

    for row, direction in enumerate(DIRECTIONS):
        row_frames = frames[row * 4 : row * 4 + 4]
        strip = Image.new(
            "RGBA",
            (args.cell_size * 4, args.cell_size),
            (0, 0, 0, 0),
        )
        for col, frame in enumerate(row_frames):
            strip.alpha_composite(frame, (col * args.cell_size, 0))
        strip.save(args.output_dir / f"{direction}-strip.png")
        _save_gif(row_frames, args.output_dir / f"{direction}.gif", args.duration)

    shutil.copy2(args.base_dir / "raw-sheet.png", args.output_dir / "source-full-raw.png")
    shutil.copy2(
        args.replacement_dir / "raw-sheet.png",
        args.output_dir / "source-up-raw.png",
    )

    metadata = {
        "target": "npc",
        "mode": "directional_walk_assembled",
        "rows": 4,
        "cols": 4,
        "cell_size": args.cell_size,
        "duration": args.duration,
        "directions": list(DIRECTIONS),
        "replace_row": args.replace_row,
        "base_directory": str(args.base_dir),
        "replacement_directory": str(args.replacement_dir),
        "frame_sources": frame_sources,
        "edge_touch_frames": [],
        "base_edge_touch_frames_ignored": base_meta.get("edge_touch_frames", []),
        "replacement_edge_touch_frames": replacement_edges,
        "assembly": "deterministic frame replacement; no creative image synthesis",
    }
    (args.output_dir / "pipeline-meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(args.output_dir.resolve())


if __name__ == "__main__":
    main()
