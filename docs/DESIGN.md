# QDVC Meetings for macOS — Design

Status: **approved; first implementation written.** The decisions taken on
the open questions are recorded in §11. Where the implementation differs
from the original proposal, this document has been updated to match it.

QDVC Meetings keeps a record of your meetings: when they are, where they are
(a room, a Google Maps link, or a Microsoft Teams or Zoom link), who is in
them, and the notes, decisions and action items that come out of them. The
notes of any meeting can be exported as a Word document, as Markdown, or as
plain text ready to paste into an email.

It follows the approach of the QDVC Nice Mail, Bibliotheca and GTD EML macOS
apps: a Foundation-only core library with unit tests, a SwiftUI/AppKit
front-end, no Xcode project file, and an ad-hoc-signed bundle built by
`scripts/build-app.sh`. Unlike its siblings, it has no Python edition, so
there are no parity fixtures; the file format in §8 is its own.

---

## 1. Principles

- **The workspace is a plain folder.** Meetings are text files you can
  read, grep, version with Git and sync with Syncthing or iCloud Drive.
  Nothing is locked in a database.
- **Writes happen immediately.** Every change is written to disk at once,
  atomically. There is no document to save, as in the sibling apps.
- **Look like Calendar, Reminders and Notes, where they have an answer.**
  People already know how Calendar shows a day and a month, how Reminders
  adds a row when you press Return, and how a token field completes names
  in Mail. Where a meeting concept has an equivalent there, the app borrows
  its placement, symbol and shortcut.
- **Every action is in the menu bar.** Toolbar buttons, context menus and
  inline controls are shortcuts to menu commands, never the only way in.
- **No network access.** Links are opened in the default browser or app;
  the app itself never fetches anything.

## 2. Window layout

