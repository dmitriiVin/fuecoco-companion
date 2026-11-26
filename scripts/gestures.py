"""Render the desktop gestures from the same atlas poses as the other animations."""
from PIL import Image, ImageColor

HEART = (
    ".oo.oo.",
    "ohhocco",
    "ohfccco",
    "ofcccco",
    ".ofcco.",
    "..oco..",
    "...o...",
)
HEART_COLORS = {"o": "#952542", "h": "#ffcece", "f": "#ff8798", "c": "#f34f78"}
PUFF = (
    "....ooo....",
    ".ooofffo...",
    "offffffoooo",
    "offfffffffo",
    ".osfffffsso",
    "..oossooos.",
    "....oo.....",
)
PUFF_COLORS = {"o": "#617d91", "f": "#fff8ea", "s": "#c1dbe2"}


def pixel_stamp(rows, colors):
    stamp = Image.new("RGBA", (len(rows[0]), len(rows)))
    for y, row in enumerate(rows):
        for x, color in enumerate(row):
            if color != ".":
                stamp.putpixel((x, y), ImageColor.getcolor(colors[color], "RGBA"))
    return stamp


def stamp_at(frame, stamp, x, y, width):
    height = max(1, round(width * stamp.height / stamp.width))
    pixels = stamp.resize((width, height), Image.Resampling.NEAREST)
    frame.alpha_composite(pixels, (x, y))


def render_gestures(cell, output):
    heart = pixel_stamp(HEART, HEART_COLORS)
    puff = pixel_stamp(PUFF, PUFF_COLORS)
    # Stagger the hearts so they rise past each other, one on each side of the face.
    for tick in range(11):
        frame = cell(0, 1 if 1 <= tick <= 8 else 0)
        for birth, x, y, drift in [(1, 142, 74, 2), (3, 27, 88, -2), (5, 154, 95, 2)]:
            age = tick - birth
            if 0 <= age < 6:
                size = (9, 17, 22, 20, 15, 9)[age]
                stamp_at(frame, heart, x + drift * age, y - 8 * age, size)
        frame.save(output / f"hearts-{tick}.png")

    calm = cell(8, 4).crop((24, 26, 154, 171))
    squint = cell(8, 1)
    # This atlas pose has separate floating hearts in the empty corner.
    squint.paste((0, 0, 0, 0), (137, 29, 171, 112))
    squint = squint.crop((24, 26, 154, 171))
    # Anchor both feet while the chest lifts, then compress the pose on the sneeze.
    poses = [
        (calm, 0, 0), (calm, 2, 3), (squint, 4, 6), (squint, 6, 7),
        (squint, -4, -12), (squint, -3, -8), (calm, -1, -3), (calm, 0, 0),
    ]
    clouds = {
        4: [(24, 102, 15)],
        5: [(11, 94, 23), (28, 113, 10)],
        6: [(4, 88, 18), (14, 117, 11), (25, 101, 7)],
        7: [(2, 83, 6), (9, 119, 4)],
    }
    for tick, (body, lean, stretch) in enumerate(poses):
        frame = Image.new("RGBA", (192, 208))
        height = body.height + stretch
        width = body.width - stretch // 3
        pixels = body.resize((width, height), Image.Resampling.NEAREST)
        frame.alpha_composite(pixels, (101 - width // 2 + lean, 179 - height))
        for x, y, size in clouds.get(tick, ()):
            stamp_at(frame, puff, x, y, size)
        frame.save(output / f"sneeze-{tick}.png")
