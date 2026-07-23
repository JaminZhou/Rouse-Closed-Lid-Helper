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
submission_log=""
trap '[[ -z "$submission_log" ]] || rm -f "$submission_log"; [[ -z "$temporary_zip" ]] || rm -f "$temporary_zip"; [[ -z "$temporary_dir" ]] || rmdir "$temporary_dir"' EXIT
if [[ "$artifact" == *.app ]]; then
  temporary_dir=$(mktemp -d /tmp/rouse-helper-notary.XXXXXX)
  temporary_zip="$temporary_dir/submission.zip"
  ditto -c -k --keepParent "$artifact" "$temporary_zip"
  submission=$temporary_zip
fi

authentication_arguments=(
  --key "$ASC_KEY_PATH"
  --key-id "$ASC_KEY_ID"
  --issuer "$ASC_ISSUER_ID"
)
wait_timeout=${NOTARY_WAIT_TIMEOUT:-10m}
submission_id=${NOTARY_SUBMISSION_ID:-}

if [[ -z "$submission_id" ]]; then
  submission_log=$(mktemp /tmp/rouse-helper-notary-submit.XXXXXX)
  set +e
  xcrun notarytool submit "$submission" \
    "${authentication_arguments[@]}" \
    --no-progress 2>&1 | tee "$submission_log"
  submission_exit=$pipestatus[1]
  set -e

  submission_id=$(sed -nE 's/.*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}).*/\1/p' "$submission_log" \
    | head -n 1)
  if [[ -z "$submission_id" ]]; then
    echo "notary submission did not return an ID" >&2
    if (( submission_exit == 0 )); then
      exit 69
    fi
    exit "$submission_exit"
  fi
  if (( submission_exit != 0 )); then
    echo "submission command exited with $submission_exit after returning $submission_id; polling that ID" >&2
  fi
else
  if ! print -r -- "$submission_id" \
    | grep -Eq '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'; then
    echo "NOTARY_SUBMISSION_ID is not a UUID" >&2
    exit 64
  fi
  echo "Resuming existing notary submission $submission_id"
fi

accepted=false
for attempt in 1 2 3; do
  echo "Waiting for notary submission $submission_id (attempt $attempt/3)"
  set +e
  xcrun notarytool wait "$submission_id" \
    "${authentication_arguments[@]}" \
    --timeout "$wait_timeout" \
    --no-progress
  wait_exit=$?
  status_output=$(xcrun notarytool info "$submission_id" \
    "${authentication_arguments[@]}" \
    --output-format json 2>&1)
  status_exit=$?
  set -e

  if (( status_exit != 0 )); then
    print -r -- "$status_output" >&2
    if (( attempt == 3 )); then
      exit "$status_exit"
    fi
    echo "Could not query submission status; retrying the same ID" >&2
    continue
  fi

  submission_status=$(print -r -- "$status_output" | plutil -extract status raw -o - -)
  echo "Notary submission $submission_id status: $submission_status"
  case "$submission_status" in
    Accepted)
      accepted=true
      break
      ;;
    Invalid|Rejected)
      xcrun notarytool log "$submission_id" "${authentication_arguments[@]}" || true
      exit 65
      ;;
    *)
      if (( attempt == 3 )); then
        echo "notary submission remained $submission_status after 3 attempts" >&2
        if (( wait_exit == 0 )); then
          exit 75
        fi
        exit "$wait_exit"
      fi
      echo "Submission is still $submission_status; retrying the same ID" >&2
      ;;
  esac
done

[[ "$accepted" == true ]] || exit 75

xcrun stapler staple "$artifact"
xcrun stapler validate "$artifact"
