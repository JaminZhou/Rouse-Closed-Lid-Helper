# Security Policy

Please do not open a public issue for a vulnerability that could allow an
untrusted process to reach the privileged daemon, modify arbitrary power
settings, execute arbitrary commands, or prevent recovery.

Report security issues privately through GitHub's private vulnerability
reporting for this repository. Include the macOS version, Mac model, Helper and
Rouse versions, relevant unified logs, and reproduction steps.

The daemon intentionally has no general command execution API. Proposals that
broaden its root interface must include a threat model and will not be accepted
only for convenience.

