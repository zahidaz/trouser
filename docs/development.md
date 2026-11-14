# Development

Swift package, AppKit + WKWebView, macOS 14 or later. The same binary is the app (when launched by launchd: Dock, Finder, `open`) and the command-line client (any other parent).

```sh
swift test
./scripts/install.sh
scripts/harness/harness.sh build|start|cli …|stop
```

- `install.sh` builds, signs with App Sandbox, installs to /Applications and links `~/.local/bin/trouser`.
- The harness runs a separate app with its own container against the local pages in `scripts/harness/pages`, without touching the installed app. WebKit sends loopback traffic around the proxy, so the pages call `harness.invalid`, which the harness profile blocks.
- Every push to `main` runs the tests and builds `Trouser.zip` as a workflow artifact; pushing a tag such as `v1.2.0` publishes it as a release with that version.

## Layout

| Folder | Holds |
| --- | --- |
| `App/` | entry point, delegate, menus, `Workspace` (profiles, sessions, event buses, burn) |
| `Profiles/` | `ProfileStore`, history, session cookies, `ProfileSettings`, tab restore, privacy report |
| `Content/` | settings → `WKContentRuleList` JSON, tracker list, compiler |
| `Network/` | per-profile loopback proxy, host rules, connection log |
| `Browser/` | window and tabs, `PageDriver` (native events, captures), `ActionSettler`, `PageObserver`, sidebar, start page, delegates |
| `Model/` | the page model: `PageCapture`, `ModelFusion`, `ElementRegistry` (stable ids), `PageModelStore`, `ModelQuery`, `ModelDiff`, `ElementActions`, `PageBrief`, `Intent` |
| `Atlas/` | `PageSignature`, `SiteAtlas`, `SiteAtlasStore` |
| `Events/` | `Event`, `EventLog` (500-event ring), `EventBus` (per profile), cookie observer |
| `Precise/` | opt-in Precise mode: `PrecisePool`, `PreciseLink`, `PreciseMapping`, `PreciseStatus` |
| `Supervision/` | `Policy`, `Supervisor`, Automation panel, approval card |
| `Rules/` | per-profile `ProfileRules`, patterns, `Decision`, certificate parsing, `RuleStore`, `RulesReport` |
| `Settings/` | Settings window: Automation tab and Profiles tab |
| `Control/` | command grammar, router, `ActionReply`, `EventWatcher`, `PageWaiter`, `Expectation`, `RouteReplay`, `LiveScreenshot`, socket server and client |

`Bundle/` is the Objective-C injected bundle for Precise mode (built by `scripts/bundle.sh`); `Sources/TrouserBridge` holds private WebKit declarations.

## Wire protocol

The client sends one JSON line: the argv array. The server answers with zero or more `{"output": "..."}` lines, then one final `Response` line (`{"ok", "message", "file"}`), then shuts the socket down. When the client hangs up, the server cancels the command's task.

## Rules of the codebase

- No script injection: no `evaluateJavaScript`, `callAsyncJavaScript`, `WKUserScript`, `WKContentWorld` or script message handlers. Declarative content rule lists are allowed.
- No Accessibility permission. Events come only from WebKit delegates, KVO and native observers.
- Every action goes through `Supervisor.authorize`. The command line never writes rules or settings.
- A profile does not open if its proxy cannot start. Lockdown Mode is only ever turned on per navigation, never off.
- Password values are never read.
- No comments in code, no dead code, one purpose per command.
