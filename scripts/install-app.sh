#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
scripts/build-app.sh

install_dir=${CHIZU_INSTALL_DIR:-"$HOME/Applications"}
mkdir -p "$install_dir"
destination=$install_dir/Chizu.app
ditto dist/Chizu.app "$destination"
codesign --verify --strict "$destination"

register=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$register" -f "$destination"
printf 'Installed %s\n' "$destination"
printf 'Run %s/Contents/MacOS/chizu default-status to inspect the current browser.\n' "$destination"
