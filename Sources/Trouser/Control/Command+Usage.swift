extension Command {
    static let usage = """
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
      run <command> \\; <command> ...  run commands in order on one connection, stopping at the first failure
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

    Tap, set, go and tab wait for the page to settle, then print what changed (or "no visible change"); add --quiet to skip the changes.
    Click and scroll coordinates refer to the visible-page screenshot, not --full.
    Event types: navigation, page, form, net, ui, download, cookies and automation, or a full type such as
    navigation.finished. A prefix matches every type under it.
    Words that match several controls list the candidates and do nothing.
    Element ids from page and query stay the same while the page updates; --ocr adds text found only in images.
    Rules, network, privacy and profile settings change only in Trouser's Settings window.
    """
}
