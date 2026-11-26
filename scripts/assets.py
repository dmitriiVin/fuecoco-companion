"""Prepare the original pixel art for the desktop companion and optional Codex pet."""
import argparse
import hashlib
import io
import json
from pathlib import Path
from urllib.request import urlopen

from PIL import Image, ImageOps

URL = "https://petscodex.com/pet-image.php?pet=fuecoco&image=spritesheet.webp&v=24e6c1aaca7f0a75"
SHA256 = "512495104b22e0df692c2fb205e1d941d30bd94f06ab459048f4081e7102b800"

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("--sheet", type=Path, help="Local copy of the original WebP")
parser.add_argument("--mac-icon", action="store_true")
parser.add_argument("--codex", type=Path, help="Also generate a standalone Codex pet package")
args = parser.parse_args()
if args.sheet:
    data = args.sheet.read_bytes()
else:
    with urlopen(URL, timeout=30) as response:
        data = response.read()
if hashlib.sha256(data).hexdigest() != SHA256:
    raise SystemExit("Unexpected sprite sheet checksum. Check the upstream artwork before updating.")
sheet = Image.open(io.BytesIO(data)).convert("RGBA")
assert sheet.size == (1536, 1872)

def cell(row, col):
    return sheet.crop((192 * col, 208 * row, 192 * (col + 1), 208 * (row + 1)))

args.output.mkdir(parents=True, exist_ok=True)
for group, row, count in [
    ("idle",0,6), ("left",1,8), ("right",2,8), ("hop",4,5),
    ("flame",5,8), ("sleep",6,6), ("tears",7,6), ("rare",8,6),
]:
    for index in range(count):
        cell(row, index).save(args.output / f"{group}-{index}.png")
for i, frame in enumerate([cell(0,0), cell(3,1), cell(3,0)]):
    frame.save(args.output / f"wave-{i}.png")
for i, frame in enumerate([cell(0,0), cell(3,2), ImageOps.mirror(cell(3,2))]):
    frame.save(args.output / f"look-{i}.png")

if args.mac_icon:
    icon = cell(0,0)
    icon.thumbnail((180,180))
    canvas = Image.new("RGBA", (208,208))
    canvas.alpha_composite(icon, ((208-icon.width)//2, (208-icon.height)//2))
    canvas.resize((1024,1024), Image.Resampling.NEAREST).save(args.output / "Fuecoco.icns")

if args.codex:
    args.codex.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", sheet.size)
    rows = [(0,range(6)),(2,range(8)),(1,range(8)),(3,range(4)),(4,range(5)),
            (7,[0,1,2,3,4,5,4,2]),(6,range(6)),(5,[0,3,4,5,6,7]),(8,range(6))]
    for dest, (row, frames) in enumerate(rows):
        for column, index in enumerate(frames):
            atlas.paste(cell(row,index), (column*192,dest*208))
    atlas.save(args.codex / "spritesheet.webp", lossless=True, exact=True)
    metadata = dict(id="fuecoco", displayName="Фуэкоко", description="Огненный Фуэкоко из Pets Codex.",
                    spritesheetPath="spritesheet.webp")
    (args.codex / "pet.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
