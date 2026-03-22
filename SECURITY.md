# Security Policy

## Architecture

AeroPulse installs a privileged LaunchDaemon helper (`AeroPulsePrivilegedHelper`) that runs as root for direct AppleSMC fan control. The helper validates all XPC connections via code signature team ID verification before accepting commands.

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately:

1. **Do NOT open a public issue**
2. Use [GitHub Security Advisories](https://github.com/inhwa-son/aeropulse-mac/security/advisories/new) to report privately
3. Include steps to reproduce and potential impact

We will respond within 48 hours and provide a fix timeline.

## Scope

Security-relevant components:
- `App/Sources/Daemon/` — Privileged helper (runs as root)
- `App/Sources/Shared/SMC/` — Direct hardware access (AppleSMC)
- `App/Sources/Infrastructure/PrivilegedFanControlClient.swift` — XPC communication
