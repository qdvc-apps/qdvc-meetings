import Foundation
import XCTest
@testable import MeetingsCore

final class DateTests: XCTestCase {
    func testOrdinalRoundTrip() {
        let d = LocalDate("2026-10-05")!
        XCTAssertEqual(LocalDate(ordinal: d.ordinal), d)
        XCTAssertEqual(LocalDate("1970-01-01")!.ordinal, 0)
        XCTAssertEqual(LocalDate("2024-02-28")!.adding(days: 1).iso, "2024-02-29")
        XCTAssertEqual(LocalDate("2026-12-31")!.adding(days: 1).iso, "2027-01-01")
    }

    func testWeekdayAndWeekStart() {
        let monday = LocalDate("2026-10-05")!
        XCTAssertEqual(monday.weekday, 2)
        XCTAssertEqual(LocalDate("2026-10-04")!.weekday, 1)
        XCTAssertEqual(LocalDate("2026-10-08")!.startOfWeek(firstWeekday: 2), monday)
        XCTAssertEqual(LocalDate("2026-10-08")!.startOfWeek(firstWeekday: 1).iso, "2026-10-04")
        XCTAssertEqual(LocalDate("2026-10-04")!.startOfWeek(firstWeekday: 2).iso, "2026-09-28")
    }

    func testMonths() {
        XCTAssertEqual(LocalDate("2026-01-31")!.adding(months: 1).iso, "2026-02-28")
        XCTAssertEqual(LocalDate("2026-11-15")!.adding(months: 3).iso, "2027-02-15")
        XCTAssertEqual(LocalDate("2026-01-15")!.adding(months: -1).iso, "2025-12-15")
    }

    func testParsing() {
        XCTAssertNil(LocalDate("2026-02-30"))
        XCTAssertNil(LocalDate("26-02-03"))
        XCTAssertEqual(LocalTime("9:05")?.text, "09:05")
        XCTAssertEqual(LocalTime("14:00:30")?.text, "14:00")
        XCTAssertNil(LocalTime("24:00"))
        XCTAssertNil(LocalTime("1400"))
        XCTAssertEqual(LocalTime("23:30")!.adding(minutes: 60).text, "00:30")
    }
}

final class LocationTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(LocationKind.of(""), .none)
        XCTAssertEqual(LocationKind.of("  Room 4.12 "), .text)
        XCTAssertEqual(LocationKind.of("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc"), .teams)
        XCTAssertEqual(LocationKind.of("HTTPS://Teams.Microsoft.com/l/x"), .teams)
        XCTAssertEqual(LocationKind.of("https://teams.live.com/meet/123"), .link)
        XCTAssertEqual(LocationKind.of("https://zoom.us/j/123456"), .zoom)
        XCTAssertEqual(LocationKind.of("https://us02web.zoom.us/j/123?pwd=x"), .zoom)
        XCTAssertEqual(LocationKind.of("http://zoom.us/j/1"), .link)
        XCTAssertEqual(LocationKind.of("https://maps.app.goo.gl/AbC123"), .googleMaps)
        XCTAssertEqual(LocationKind.of("https://www.google.com/maps/place/Sydney"), .googleMaps)
        XCTAssertEqual(LocationKind.of("https://maps.google.com.au/?q=x"), .googleMaps)
        XCTAssertEqual(LocationKind.of("https://goo.gl/maps/xyz"), .googleMaps)
        XCTAssertEqual(LocationKind.of("https://www.google.com/search?q=maps"), .link)
        XCTAssertEqual(LocationKind.of("https://example.com/teams-microsoft"), .link)
        XCTAssertEqual(LocationKind.of("Zoom room on level 2"), .text)
    }
}

final class NamingTests: XCTestCase {
    func testSlugify() {
        XCTAssertEqual(Naming.slugify("Budget review"), "budget-review")
        XCTAssertEqual(Naming.slugify("  Q4 Budget — Review!! "), "q4-budget-review")
        XCTAssertEqual(Naming.slugify("Café crème with Zoë"), "cafe-creme-with-zoe")
        XCTAssertEqual(Naming.slugify("Straße & Ørsted"), "strasse-and-orsted")
        XCTAssertEqual(Naming.slugify("Bob's 1:1"), "bobs-1-1")
        XCTAssertEqual(Naming.slugify("会议"), "meeting")
        XCTAssertEqual(Naming.slugify("R&D"), "r-and-d")
        XCTAssertEqual(Naming.slugify("--__--"), "meeting")
    }

