#!/usr/bin/env python3
"""Render the app icons in docs/app-icons/*.svg into the asset catalog and the bundle.

    python3 scripts/app-icons/render.py

Needs rsvg-convert (brew install librsvg) and Pillow. Lettering is in the SVGs as outlines
(Pirata One), so no fonts are needed. Writes:

- Assets.xcassets/AppIcon.appiconset: the crest, full-bleed for iPadOS and shaped for macOS
- Assets.xcassets/AppIcon-<Name>.appiconset: the other designs, iPadOS alternate icons

Each iPadOS icon comes in the Home Screen's three looks: light (the art), dark (the art without
its `<g id="background">`, so the hex `<g id="pattern">` lies on the system's dark gradient) and
tinted (the foreground alone, in grey, which iPadOS tints; its clear look is made from it too). `--preview out.png` draws every icon in
every look, to check them side by side.
- Resources/Images/app-icons/<id>.png (full-bleed, Settings' picker) and <id>-mac.png
  (shaped, the Dock icon while the game runs on a Mac)

The ids and names must match `AppIconChoice` and project.yml's
ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES (AppIconTests checks).
"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = ROOT / "docs/app-icons"
CATALOG = ROOT / "GlavenGame/Assets.xcassets"
IMAGES = ROOT / "GlavenGame/Resources/Images/app-icons"

PRIMARY = "crest"
# id → the alternate icon set's name (AppIconChoice.alternateIconName)
ALTERNATES = {
    "hex-blade": "AppIcon-HexBlade",
    "spectacles": "AppIcon-Spectacles",
    "critical": "AppIcon-Critical",
    "elements": "AppIcon-Elements",
}

# macOS icon grid: an 824 body with 185 corners on the 1024 canvas, a soft shadow below.
MAC_BODY, MAC_RADIUS = 824, 185
MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
# (point size, scale) → pixels, for Contents.json
MAC_SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def render(svg: pathlib.Path, size: int, leave_out: tuple = ()) -> Image.Image:
    """The art at a size, without the named groups (`background`, `pattern`)."""
    text = svg.read_text()
    for group in leave_out:
        text, found = re.subn(rf'<g id="{group}">.*?</g>\n?', "", text, flags=re.S)
        if not found and group == "background":
            sys.exit(f'{svg.name}: no <g id="background"> to leave out of the dark and tinted icons')
    with tempfile.NamedTemporaryFile(suffix=".svg", mode="w") as source, tempfile.NamedTemporaryFile(suffix=".png") as out:
        source.write(text)
        source.flush()
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", out.name, source.name], check=True)
        return Image.open(out.name).convert("RGBA")


def tinted(foreground: Image.Image) -> Image.Image:
    """The foreground's lightness on black, stretched to the full range with the middle tones
    darkened: iPadOS tints the light parts, so the gold and the white stand out of the fills."""
    alpha = foreground.split()[3]
    grey = foreground.convert("L")
    drawn = alpha.point(lambda a: 255 if a > 200 else 0)
    low = Image.composite(grey, Image.new("L", grey.size, 255), drawn).getextrema()[0]
    high = Image.composite(grey, Image.new("L", grey.size, 0), drawn).getextrema()[1]
    span = max(high - low, 1)
    grey = grey.point(lambda v: round(25 + 230 * (min(max(v - low, 0), span) / span) ** 1.5))
    flat = Image.new("L", foreground.size, 0)
    flat.paste(grey, mask=alpha)
    return flat.convert("RGB")


def opaque(image: Image.Image) -> Image.Image:
    """App Store icons may not have an alpha channel."""
    flat = Image.new("RGB", image.size, (0, 0, 0))
    flat.paste(image, mask=image.split()[3])
    return flat


def mac_shaped(svg: pathlib.Path) -> Image.Image:
    """The 1024 macOS icon: the art in a rounded square, inset, on a shadow."""
    supersample = 4
    body = render(svg, MAC_BODY)
    mask = Image.new("L", (MAC_BODY * supersample,) * 2, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, MAC_BODY * supersample - 1, MAC_BODY * supersample - 1],
                                           radius=MAC_RADIUS * supersample, fill=255)
    mask = mask.resize((MAC_BODY, MAC_BODY), Image.LANCZOS)

    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    inset = (1024 - MAC_BODY) // 2
    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (inset, inset + 12), mask)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
    body.putalpha(mask)
    canvas.alpha_composite(body, (inset, inset))
    return canvas


def write_set(name: str, entries: list, files: dict):
    folder = CATALOG / f"{name}.appiconset"
    folder.mkdir(exist_ok=True)
    for old in folder.glob("*.png"):
        old.unlink()
    for filename, image in files.items():
        image.save(folder / filename, optimize=True)
    contents = {"images": entries, "info": {"author": "xcode", "version": 1}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    IMAGES.mkdir(parents=True, exist_ok=True)
    looks = []
    for svg in sorted(SOURCES.glob("*.svg")):
        icon = svg.stem
        if icon != PRIMARY and icon not in ALTERNATES:
            sys.exit(f"{svg.name}: not the primary icon or an alternate — add it to ALTERNATES")
        full = render(svg, 1024)
        dark = render(svg, 1024, leave_out=("background",))
        foreground = render(svg, 1024, leave_out=("background", "pattern"))
        mac = mac_shaped(svg)
        opaque(full).resize((256, 256), Image.LANCZOS).save(IMAGES / f"{icon}.png", optimize=True)
        mac.resize((512, 512), Image.LANCZOS).save(IMAGES / f"{icon}-mac.png", optimize=True)

        ios_files = {"ios.png": opaque(full), "ios-dark.png": dark, "ios-tinted.png": tinted(foreground)}
        ios_entries = [{"filename": "ios.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
        for look in ("dark", "tinted"):
            ios_entries.append({"appearances": [{"appearance": "luminosity", "value": look}],
                                "filename": f"ios-{look}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})
        if icon == PRIMARY:
            files = dict(ios_files)
            files.update({f"mac-{s}.png": mac.resize((s, s), Image.LANCZOS) for s in MAC_SIZES})
            entries = ios_entries + [{"filename": f"mac-{pt * scale}.png", "idiom": "mac",
                                      "scale": f"{scale}x", "size": f"{pt}x{pt}"} for pt, scale in MAC_SLOTS]
            write_set("AppIcon", entries, files)
        else:
            write_set(ALTERNATES[icon], ios_entries, ios_files)
        looks.append((icon, full, dark, ios_files["ios-tinted.png"]))
        print(f"rendered {icon}")
    if "--preview" in sys.argv:
        preview(looks, pathlib.Path(sys.argv[sys.argv.index("--preview") + 1]))


def preview(looks, out: pathlib.Path):
    """Every icon in every look, roughly as the Home Screen draws them: light, dark (on the
    system's gradient), tinted in two colours, and clear (the tinted grey as frosted white)."""
    size, gap = 180, 28
    columns = ["Light", "Dark", "Tinted amber", "Tinted blue", "Clear"]
    sheet = Image.new("RGB", (gap + len(columns) * (size + gap), gap + len(looks) * (size + gap)), (58, 66, 84))
    mask = Image.new("L", (size * 4,) * 2, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=round(size * 4 * 0.2237), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    backdrop = Image.linear_gradient("L").resize((size, size)).point(lambda v: 58 - v * 30 // 255)
    backdrop = Image.merge("RGB", [backdrop] * 3)
    for row, (icon, full, dark, grey) in enumerate(looks):
        g = grey.convert("L").resize((size, size), Image.LANCZOS)
        cells = [full.convert("RGB").resize((size, size), Image.LANCZOS)]
        on_dark = backdrop.copy()
        on_dark.paste(dark.resize((size, size), Image.LANCZOS), mask=dark.resize((size, size), Image.LANCZOS).split()[3])
        cells.append(on_dark)
        for tint in ((255, 186, 60), (90, 170, 255)):
            cells.append(Image.merge("RGB", [g.point(lambda v, c=c: 16 + v * (c - 16) // 255) for c in tint]))
        glass = Image.new("RGB", (size, size), (110, 120, 140))
        glass.paste((255, 255, 255), mask=g.point(lambda v: 40 + v * 200 // 255))
        cells.append(glass)
        for column, cell in enumerate(cells):
            sheet.paste(cell, (gap + column * (size + gap), gap + row * (size + gap)), mask)
    sheet.save(out)
    print(f"preview: {out} (columns: {', '.join(columns)})")


if __name__ == "__main__":
    main()
