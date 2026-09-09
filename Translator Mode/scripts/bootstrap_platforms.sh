#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v flutter >/dev/null || { echo "Flutter SDK is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

flutter create \
  --platforms=android \
  --org ai.eburon \
  --project-name matuk_translator_mode \
  "$TMP/matuk_translator_mode"

rm -rf "$ROOT/android"
cp -R "$TMP/matuk_translator_mode/android" "$ROOT/android"

python3 "$ROOT/scripts/apply_platform_config.py" "$ROOT"
cd "$ROOT"
flutter pub get
dart format lib test
# Compiler/analyzer errors and warnings remain fatal. Pure style/info lints do
# not block a release build; they are still printed in CI for cleanup.
flutter analyze --no-fatal-infos
flutter test

echo "Translator Mode Android bootstrap + static tests complete."
