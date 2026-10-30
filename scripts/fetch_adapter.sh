#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/.build/deps"
SOURCE="$DEPS/mediaremote-adapter"
PIN="0e82bf1"
mkdir -p "$DEPS"
if [[ ! -d "$SOURCE/.git" ]]; then
  git clone https://github.com/ungive/mediaremote-adapter.git "$SOURCE"
fi
git -C "$SOURCE" checkout --detach "$PIN"
cmake -S "$SOURCE" -B "$SOURCE/build" -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build "$SOURCE/build" --config Release
[[ -d "$SOURCE/build/MediaRemoteAdapter.framework" ]] || { echo 'MediaRemoteAdapter.framework was not produced' >&2; exit 1; }
