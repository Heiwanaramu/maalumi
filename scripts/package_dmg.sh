#!/usr/bin/env bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_ROOT"

echo "=== Building Maalumi (Release) ==="
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/Maalumi"

if [ ! -f "$BIN_PATH" ]; then
    echo "❌ Error: Maalumi binary not found at $BIN_PATH"
    exit 1
fi

APP_NAME="Maalumi"
APP_BUNDLE="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}.dmg"
DMG_STAGING="dist/dmg_staging"

echo "=== Packaging ${APP_NAME}.app ==="
rm -rf "dist"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "$BIN_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
if [ -f "Info.plist" ]; then
    cp "Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
elif [ -f "Resources/Info.plist" ]; then
    cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
fi

# Copy AppIcon.icns
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Copy SwiftPM resource bundles (e.g. MaalumiCore, SwiftyJSON)
for bundle in "$BIN_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        echo "   Bundling $(basename "$bundle")..."
        cp -R "$bundle" "${APP_BUNDLE}/Contents/Resources/"
    fi
done

# Write PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "=== Creating ${APP_NAME}.dmg ==="
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Add Applications symlink for drag-and-drop install
ln -s /Applications "$DMG_STAGING/Applications"

# Generate DMG using hdiutil
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo "=== Packaging Complete ==="
echo "Artifact: $DMG_PATH"
ls -lh "$DMG_PATH"
