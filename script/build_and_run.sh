#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OpenWebUINative"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INFO_PLIST_TEMPLATE="$ROOT_DIR/Resources/macOS/OpenWebUINative-Info.plist"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$INFO_PLIST_TEMPLATE" "$INFO_PLIST"
/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

sign_app() {
  /usr/bin/codesign --force --options runtime --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"
}

validate_package() {
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

case "$MODE" in
  --package|package)
    echo "$APP_BUNDLE"
    ;;
  --sign|sign)
    sign_app
    echo "$APP_BUNDLE"
    ;;
  --validate-package|validate-package)
    sign_app
    validate_package
    echo "$APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"dev.xtrasalty.OpenWebUINative\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--sign|--validate-package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
