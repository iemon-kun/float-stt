#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="FloatSTT"
BUNDLE_ID="com.example.floatstt"
CONFIG="${1:-release}"

BUILD_DIR=".build/${CONFIG}"
BIN_PATH="${BUILD_DIR}/${APP_NAME}"

echo "Building (${CONFIG})..."
swift build -c "${CONFIG}"

if [[ ! -f "${BIN_PATH}" ]]; then
  echo "Binary not found: ${BIN_PATH}" >&2
  exit 1
fi

OUT_DIR="dist"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RES_DIR="${CONTENTS_DIR}/Resources"
ICON_SRC="${ROOT_DIR}/nano-banana/AppIcon.icns"
STATUS_ICON_SRC="${ROOT_DIR}/nano-banana/menu_icon_trim.png"

echo "Creating app bundle: ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

INFO_PLIST_TMP="${RES_DIR}/Info.plist"
cat > "${INFO_PLIST_TMP}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>音声入力のためにマイクを使用します。</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>音声を文字起こしするために音声認識を使用します。</string>
<key>NSHighResolutionCapable</key>
<true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
EOF

cp "${INFO_PLIST_TMP}" "${CONTENTS_DIR}/Info.plist"
rm -f "${INFO_PLIST_TMP}"

if [[ -f "${ICON_SRC}" ]]; then
  cp "${ICON_SRC}" "${RES_DIR}/AppIcon.icns"
fi

if [[ -f "${STATUS_ICON_SRC}" ]]; then
  cp "${STATUS_ICON_SRC}" "${RES_DIR}/StatusIcon.png"
fi

echo "Ad-hoc codesign..."
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "Done:"
echo "  ${APP_DIR}"
echo ""
echo "To run: open ${APP_DIR}"
