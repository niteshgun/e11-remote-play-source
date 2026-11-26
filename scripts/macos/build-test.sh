#!/usr/bin/env bash
# e11: build the current version into build-test/ (separate from build/) and open it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BREW="$(brew --prefix)"
cd "$ROOT"
cmake -S . -B build-test -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DCHIAKI_ENABLE_CLI=OFF -DCHIAKI_ENABLE_TESTS=OFF -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF \
	-DOPENSSL_ROOT_DIR="$BREW/opt/openssl@3" \
	-DCMAKE_PREFIX_PATH="$ROOT/../deps;$BREW/opt/openssl@3;$BREW/opt/qt@6;$BREW/opt/protobuf@29"
CPATH="$BREW/opt/ffmpeg/include" cmake --build build-test --config Release --target chiaki
echo
echo "Built: $ROOT/build-test/gui/e11remoteplay.app"
open "$ROOT/build-test/gui/e11remoteplay.app"
