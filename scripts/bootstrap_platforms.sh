#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v flutter >/dev/null || { echo "Flutter SDK is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

flutter create \
  --platforms=android,ios \
  --org ai.eburon \
  --project-name gemma_voice_assistant \
  "$TMP/gemma_voice_assistant"

rm -rf "$ROOT/android" "$ROOT/ios"
cp -R "$TMP/gemma_voice_assistant/android" "$ROOT/android"
cp -R "$TMP/gemma_voice_assistant/ios" "$ROOT/ios"

python3 "$ROOT/scripts/apply_platform_config.py" "$ROOT"
cd "$ROOT"
flutter pub get
dart format lib test
flutter analyze
flutter test

echo "Platform bootstrap + static tests complete."
