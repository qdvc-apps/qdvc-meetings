# QDVC Meetings for macOS — Maintenance Guide

This guide is for whoever maintains the app next. It explains how the code
is laid out, which behaviour must be preserved, and how it is tested.

The one rule that matters most: **the workspace is the contract.** The file
names and YAML the app writes are documented in [FILE_FORMAT.md](FILE_FORMAT.md)
and checked by the unit tests. Any change to a file name or to the bytes of a
meeting file is a format change: update FILE_FORMAT.md and the tests with it.

## 1. Layout

```
Package.swift                 SwiftPM manifest (no Xcode project)
Sources/MeetingsCore/         the model: Foundation + Yams, no AppKit/SwiftUI
Sources/QDVCMeetings/         the SwiftUI/AppKit app
Tests/MeetingsCoreTests/      unit tests
tools/make_icon.py            regenerates Resources/AppIcon.{svg,icns}
scripts/build-app.sh          builds and ad-hoc signs "QDVC Meetings.app"
Resources/Info.plist          bundle id org.qdvc.meetings.mac
sample-workspace/             nine meetings (one with two attachments) and platform instructions
docs/                         DESIGN, FILE_FORMAT, this guide
```

`MeetingsCore` has no AppKit or SwiftUI imports and builds on Linux; the app
target is declared on macOS only (see `Package.swift`). Yams (from 5.1.0) is
the only dependency. Commit `Package.resolved` after the first build so
everyone gets the same Yams.

### 1.1 App icon

`tools/make_icon.py` writes `Resources/AppIcon.svg` and `Resources/AppIcon.icns`
(needs `rsvg-convert`; `brew install librsvg`). The design is a frosted-glass
calendar card sealed with a blue two-person badge, in a "Lagoon" palette, on
Apple's template geometry, matching the other QDVC apps. `--preview` also
writes `build/icon-preview.png`.

## 2. Modules

`MeetingsCore`:

