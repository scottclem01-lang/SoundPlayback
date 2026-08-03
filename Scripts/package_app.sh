#!/usr/bin/env bash
# Build a release SoundPlayback.app and an installable DMG.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SoundPlayback"
BUNDLE_ID="com.scottclem.SoundPlayback"
VERSION="${VERSION:-1.0.2}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGE_DIR="${DIST_DIR}/dmg-stage"

cd "${ROOT_DIR}"

echo "==> Building release binary…"
swift build -c release --product "${APP_NAME}"

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN}" ]]; then
  echo "ERROR: binary not found at ${BIN}" >&2
  exit 1
fi

echo "==> Assembling ${APP_NAME}.app…"
rm -rf "${APP_BUNDLE}" "${STAGE_DIR}" "${DMG_PATH}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>Sound Playback</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.music</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

cp "${BIN}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "==> Ad-hoc code signing…"
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --verbose=2 "${APP_BUNDLE}"

echo "==> Creating DMG…"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_BUNDLE}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}"

rm -rf "${STAGE_DIR}"

echo
echo "Done."
echo "  App:  ${APP_BUNDLE}"
echo "  DMG:  ${DMG_PATH}"
echo
echo "Install: open the DMG and drag SoundPlayback into Applications."
echo "First launch: right-click → Open if Gatekeeper blocks an unsigned local build."
