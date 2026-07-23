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
