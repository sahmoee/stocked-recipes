#!/bin/bash
# Launch Recipe Manager — compiles the SwiftUI app (first run) and opens it.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="RecipeManager"; SRC="$DIR/$APP_NAME.swift"
BUILD="$DIR/.build"; APP="$BUILD/$APP_NAME.app"; MACOS="$APP/Contents/MacOS"; BIN="$MACOS/$APP_NAME"
echo "Recipe Manager launcher"; echo "======================="
if ! xcrun --find swiftc >/dev/null 2>&1; then echo "Installing Command Line Tools…"; xcode-select --install 2>/dev/null; exit 1; fi
need_build=1; if [ -f "$BIN" ] && [ "$BIN" -nt "$SRC" ]; then need_build=0; fi
if [ "$need_build" -eq 1 ]; then
  echo "Building…"; mkdir -p "$MACOS" "$APP/Contents/Resources"
  if ! xcrun swiftc -O -parse-as-library "$SRC" -o "$BIN" 2>"$BUILD/build.log"; then
    echo "Build failed:"; cat "$BUILD/build.log"; echo; echo "Send the errors above to Claude."; exit 1; fi
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Recipe Manager</string>
  <key>CFBundleDisplayName</key><string>Recipe Manager</string>
  <key>CFBundleIdentifier</key><string>com.sowens.recipemanager</string>
  <key>CFBundleExecutable</key><string>RecipeManager</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
  echo -n 'APPL' > "$APP/Contents/PkgInfo"; echo "Built."
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "Opening…"; open "$APP"
