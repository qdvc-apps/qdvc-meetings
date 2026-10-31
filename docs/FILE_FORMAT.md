# Workspace File Format

A QDVC Meetings workspace is an ordinary folder of small YAML files. Nothing
is kept in a database, so a workspace can be versioned with Git, synced with
Syncthing or iCloud Drive, searched with `grep`, and edited by hand. This
document is the reference for the format; `MeetingsCore` implements it and
its tests check it.

---

## 1. Layout

```
(workspace root)/
    meetings/<yyyy>/<yyyy-mm-dd>-<hhmm>-<title-slug>.yml   one meeting per file
    platforms.yml                                        platform instructions (optional)
```

- A folder counts as a workspace if it contains `meetings/`. Opening any
  other folder (after confirmation) creates `meetings/`.
- Every `*.yml` or `*.yaml` file anywhere under `meetings/` is a meeting,
  whatever its name or folder, **except** inside an attachments folder: a
  folder with a meeting file of the same name beside it (§3.4). So a `.yml`
  file attached to a meeting is never read as a meeting. Hidden files and folders (names starting
  with `.`) are ignored, so sync-tool folders such as Syncthing's
  `.stversions` do not create phantom meetings.
- Files are written atomically and immediately. Encoding is UTF-8 with `\n`
  line endings.

## 2. File names

Every name the app makes uses only lower-case `a–z`, digits `0–9` and `-`,
with `/` between folders and the `.yml` extension:

```
meetings/2026/2026-10-05-1400-budget-review.yml
```

- The folder is the meeting's year, `meetings/<yyyy>`.
- The stem is `<yyyy-mm-dd>-<hhmm>-<title-slug>`, at most 56 characters.
- If the name is taken, `-2`, `-3`… is added: `…-budget-review-2.yml`. A
  folder of the same name (without `.yml`) also counts as taken, so a new
  meeting never adopts an existing folder as its attachments.
- The file is renamed (and moved to another year folder) when the meeting's
  date, time or title changes, and its attachments folder (§3.4) moves with
  it, so the folder reads as a chronological log.
  A name that differs only by its collision suffix is left alone. A year
  folder left empty by a move or a deletion is removed.
- The name is only a convenience: the app never reads anything from it. A
  file you name yourself is read, and keeps its name until you change the
  meeting's date, time or title in the app.

### 2.1 The title slug

