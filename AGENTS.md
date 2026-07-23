# Rouse Closed-Lid Helper — Agent Instructions

## Safety Boundary

- The Mac App Store Rouse app never runs as root and never invokes `sudo`.
- The privileged daemon only manages the `pmset disablesleep` setting through
  bounded leases.
- Persist the original power settings before changing them and restore them on
  lease expiry, client disconnect, daemon shutdown, or explicit removal.
- Never add an unbounded "enable" command or a general-purpose command runner
  to the daemon XPC surface.

## Distribution

- Build the app with Tuist from `Project.swift`.
- Direct downloads use Developer ID signing, hardened runtime, Apple
  notarization, and a stapled DMG.
- Keep signing certificates, private keys, and notarization credentials out of
  the repository.
- Release artifacts are published from tags through GitHub Actions only after
  the unsigned CI build and tests pass.

## Git

- Use lowercase conventional branch and commit prefixes.
- Pull requests are ready for review by default.
- Prefer squash merge.