    func testSlugLength() {
        let long = Naming.slugify("Quarterly planning workshop for the regional operations leadership team")
        XCTAssertLessThanOrEqual(long.count, Naming.maxSlugLength)
        XCTAssertEqual(long, "quarterly-planning-workshop-for-the")
        let word = Naming.slugify(String(repeating: "a", count: 60))
        XCTAssertEqual(word.count, 40)
        XCTAssertEqual(Naming.slugify("abc def", maxLength: 3), "abc")
    }

    func testSlugAlphabet() {
        let samples = ["Ünïcødé 2026/10 – planning?", "a/b\\c", "Ελληνικά test", "x\ny\tz"]
        for s in samples {
            let slug = Naming.slugify(s)
            XCTAssertTrue(slug.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }, slug)
            XCTAssertFalse(slug.hasPrefix("-") || slug.hasSuffix("-") || slug.contains("--"), slug)
        }
    }

    func testStemAndPaths() {
        let m = Meeting(title: "Budget Review", date: LocalDate("2026-10-05")!, time: LocalTime("9:30")!)
        XCTAssertEqual(Naming.stem(for: m), "2026-10-05-0930-budget-review")
        XCTAssertEqual(Naming.folder(for: m), "meetings/2026")
        let folder = "meetings/2026"
        XCTAssertTrue(Naming.path("meetings/2026/2026-10-05-0930-budget-review.yml", fits: "2026-10-05-0930-budget-review", in: folder))
        XCTAssertTrue(Naming.path("meetings/2026/2026-10-05-0930-budget-review-3.yml", fits: "2026-10-05-0930-budget-review", in: folder))
        XCTAssertFalse(Naming.path("meetings/2026/2026-10-05-0930-budget-review-x.yml", fits: "2026-10-05-0930-budget-review", in: folder))
        XCTAssertFalse(Naming.path("meetings/2025/2026-10-05-0930-budget-review.yml", fits: "2026-10-05-0930-budget-review", in: folder))
        let taken: Set<String> = ["meetings/2026/a.yml", "meetings/2026/a-2.yml"]
        XCTAssertEqual(Naming.uniquePath(stem: "a", in: folder, taken: taken), "meetings/2026/a-3.yml")
        XCTAssertEqual(Naming.exportFileName(for: m, extension: "docx"), "2026-10-05-budget-review-notes.docx")
    }
}

final class PeopleTests: XCTestCase {
    func meetings() -> [Meeting] {
        let d = LocalDate("2026-10-01")!
        return [
            Meeting(title: "A", date: d, time: LocalTime("09:00")!, people: ["Alice Smith", "Bob Jones"]),
            Meeting(title: "B", date: d.adding(days: 2), time: LocalTime("09:00")!, people: ["alice smith", "Carol White"],
                    notes: [Note(text: "Do it", kind: .action, assignees: ["Erin Brown"]),
                            Note(text: "Hidden", kind: .note, assignees: ["Zed Hidden"])]),
            Meeting(title: "C", date: d.adding(days: 4), time: LocalTime("09:00")!, people: ["Alice Smith", "Alice Walker"]),
        ]
    }

    func testIndex() {
        let index = PeopleIndex(meetings: meetings())
        XCTAssertEqual(index.all.map(\.name), ["Alice Smith", "Alice Walker", "Bob Jones", "Carol White", "Erin Brown"])
        XCTAssertEqual(index.person(forKey: "alice smith")?.meetingCount, 3)
        XCTAssertEqual(index.canonicalName("ALICE   smith"), "Alice Smith")
        XCTAssertEqual(index.canonicalName(" new  person "), "new person")
    }

    func testSuggestions() {
        let index = PeopleIndex(meetings: meetings())
        XCTAssertEqual(index.suggestions(matching: "a").map(\.name), ["Alice Smith", "Alice Walker"])
        XCTAssertEqual(index.suggestions(matching: "smi").map(\.name), ["Alice Smith"])
        XCTAssertEqual(index.suggestions(matching: "", excluding: ["alice smith"]).first?.name, "Alice Walker")
        let assignees = index.assigneeSuggestions(matching: "", meetingPeople: ["Carol White", "Bob Jones"])
        XCTAssertEqual(Array(assignees.prefix(3)), ["Carol White", "Bob Jones", "Alice Smith"])
        XCTAssertTrue(People.name("José García", matches: "garc"))
    }

