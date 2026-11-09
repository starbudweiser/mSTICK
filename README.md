# mSTICK

[Français](README.fr.md)

## About

mSTICK is a personal sticky-notes app for macOS by Starbudweiser, built with Claude Code (Anthropic). It is inspired by Hold My Notes and is not affiliated with its authors. Provided as is, without warranty. MIT License.

Sticky notes tucked at the edge of your screen, encrypted and always within reach.

## Features

- **The deck**: all your notes live in a stack on the screen edge (top, bottom, left or right, on the screen of your choice). At rest, only thin stripes show; move the pointer over them and the notes fan out, one tab per note with its vertical title. Click a tab to open the note.
- **Floating notes**: title, emoji, five pastel colors plus your own, a font per note, pin, Markdown (bold, italic, underline, strikethrough, headings, bullets, numbered lists, checkboxes, links, tables) styled live as you type.
- **Archive and search**: archive instead of deleting, search titles and text, multi-select, delete with a 10-second undo.
- **Export and import**: Markdown or plain text (one file per note), a single file, or a re-importable `.stickies` archive. Optional Markdown folder (for example an Obsidian vault) kept in sync.
- **Encrypted**: notes are encrypted on disk with AES-GCM, the key lives in your Keychain. No account, no server, no telemetry.
- **Optional sync** between your Macs through a folder (iCloud Drive by default), one `.hmnote` file per note.
- **Global shortcuts** (no Accessibility permission): new note ⌥⌘N, reopen last ⌥⌘O, all notes ⌥⌘L, archive ⌥⌘A, move the deck ⌥⌘E, hide everything ⌃⌥⌘H. All can be changed.
- **Automatic updates** from GitHub releases, signature and notarization verified.
- **Four languages** (French, English, Spanish, Italian), picked from the system language.

## Build

Requires macOS 14+ and Xcode (Swift 6).

```bash
swift test          # unit tests
./build_app.sh      # builds mSTICK.app, signs it and installs it
```

`NO_INSTALL=1 ./build_app.sh` builds `./mSTICK.app` without installing it. `mSTICK --selftest` checks the editor without opening any window. Notes are stored in `~/Library/Application Support/mSTICK` (`MSTICK_DATA_DIR` to change it).
