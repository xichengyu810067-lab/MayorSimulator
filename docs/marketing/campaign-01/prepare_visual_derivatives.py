from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parent
VISUALS = ROOT / "visuals"


def cover(
    source: Path,
    destination: Path,
    size: tuple[int, int],
    vertical_anchor: str = "center",
) -> None:
    image = Image.open(source).convert("RGB")
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - size[0]) // 2
    top = 0 if vertical_anchor == "top" else (resized.height - size[1]) // 2
    resized.crop((left, top, left + size[0], top + size[1])).save(
        destination, quality=95
    )


def portrait_with_blurred_fill(
    source: Path, destination: Path, size: tuple[int, int]
) -> None:
    image = Image.open(source).convert("RGB")

    background_scale = max(size[0] / image.width, size[1] / image.height)
    background = image.resize(
        (
            round(image.width * background_scale),
            round(image.height * background_scale),
        ),
        Image.Resampling.LANCZOS,
    )
    left = (background.width - size[0]) // 2
    top = (background.height - size[1]) // 2
    background = background.crop((left, top, left + size[0], top + size[1]))
    background = ImageEnhance.Brightness(background).enhance(0.58)
    background = background.filter(ImageFilter.GaussianBlur(radius=28))

    foreground_scale = min(size[0] / image.width, size[1] / image.height)
    foreground = image.resize(
        (
            round(image.width * foreground_scale),
            round(image.height * foreground_scale),
        ),
        Image.Resampling.LANCZOS,
    )
    x = (size[0] - foreground.width) // 2
    y = (size[1] - foreground.height) // 2
    background.paste(foreground, (x, y))
    background.save(destination, quality=95)


def main() -> None:
    hero = VISUALS / "mayor-simulator-mvp-alpha-hero-16x9-v1.png"
    community = VISUALS / "mayor-simulator-community-4x5-v1.png"
    short = VISUALS / "mayor-simulator-promise-9x16-v1.png"
    itch_cover = VISUALS / "mayor-simulator-itch-cover-source-v1.png"

    cover(hero, VISUALS / "mayor-simulator-mvp-alpha-hero-1920x1080-v1.jpg", (1920, 1080))
    portrait_with_blurred_fill(
        community,
        VISUALS / "mayor-simulator-community-1080x1350-v1.jpg",
        (1080, 1350),
    )
    cover(
        short,
        VISUALS / "mayor-simulator-promise-1080x1920-v1.jpg",
        (1080, 1920),
    )
    cover(
        itch_cover,
        VISUALS / "mayor-simulator-itch-cover-630x500-v1.jpg",
        (630, 500),
        vertical_anchor="top",
    )

    for path in sorted(VISUALS.glob("*")):
        if path.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
            continue
        with Image.open(path) as image:
            print(f"{path.name}\t{image.width}x{image.height}\t{image.mode}")


if __name__ == "__main__":
    main()
