#!/bin/bash
# Bundle TrueshiftBar as a macOS .app and install to /Applications

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="TrueshiftBar"
BUNDLE_ID="io.github.aaqifz.TrueshiftBar"
APP_BUNDLE="$APP_NAME.app"
INSTALL_DIR="/Applications"

cd "$PROJECT_DIR"

echo "Building TrueshiftBar..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable and ad-hoc sign (required for private framework access)
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>TrueshiftBar</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Installing to $INSTALL_DIR..."
# Remove old version if exists
if [ -d "$INSTALL_DIR/$APP_BUNDLE" ]; then
    rm -rf "$INSTALL_DIR/$APP_BUNDLE"
fi

# Move to Applications
mv "$APP_BUNDLE" "$INSTALL_DIR/"

echo "Done! TrueshiftBar installed to $INSTALL_DIR/$APP_BUNDLE"
echo ""
echo "You can now:"
echo "  - Find 'TrueshiftBar' in Raycast"
echo "  - Launch from Spotlight"
echo "  - Find it in /Applications"
