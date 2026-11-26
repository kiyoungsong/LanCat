#!/bin/bash
# LanCat 빌드 스크립트
#   ./build.sh              → build/LanCat.app 생성
#   ./build.sh --run        → 생성 후 바로 실행
#   ./build.sh --dmg        → build/LanCat.dmg 까지 생성 (배포용)
#
# 환경 변수
#   VERSION=1.2.0           → 앱 버전 (기본값: 아래 DEFAULT_VERSION)
#   UNIVERSAL=1             → Apple Silicon + Intel 유니버설 빌드 (Xcode 필요)
set -euo pipefail
cd "$(dirname "$0")"

DEFAULT_VERSION="1.0.0"
VERSION="${VERSION:-$DEFAULT_VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if ! command -v swift >/dev/null 2>&1; then
  echo "swift가 없어요. 'xcode-select --install'로 Command Line Tools를 먼저 설치해 주세요."
  exit 1
fi

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▶ 컴파일 중... (v$VERSION)"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/LanCat"

APP="build/LanCat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LanCat"
cp Resources/icon_*.png Resources/scene_*.png "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# 앱 아이콘 (.icns)
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LanCat</string>
  <key>CFBundleDisplayName</key><string>LanCat</string>
  <key>CFBundleIdentifier</key><string>com.kiyoung.lancat</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>ko</string><string>ja</string><string>zh-Hans</string></array>
  <key>CFBundleExecutable</key><string>LanCat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Kiyoung Song. MIT License.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "✔ 완료: $APP"

for arg in "$@"; do
  case "$arg" in
    --dmg)
      echo "▶ DMG 만드는 중..."
      DMG="build/LanCat.dmg"
      STAGE="build/dmg"
      rm -rf "$STAGE" "$DMG"
      mkdir -p "$STAGE"
      cp -R "$APP" "$STAGE/"
      ln -s /Applications "$STAGE/Applications"
      hdiutil create -volname "LanCat" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
      rm -rf "$STAGE"
      echo "✔ 완료: $DMG"
      ;;
    --run)
      pkill -x LanCat 2>/dev/null || true
      sleep 0.3
      open "$APP"
      echo "▶ 메뉴바를 확인해 보세요!"
      ;;
  esac
done