| File | Responsibility |
| --- | --- |
| `Dates.swift` | `LocalDate` (a zone-less day, with ordinal arithmetic, weekdays and week starts) and `LocalTime` |
| `Models.swift` | `Meeting`, `Note`, `NoteKind`, `LocationKind` (link detection), `ConferencePlatform`, `PlatformInstructions`, search |
| `Naming.swift` | the slug, file stems, collision suffixes, export file names |
| `People.swift` | name normalisation, `PeopleIndex` (derived people, suggestions, short names), renaming |
| `MeetingFile.swift` | reading and writing meeting files and `platforms.yml` (key order, quoting, unknown keys) |
| `Workspace.swift` | scanning (meeting files and attachments folders), loading (cached by modification date and size), saving with renames that carry the attachments folder along, adding and listing attachments, platform instructions |
| `Formatting.swift` | `DateBucketer` (list headings) and `MeetingFormatter` (dates and times in the user's locale, cached formatters) |
| `Export.swift` | the content shared by exports; plain text and Markdown |
| `DOCX.swift`, `Zip.swift` | the Word document (OOXML parts) and a stored-entry ZIP writer with CRC-32 |

The app (`QDVCMeetings`): `MeetingsApp` (scenes, app delegate), `AppModel`
(all state and actions, `@Observable`, main actor), `Commands` (menus and
shortcuts), `ContentView` (window, toolbar, banners, welcome screen,
dialogs), `SidebarView` (and Rename Person), `MeetingListView` (rows, the
notes badge, context menu), `CalendarMonthView` (grid, chips, drag
payloads), `MeetingPane` (header, location, callout, people, attachments with Quick
Look thumbnails, file drops, `FlowLayout`),
`NotesList` (inline notes, kinds, assignees, drag and drop),
`TokenField` (`NSTokenField` wrapper), `MeetingSheet`, `SettingsView`,
`Prefs`, `Platform` (AppKit services and symbols).

### 2.1 How changes reach the disk

Every change goes through `AppModel.update(_:undo:debounce:_:)`, which
changes the meeting in memory, registers an undo snapshot if the change is
named, and writes the file through `Workspace.save`, which also renames it
when its date, time or title changed.

- **Typing in a note** is written after 0.7 s without typing
  (`scheduleSave`), and at once when the selection changes, the app is left
  or quits, a sheet opens, or the workspace is refreshed (`flushSaves`).
- **Blank notes** exist only in memory while you type into them; they are
  never written, and are dropped when you leave the meeting.
- **Undo** restores a whole-meeting snapshot (and registers the redo the
  same way), so every undoable action is one step whatever it touched. Note
  text is undone by the text field itself while you edit. Deleting a
  meeting is not undoable (it goes to the Trash after a confirmation), and
  Rename Person clears the undo stack because it can touch many files.
- **Refresh** (⌘R, and whenever the app becomes active) re-reads files that
  changed on disk. A meeting with unsaved typing keeps its in-memory
  version.

### 2.2 Attachments

Attachments are not part of `Meeting`: the app keeps them in
`AppModel.attachments`, by meeting, filled from `LoadResult.attachments` on
every load and re-listed after each add, remove or rename. Undo therefore
never touches them. File drops anywhere on the meeting pane go to
`importDroppedFiles`; the notes rows also accept file drops (they are drop
targets for note reordering, and would otherwise swallow them) and pass
them on.

### 2.3 Note drag and drop

Notes are dragged by their ≡ handle (`onDrag`, which also records a
snapshot). Each row is a drop target whose `isTargeted` callback moves the
dragged note into that row's place as the pointer passes, so the list
rearranges live. The drop, or failing that the next hover over the list
(hover events stop during a drag), ends the drag and registers one undo for
the whole move.

## 3. Behaviour to preserve

- File names use only `a–z 0–9 -`, are at most 56 characters before `.yml`,
  and follow FILE_FORMAT.md §2 exactly (tested in `NamingTests`).
- Meeting files keep key order and unknown keys, quote times, and omit empty
  keys and blank notes (`MeetingFileTests`).
- Location kinds follow FILE_FORMAT.md §3.1 (`LocationTests`).
- A file that cannot be read is never rewritten.
- People are one person whatever their capitalisation or spacing, and
  suggestions put the meeting's own people first for assignees.
- Exports list notes in order with DECISION / ACTION labels, then a recap of
  action items; plain text uses plain spaces and ASCII punctuation around
  the user's own text (`ExportTests`).

## 4. Shortcut choices

- **⌘[ / ⌘]** move between months, not Calendar's ⌘← / ⌘→: menu shortcuts
  take precedence over the focused text field, and ⌘← / ⌘→ move the cursor
  in text.
- **⌘⌫** (Delete Meeting) is passed on to the text as "delete to start of
  line" when a text field is being edited (`Platform.isEditingText`).
- **⌥⌘0 / ⌥⌘A / ⌥⌘D** set a note's kind; **⌥⌘↑ / ⌥⌘↓** move it. They act
  on the note whose text field has the focus.

## 5. Tests

```
swift test
```

`CoreTests.swift` covers dates, location kinds, slugs and paths, the people
index and suggestions, reading and writing meeting files (including a
byte-for-byte round trip), the workspace (save, collisions, renames across
years, unreadable files, folder clean-up), attachments (copying, Finder-style
name numbering, `.yml` attachments not read as meetings, the folder moving
with a renamed meeting), list headings, and the three
exports (including a CRC-32 check and the DOCX parts).

The core and its tests also build with a Linux Swift toolchain (5.8 or
later; lower the manifest's tools version and platform if your toolchain is
older than 5.10), which is how they were first run. The SwiftUI app needs
macOS 14 and Xcode 16.

To regenerate `sample-workspace/`, write meetings with `Workspace.save` from
a scratch executable; that keeps its files exactly as the app writes them.

## 6. Roadmap

- A Week view in the calendar.
- Import from and export to `.ics`, or syncing with Calendar (EventKit).
- Optional e-mail addresses for people, and a To line in the plain-text
  export.
- A done state for action items, if they are to be tracked after the
  meeting.
