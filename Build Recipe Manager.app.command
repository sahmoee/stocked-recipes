#!/bin/bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="RecipeManager"; SRC="$DIR/$APP_NAME.swift"; APP="$DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"; MACOS="$CONTENTS/MacOS"; RES="$CONTENTS/Resources"; BIN="$MACOS/$APP_NAME"
BUNDLE_ID="com.sowens.recipemanager"
echo "Recipe Manager — app builder"; echo "============================"
[ -f "$SRC" ] || { echo "Keep this next to $APP_NAME.swift."; exit 1; }
if ! xcrun --find swiftc >/dev/null 2>&1; then echo "Installing Command Line Tools…"; xcode-select --install 2>/dev/null; exit 1; fi
echo "Compiling (release)…"; rm -rf "$APP"; mkdir -p "$MACOS" "$RES"
if ! xcrun swiftc -O -parse-as-library "$SRC" -o "$BIN" 2>"$DIR/build.log"; then
  echo "Build failed:"; cat "$DIR/build.log"; echo; echo "Send the errors to Claude."; exit 1; fi
rm -f "$DIR/build.log"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Recipe Manager</string>
  <key>CFBundleDisplayName</key><string>Recipe Manager</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>CFBundleShortVersionString</key><string>1.3</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo -n 'APPL' > "$CONTENTS/PkgInfo"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 && echo "Signed." || echo "Signing skipped."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo; echo "Built: $APP"
printf "Install to /Applications now? [y/N] "; read -r A
case "$A" in y|Y|yes|YES) D="/Applications/$APP_NAME.app"; rm -rf "$D"; cp -R "$APP" "$D" 2>/dev/null && { xattr -dr com.apple.quarantine "$D" 2>/dev/null||true; echo "Installed."; open "$D"; } || { echo "Drag it to /Applications manually."; open -R "$APP"; } ;; *) open -R "$APP" ;; esac
echo "Done."
