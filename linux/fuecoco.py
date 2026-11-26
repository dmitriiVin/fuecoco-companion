#!/usr/bin/python3
import argparse
import ctypes as c
from pathlib import Path
import signal
import sys
import time

from PyQt6.QtCore import QLockFile, QSettings, QStandardPaths, Qt, QTimer
from PyQt6.QtGui import QActionGroup, QIcon, QPainter, QPixmap
from PyQt6.QtWidgets import QApplication, QMenu, QSystemTrayIcon, QWidget

ROOT = Path(__file__).resolve().parent
CORNERS = {"bottom-left": "Слева внизу", "bottom-right": "Справа внизу",
           "top-left": "Слева вверху", "top-right": "Справа вверху"}


class Frame(c.Structure):
    _fields_ = [("group", c.c_char_p), ("index", c.c_int), ("dx", c.c_double), ("dy", c.c_double)]


class Build(c.Structure):
    _fields_ = [("building", c.c_bool), ("failed", c.c_bool)]


def load_core():
    lib = c.CDLL(str(ROOT / "libfuecoco.so"))
    lib.fc_create.restype = c.c_void_p
    for command in (lib.fc_destroy, lib.fc_wave, lib.fc_dash, lib.fc_sneeze, lib.fc_hearts):
        command.argtypes = [c.c_void_p]
        command.restype = None
    lib.fc_step.argtypes = [c.c_void_p, c.c_double] + [c.c_bool] * 4
    lib.fc_step.restype = Frame
    lib.fc_sample_build.restype = Build
    return lib


class Pet(QWidget):
    def __init__(self, app, corner, reduced):
        flags = (Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint |
                 Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.WindowTransparentForInput |
                 Qt.WindowType.WindowDoesNotAcceptFocus)
        super().__init__(None, flags)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setWindowTitle("Фуэкоко")
        self.setFixedSize(260, 176)
        self.core = load_core()
        self.pet = self.core.fc_create()
        if not self.pet:
            raise MemoryError("Cannot initialize Fuecoco")
        app.aboutToQuit.connect(lambda: self.core.fc_destroy(self.pet))
        self.settings = QSettings("Fuecoco", "Companion")
        self.corner = corner or self.settings.value("corner", "bottom-left")
        self.reduced = reduced
        self.images = {p.stem.encode(): QPixmap(str(p)) for p in (ROOT / "assets").glob("*.png")}
        self.frame = None
        self.build = Build()
        self.next_poll = 0
        self.menu = QMenu()
        self.gestures = self.menu.addMenu("Анимации")
        for label, command in [("Помахать лапой", self.core.fc_wave), ("Пробежаться", self.core.fc_dash),
                               ("Чихнуть", self.core.fc_sneeze), ("Пустить сердечки", self.core.fc_hearts)]:
            action = self.gestures.addAction(label)
            action.triggered.connect(lambda checked=False, play=command: play(self.pet))
            if command == self.core.fc_dash:
                action.setEnabled(not self.reduced)
        self.menu.addSeparator()
        self.choices = QActionGroup(self)
        for key, label in CORNERS.items():
            action = self.menu.addAction(label)
            action.setCheckable(True)
            self.choices.addAction(action)
            action.setChecked(key == self.corner)
            action.triggered.connect(lambda _, k=key: self.set_corner(k))
        self.menu.addSeparator()
        self.menu.addAction("Закрыть Фуэкоко").triggered.connect(app.quit)
        self.tray = QSystemTrayIcon(QIcon(self.images[b"idle-0"]), self)
        self.tray.setContextMenu(self.menu)
        self.tray.show()
        app.primaryScreenChanged.connect(self.place)
        for screen in app.screens():
            screen.availableGeometryChanged.connect(self.place)
        self.place()
        self.tick()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(100)

    def set_corner(self, corner):
        self.corner = corner
        self.settings.setValue("corner", corner)
        self.place()

    def place(self, *_):
        screen = QApplication.primaryScreen()
        if screen is None:
            return
        area = screen.availableGeometry()
        x = area.right() - self.width() - 7 if self.corner.endswith("right") else area.left() + 8
        y = area.bottom() - self.height() - 7 if self.corner.startswith("bottom") else area.top() + 8
        self.move(x, y)

    def tick(self):
        now = time.monotonic()
        if now >= self.next_poll:
            self.next_poll = now + 2
            self.build = self.core.fc_sample_build()
            self.tray.setToolTip("Фуэкоко · идёт сборка" if self.build.building else "Фуэкоко")
            self.gestures.setEnabled(not (self.build.building or self.build.failed))
        self.frame = self.core.fc_step(self.pet, now, self.build.building, self.build.failed,
                                       self.corner.endswith("right"), self.reduced)
        self.update()

    def paintEvent(self, event):
        key = self.frame.group + b"-" + str(self.frame.index).encode()
        painter = QPainter(self)
        painter.drawPixmap(round((self.width() - 144) / 2 + self.frame.dx),
                           self.height() - 156 - round(self.frame.dy), 144, 156, self.images[key])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corner", choices=CORNERS)
    parser.add_argument("--reduce-motion", action="store_true")
    args = parser.parse_args()
    app = QApplication([sys.argv[0]])
    app.setQuitOnLastWindowClosed(False)
    runtime = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.RuntimeLocation)
    lock = QLockFile(str(Path(runtime) / "fuecoco-companion.lock"))
    if not lock.tryLock(0):
        print("Фуэкоко уже запущен.", file=sys.stderr)
        return 1
    pet = Pet(app, args.corner, args.reduce_motion)
    pet.show()
    signal.signal(signal.SIGINT, lambda *_: app.quit())
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
