#!/bin/sh
# Builds Crate and wraps it as Crate.app in this folder. Run: ./make-app.sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Crate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Crate "$APP/Contents/MacOS/Crate"
cp -R Sounds "$APP/Contents/Resources/Sounds"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Crate</string>
  <key>CFBundleDisplayName</key><string>Crate</string>
  <key>CFBundleIdentifier</key><string>us.okeke.crate</string>
  <key>CFBundleExecutable</key><string>Crate</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Crate Project</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>us.okeke.crate.project</string></array>
  </dict></array>
  <key>UTExportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>us.okeke.crate.project</string>
    <key>UTTypeDescription</key><string>Crate Project</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.content</string></array>
    <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>crate</string></array></dict>
  </dict></array>
</dict>
</plist>
PLIST
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "Built $(pwd)/$APP"
