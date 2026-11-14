# Profiles, privacy and modes

## Profiles

Each profile has its own cookies, logins, storage, history, settings and rules. `default` always exists. Create, open and delete profiles in Settings › Profiles (Profile › Manage Profiles…) or switch with ⌥⌘1–9.

- **Settings per profile** (Settings › Profiles › Browsing): JavaScript, Lockdown Mode, desktop or mobile content, user agent, zoom, fixed viewport, background-tab scheduling and content blocking (images, web fonts, a bundled tracker list, extra domains, CSS selectors to hide). Blocking compiles to WebKit content rules.
- **Tabs and logins** come back when a profile opens again, including session cookies.
- **History**: remove single entries or clear all from the start page and sidebar.
- **Downloads** go to ~/Downloads and are quarantined.

## Privacy

- **Network proxy**: each open profile routes through its own authenticated proxy on 127.0.0.1 that logs every connection's host, port, duration and byte counts without decrypting TLS, and refuses blocked hosts. A profile does not open if its proxy cannot start. Loopback hosts bypass it, and HTTP/3 falls back to HTTP/2.
- **Website data** (Settings › Profiles › Website Data): stored data and cookie counts per site, with a delete button per site.
- **Burn Everything**: 🔥 or ⇧⌘⌫ closes all tabs and deletes the data of every profile. Permission rules are kept.

## Background mode

`trouser background on` hides every window and the Dock icon while pages keep rendering off screen. Approvals appear at the top right of the screen and the menu-bar shield brings Trouser back. It needs a logged-in macOS session; it is not a server-style headless browser.

## Precise mode

An opt-in per profile (Settings › Profiles › Browsing, off by default). Tabs opened afterwards load a WebKit injected bundle that reads WebKit's own accessibility tree natively: exact frames, live values, states, and request and form events. It never runs JavaScript and never reads password values.

- `page`, `query`, `tap`, `set`, `show` and `wait text` use the live tree: icon-only buttons have frames, elements scrolled away are listed as `offscreen`, and taps are hit-tested so they land on the element.
- WebKit loads injected bundles only into its development WebContent service, so those pages run with reduced process hardening. Keep it off for profiles that browse untrusted sites.
- If the bundle cannot load or a Precise web process stops, the tab falls back to the standard model, a `page.precise` event says why, and `status` and `profile` show it. Browsing is never blocked.
- Limits: no shadow roots, cross-process iframes or canvas content (use `--ocr`).
