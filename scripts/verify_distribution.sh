#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/Helper.app /path/to/Helper.dmg" >&2
  exit 64
fi

app_path=$1
dmg_path=$2
app_executable="$app_path/Contents/MacOS/Rouse Closed-Lid Helper"
daemon_path="$app_path/Contents/Library/HelperTools/RouseClosedLidDaemon"
plist_path="$app_path/Contents/Library/LaunchDaemons/NA4X3TYR2P.com.jaminzhou.rouse.closed-lid-daemon.plist"

[[ -d "$app_path" ]] || { echo "app not found: $app_path" >&2; exit 66; }
[[ -x "$app_executable" ]] || { echo "app executable not found" >&2; exit 66; }
[[ -x "$daemon_path" ]] || { echo "embedded daemon not found" >&2; exit 66; }
[[ -f "$plist_path" ]] || { echo "launch daemon plist not found" >&2; exit 66; }
[[ -f "$dmg_path" ]] || { echo "DMG not found: $dmg_path" >&2; exit 66; }

codesign --verify --deep --strict --verbose=2 "$app_path"
codesign --verify --strict --verbose=2 "$daemon_path"
codesign --verify --strict --verbose=2 "$dmg_path"
spctl --assess --type execute --verbose=4 "$app_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"
xcrun stapler validate "$app_path"
xcrun stapler validate "$dmg_path"

app_signature=$(codesign -dvv "$app_path" 2>&1)
daemon_signature=$(codesign -dvv "$daemon_path" 2>&1)
[[ "$app_signature" == *"flags="*"runtime"* ]] || { echo "app hardened runtime is missing" >&2; exit 65; }
[[ "$daemon_signature" == *"flags="*"runtime"* ]] || { echo "daemon hardened runtime is missing" >&2; exit 65; }

if codesign -d --entitlements :- "$app_path" 2>/dev/null | grep -q 'get-task-allow'; then
  echo "release app contains get-task-allow" >&2
  exit 65
fi

plutil -lint "$plist_path"

lipo "$app_executable" -verify_arch arm64 x86_64
lipo "$daemon_path" -verify_arch arm64 x86_64

"$app_executable" --self-test
"$daemon_path" --self-test

if [[ "$(uname -m)" == "arm64" ]]; then
  if ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    echo "Rosetta is required to validate the x86_64 slices" >&2
    exit 65
  fi
  arch -x86_64 "$app_executable" --self-test
  arch -x86_64 "$daemon_path" --self-test
fi