    func testShortNamesAndRename() {
        let index = PeopleIndex(meetings: meetings())
        XCTAssertEqual(index.shortName("Bob Jones"), "Bob")
        XCTAssertEqual(index.shortName("Alice Smith"), "Alice Smith")
        let m = meetings()[1]
        let renamed = People.renaming(m, from: "alice smith", to: "Carol White")!
        XCTAssertEqual(renamed.people, ["Carol White"])
        XCTAssertNil(People.renaming(m, from: "nobody", to: "X"))
        XCTAssertEqual(People.merge([" a ", "A", "b", ""]), ["a", "b"])
    }
}

final class MeetingFileTests: XCTestCase {
    let sample = """
    title: Budget review
    date: 2026-10-05
    time: '14:00'
    end_time: 15:00
    location: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc
    people:
    - Alice Smith
    - Bob Jones
    description: |-
      Q4 forecast.
      Discretionary spend.
    notes:
    - text: Forecast is on track.
    - text: Freeze spend.
      kind: decision
    - text: Send forecast.
      kind: action
      assignees:
      - Alice Smith
      - Erin Brown
      due: 2026-10-10
    - Plain string note
    custom_key:
      nested: [1, 2]

    """

    func testParse() throws {
        let m = try MeetingFile.parse(sample, relativePath: "meetings/2026/x.yml")
        XCTAssertEqual(m.title, "Budget review")
        XCTAssertEqual(m.date.iso, "2026-10-05")
        XCTAssertEqual(m.time.text, "14:00")
        XCTAssertEqual(m.endTime?.text, "15:00")
        XCTAssertEqual(m.locationKind, .teams)
        XCTAssertEqual(m.people, ["Alice Smith", "Bob Jones"])
        XCTAssertEqual(m.details, "Q4 forecast.\nDiscretionary spend.")
        XCTAssertEqual(m.notes.map(\.kind), [.note, .decision, .action, .note])
        XCTAssertEqual(m.notes[2].assignees, ["Alice Smith", "Erin Brown"])
        XCTAssertEqual(m.notes[2].extras.map(\.key), ["due"])
        XCTAssertEqual(m.notes[3].text, "Plain string note")
        XCTAssertEqual(m.extras.map(\.key), ["custom_key"])
        XCTAssertEqual(m.noteCount, 4)
        XCTAssertEqual(m.actionItemCount, 1)
        XCTAssertEqual(m.decisionCount, 1)
    }

    func testRenderRoundTrip() throws {
        let m = try MeetingFile.parse(sample)
        let text = MeetingFile.render(m)
        let expected = """
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
        - text: Forecast is on track.
        - text: Freeze spend.
          kind: decision
        - text: Send forecast.
          kind: action
          assignees:
          - Alice Smith
          - Erin Brown
          due: 2026-10-10
        - text: Plain string note
        custom_key:
          nested:
          - 1
          - 2

        """
        // Unknown keys keep their values, though not their flow style.
        XCTAssertEqual(text, expected)
        let again = try MeetingFile.parse(text, id: m.id)
        var a = m, b = again
        for i in a.notes.indices { a.notes[i].id = b.notes[i].id }
        a.extras = []; b.extras = []
        for i in a.notes.indices { a.notes[i].extras = []; b.notes[i].extras = [] }
        XCTAssertEqual(a, b)
    }

    func testQuotingAndUnicode() throws {
        var m = Meeting(title: "yes", date: LocalDate("2026-01-02")!, time: LocalTime("08:00")!,
                        location: "Café: level 2", people: ["Zoë 12", "123"], details: "",
                        notes: [Note(text: "- not a list"), Note(text: "  "), Note(text: "a #tag # here")])
        m.notes.append(Note(text: "multi\nline\n", kind: .action, assignees: ["true"]))
        let text = MeetingFile.render(m)
        XCTAssertTrue(text.contains("title: 'yes'"), text)
        XCTAssertTrue(text.contains("Zoë"), text)
        let back = try MeetingFile.parse(text)
        XCTAssertEqual(back.title, "yes")
        XCTAssertEqual(back.location, "Café: level 2")
        XCTAssertEqual(back.people, ["Zoë 12", "123"])
        XCTAssertEqual(back.notes.map(\.text), ["- not a list", "a #tag # here", "multi\nline"])
        XCTAssertEqual(back.notes.last?.assignees, ["true"])
    }

