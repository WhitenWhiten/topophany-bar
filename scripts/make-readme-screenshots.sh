#!/bin/bash
# Render both README illustrations from native SwiftUI views and synthetic fixtures.
set -euo pipefail

usage() {
    printf 'Usage: %s [OUTPUT_DIR]\n' "$(basename "$0")"
    printf 'Defaults to docs/assets in this repository. Requires macOS 26+ and full Xcode.\n'
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    exit 0
fi
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi
if [[ $(uname -s) != Darwin ]]; then
    printf 'Error: native SwiftUI screenshot rendering requires macOS.\n' >&2
    exit 1
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output_dir=${1:-"$repo_root/docs/assets"}
case "$output_dir" in
    /*) ;;
    *) output_dir="$PWD/$output_dir" ;;
esac

if [[ -z ${DEVELOPER_DIR:-} ]]; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        export DEVELOPER_DIR="$(xcode-select -p)"
    fi
fi
if [[ ! -d "$DEVELOPER_DIR/Platforms/MacOSX.platform" ]]; then
    printf 'Error: set DEVELOPER_DIR to a full Xcode installation (Contents/Developer).\n' >&2
    exit 1
fi

render_dir=$(mktemp -d "${TMPDIR:-/tmp}/topophany-readme.XXXXXX")
trap 'rm -rf "$render_dir"' EXIT
cd "$repo_root"

# Isolated output prevents a failed render from publishing stale snapshots.
# These two render cases use fixed English demo data, without launching the app.
TOPOPHANY_SNAPSHOT_DIR="$render_dir" xcrun swift test --filter ReadmeSnapshots
for name in readme-panels readme-widgets; do
    if [[ ! -s "$render_dir/$name.png" ]]; then
        printf 'Error: renderer did not produce %s.png; existing images were not changed.\n' "$name" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"
cp "$render_dir/readme-panels.png" "$output_dir/panel-columns.png"
cp "$render_dir/readme-widgets.png" "$output_dir/widget-gallery.png"
printf 'Generated:\n  %s/panel-columns.png\n  %s/widget-gallery.png\n' "$output_dir" "$output_dir"