One window, a `NavigationSplitView` with a collapsible sidebar (⌃⌘S, View →
Hide Sidebar). To its right sit either the **meeting list** and the **meeting pane**, side
by side in an `HSplitView`, as Mail places its message list and reading
pane, or the **month calendar** on its own, using the full width (as
Calendar's Month view has no inspector open by default). The window opens at about
1200 × 760 pt and works down to about 900 × 560 pt; hiding the sidebar
recovers its width.

### 2.1 Toolbar

Following the family's HIG notes (Nice Mail `docs/HIG.md` §2): no window
title in the toolbar, icon-only buttons with tooltips naming the shortcut,
and every button also in the menu bar.

| Position | Item | Symbol | Shortcut |
| --- | --- | --- | --- |
| Leading | Sidebar toggle (system) | `sidebar.left` | ⌃⌘S |
| Centre | **View** segmented control: List, Calendar | `list.bullet`, `calendar` | ⌘1, ⌘2 |
| Trailing | New Meeting | `plus` | ⌘N |
| Trailing | Export Notes (menu: Word, Markdown, Copy as Plain Text) | `square.and.arrow.up` | — |
| Trailing | Search (title, people, location, description, notes) | — | ⌘F |

The List / Calendar control is Calendar's own Day / Week / Month control
and Finder's view-mode control (both ⌘1…). In Calendar mode the toolbar
also gets Calendar's **‹ Today ›** month navigation (⌘[ / ⌘T / ⌘]). Calendar
itself uses ⌘← / ⌘→, but menu shortcuts take precedence over a focused text
field, where those keys move the cursor; ⌘[ / ⌘] are Safari's and Finder's
Back and Forward.

### 2.2 Sidebar

The sidebar filters which meetings are shown, in both views.

| Section | Entries | Symbols |
| --- | --- | --- |
| Meetings | Today, Upcoming, Past, All Meetings (with counts) | `sun.max`, `calendar.badge.clock`, `clock.arrow.circlepath`, `tray.full` |
| People | everyone who has been in a meeting, alphabetically, with counts | `person` |

"Upcoming" is today onwards; "Past" is before today. Choosing a person
shows only their meetings, as choosing a mailbox does in Mail. The People
section is derived from the meetings (§6) and can be collapsed.

In Calendar mode the date filters do not apply (the calendar is itself the
date filter), so they are dimmed and choosing one switches to the list; a
person still filters the grid.

### 2.3 List view

Mail- and Calendar-style rows rather than a `Table`, grouped under
collapsible date headings: Today, Tomorrow, then weekday names for the rest
of this week, then Next Week, Later This Month, and month names (and the
mirror image for Past: Yesterday, Earlier This Week, …). Each row has:

- **Line 1:** the title (bold) and the start time on the right.
- **Line 2:** the location's symbol and a short label: the free text,
  "Google Maps", "Microsoft Teams" or "Zoom".
- **Line 3:** the people (first names where unambiguous), and the **notes
  badge**: a tinted capsule with the number of notes, and of action items
  and decisions where there are any (white on the selection highlight).
  A meeting that has happened (today or earlier) with no notes shows a
  faint "No notes" instead, so meetings still waiting for notes stand out.
  Upcoming meetings without notes show nothing.

Rows under a heading that spans several days (Next Week, a month) also
show the date, as "Mon 12 Oct, 14:00".

Upcoming is sorted soonest first; Past and All latest first, as a log. A
row's context menu repeats the Meeting menu (§4).

### 2.4 Calendar view

A month grid, as in Calendar's Month view. The week starts on the day your
macOS region settings say, as in Calendar. Each day shows up to three
meetings as small chips (start time, title, and the platform symbol for
Teams and Zoom, and a **notes symbol**, in the accent colour, when the
meeting has notes), then "2 more", which shows all of the day's meetings in a
popover. The number of chips adapts to the window's height. Today's date is circled in the accent colour.

- **Click a chip to show the meeting in the list:** the view switches to
  List, under Upcoming (today onwards) or Past, with the meeting selected,
  its heading expanded and the list scrolled to it, so its pane is beside
  it. The calendar has no meeting pane of its own.
- Double-click an empty part of a day to create a meeting on that day.
- Drag a chip to another day to move the meeting (keeping its time), as in
  Calendar. Undo (⌘Z) moves it back.

### 2.5 Meeting pane

Laid out like Calendar's event inspector, then Reminders-style notes:

1. **Title**, then the **date and time** ("Monday 5 October 2026 ·
   14:00–15:00").
2. **Location row:** the location's symbol and text, and one action button:
   **Join** for Teams and Zoom, **Open Map** for a Google Maps link, and
   **Show in Maps** (Apple Maps search) for free text. A context menu
   copies the link.
3. **Platform callout:** for a Teams or Zoom meeting whose platform has
   instructions in Settings (§5), a tinted callout with an `info.circle`
   symbol, as in Nice Mail's Note to Self ref callout. No callout when
   there are no instructions for that platform.
4. **People** as tokens. Clicking one selects them in the sidebar.
5. **Description**, if any.
6. **Attachments** (§3a), when there are any.
7. **Notes** (§3).

Edit Meeting (⌘E), Duplicate Meeting (⌘D) and the Export menu are also
reachable from a `…` menu at the top right of the pane.

## 3. Notes

Notes are an ordered list in the meeting pane, edited in place, as in
Reminders:

- Click **New Note** at the end of the list (or ⇧⌘N, Meeting → New Note)
  to start a note. Return finishes it and starts another; Return on an
  empty note ends the run, as in Reminders. ⌥Return inserts a line break.
- Each note has a **kind**, shown as its leading symbol and set from the
  note's context menu, a small menu on the symbol, or the Note menu:

  | Kind | Symbol | Shortcut |
  | --- | --- | --- |
  | Note (default) | `circle.fill` (small, secondary) | ⌥⌘0 |
  | Action item | `checklist` (accent colour) | ⌥⌘A |
  | Decision | `checkmark.seal` (purple) | ⌥⌘D |

- An **action item** shows an **Assigned to** token field under its text.
  Typing completes names as Mail's address field does (it is an
  `NSTokenField`), offering the meeting's people first, then everyone
  else; anything else typed becomes a new name. (The native completion list
  cannot show group headings, so the grouping is by order.) Someone
  assigned who isn't among the meeting's people is drawn as a square token
  rather than a rounded one, and is **not** added to the meeting's people.
- Turning an action item back into a note or decision keeps its assignees
  on disk, hidden, so switching back and forth loses nothing. (They are
  dropped from exports while hidden.)
- **Reorder by drag and drop:** every note has a ≡ handle at its leading
  edge (faint, darker on hover). Drag it, and the other notes move aside
  live as it passes over them, as in Reminders; drop it anywhere in the
  list, including on New Note to send it to the end. The whole drag is one
  Undo step. Move Up / Move Down (⌥⌘↑ / ⌥⌘↓, and the note's context menu)
  do the same from the keyboard. Delete with ⌫ on an empty note or
  from the context menu. All note edits are undoable (⌘Z).

## 3a. Attachments

Files of any kind (a screenshot, a photo of the whiteboard, the slides) can
be attached to a meeting. They are **copied** into a folder named like the
meeting's file, beside it (FILE_FORMAT.md §3.4), so they stay with the
meeting in Finder, in backups and in sync.

- **Attach** with Meeting → Add Attachments… (⇧⌘A, as Mail's Attach Files),
  the paperclip button in the meeting pane's header, or by **dropping files**
  from Finder, Mail or Photos anywhere on the meeting pane (it is outlined
  while you drag, and says "Drop to attach to this meeting").
- **Shown** as Quick Look thumbnails (the file's icon when Quick Look has no
  preview) in an Attachments section above the notes, with name and size.
  Clicking one opens **Quick Look**, where ← / → move between the meeting's
  attachments. Its context menu has Open, Reveal in Finder and Move to
  Trash. Dragging one out copies it, for instance into a Mail message.
- **Names are kept** as they were; a name already taken gets a number, as
  Finder does ("photo 2.png").
- **Indicators:** a paperclip after the title in the list (as in Mail) and
  on calendar chips, and the count in their tooltips.
- Removing an attachment moves it to the **Trash**; the folder itself goes
  when it is empty. Deleting a meeting moves its folder to the Trash too.
  Duplicate Meeting does not copy attachments.

## 4. Meetings: creating and editing

**New Meeting** (⌘N) opens a sheet, as Calendar's New Event opens an
inspector; **Edit Meeting** (⌘E, or double-click a row or chip) opens the
same sheet for the selected meeting.

| Field | Control | Required |
| --- | --- | --- |
| Title | text field | yes |
| Date | date picker (field and calendar popover, Calendar-style) | yes |
| Time | time picker | yes |
| End time | time picker, with a "No end time" option (see Q2) | no |
| Location | text field; its symbol and kind update as you type (§4.1) | no |
| People | token field with completion (§6) | no |
| Description | multi-line text, a few lines high | no |

A new meeting defaults to the next whole hour today, or 09:00 on the day
double-clicked in the calendar. **Duplicate Meeting** (⌘D) copies title,
time, location, people and description to a new meeting a week later, with
no notes, which covers recurring meetings without a recurrence engine.
**Delete Meeting** (⌘⌫; while a text field is being edited, ⌘⌫ deletes to
the start of the line instead) asks for confirmation and moves the file to the
Trash, so it can be recovered in Finder.

### 4.1 Location kinds

The kind is detected from the text whenever it is shown, not stored, so a
pasted link is always classified the same way. Matching is
case-insensitive, on the URL's scheme and host, after trimming whitespace:

| Kind | Rule (from your brief) | Examples |
| --- | --- | --- |
| Microsoft Teams | `https://*teams*microsoft*/`: an `https` URL whose host contains `teams` and, after it, `microsoft` | `https://teams.microsoft.com/l/meetup-join/…` |
| Zoom | `https://*zoom*/`: an `https` URL whose host contains `zoom` | `https://zoom.us/j/…`, `https://us02web.zoom.us/j/…` |
| Google Maps | an `https` URL for Google Maps: host `maps.google.*`, `google.*` with a path starting `/maps`, `maps.app.goo.gl`, or `goo.gl` with a path starting `/maps` | `https://maps.app.goo.gl/AbC123` |
| Free text | anything else, including other URLs (shown as a link if it is one) | `Room 4.12`, `Café on King St` |

## 5. Platform instructions

Settings (⌘,) gets a **Platforms** pane with one short text field each for
Microsoft Teams and Zoom, a live preview of the callout, and a gentle
character count (about 200 characters, which is two sentences; longer text
is allowed but the count turns orange). An empty field means no callout.
Where these are stored is Q6.

## 6. People and suggestions

A person is a name (but see Q4). The **people index** is derived each time
the workspace loads, from every meeting's people and every action item's
assignees, so it needs no file of its own and cannot drift out of date.

- Names are compared case-insensitively after trimming and collapsing
  spaces, so "alice smith" completes to, and is stored as, "Alice Smith"
  (the most common spelling wins).
- Suggestions match the start of any word ("smi" finds Alice Smith), and
  are ordered by how many meetings the person has been in, then by the
  most recent.
- When editing a meeting, suggestions are everyone in the index. When
  assigning an action item, they come in two groups as in §3.
- Renaming a person everywhere (for a typo) is in the People section's
  context menu: **Rename Person…** rewrites every meeting that mentions them.

## 7. Exports

From the toolbar's Export menu, File → Export Notes, or the meeting pane's
`…` menu, for the selected meeting:

| Command | Output | Shortcut |
| --- | --- | --- |
| Export as Word Document… | `.docx`, via a Save panel | ⌥⌘E |
| Export as Markdown… | `.md`, via a Save panel | — |
| Copy Notes as Plain Text | the pasteboard, ready for an email | ⇧⌘C |

The suggested file name is `yyyy-mm-dd-<title-slug>-notes.docx` (or
`.md`). After a copy, the toolbar's Export button shows a checkmark for
1.5 s, as Nice Mail's Copy button does.

The proposed content (the layout is Q5) is a short header followed by the
notes in their order, with action items and decisions labelled:

```
Budget review
Monday 5 October 2026, 14:00–15:00
Location: Microsoft Teams (https://teams.microsoft.com/l/…)
People: Alice Smith, Bob Jones, Carol White

Q4 forecast and discretionary spend.

Notes
- Forecast is on track for Q4.
- DECISION: Freeze discretionary spend until January.
- ACTION (Alice Smith, Erin Brown): Send revised forecast to finance.

Action items
- Alice Smith, Erin Brown: Send revised forecast to finance.
```

- **Plain text** uses only ASCII-safe punctuation apart from the people's
  own names, wraps nothing (mail clients wrap), and ends with a newline.
- **Markdown** uses a level-1 heading for the title, a bullet list for the
  header fields, and `**Decision:**` / `**Action (…):**` labels.
- **Word** uses the built-in Title, Heading 1 and List Bullet styles, so
  the result picks up the reader's theme, with bold labels. The `.docx`
  is written by the core (a handful of OOXML parts in a ZIP), with no
  third-party dependency, and opens in Word, Pages and Google Docs.

## 8. Workspace format

The full reference, including the slug rules, is
[FILE_FORMAT.md](FILE_FORMAT.md). In short:

```
(workspace root)/
    meetings/<yyyy>/<yyyy-mm-dd>-<hhmm>-<title-slug>.yml   one meeting per file
    platforms.yml                                        platform instructions (if Q6 = workspace)
```

```yaml
title: Budget review
date: 2026-10-05
time: '14:00'
end_time: '15:00'
location: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc
people:
- Alice Smith
- Bob Jones
- Carol White
description: Q4 forecast and discretionary spend.
notes:
- text: Forecast is on track for Q4.
- text: Freeze discretionary spend until January.
  kind: decision
- text: Send revised forecast to finance.
  kind: action
  assignees:
  - Alice Smith
  - Erin Brown
```

- Times are **local wall-clock times** with no time zone, as written in a
  paper diary. A 14:00 meeting stays at 14:00 if you travel.
- The file name is derived from the date, time and title, using only
  lower-case letters, digits and dashes (the title becomes a slug of at
  most 40 characters, accents removed), at most 56 characters before
  `.yml`. The file is renamed when any of those change (with `-2`, `-3`… on
  a collision), so the folder reads as a chronological log in Finder. The
  year folders keep any one folder small.
- Keys are written in the order shown, empty optional keys are omitted,
  and unknown keys are preserved, so a hand edit or a future version's
  field survives a save.
- A file that does not parse is left untouched and listed in a banner
  ("1 meeting file could not be read"), with Reveal in Finder.
- **Refresh** (⌘R) re-reads files that changed on disk, and the app also
  refreshes when it becomes active, to pick up edits from a sync client.

## 9. Modules

```
Package.swift                 SwiftPM manifest (no Xcode project)
Sources/MeetingsCore/         the model: Foundation + Yams, no AppKit/SwiftUI
Sources/QDVCMeetings/         the SwiftUI/AppKit app
Tests/MeetingsCoreTests/      unit tests
tools/make_icon.py            regenerates Resources/AppIcon.{svg,icns}
scripts/build-app.sh          builds and ad-hoc signs "QDVC Meetings.app"
sample-workspace/             a few meetings to try the app on
```

`MeetingsCore`: `Models` (Meeting, Note, NoteKind), `Location` (kind
detection), `People` (normalisation, the index, suggestions, rename),
`Naming` (slugs, file names, collisions), `MeetingFile` (YAML read/write
with key order and unknown keys), `Workspace` (load, refresh, create, save,
rename, trash), `DateBuckets` (list headings), `Export` (plain text,
Markdown), `DOCX` (OOXML parts and a small ZIP writer with CRC-32).

The app (`QDVCMeetings`): `MeetingsApp`, `AppModel` (`@Observable`,
main-actor), `Commands`, `ContentView` (window, toolbar, banners, welcome
screen), `SidebarView`, `MeetingListView`, `CalendarMonthView`,
`MeetingPane`, `NotesList`, `TokenField` (an `NSTokenField` wrapper with
grouped completions), `MeetingSheet`, `SettingsView`, `Prefs`, `Platform`.

As in GTD EML, the core declares no macOS-only API, so it and its tests
also build with a Linux Swift toolchain.

## 10. Not planned

- Syncing with Calendar (EventKit), or importing / exporting `.ics`.
- Recurrence rules (Duplicate Meeting covers the common case).
- Reminders or notifications.
- Contacts integration (see Q4).
- Any network access.

## 11. Decisions

All the proposals above were accepted, including Duplicate Meeting and
Rename Person. The open questions were settled as follows:

1. **Storage:** one YAML file per meeting in a workspace folder, as in §8.
2. **End time:** optional.
3. **Location:** one field, which can hold any of the four kinds.
4. **People:** names only.
5. **Export layout:** notes in order with DECISION / ACTION labels, then a
   recap of the action items.
6. **Platform instructions:** stored in the workspace (`platforms.yml`).
7. **Action items:** text and assignees, no done state.

Three adjustments were asked for and made:

- Whether a meeting has notes is very clear in both views: the notes badge
  and "No notes" in the list (§2.3) and the notes symbol on calendar chips
  (§2.4).
- Notes can be rearranged by drag and drop (§3).
- File names contain only lower-case letters, digits, dashes and the
  folder slashes (and the `.yml` extension), are generated by the slug
  rules, and are kept short (§8, FILE_FORMAT.md §2).

Identity: repository `qdvc-meetings-mac`, app "QDVC Meetings", bundle
identifier `org.qdvc.meetings.mac`. The calendar has a Month view only;
callouts are for Teams and Zoom only.

Changes made while building:

- Month navigation uses ⌘[ / ⌘] rather than ⌘← / ⌘→ (§2.1).
- Assignee suggestions are ordered rather than grouped under headings (§3).
- Settings also has the default length of a new meeting (no end time, or
  15 minutes to 2 hours; 1 hour by default).
- Search (⌘F, Edit → Search Meetings) looks through every date, as Mail's
  search looks through every mailbox; in Calendar view it filters the grid.

Changes asked for after the first build:

- The calendar has no meeting pane; clicking a meeting shows it in the list
  under Upcoming or Past (§2.4).
- Meetings can have attachments (§3a), kept in a folder beside the meeting
  file. Attachment names are kept as given, not slugified; only the meeting
  file and its folder follow the slug rules.
