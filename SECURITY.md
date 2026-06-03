# Security Policy

## Supported versions

Only the latest release is actively maintained.

| Version | Supported |
|---------|-----------|
| latest  | ✅ |
| older   | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Email [julio@nlc.com](mailto:julio@nlc.com) with:

- A description of the vulnerability
- Steps to reproduce
- Potential impact

You'll get a response within 72 hours. If the report is confirmed, a patch will be released and you'll be credited in the changelog (unless you prefer otherwise).

## Scope

This script runs with elevated privileges when sudo modules are selected. The main attack surfaces to be aware of:

- **Path traversal in module targets** — all deletions go through `safe_delete`, which enforces a blocklist before any `rm` is issued.
- **Arbitrary code execution via config file** — `~/.config/mac-optimizer/config.toml` is parsed with `grep`/`sed`, not sourced. It cannot execute code.
- **sudo heartbeat process** — the keepalive subprocess runs `sudo -n -v` only; it has no write access beyond what the user already granted.
