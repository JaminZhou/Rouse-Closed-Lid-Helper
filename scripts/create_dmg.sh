#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/Helper.app /path/to/output.dmg" >&2
  exit 64
fi

app_path=$1
dmg_path=$2

[[ -d "$app_path" ]] || { echo "app not found: $app_path" >&2; exit 66; }
[[ "$dmg_path" == *.dmg ]] || { echo "output must end in .dmg" >&2; exit 64; }

staging_dir=$(mktemp -d /tmp/rouse-helper-dmg.XXXXXX)
trap 'rm -rf "$staging_dir"' EXIT

ditto "$app_path" "$staging_dir/${app_path:t}"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "${dmg_path:h}"
rm -f "$dmg_path"

hdiutil create \
  -volname "Rouse Closed-Lid Helper" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$dmg_path"

identity=${DEVELOPER_ID_APPLICATION:-}
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)"/\1/p' | head -1)
fi
[[ -n "$identity" ]] || { echo "Developer ID Application identity not found" >&2; exit 69; }
codesign --force --timestamp --sign "$identity" "$dmg_path"

