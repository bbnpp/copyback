# Copyback

A tiny macOS menu bar clipboard history app. It remembers what you copy and lets you copy it back.
Free, local-only, no network access, no dependencies.

> The UI is currently in Korean.

## Features

- Menu bar icon and a global shortcut (`⇧⌘V`) to open the history
- Search, keyboard navigation (`↑`/`↓`, `⏎`, `⌘1`–`⌘9`), delete with `⌘⌫`
- Restores the original formats: rich text (RTF/HTML), images, files copied in Finder
- Keeps up to 300 items; copying the same thing again moves it to the top
- Pin frequently used items (`⌘P` or right-click): pinned items stay at the top in the order you pinned them, don't count toward the 300-item limit, and are kept when you clear the history
- Skips content that password managers mark as concealed/transient ([nspasteboard.org](http://nspasteboard.org) convention)
- Also skips copies made while Passwords or Keychain Access is the frontmost app (best effort: the clipboard is checked every 0.5 s, so switching apps right after copying can slip through)

After you pick an item the popover closes and focus returns to the app you were using, so you can paste with `⌘V`.

## Requirements

- macOS 14 or later
- Xcode or the Command Line Tools (`xcode-select --install`)

## Build & install

```sh
make test       # self-test of the core logic (uses a private pasteboard, not your clipboard)
make install    # build, copy to /Applications, launch
make uninstall  # remove the app (history data is kept)
```

The build uses `swiftc` directly from a `Makefile` instead of SwiftPM, so it works with only the Command Line Tools installed.
The app is ad-hoc signed on your machine; there is no prebuilt binary.

Launch at login can be turned on from the gear menu at the bottom of the popover.

## Customize

- Shortcut: `hotKeyCode` / `hotKeyModifiers` in `Sources/Copyback/AppDelegate.swift`.
  Note that a global `⇧⌘V` overrides "paste without formatting" in apps such as Chrome and Slack.
- History size: `maxItems` in `Sources/Copyback/ClipboardHistory.swift`

## Privacy

History is stored **unencrypted** in `~/Library/Application Support/Copyback/` (folder permission `0700`, excluded from Time Machine).

- `history.json`: item list
- `blobs/`: raw clipboard data
- `thumbs/`: image previews

Passwords copied from places that don't mark them (Terminal, text files, some apps) will be recorded.
Delete them with `⌘⌫`, or use "모두 지우기" (Clear All), which wipes all stored data except pinned items.
Copies larger than 32 MB are not recorded.

To remove everything: `make uninstall && rm -rf ~/Library/Application\ Support/Copyback`

## 한국어 요약

메뉴 막대에 상주하는 클립보드 기록 앱입니다. `⇧⌘V` 또는 아이콘 클릭으로 기록을 열고, 항목을 클릭하거나 `⏎`로 다시 복사합니다.
`make install`로 빌드·설치합니다 (macOS 14+, Command Line Tools 필요). 기록은 이 Mac에만 암호화 없이 저장됩니다.

## License

[MIT](LICENSE)
