# Security policy

Rambla needs the macOS **Accessibility** permission to move other apps' windows, and it updates itself. Both deserve care, so security reports are very welcome.

## Reporting a vulnerability

Please report it **privately** through [GitHub's private vulnerability reporting](https://github.com/Coru29/rambla/security/advisories/new) instead of opening a public issue. Spanish or English is fine. You will get an answer within a few days, and a fix will be released as soon as possible with credit to you (unless you prefer otherwise).

Only the latest release is supported.

## What Rambla does and does not do

- It reads and moves windows of other apps through the Accessibility API. It does not read window contents, record the screen, log keystrokes or need Input Monitoring.
- It collects no data and has no telemetry. Its only network request is a check of `api.github.com/repos/Coru29/rambla/releases/latest` shortly after it starts and once a day (it can be turned off in Settings → General).
- With **Site icons** turned on (Settings → Appearance, off unless the user turns it on), it reads the address of the page each browser window shows, through the Accessibility API, and asks that site for its icon over HTTPS: the site's home page and an icon file, once per site while it runs, with no cookies. The icons are kept only in memory.
- It saves the layout in `~/Library/Application Support/Rambla/state.json` (window ids, app ids and window titles) to restore it after a restart, and nothing leaves the Mac.
- Updates are installed only if the downloaded app satisfies the running app's code-signing designated requirement (same bundle id and same certificate). Anything else is refused.
- Web pages and other local processes can send it commands through `rambla://` links and the `rambla` command. A link can only run window actions (not closing a window) and open the settings. The command line can also close windows and run the diagnostics and test commands (`rambla dump`, `rambla debug-windows`, and two that move a window or try an update from a test feed you set yourself); their replies are written only to Rambla's own file in your temporary folder, never to a path chosen by the sender.

Especially interesting reports: ways to make the updater install code that is not signed by the project, ways to escalate through the Accessibility permission, and anything that leaves windows unreachable.
