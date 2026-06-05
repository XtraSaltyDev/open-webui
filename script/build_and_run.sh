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

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "OpenWebUINative packaging is only supported on macOS." >&2
    exit 2
  fi
}

package_app() {
  swift build
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$INFO_PLIST_TEMPLATE" "$INFO_PLIST"
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
}

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

smoke_test() {
  require_macos
  echo "Running smoke validation on macOS..."
  swift test
  swift build
  package_app
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
  # verify the packaged app binary exists
  if [[ ! -x "$APP_BINARY" ]]; then
    echo "Packaged app binary missing: $APP_BINARY" >&2
    exit 1
  fi
  if [[ -x /usr/bin/codesign ]]; then
    sign_app
    validate_package
  fi
  echo "$APP_BUNDLE"
}

require_macos

case "$MODE" in
  --smoke|smoke)
    smoke_test
    ;;
  --package|package)
    package_app
    echo "$APP_BUNDLE"
    ;;
  --sign|sign)
    package_app
    sign_app
    echo "$APP_BUNDLE"
    ;;
  --validate-package|validate-package)
    package_app
    sign_app
    validate_package
    echo "$APP_BUNDLE"
    ;;
  run)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    package_app
    open_app
    ;;
  --debug|debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    package_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    package_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    package_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"dev.xtrasalty.OpenWebUINative\""
    ;;
  --verify|verify)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    package_app
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--sign|--validate-package|--smoke|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
