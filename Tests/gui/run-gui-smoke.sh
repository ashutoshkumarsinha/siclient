#!/usr/bin/env bash
# GUI smoke checks — verifies the SwiftUI lab app builds and ViewModel tests pass.
# Full UI automation (XCUITest) requires Xcode; CI uses ViewModel + CLI subprocess tests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "== SICLient GUI smoke =="

echo "[1/3] Build CLI + GUI targets"
swift build --product siclient --product siclient-gui

echo "[2/3] Verify GUI binary exists"
test -x .build/debug/siclient-gui

echo "[3/3] Run GUI/CLI integration tests"
swift test --filter SICLientGUITests

echo "GUI smoke complete"
