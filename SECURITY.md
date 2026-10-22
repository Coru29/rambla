# Security policy

Rambla needs the macOS **Accessibility** permission to move other apps' windows, and it updates itself. Both deserve care, so security reports are very welcome.

## Reporting a vulnerability

Please report it **privately** through [GitHub's private vulnerability reporting](https://github.com/Coru29/rambla/security/advisories/new) instead of opening a public issue. Spanish or English is fine. You will get an answer within a few days, and a fix will be released as soon as possible with credit to you (unless you prefer otherwise).

Only the latest release is supported.

## What Rambla does and does not do

- It reads and moves windows of other apps through the Accessibility API. It does not read window contents, record the screen, log keystrokes or need Input Monitoring.
- It collects no data and has no telemetry. Its only network request is a check of `api.github.com/repos/Coru29/rambla/releases/latest` shortly after it starts and once a day (it can be turned off in Settings → General).
- It saves the layout in `~/Library/Application Support/Rambla/state.json` (window ids, app ids and window titles) to restore it after a restart, and nothing leaves the Mac.
- Updates are installed only if the downloaded app satisfies the running app's code-signing designated requirement (same bundle id and same certificate). Anything else is refused.
- Web pages and other local processes can send it commands through `rambla://` links and the `rambla` command. A link can only run window actions and open the settings, the same things the keyboard shortcuts do. The command line can also ask for diagnostics (`rambla dump`), whose reply is written only to Rambla's own file in your temporary folder, never to a path chosen by the sender.

Especially interesting reports: ways to make the updater install code that is not signed by the project, ways to escalate through the Accessibility permission, and anything that leaves windows unreachable.