    func testErrors() {
        XCTAssertThrowsError(try MeetingFile.parse("title: x\ntime: '10:00'\n")) {
            XCTAssertEqual($0 as? MeetingFileError, .missingDate)
        }
        XCTAssertThrowsError(try MeetingFile.parse("date: 2026-13-01\ntime: '10:00'\n"))
        XCTAssertThrowsError(try MeetingFile.parse("- a\n- b\n")) {
            XCTAssertEqual($0 as? MeetingFileError, .notAMapping)
        }
        XCTAssertThrowsError(try MeetingFile.parse("date: [unclosed\n"))
        let untitled = try? MeetingFile.parse("date: 2026-01-01\ntime: 9:00\n")
        XCTAssertEqual(untitled?.title, "Untitled Meeting")
    }

    func testPlatforms() throws {
        let p = try MeetingFile.parsePlatforms("teams: Use the desktop app.\nzoom: 'Join: via SSO'\nwebex: later\n")
        XCTAssertEqual(p.teams, "Use the desktop app.")
        XCTAssertEqual(p.zoom, "Join: via SSO")
        XCTAssertEqual(MeetingFile.renderPlatforms(p), "teams: Use the desktop app.\nzoom: 'Join: via SSO'\nwebex: later\n")
        XCTAssertEqual(MeetingFile.renderPlatforms(PlatformInstructions()), "{}\n")
        XCTAssertEqual(try MeetingFile.parsePlatforms("{}\n"), PlatformInstructions())
        XCTAssertEqual(try MeetingFile.parsePlatforms(""), PlatformInstructions())
    }
}

