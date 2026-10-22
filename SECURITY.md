# Security policy

Rambla needs the macOS **Accessibility** permission to move other apps' windows, and it updates itself. Both deserve care, so security reports are very welcome.

## Reporting a vulnerability

Please report it **privately** through [GitHub's private vulnerability reporting](https://github.com/Coru29/rambla/security/advisories/new) instead of opening a public issue. Spanish or English is fine. You will get an answer within a few days, and a fix will be released as soon as possible with credit to you (unless you prefer otherwise).

Only the latest release is supported.

## What Rambla does and does not do

- It reads and moves windows of other apps through the Accessibility API. It does not read window contents, record the screen, log keystrokes or need Input Monitoring.
- It collects no data and has no telemetry. Its only network request is a daily check of `api.github.com/repos/Coru29/rambla/releases/latest` (can be turned off in Configuración → General).
- Updates are installed only if the downloaded app satisfies the running app's code-signing designated requirement (same bundle id and same certificate). Anything else is refused.
- Other local processes can send it window commands through the `rambla://` URL scheme and the `rambla` command. They can only arrange windows, the same thing the keyboard shortcuts do.

Especially interesting reports: ways to make the updater install code that is not signed by the project, ways to escalate through the Accessibility permission, and anything that leaves windows unreachable.
