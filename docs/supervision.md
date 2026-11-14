# Supervision and rules

Every command passes through the supervisor before it touches a page.

## Global modes

Settings › Automation sets Allow, Ask or Block for each kind of action: view, navigate, pointer, scroll, keyboard, submit and download. Ask shows an approval card with the target and blocks the command until you answer. Pause blocks everything at once.

## Per-profile rules

Settings › Profiles › Rules refines the global modes:

- **Site rules** override the global modes per host pattern (`shop.example.com`, `*.example.com`). The most specific pattern that sets an action wins.
- **Protected actions**: a tap whose target label contains a protected phrase (`publish`, `delete`, `pay`, `send*for review`…) always asks, even when rules allow it. A rule that blocks still blocks.
- **Navigation fence**: when set, automation can only navigate to the listed hosts, including popups, redirects and link clicks. Your own browsing is never fenced.
- **Certificate pins**: connections to a pinned host must pass normal trust evaluation and match an allowed issuer or SPKI fingerprint.
- **Camera and microphone** are denied unless a site rule allows them.

If a profile's rules file cannot be read, every automation action in that profile is blocked until you fix or reset it in Settings.

## Always yours

- File pickers, JavaScript dialogs and logins are always yours to answer.
- While a JavaScript alert or confirm is open the page answers nothing, so every command on that tab fails at once and names the dialog; `tab` still works.
- The command line can read rules and settings (`rules`, `profile`, `network`, `privacy`) but never change them.
