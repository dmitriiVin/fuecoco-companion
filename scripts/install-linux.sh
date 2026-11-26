#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
share=${XDG_DATA_HOME:-"$HOME/.local/share"}
dest="$share/fuecoco-companion"
bin="$HOME/.local/bin"
mkdir -p "$share" "$bin" "$share/applications"
stage=$(mktemp -d "$share/.fuecoco-XXXXXX")
trap 'rm -rf "$stage"' EXIT
/usr/bin/python3 -c 'from PyQt6.QtWidgets import QApplication; from PIL import Image'
/usr/bin/python3 "$root/scripts/assets.py" "$stage/assets" "$@"
cc -shared -fPIC -O2 "$root/shared/build.c" "$root/shared/motion.c" -lm -o "$stage/libfuecoco.so"
install -m 755 "$root/linux/fuecoco.py" "$stage/fuecoco"
mkdir -p "$dest"
cp -R "$stage/assets" "$dest/"
install -m 755 "$stage/fuecoco" "$dest/fuecoco"
mv "$stage/libfuecoco.so" "$dest/libfuecoco.so"
ln -sfn "$dest/fuecoco" "$bin/fuecoco"
install -m 755 "$root/scripts/fuecoco-build" "$bin/fuecoco-build"
/usr/bin/python3 - "$dest" "$share/applications/fuecoco.desktop" <<'PY'
from pathlib import Path
import sys
dest = Path(sys.argv[1])
# Desktop Entry Exec has its own argument quoting and field-code expansion.
exe = str(dest / "fuecoco").replace('\\', '\\\\\\\\').replace('"', '\\\\"').replace('`', '\\\\`').replace('$', '\\\\$').replace('%', '%%')
Path(sys.argv[2]).write_text(f'''[Desktop Entry]
Type=Application
Name=Fuecoco
Name[ru]=Фуэкоко
Comment=Animated desktop companion
Exec="{exe}"
Icon={dest}/assets/idle-0.png
Terminal=false
Categories=Utility;
''', encoding="utf-8")
PY
echo "Фуэкоко установлен. Запуск: $bin/fuecoco"
