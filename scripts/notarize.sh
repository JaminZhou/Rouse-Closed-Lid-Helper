#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Helper.app-or.dmg" >&2
  exit 64
fi

artifact=$1
[[ -e "$artifact" ]] || { echo "artifact not found: $artifact" >&2; exit 66; }
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH is required}"
[[ -f "$ASC_KEY_PATH" ]] || { echo "ASC_KEY_PATH does not point to a file" >&2; exit 66; }

submission=$artifact
temporary_dir=""
temporary_zip=""
trap '[[ -z "$temporary_zip" ]] || rm -f "$temporary_zip"; [[ -z "$temporary_dir" ]] || rmdir "$temporary_dir"' EXIT
if [[ "$artifact" == *.app ]]; then
  temporary_dir=$(mktemp -d /tmp/rouse-helper-notary.XXXXXX)
  temporary_zip="$temporary_dir/submission.zip"
  ditto -c -k --keepParent "$artifact" "$temporary_zip"
  submission=$temporary_zip
fi

xcrun notarytool submit "$submission" \
  --key "$ASC_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait

xcrun stapler staple "$artifact"
xcrun stapler validate "$artifact"
