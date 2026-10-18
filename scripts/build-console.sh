#!/usr/bin/env sh
# Builds the console and copies it into the server's embed directory.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/console"
[ -d node_modules ] || npm ci
npm run build
dist="$root/server/internal/web/dist"
find "$dist" -mindepth 1 ! -name .gitkeep -exec rm -rf {} +
cp -R "$root/console/dist/." "$dist/"
echo "console copied to $dist"
