# Command line

```
usage: trouser [-p <profile>] <command> [arguments]

Commands act on the front tab of the active profile unless -p is given.

Read
  page [--json]                   what matters on the page: blockers, main actions, fields and navigation, with ids
  page --all [--json] [--ocr]     every element with a stable id, role, label, value, states and position
  query <expr>                    elements matching roles, states, ids and quoted text: button "Save", textbox, !disabled
  screenshot [--full]             save the visible page, or the whole page, as PNG
  screenshot --live [--every seconds]
                                  keep a low-quality JPEG of the page up to date until stopped (pixels are click coordinates)
  source [--all]                  save the page's HTML, or every resource, to a folder

Act
  tap <id|words>                  click the element with that id, or the control that best matches the words
  set <id|words> <text>           replace the text of that field (set e4 "" clears it); quote words with spaces
  show <id|text>                  scroll until that element, or that text, is visible
  click <x> <y> [count]           click at screenshot coordinates
  drag <x1> <y1> <x2> <y2>        press at the first point, move to the second and release
  scroll <x> <y> <dx> <dy>        scroll by pixels at a point
  type <text>                     type into the focused element
  key <combo>                     press a key: enter, tab, esc, cmd+a, shift+tab...
  path <page title or label>      replay the shortest path known from the site atlas, stopping if a page differs
  run <command> \; <command> ...  run commands in order on one connection, stopping at the first failure
  run -                           run commands read from stdin, one per line

Navigate
  go <url|back|forward|reload>    navigate the current tab in place
  tab <new [url]|close|n>         open a new tab, close this one, or switch to tab n

Observe
  watch [--json] [--types a,b] [--count n] [--until type] [--since seq]
                                  print live events until Ctrl-C, n events or the --until type
  wait <load|idle|url s|text s|event type> [--timeout seconds]
                                  poll until the condition holds; exit 1 after the timeout (30 s)
  expect <text s|url s|no-change> check once, now: fail unless the page shows s, the URL contains s or the last action changed nothing
  downloads                       list downloaded files with their paths
  network [--json] [--hosts]      recent connections of the profile, or totals per host
  privacy [--json]                sites with stored website data and their cookie counts
  rules                           the profile's permission rules (read-only)

Profiles
  status                          profiles, tabs and pause state
  open [url]                      open the profile's window (a tab at url if given); use go to navigate an open tab
  profile                         the profile's effective content, privacy and network settings
  profile delete <name>           delete a profile and all its data after you confirm in Trouser
  background <on|off>             hide every window and drive pages invisibly, or show them again
```

The CLI can read rules and settings but never change them; they change only in the Settings window.

## The loop

`page` → `tap` or `set` → read the reply. One call is one step: never sleep, screenshot or re-read after an action.

```
$ trouser page
Store listing — shop.example.com/admin/app/42/listing
# e1 “Store listing”
! e4 textbox “App name” (empty) required
! e7 button “Publish” disabled — “Only the account owner can publish this app”
> e6 button “Save draft”
= e5 textbox “Short description” = “A tiny app”
nav: e11 “Home” · e12 “Releases”

$ trouser set "App name" "My app"
$ trouser tap "save draft"
tap e6 button “Save draft”: done
Store listing — shop.example.com/admin/app/42/listing
+ e21  text  “Saved”  112,239
```

- **`page`** prints at most 25 lines, most important first: `#` headings, `!` blockers (pending approvals, alerts, errors, required or invalid fields, disabled primary buttons with the text that explains them), `>` primary actions, `=` fields with values, then navigation. Controls with a known destination end with `→ <page>`.
- **`tap` and `set`** take an id from `page` or `query`, or words. Words are ranked against the page's controls (label, placeholder, row or heading context, known destination, link path; `button`, `link`, `tab` or `field` favor that role). The command acts only when one candidate clearly leads; otherwise nothing happens and the reply lists the top three with ids and reasons. Ids stay the same while the page updates.
- **`show`** scrolls until an element (by id) or a piece of text is visible, even if the page model does not list that text yet.
- **Replies** are the done line, the page title and URL, anything the action caused (navigation failure, HTTP error, download) and the lines that changed. `no visible change` means the action did nothing. `--quiet` skips the changes.
- **Settling**: after an action Trouser waits briefly for the page to react (navigation, title or URL change, dialog, popup, download, network traffic through the profile's proxy), then until those signals go quiet, and reads the page again if a reaction has not shown up in the model yet.

Chain steps that need no decision:

```sh
trouser run tap "Save draft" \; expect text "Saved" \; tap "Next" \; expect url /review
printf 'go example.com\nwait text "Example Domain"\npage\n' | trouser run -
```

`expect` checks once and stops the run at the first wrong step. `wait` polls and is meant for long operations such as uploads and exports; inside `run`, `wait event` also counts events since the previous step began, so a fast download cannot be missed.

There is no hover command: synthetic mouse-moved events break WKWebView click handling. A map is panned with `drag` and zoomed with `scroll`.

## Page model

`page --all` lists every control, heading and line of visible text once, in reading order:

```
e3   textbox   “App name” = “My Cool App”  78,181  required
e4   textbox   “Short description” (empty, “Describe your app in 80 characters”)  154,267
e11  button    “Save as draft”  1177,876  disabled
```

- It is built from the page's DOM (read from a web archive, never a script) and the text WebKit renders; `--ocr` adds text that exists only in pixels.
- Password fields never show their value.
- The selected tab's model is kept warm in the background, so `page` and `query` usually answer from the cache.
- `page --all --json` prints a stable schema: `{"schema":1,"page":{…},"focus":"e3"|null,"elements":[{"id","role","label","value","placeholder","states","frame","center","visible","source","url","context"}]}`.

## Seeing the page

- `screenshot` saves one PNG; its pixels are click coordinates.
- `screenshot --live` keeps one low-quality JPEG up to date (and refreshes it before every action replies) until you stop it. It is off until you turn on Settings › Profiles › Browsing › Live screenshot, it is a supervised view action, and the file is readable only by you and deleted when the stream stops.

## Site atlas

Each profile remembers where its controls lead: the page signature (host, path pattern, title), the control's label and the page it reached. Only labels, path patterns and titles are stored, never field values or queries. `page` shows known destinations, `tap` ranks on them, and `path "App details"` replays the shortest known path through normal supervised taps, stopping if a page differs.

## Events

Each profile keeps its last 500 events. `watch` streams them; `--types` and `--until` take a full type or a prefix.

| Group | Types |
| --- | --- |
| `navigation` | started, redirected, committed, finished, failed, response |
| `page` | title, url, progress, secure, certificate, capture, precise |
| `form` | focus, change, submit (labels and counts only, never values) |
| `net` | request, response, finished, failed (Precise mode only) |
| `ui` | popup, tab.opened/closed/selected, dialog.shown/answered, picker.shown/closed, process.terminated/reloaded |
| `download` | started, progress, finished, failed |
| `cookies` | changed (count only) |
| `automation` | requested, pending, granted, denied, done, blocked, failed, paused, background |

A line looks like `#42 14:03:22.120 default[1] navigation.finished duration=118ms url=https://example.com/`; `--json` prints one object per line. The Automation panel shows the same events under Timeline.
