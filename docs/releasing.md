# Release process

## Release gate

Do not create a public release until all of the following pass:

- unit tests and unsigned CI build;
- Developer ID archive and export;
- nested daemon and outer app signature verification;
- notarization and stapling of both app and DMG;
- Gatekeeper assessment on a clean macOS user account;
- registration, approval, restart, update, removal, and recovery tests;
- universal app and daemon binaries with verified `arm64` and `x86_64` slices;
- Apple silicon real-device matrix for AC and battery power;
- `x86_64` Helper and daemon self-tests plus signature assessment under Rosetta
  when an Intel test Mac is not available;
- Rouse start, stop, timed expiry, force quit, daemon kill, and lease expiry;
- explicit Sleep, low-battery protection, restart, and shutdown behavior;
- verification that original per-power-source values are restored.

Until this matrix passes, public copy must describe the feature as pre-release
and must not promise closed-lid operation.

Intel real-device coverage is the only exception for the initial release: all
other gates above must pass, including the Apple silicon matrix and
universal-binary checks. Record Intel real-device coverage separately when it
becomes available; do not describe Rosetta validation as an Intel real-device
result.

### v1.0.0 recorded validation exception

The initial `v1.0.0` release was authorized on 2026-07-26 with a documented
deferral of disruptive real-device checks so active user workloads would not be
interrupted. This is a release-specific risk acceptance, not evidence that the
deferred checks passed and not a change to the general release gate above.

Verified before the release decision:

- Developer ID signing, notarization, stapling, Gatekeeper assessment, and
  universal `arm64` / `x86_64` distribution checks;
- native and Rosetta Helper and daemon self-tests;
- service registration, approval, removal, and reinstall smoke tests;
- integration with Rouse `1.11.0` TestFlight build `202607261128`, including
  the expected team identifier, App Group, and sandbox entitlements;
- ready and active XPC states, normal stop, 45-second timed expiry, Rouse force
  quit, 120-second bounded lease expiry, and toggling the Helper during an
  active Rouse session;
- exact restoration to `SleepDisabled 0` with recovery-journal cleanup after
  every completed recovery check; and
- closed-lid operation on Apple silicon while connected to AC power.

Deferred and therefore not recorded as passed:

- closed-lid battery operation and AC-to-battery transitions;
- explicit Sleep and low-battery protection on a real device;
- forced daemon restart during an active lease;
- full system restart and shutdown recovery;
- clean-account validation of the published release artifact; and
- an in-place update from an older public Helper release.

Complete and record these items when they can be run without interrupting active
workloads. Future release notes and public claims must continue to distinguish
verified checks from these deferred checks.

## GitHub Actions secrets

Configure the following repository secrets:

- `DEVELOPER_ID_APPLICATION`: full Developer ID Application identity name;
- `DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded `.p12`;
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: `.p12` export password;
- `BUILD_KEYCHAIN_PASSWORD`: random ephemeral CI keychain password;
- `ASC_KEY_ID`: App Store Connect API key ID;
- `ASC_ISSUER_ID`: App Store Connect issuer ID;
- `ASC_KEY_BASE64`: base64-encoded `.p8` key.

The release runner imports the certificate into an ephemeral keychain and writes
the API key under `$RUNNER_TEMP`. Neither is included in the artifact.

## Publish

1. Update `appVersion` and `buildNumber` in `Project.swift`.
2. Merge a reviewed PR with green CI.
3. Create and push an annotated `vX.Y.Z` tag from the merge commit.
4. The Release workflow builds, signs, notarizes, staples, verifies, and uploads:
   - `Rouse-Closed-Lid-Helper.dmg`
   - `Rouse-Closed-Lid-Helper.dmg.sha256`
5. Download the published DMG on a clean account and repeat Gatekeeper,
   registration, and removal smoke tests.

## Delayed notarization

The notarization script submits once, then polls the returned submission ID up
to three times. Submission output is streamed so the ID remains visible even if
the command is interrupted. An ID is allocated before the artifact finishes
uploading: if the command fails without printing `Successfully uploaded file`,
inspect that ID with `notarytool info` and resume it only when Apple confirms
the upload. If a local run is interrupted after a confirmed upload, resume that
exact artifact without uploading a duplicate:

```bash
NOTARY_SUBMISSION_ID=<submission-id> ./scripts/notarize.sh "<same app-or-dmg path>"
```

`NOTARY_WAIT_TIMEOUT` can override the default `10m` wait for each attempt.
Stapling still proceeds only after the resumed submission reports `Accepted`;
using an ID for a different artifact will fail ticket stapling.
