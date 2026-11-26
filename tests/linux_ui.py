"""Render the installed widget and exercise its menu without a window manager."""
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import os
from pathlib import Path

from PyQt6.QtWidgets import QApplication
from PyQt6.QtCore import Qt

path = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "fuecoco-companion/fuecoco"
loader = SourceFileLoader("fuecoco", str(path))
companion = module_from_spec(spec_from_loader(loader.name, loader))
loader.exec_module(companion)
app = QApplication([])
pet = companion.Pet(app, "bottom-left", False)
pet.show()
app.processEvents()
for group, count in [("hearts", 11), ("sneeze", 8)]:
    assert all(f"{group}-{i}".encode() in pet.images for i in range(count))
assert all(not image.isNull() for image in pet.images.values())
assert pet.windowFlags() & Qt.WindowType.WindowStaysOnTopHint
assert pet.windowFlags() & Qt.WindowType.WindowTransparentForInput
a = pet.pos().x()
pet.set_corner("bottom-right")
assert pet.pos().x() > a
expected = {"Помахать лапой": b"wave", "Пробежаться": b"left",
            "Чихнуть": b"sneeze", "Пустить сердечки": b"hearts"}
for action in pet.gestures.actions():
    action.trigger()
    pet.tick()
    assert pet.frame.group == expected.pop(action.text())
assert not expected
snapshot = pet.grab().toImage()
assert any(snapshot.pixelColor(x,y).alpha() for x in range(0,snapshot.width(),6)
           for y in range(0,snapshot.height(),6))
print("Installed Linux widget rendered, changed corner and played all four gestures")
