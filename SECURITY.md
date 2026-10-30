# Security Policy

## Supported Versions

No public release has been made yet, so a supported-version policy is not established.

## Data handling

NotchCurtain uses local process information (`ps`, `lsof`), local session-log metadata, local Orca and Codex CLI interfaces, and macOS Now Playing through `mediaremote-adapter`. The app source has no HTTP client and does not implement analytics or telemetry. The adapter uses Apple's private MediaRemote interface through Perl; it is not suitable for the Mac App Store and can be affected by macOS updates.

## Reporting a Vulnerability

This repository does not currently publish a security contact. Before enabling public contributions, the maintainer should enable GitHub private vulnerability reporting or add a monitored private contact method. Please do not put sensitive vulnerability details in a public issue.
