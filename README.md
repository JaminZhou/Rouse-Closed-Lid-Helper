# Rouse Closed-Lid Helper

An optional, open-source companion for [Rouse](https://jaminzhou.com/rouse/) that
uses Apple's Service Management framework to manage a narrowly scoped privileged
daemon on macOS 13 or later.

> **Download:** use the
> [latest GitHub release](https://github.com/JaminZhou/Rouse-Closed-Lid-Helper/releases/latest)
> for the Developer ID-signed and Apple-notarized DMG. The initial release
> verifies the signed Rouse TestFlight integration and the core bounded-recovery
> paths on Apple silicon. Disruptive battery, explicit-sleep, daemon-restart,
> and full power-cycle coverage is recorded separately in
> [`docs/releasing.md`](docs/releasing.md), rather than being inferred from
> automated tests. Intel real-device coverage is also tracked separately and is
> not inferred from Rosetta validation.

## Why a separate helper?

The Mac App Store version of Rouse is sandboxed and does not run commands as
root. Changing the system-wide `pmset disablesleep` setting requires an optional
component distributed outside the Mac App Store. Keeping that component in a
public repository makes the privileged behavior reviewable and keeps the MAS
app's security boundary intact.

## Safety model

The daemon does not expose a shell or a general command API. It accepts only:

- status requests;
- a renewable lease capped at 120 seconds;
- release of the caller's lease; and
- restoration of the original settings.

Before changing any power setting, the daemon writes the original per-power-
source values to a root-owned recovery journal. It restores those values when:

- the Rouse XPC connection ends;
- the last lease expires;
- the daemon receives a termination signal;
- the helper is removed through its UI; or
- the daemon starts and detects an interrupted prior session.

The XPC Mach service name is scoped to Rouse's macOS App Group, and the listener
also requires Rouse's Apple Developer team identifier plus an approved Rouse or
Helper bundle identifier.

## Architecture

```text
Rouse (MAS sandbox)
  └─ App Group-scoped privileged XPC
      └─ root LaunchDaemon
          ├─ bounded lease controller
          ├─ root-only recovery journal
          └─ /usr/bin/pmset with fixed arguments

Rouse Closed-Lid Helper.app
  └─ SMAppService registration, approval, diagnostics, and removal UI
```

The helper app must remain in `/Applications` while its daemon is registered.
Registration requires administrator approval in System Settings > General >
Login Items & Extensions.

## Build

Requirements:

- macOS 13 or later
- Xcode 16 or later
- Tuist 4.202.6

```bash
make lint
make build
make test
```

Unsigned CI builds never register the daemon and never change local power
settings.

## Manual recovery

Use the Helper's **Restore & Remove Service** action first. If the app and daemon
were deleted before cleanup and the Mac refuses to sleep, an administrator can
restore the default explicitly:

```bash
sudo pmset -a disablesleep 0
```

This fallback cannot reconstruct a non-default value that another tool had set.
Normal Helper removal restores the exact values captured before Rouse changed
them.

## Distribution

Releases are built as Developer ID-signed, hardened, notarized, and stapled DMG
files. The release workflow requires GitHub Actions secrets documented in
[`docs/releasing.md`](docs/releasing.md). Signing keys are never committed.

## License

MIT. See [LICENSE](LICENSE).
