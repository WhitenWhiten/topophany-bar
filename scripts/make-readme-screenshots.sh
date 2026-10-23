#!/bin/bash
# Render the README illustrations from native SwiftUI views and synthetic fixtures.
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

# Rendered name, then the README's.
images=(
    readme-hero.png:hero.png
    readme-menu-bar.png:menu-bar.png
    readme-white-night.gif:white-night.gif
    readme-direct.png:direct-sources.png
    readme-themes.png:themes.png
    readme-widgets.png:widget-gallery.png
)

# Isolated output prevents a failed render from publishing stale snapshots.
# These render cases use fixed English demo data, without launching the app.
TOPOPHANY_SNAPSHOT_DIR="$render_dir" xcrun swift test --filter ReadmeSnapshots
for pair in "${images[@]}"; do
    if [[ ! -s "$render_dir/${pair%%:*}" ]]; then
        printf 'Error: renderer did not produce %s; existing images were not changed.\n' "${pair%%:*}" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"
printf 'Generated:\n'
for pair in "${images[@]}"; do
    cp "$render_dir/${pair%%:*}" "$output_dir/${pair#*:}"
    printf '  %s/%s\n' "$output_dir" "${pair#*:}"
done