final class WorkspaceTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("meetings-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSaveRenameAndLoad() throws {
        let ws = Workspace(root: root)
        XCTAssertFalse(Workspace.looksLikeWorkspace(root))
        try ws.ensureLayout()
        XCTAssertTrue(Workspace.looksLikeWorkspace(root))

        var a = Meeting(title: "Design sync", date: LocalDate("2026-10-05")!, time: LocalTime("16:30")!)
        a = try ws.save(a)
        XCTAssertEqual(a.relativePath, "meetings/2026/2026-10-05-1630-design-sync.yml")

        var b = Meeting(title: "Design Sync!", date: LocalDate("2026-10-05")!, time: LocalTime("16:30")!)
        b = try ws.save(b)
        XCTAssertEqual(b.relativePath, "meetings/2026/2026-10-05-1630-design-sync-2.yml")

        // Saving b unchanged keeps its -2 name.
        b.people = ["Alice"]
        b = try ws.save(b)
        XCTAssertEqual(b.relativePath, "meetings/2026/2026-10-05-1630-design-sync-2.yml")

        // Moving a to next year renames it and removes the empty folder later.
        a.date = LocalDate("2027-01-04")!
        a.title = "Kick-off"
        a = try ws.save(a)
        XCTAssertEqual(a.relativePath, "meetings/2027/2027-01-04-1630-kick-off.yml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("meetings/2026/2026-10-05-1630-design-sync.yml").path))

        let result = ws.load()
        XCTAssertEqual(result.failures, [])
        XCTAssertEqual(Set(result.meetings.map(\.id)), Set([a.id, b.id]))

        // An unreadable file is reported, not loaded.
        try "date: nope\n".write(to: root.appendingPathComponent("meetings/2026/bad.yml"), atomically: true, encoding: .utf8)
        let again = ws.load()
        XCTAssertEqual(again.meetings.count, 2)
        XCTAssertEqual(again.failures.map(\.relativePath), ["meetings/2026/bad.yml"])

        // Moving b away empties 2026 except for bad.yml, so the folder stays.
        b.date = LocalDate("2027-02-01")!
        b = try ws.save(b)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("meetings/2026").path))
        try FileManager.default.removeItem(at: root.appendingPathComponent("meetings/2026/bad.yml"))
        ws.forget("meetings/2026/bad.yml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("meetings/2026").path))
    }

    func testAttachments() throws {
        let ws = Workspace(root: root)
        try ws.ensureLayout()
        var m = Meeting(title: "Site visit", date: LocalDate("2026-10-07")!, time: LocalTime("11:00")!)
        m = try ws.save(m)
        XCTAssertEqual(Workspace.attachmentsFolder(forMeetingPath: m.relativePath!), "meetings/2026/2026-10-07-1100-site-visit")

        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let photo = src.appendingPathComponent("Photo.PNG")
        try Data("png".utf8).write(to: photo)
        // A .yml attachment must not be read as a meeting.
        let config = src.appendingPathComponent("config.yml")
        try "date: 2026-01-01\ntime: '09:00'\n".write(to: config, atomically: true, encoding: .utf8)

        XCTAssertEqual(try ws.addAttachments([photo, config], toMeetingPath: m.relativePath!), ["Photo.PNG", "config.yml"])
        XCTAssertEqual(try ws.addAttachments([photo], toMeetingPath: m.relativePath!), ["Photo 2.PNG"])
        let inFolder = ws.url(for: "meetings/2026/2026-10-07-1100-site-visit/Photo.PNG")
        XCTAssertEqual(try ws.addAttachments([inFolder], toMeetingPath: m.relativePath!), [])

        let result = ws.load()
        XCTAssertEqual(result.meetings.count, 1)
        XCTAssertEqual(result.attachments[m.relativePath!]?.map(\.name), ["config.yml", "Photo 2.PNG", "Photo.PNG"])
        XCTAssertEqual(result.attachments[m.relativePath!]?.first?.size, 31)

        // Renaming the meeting moves its folder, across years too.
        m.title = "Site walk"
        m.date = LocalDate("2027-03-01")!
        m = try ws.save(m)
        XCTAssertEqual(m.relativePath, "meetings/2027/2027-03-01-1100-site-walk.yml")
        XCTAssertEqual(ws.attachments(forMeetingPath: m.relativePath!).count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ws.url(for: "meetings/2026").path))

        // A folder already using a stem pushes a new meeting to -2.
        try FileManager.default.createDirectory(at: ws.url(for: "meetings/2027/2027-03-02-0900-x"), withIntermediateDirectories: true)
        let other = try ws.save(Meeting(title: "X", date: LocalDate("2027-03-02")!, time: LocalTime("09:00")!))
        XCTAssertEqual(other.relativePath, "meetings/2027/2027-03-02-0900-x-2.yml")

        for a in ws.attachments(forMeetingPath: m.relativePath!) {
            try FileManager.default.removeItem(at: ws.url(for: a.relativePath))
        }
        ws.removeAttachmentsFolderIfEmpty(forMeetingPath: m.relativePath!)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ws.url(for: "meetings/2027/2027-03-01-1100-site-walk").path))
        XCTAssertEqual(Workspace.uniqueAttachmentName("notes", taken: ["notes", "notes 2"]), "notes 3")
    }

    func testPlatformsFile() throws {
        let ws = Workspace(root: root)
        XCTAssertEqual(try ws.loadPlatformInstructions(), PlatformInstructions())
        try ws.savePlatformInstructions(PlatformInstructions(teams: "Desktop app.", zoom: ""))
        XCTAssertEqual(try String(contentsOf: ws.platformsURL, encoding: .utf8), "teams: Desktop app.\n")
        XCTAssertEqual(try ws.loadPlatformInstructions().teams, "Desktop app.")
    }
}

final class BucketTests: XCTestCase {
    func testBuckets() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_GB")
        cal.firstWeekday = 2
        // Wednesday 7 October 2026.
        let b = DateBucketer(today: LocalDate("2026-10-07")!, calendar: cal)
        func t(_ s: String) -> String { b.bucket(for: LocalDate(s)!).title }
        XCTAssertEqual(t("2026-10-07"), "Today")
        XCTAssertEqual(t("2026-10-08"), "Tomorrow")
        XCTAssertEqual(t("2026-10-10"), "Saturday")
        XCTAssertEqual(t("2026-10-11"), "Sunday")
        XCTAssertEqual(t("2026-10-12"), "Next Week")
        XCTAssertEqual(t("2026-10-19"), "Later This Month")
        XCTAssertEqual(t("2026-11-02"), "November")
        XCTAssertEqual(t("2027-01-02"), "January 2027")
        XCTAssertEqual(t("2026-10-06"), "Yesterday")
        XCTAssertEqual(t("2026-10-05"), "Monday")
        XCTAssertEqual(t("2026-09-28"), "Last Week")
        XCTAssertEqual(t("2026-10-01"), "Last Week")
        XCTAssertEqual(t("2026-09-20"), "September")
        XCTAssertEqual(t("2025-12-20"), "December 2025")
    }
}

