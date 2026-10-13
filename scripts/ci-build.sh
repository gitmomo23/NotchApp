#!/bin/bash
# Release build for Notchling: XcodeGen, arm64, ad-hoc signature, DMG + ZIP.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode_26.6.app ]]; then
  sudo xcode-select -s /Applications/Xcode_26.6.app
elif [[ -d /Applications/Xcode.app ]]; then
  sudo xcode-select -s /Applications/Xcode.app
fi

echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
echo "macOS SDK: ${SDK_VERSION}"
SDK_MAJOR="${SDK_VERSION%%.*}"
if [[ "${SDK_MAJOR}" -lt 26 ]]; then
  echo "error: macOS 26 SDK required, found ${SDK_VERSION}" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
xcodegen generate --spec project.yml

DERIVED="${DERIVED_DATA_PATH:-${RUNNER_TEMP:-$ROOT/build}/DerivedData}"
rm -rf "$DERIVED"
xcodebuild \
  -project Notchling.xcodeproj \
  -scheme Notchling \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="$DERIVED/Build/Products/Release/Notchling.app"
if [[ ! -d "$APP" ]]; then
  echo "error: built app not found at $APP" >&2
  find "$DERIVED/Build/Products" -name '*.app' -print >&2 || true
  exit 1
fi

rm -rf dist
mkdir -p dist
cp -R "$APP" dist/Notchling.app
codesign -s - --force dist/Notchling.app
codesign --verify --verbose=2 dist/Notchling.app

INFO="dist/Notchling.app/Contents/Info.plist"
LSUI="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO")"
if [[ "$LSUI" != "true" ]]; then
  echo "error: LSUIElement is '$LSUI', expected true" >&2
  exit 1
fi
for KEY in NSCameraUsageDescription NSCalendarsUsageDescription NSCalendarsFullAccessUsageDescription NSAppleEventsUsageDescription; do
  VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$INFO")"
  if [[ -z "$VALUE" ]]; then
    echo "error: $KEY is empty" >&2
    exit 1
  fi
  echo "$KEY ok"
done
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")"
echo "LSMinimumSystemVersion=$MIN_OS"
case "$MIN_OS" in
  26*) ;;
  *)
    echo "error: expected deployment target 26, found $MIN_OS" >&2
    exit 1
    ;;
esac

BIN="dist/Notchling.app/Contents/MacOS/Notchling"
if ! file "$BIN" | grep -q arm64; then
  echo "error: binary is not arm64" >&2
  file "$BIN" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
cp -R dist/Notchling.app "$STAGE/Notchling.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Notchling" -srcfolder "$STAGE" -ov -format UDZO dist/Notchling.dmg
rm -rf "$STAGE"
ditto -c -k --keepParent dist/Notchling.app dist/Notchling.zip

echo "Packaged:"
ls -lh dist/Notchling.dmg dist/Notchling.zip
