#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.47.4"
FLUTTER_DIR="$(mktemp -d /tmp/anchor-flutter.XXXXXX)"

git clone \
  --depth 1 \
  --branch "$FLUTTER_VERSION" \
  https://github.com/flutter/flutter.git \
  "$FLUTTER_DIR"

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --no-analytics
flutter pub get

flutter build web --release \
  --dart-define=API_URL=https://anchor-api-nu7a.onrender.com