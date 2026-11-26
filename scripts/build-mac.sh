#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
out="$root/build"
app="$out/Fuecoco.app/Contents"
mkdir -p "$app/Resources" "$app/MacOS"
python3 "$root/scripts/assets.py" "$app/Resources" --mac-icon "$@"
python3 "$root/scripts/growl.py" "$app/Resources/growl.wav"
cp "$root/scripts/fuecoco-build" "$app/Resources/"
cp "$root/macos/Info.plist" "$app/Info.plist"
for src in build motion; do
    xcrun clang -O2 -mmacosx-version-min=13.0 -c "$root/shared/$src.c" -o "$out/$src.o"
done
xcrun swiftc -O -target "$(uname -m)-apple-macos13.0" -import-objc-header "$root/shared/fuecoco.h" \
    "$root"/macos/*.swift "$out/build.o" "$out/motion.o" -o "$app/MacOS/Fuecoco"
codesign --force --sign - "$out/Fuecoco.app"
codesign --verify --strict "$out/Fuecoco.app"