final class ExportTests: XCTestCase {
    func meeting() -> Meeting {
        Meeting(title: "Budget review", date: LocalDate("2026-10-05")!, time: LocalTime("14:00")!,
                endTime: LocalTime("15:00")!,
                location: "https://teams.microsoft.com/l/x", people: ["Alice Smith", "Bob Jones"],
                details: "Q4 forecast.",
                notes: [Note(text: "Forecast is on track."),
                        Note(text: "Freeze spend.", kind: .decision),
                        Note(text: "Send forecast.\nBy Friday.", kind: .action, assignees: ["Alice Smith", "Erin Brown"]),
                        Note(text: "Book room.", kind: .action),
                        Note(text: "   ")])
    }

    let formatter = MeetingFormatter(locale: Locale(identifier: "en_GB"))

    func testPlainText() {
        let text = NotesExport.plainText(meeting(), formatter: formatter)
        let when = formatter.when(meeting(), dash: "-")
        XCTAssertEqual(text, """
        Budget review
        \(when)
        Location: Microsoft Teams (https://teams.microsoft.com/l/x)
        People: Alice Smith, Bob Jones

        Q4 forecast.

        Notes
        - Forecast is on track.
        - DECISION: Freeze spend.
        - ACTION (Alice Smith, Erin Brown): Send forecast.
          By Friday.
        - ACTION: Book room.

        Action items
        - Alice Smith, Erin Brown: Send forecast.
          By Friday.
        - Unassigned: Book room.

        """)
        XCTAssertTrue(when.hasSuffix("14:00-15:00"), when)
    }

    func testMarkdown() {
        let md = NotesExport.markdown(meeting(), formatter: formatter)
        XCTAssertTrue(md.hasPrefix("# Budget review\n\n- **When:** "), md)
        XCTAssertTrue(md.contains("- **Location:** [Microsoft Teams](https://teams.microsoft.com/l/x)\n"), md)
        XCTAssertTrue(md.contains("- **Decision:** Freeze spend.\n"), md)
        XCTAssertTrue(md.contains("- **Action (Alice Smith, Erin Brown):** Send forecast.\n  By Friday.\n"), md)
        XCTAssertTrue(md.contains("## Action items\n\n- **Alice Smith, Erin Brown:** Send forecast."), md)
        var empty = meeting()
        empty.notes = []
        XCTAssertTrue(NotesExport.markdown(empty, formatter: formatter).contains("## Notes\n\nNo notes.\n"))
        XCTAssertFalse(NotesExport.markdown(empty, formatter: formatter).contains("Action items"))
    }

    func testDocxIsAZip() {
        let data = DocxExport.document(meeting(), formatter: formatter, created: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("[Content_Types].xml"))
        XCTAssertTrue(text.contains("word/document.xml"))
        XCTAssertTrue(text.contains("<w:pStyle w:val=\"ListBullet\"/>"))
        XCTAssertTrue(text.contains("Send forecast.</w:t><w:br/><w:t xml:space=\"preserve\">By Friday."))
        XCTAssertTrue(text.contains("TargetMode=\"External\""))
        XCTAssertEqual(DocxExport.escape("a<b & \"c\"\u{1}"), "a&lt;b &amp; &quot;c&quot;")
    }

    func testCRC32() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testSearch() {
        let m = meeting()
        XCTAssertTrue(m.matches("erin"))
        XCTAssertTrue(m.matches("budget FORECAST"))
        XCTAssertFalse(m.matches("budget nothing"))
        XCTAssertTrue(m.matches(""))
        XCTAssertTrue(m.involves(personKey: "erin brown"))
        XCTAssertEqual(m.duplicated().date.iso, "2026-10-12")
        XCTAssertTrue(m.duplicated().notes.isEmpty)
    }
}
