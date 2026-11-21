#!/usr/bin/env python3
"""Regenerate every native launcher icon from the official Sinsajo logo.

The logo lives in ``web/sinsajo.svg``.  All outputs are derived from that one
file so the Android, iOS, macOS, Windows and Linux icons never drift apart.

Requirements:
  * Python 3
  * Pillow (``python3 -m pip install Pillow``)
  * librsvg's ``rsvg-convert`` command

Run from anywhere:
  python3 tool/generate_app_icons.py
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOGO_PATH = ROOT / "web" / "sinsajo.svg"

# Brand palette (matches docs-site/src/styles/custom.css and the SVG logo).
BRAND_ORANGE = "#FF8000"
BRAND_WHITE = "#FFFFFF"
BRAND_DARK = "#14100B"

# Logo placement as a fraction of the icon canvas.  The bird is wider than it
# is tall (64x58), so the height follows automatically.
ANDROID_LEGACY_RATIO = 0.66
ANDROID_ROUND_RATIO = 0.62
ADAPTIVE_FOREGROUND_RATIO = 62 / 108
IOS_RATIO = 0.66
MACOS_RATIO = 0.50  # 62% of the 824/1024 rounded tile.
WINDOWS_RATIO = 0.625
LINUX_RATIO = 0.66
WEB_RATIO = 0.66
WEB_MASKABLE_RATIO = 0.52

ANDROID_DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

WINDOWS_ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def _require_tools() -> None:
    if shutil.which("rsvg-convert") is None:
        raise SystemExit("rsvg-convert was not found. Install librsvg (e.g. apt install librsvg2-bin).")


def _read_logo() -> tuple[str, float, float]:
    svg = LOGO_PATH.read_text(encoding="utf-8")
    match = re.search(r"<svg\b([^>]*)>(.*?)</svg>", svg, re.S)
    if match is None:
        raise SystemExit(f"Could not parse {LOGO_PATH}")
    attributes, inner = match.groups()
    view_box = re.search(r'viewBox="([\d.\s-]+)"', attributes)
    if view_box is None:
        raise SystemExit(f"{LOGO_PATH} has no viewBox")
    _, _, width, height = (float(value) for value in view_box.group(1).split())
    return inner.strip(), width, height


LOGO_INNER, LOGO_WIDTH, LOGO_HEIGHT = _read_logo()


def _fmt(value: float) -> str:
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return text or "0"


def _icon_svg(
    size: int,
    logo_ratio: float,
    *,
    rounded: tuple[float, float] | None = None,
    circle: bool = False,
    transparent: bool = False,
    monochrome: bool = False,
) -> str:
    """Return a square SVG with the official logo centred on a brand canvas.

    ``rounded`` is ``(inset, radius)`` as fractions of the canvas.  ``circle``
    draws a circular background (used by Android's legacy round icon).
    """
    inner = LOGO_INNER
    if monochrome:
        inner = re.sub(r'fill="#[0-9a-fA-F]{6}"', f'fill="{BRAND_WHITE}"', inner)

    logo_width = size * logo_ratio
    scale = logo_width / LOGO_WIDTH
    logo_height = LOGO_HEIGHT * scale
    logo_x = (size - logo_width) / 2
    logo_y = (size - logo_height) / 2

    if transparent:
        background = ""
    elif circle:
        background = (
            f'<circle cx="{_fmt(size / 2)}" cy="{_fmt(size / 2)}" '
            f'r="{_fmt(size / 2)}" fill="{BRAND_DARK}"/>'
        )
    elif rounded is not None:
        inset, radius = rounded
        margin = size * inset
        background = (
            f'<rect x="{_fmt(margin)}" y="{_fmt(margin)}" '
            f'width="{_fmt(size - margin * 2)}" height="{_fmt(size - margin * 2)}" '
            f'rx="{_fmt(size * radius)}" fill="{BRAND_DARK}"/>'
        )
    else:
        background = f'<rect width="{size}" height="{size}" fill="{BRAND_DARK}"/>'

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}" shape-rendering="crispEdges">'
        f"{background}"
        f'<g transform="translate({_fmt(logo_x)} {_fmt(logo_y)}) scale({_fmt(scale)})">'
        f"{inner}"
        "</g></svg>"
    )


def _render(svg: str, size: int) -> Image.Image:
    return _render_canvas(svg, size, size)


def _render_canvas(svg: str, width: int, height: int) -> Image.Image:
    with tempfile.TemporaryDirectory(prefix="sinsajo-icon-") as directory:
        svg_path = Path(directory) / "icon.svg"
        png_path = Path(directory) / "icon.png"
        svg_path.write_text(svg, encoding="utf-8")
        subprocess.run(
            [
                "rsvg-convert",
                "-w",
                str(width),
                "-h",
                str(height),
                "-o",
                str(png_path),
                str(svg_path),
            ],
            check=True,
        )
        with Image.open(png_path) as image:
            return image.convert("RGBA")


def _render_logo(width: int) -> Image.Image:
    """Render the transparent logo at exactly ``width`` pixels wide."""
    height = round(LOGO_HEIGHT / LOGO_WIDTH * width)
    scale = width / LOGO_WIDTH
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" shape-rendering="crispEdges">'
        f'<g transform="scale({_fmt(scale)})">{LOGO_INNER}</g>'
        "</svg>"
    )
    return _render_canvas(svg, width, height)


def _save_png(image: Image.Image, path: Path, *, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        image = image.convert("RGB")
    image.save(path, format="PNG", optimize=True)


def _pixel_size(entry: dict) -> int:
    width = float(entry["size"].split("x")[0])
    scale = int(entry["scale"].rstrip("x"))
    return round(width * scale)


def _generate_android() -> None:
    res = ROOT / "android" / "app" / "src" / "main" / "res"

    for density, size in ANDROID_DENSITIES.items():
        legacy = _render(_icon_svg(size, ANDROID_LEGACY_RATIO), size)
        _save_png(legacy, res / f"mipmap-{density}" / "ic_launcher.png")

        round_icon = _render(_icon_svg(size, ANDROID_ROUND_RATIO, circle=True), size)
        _save_png(round_icon, res / f"mipmap-{density}" / "ic_launcher_round.png")

    # Adaptive foreground/monochrome are vectors, so they stay crisp at every
    # density and are tinted correctly by Android 13+ themed icons.
    rects = re.findall(r"<rect\b([^>]*)/>", LOGO_INNER)
    parsed = []
    for attributes in rects:
        values = dict(re.findall(r'(\w+)="([^"]*)"', attributes))
        parsed.append(values)

    def rect_path(values: dict) -> str:
        x, y = float(values["x"]), float(values["y"])
        width, height = float(values["width"]), float(values["height"])
        return (
            f"M{_fmt(x)},{_fmt(y)}"
            f"h{_fmt(width)}v{_fmt(height)}h{_fmt(-width)}z"
        )

    orange_path = " ".join(rect_path(value) for value in parsed if value.get("fill", "").upper() == BRAND_ORANGE)
    white_path = " ".join(rect_path(value) for value in parsed if value.get("fill", "").upper() == BRAND_WHITE)
    monochrome_path = " ".join(rect_path(value) for value in parsed)

    scale = ADAPTIVE_FOREGROUND_RATIO * 108 / LOGO_WIDTH
    logo_width = LOGO_WIDTH * scale
    logo_height = LOGO_HEIGHT * scale
    translate_x = (108 - logo_width) / 2
    translate_y = (108 - logo_height) / 2
    group = (
        f'<group android:translateX="{_fmt(translate_x)}" '
        f'android:translateY="{_fmt(translate_y)}" '
        f'android:scaleX="{_fmt(scale)}" android:scaleY="{_fmt(scale)}">'
    )

    drawable = res / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    (drawable / "ic_launcher_foreground.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n'
        '    android:height="108dp"\n'
        '    android:viewportWidth="108"\n'
        '    android:viewportHeight="108">\n'
        f"    {group}\n"
        f'        <path android:fillColor="{BRAND_ORANGE}" android:pathData="{orange_path}"/>\n'
        f'        <path android:fillColor="{BRAND_WHITE}" android:pathData="{white_path}"/>\n'
        "    </group>\n"
        "</vector>\n",
        encoding="utf-8",
    )
    (drawable / "ic_launcher_monochrome.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n'
        '    android:height="108dp"\n'
        '    android:viewportWidth="108"\n'
        '    android:viewportHeight="108">\n'
        f"    {group}\n"
        f'        <path android:fillColor="{BRAND_WHITE}" android:pathData="{monochrome_path}"/>\n'
        "    </group>\n"
        "</vector>\n",
        encoding="utf-8",
    )

    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    adaptive_monochrome = adaptive.replace(
        "</adaptive-icon>",
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n</adaptive-icon>',
    )
    for qualifier, body in (("mipmap-anydpi-v26", adaptive), ("mipmap-anydpi-v33", adaptive_monochrome)):
        directory = res / qualifier
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "ic_launcher.xml").write_text(body, encoding="utf-8")
        (directory / "ic_launcher_round.xml").write_text(body, encoding="utf-8")

    (res / "values" / "colors.xml").parent.mkdir(parents=True, exist_ok=True)
    (res / "values" / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{BRAND_DARK}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )


def _generate_ios() -> None:
    app_icon_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((app_icon_dir / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents["images"]:
        size = _pixel_size(entry)
        image = _render(_icon_svg(size, IOS_RATIO), size)
        _save_png(image, app_icon_dir / entry["filename"], opaque=True)


def _generate_launch_images() -> None:
    # iOS launch storyboard: one transparent logo per scale.
    launch_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    for scale in (1, 2, 3):
        width = 168 * scale
        image = _render_logo(width)
        filename = "LaunchImage.png" if scale == 1 else f"LaunchImage@{scale}x.png"
        _save_png(image, launch_dir / filename)

    # Android pre-12 splash: one transparent logo per density (160dp wide).
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for density, scale in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
        width = round(160 * scale)
        _save_png(_render_logo(width), res / f"drawable-{density}" / "launch_image.png")


def _generate_macos() -> None:
    app_icon_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((app_icon_dir / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents["images"]:
        size = _pixel_size(entry)
        image = _render(
            _icon_svg(size, MACOS_RATIO, rounded=(100 / 1024, 185 / 1024)),
            size,
        )
        _save_png(image, app_icon_dir / entry["filename"])


def _generate_windows() -> None:
    icon_path = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    master = _render(
        _icon_svg(1024, WINDOWS_RATIO, rounded=(0, 200 / 1024)),
        1024,
    )
    icon_path.parent.mkdir(parents=True, exist_ok=True)
    master.save(icon_path, format="ICO", sizes=WINDOWS_ICO_SIZES)


def _generate_linux() -> None:
    icon = _render(_icon_svg(512, LINUX_RATIO), 512)
    _save_png(icon, ROOT / "linux" / "runner" / "resources" / "sinsajo.png")


def _generate_web() -> None:
    icons = ROOT / "web" / "icons"
    for size in (192, 512):
        full = _render(_icon_svg(size, WEB_RATIO), size)
        _save_png(full, icons / f"Icon-{size}.png")

        maskable = _render(_icon_svg(size, WEB_MASKABLE_RATIO), size)
        _save_png(maskable, icons / f"Icon-maskable-{size}.png")

    _save_png(_render(_icon_svg(180, WEB_RATIO), 180), icons / "apple-touch-icon.png")


def main() -> None:
    _require_tools()
    _generate_android()
    _generate_ios()
    _generate_launch_images()
    _generate_macos()
    _generate_windows()
    _generate_linux()
    _generate_web()
    print("Generated Android, iOS, macOS, Windows, Linux and Web icons from web/sinsajo.svg")


if __name__ == "__main__":
    main()