1. Lower-case the title; replace `&` with " and " and `@` with " at ".
2. Remove apostrophes and backticks (`'`, `’`, `‘`, `` ` ``), so "Bob's"
   becomes "bobs".
3. Replace letters that have no accent-free form: `ß`→`ss`, `æ`→`ae`,
   `œ`→`oe`, `ø`→`o`, `ł`→`l`, `đ`/`ð`→`d`, `þ`→`th`, `ı`→`i`, `ħ`→`h`,
   `ŋ`→`n`, `ſ`→`s`. Then remove accents (`é`→`e`, `ü`→`u`).
4. Turn every run of characters other than `a–z` and `0–9` into a single
   `-`, and trim `-` from both ends.
5. If the result is longer than 40 characters, cut it at 40; if that cut
   falls inside a word, cut instead at the last `-` that keeps at least 20
   characters. Trim `-` again.
6. If nothing is left (for example a title in a non-Latin script), use
   `meeting`.

| Title | Slug |
| --- | --- |
| `Budget review` | `budget-review` |
| `Supplier call: Ørsted & Co` | `supplier-call-orsted-and-co` |
| `Bob's 1:1` | `bobs-1-1` |
| `Café catch-up` | `cafe-catch-up` |
| `Quarterly planning workshop for the regional operations leadership team` | `quarterly-planning-workshop-for-the` |
| `会议` | `meeting` |

Export file names use the same slug: `yyyy-mm-dd-<title-slug>-notes.docx`
(or `.md`).

## 3. Meeting files

```yaml
title: Budget review
date: 2026-10-05
time: '14:00'
end_time: '15:00'
location: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc
people:
- Alice Smith
- Bob Jones
description: |-
  Q4 forecast.
  Discretionary spend.
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

| Key | Type | Required | Notes |
| --- | --- | --- | --- |
| `title` | string | no | One line. Missing or empty reads as "Untitled Meeting". |
| `date` | `yyyy-mm-dd` | **yes** | A calendar day with no time zone. |
| `time` | `HH:MM` | **yes** | Wall-clock start time, 24-hour. `H:MM` and `HH:MM:SS` are also read. |
| `end_time` | `HH:MM` | no | Wall-clock end time on the same day. |
| `location` | string | no | One line: free text, or a link (§3.1). |
| `people` | list of strings | no | Names (§3.2). A single string reads as a one-item list. |
| `description` | string | no | Any number of lines. |
| `notes` | list | no | §3.3. |

- **Times have no time zone**, as in a paper diary: a 14:00 meeting stays at
  14:00 wherever you are. They are written single-quoted (`'14:00'`)
  because YAML 1.1 readers such as PyYAML would read a bare `14:00` as the
  number 840. Bare times are read correctly here, since every scalar is
  read as the text written.
- **Key order** on write: the order in the table, then any other keys in
  the order they were read. Empty optional keys are left out.
- **Unknown keys are kept.** A key this version does not know (at the top
  level or in a note) is written back unchanged, so a hand edit or a future
  version's field survives a save. Its value keeps its content but not
  necessarily its layout: a flow-style list `[1, 2]` comes back in block
  style.
- **Strings** are written plain where that reads back as the same string,
  single-quoted where a plain scalar would read as something else
  (`'yes'`, `'123'`, or text containing `: `), and as a literal block
  (`|-`) when they have several lines. Trailing spaces and newlines are
  trimmed.
- **A file that cannot be read** (not YAML, not a mapping, or no usable
  `date` or `time`) is left untouched and named in a banner above the
  meetings, with Reveal in Finder.

### 3.1 Location kinds

The kind is worked out from the text each time it is shown, never stored.
Matching is case-insensitive, on the URL's scheme and host, after trimming
spaces; text containing spaces is never a link.

| Kind | Rule | Example |
| --- | --- | --- |
| Microsoft Teams | `https` URL whose host contains `teams` and, later, `microsoft` (the `https://*teams*microsoft*/` pattern) | `https://teams.microsoft.com/l/meetup-join/…` |
| Zoom | `https` URL whose host contains `zoom` (`https://*zoom*/`) | `https://us02web.zoom.us/j/…` |
| Google Maps | `https` URL with host `maps.google.*`, `maps.app.goo.gl`, `google.*` and a path starting `/maps`, or `goo.gl` and a path starting `/maps` (a leading `www.` is ignored) | `https://maps.app.goo.gl/AbC123` |
| Other link | any other `http` or `https` URL | `https://example.com/room` |
| Free text | anything else | `Room 4.12` |

### 3.2 People

A person is a name. Names are compared ignoring case and extra spaces, so
`alice  SMITH` and `Alice Smith` are one person. On write, names are
trimmed, runs of spaces are collapsed and later duplicates are removed.
There is no separate file of people: the app derives the list from every
meeting's `people` and every action item's `assignees` each time it loads,
showing each person under their most common spelling.

### 3.3 Notes

Each item in `notes` is a mapping:

| Key | Type | Notes |
| --- | --- | --- |
| `text` | string | Any number of lines. Notes with no text are not written. |
| `kind` | `action` or `decision` | Omitted for a plain note. On read, `action item`, `action_item`, `todo` and `task` also mean `action`, and `decided` means `decision`; anything else is a plain note. |
| `assignees` | list of strings | People assigned to an action item. |

- Notes are kept in the order written; the app's drag and drop and Move
  Up / Move Down change that order.
- `assignees` are kept on a note that is not an action item (so turning an
  action item into a decision and back loses nothing), but are only shown,
  searched, counted and exported for action items.
- A plain string in the list reads as a plain note with that text.

### 3.4 Attachments

A meeting's attachments are the files in the folder beside its file with
the same name minus the extension:

```
meetings/2026/2026-09-14-1000-project-kick-off.yml
meetings/2026/2026-09-14-1000-project-kick-off/
    Agenda.pdf
    Whiteboard photo.png
```

- The folder is created when the first file is attached, and removed when
  the last is moved to the Trash (a folder holding only `.DS_Store` counts
  as empty). It follows the meeting's file when that is renamed or moved to
  another year, and goes to the Trash with it when the meeting is deleted.
- Nothing about attachments is stored in the meeting file: the folder's
  contents are the attachments, so files added or removed in Finder show up
  on the next refresh.
- Attachments keep the names they were given. When a name is taken
  (ignoring case), a number is added before the extension, as Finder does:
  `photo.png`, `photo 2.png`, `photo 3.png`. These names are exempt from
  the slug rules in §2.
- Hidden files (names starting with `.`) are not shown. Folders inside the
  attachments folder are shown as single attachments.

## 4. `platforms.yml`

Short instructions shown as a callout on every meeting on that platform:

```yaml
teams: Use the Teams desktop app and sign in with your work account.
zoom: 'Join from the Zoom app with SSO (company domain: example).'
```

- Keys `teams` and `zoom`; empty ones are left out, and other keys are
  kept. A file with no instructions is written as `{}`.
- The file is optional; a missing file means no callouts. About 200
  characters (two sentences) fit the callout well; longer text is allowed.
- Edited in Settings → Platforms, and written when you leave each field.
