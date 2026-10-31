import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MeetingsCore

enum ViewMode: String, CaseIterable, Identifiable {
    case list
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .calendar: return "Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        }
    }
}

/// The Meetings section of the sidebar.
enum DateFilter: String, CaseIterable, Identifiable {
    case today
    case upcoming
    case past
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .past: return "Past"
        case .all: return "All Meetings"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .upcoming: return "calendar.badge.clock"
        case .past: return "clock.arrow.circlepath"
        case .all: return "tray.full"
        }
    }

    /// Upcoming and Today read soonest first; Past and All latest first.
    var ascending: Bool { self == .today || self == .upcoming }

    func includes(_ day: LocalDate, today: LocalDate) -> Bool {
        switch self {
        case .today: return day == today
        case .upcoming: return day >= today
        case .past: return day < today
        case .all: return true
        }
    }
}

enum SidebarItem: Hashable {
    case dates(DateFilter)
    /// A person, by `People.key`.
    case person(String)
}

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// The fields of the New / Edit Meeting sheet.
struct MeetingDraft: Equatable {
    var title = ""
    var date = Date()
    var start = Date()
    var hasEnd = true
    var end = Date()
    var location = ""
    var people: [String] = []
    var details = ""

    init(_ m: Meeting) {
        let cal = Calendar.current
        title = m.title
        date = m.date.date(calendar: cal)
        start = m.date.date(at: m.time, calendar: cal)
        hasEnd = m.endTime != nil
        end = m.date.date(at: m.endTime ?? m.time.adding(minutes: 60), calendar: cal)
        location = m.location
        people = m.people
        details = m.details
    }

    var startTime: LocalTime { LocalTime(start) }
    var endTime: LocalTime? { hasEnd ? LocalTime(end) : nil }

    var endsBeforeStart: Bool {
        guard let e = endTime else { return false }
        return e <= startTime
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !endsBeforeStart
    }

    /// Writes the fields into `m`, keeping its notes and identity.
    func apply(to m: inout Meeting) {
        m.title = People.normalize(title)
        m.date = LocalDate(date)
        m.time = startTime
        m.endTime = endTime
        m.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        m.people = People.merge(people)
        m.details = details
    }
}

struct MeetingEditorRequest: Identifiable {
    let id = UUID()
    /// Nil for a new meeting.
    let meetingID: UUID?
    let original: Meeting
}

enum ActiveSheet: Identifiable {
    case meeting(MeetingEditorRequest)
    case renamePerson(PersonSummary)

    var id: String {
        switch self {
        case .meeting(let r): return "meeting-\(r.id)"
        case .renamePerson(let p): return "rename-\(p.id)"
        }
    }
}

struct ListSection: Identifiable {
    let bucket: DateBucket
    var meetings: [Meeting]
    var id: String { bucket.id }
}

/// All app state and actions. Every change to a meeting is written to its
/// file straight away, except typing in a note, which is written after a
/// short pause (and whenever the selection changes or the app is left).
@Observable
@MainActor
final class AppModel {
    private(set) var workspace: Workspace?
    private(set) var meetings: [Meeting] = []
    private(set) var failures: [LoadFailure] = []
    /// Each meeting's attachments (the files in the folder beside its file).
    private(set) var attachments: [UUID: [Attachment]] = [:]
    private(set) var people = PeopleIndex(meetings: [])
    private(set) var instructions = PlatformInstructions()
    private(set) var instructionsError: String?
    private(set) var recentWorkspaces: [String] = Prefs.recentWorkspaces

    var sidebarSelection: SidebarItem? = .dates(.upcoming) {
        didSet { sidebarSelectionChanged() }
    }
    /// The date filter to return to when the list comes back.
    private var lastDateFilter: DateFilter = .upcoming

    var viewMode: ViewMode = Prefs.viewMode {
        didSet { if oldValue != viewMode { viewModeChanged() } }
    }

    var selectedMeetingID: UUID? {
        didSet { if oldValue != selectedMeetingID { selectionChanged(from: oldValue) } }
    }

    var searchText = ""
    var displayedMonth = LocalDate.today().firstOfMonth
    private(set) var today = LocalDate.today()

    var activeSheet: ActiveSheet?
    var alert: AlertInfo?
    /// The meeting awaiting confirmation of Delete Meeting.
    var pendingDeletion: Meeting?
    /// The toolbar Export button shows a checkmark after a copy.
    private(set) var justCopied = false
    var collapsedBuckets: Set<String> = []
    /// A meeting the list should scroll to (observed by MeetingListView).
    var listScrollTarget: UUID?
    /// Quick Look: the attachment shown, and its siblings for ← / →.
    var quickLookURL: URL?
    private(set) var quickLookURLs: [URL] = []

    var reopenLast: Bool = Prefs.reopenLast {
        didSet { Prefs.reopenLast = reopenLast }
    }
    var defaultDuration: Int = Prefs.defaultDuration {
        didSet { Prefs.defaultDuration = defaultDuration }
    }

    // Notes editing.
    /// The note whose text field has the keyboard focus (set by NotesList).
    var focusedNoteID: UUID?
    /// A note that should take the focus (observed by NotesList).
    var noteFocusRequest: UUID?
    /// The note being dragged, while a drag is in progress.
    var draggingNoteID: UUID?
    @ObservationIgnored private var dragSnapshot: Meeting?

    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var pendingSaves: Set<UUID> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var copiedTask: Task<Void, Never>?

    let formatter = MeetingFormatter()

    // MARK: Workspace

    var windowTitle: String {
        workspace?.root.lastPathComponent ?? "QDVC Meetings"
    }

    func startUp() {
        guard workspace == nil else { return }
        if reopenLast, let last = Prefs.lastWorkspace, directoryExists(URL(fileURLWithPath: last)) {
            open(URL(fileURLWithPath: last, isDirectory: true))
        }
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a meetings workspace, or an empty folder to start one."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        let root = url.standardizedFileURL
        guard directoryExists(root) else {
            alert = AlertInfo(title: "Folder Not Found", message: "\(root.path) no longer exists.")
            recentWorkspaces.removeAll { $0 == root.path }
            Prefs.recentWorkspaces = recentWorkspaces
            return
        }
        if !Workspace.looksLikeWorkspace(root) {
            let confirm = NSAlert()
            confirm.messageText = "Start a meetings workspace here?"
            confirm.informativeText = "\(root.lastPathComponent) has no meetings folder yet. QDVC Meetings will create one, and keep each meeting in it as a small text file."
            confirm.addButton(withTitle: "Create")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }
        flushSaves()
        let ws = Workspace(root: root)
        do {
            try ws.ensureLayout()
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Open Workspace", message: error.localizedDescription)
            return
        }
        workspace = ws
        selectedMeetingID = nil
        searchText = ""
        undoManager?.removeAllActions()
        reload()
        loadInstructions()
        recentWorkspaces.removeAll { $0 == root.path }
        recentWorkspaces.insert(root.path, at: 0)
        Prefs.recentWorkspaces = recentWorkspaces
        recentWorkspaces = Prefs.recentWorkspaces
        Prefs.lastWorkspace = root.path
    }

    func closeWorkspace() {
        flushSaves()
        activeSheet = nil
        workspace = nil
        meetings = []
        failures = []
        attachments = [:]
        people = PeopleIndex(meetings: [])
        instructions = PlatformInstructions()
        selectedMeetingID = nil
        undoManager?.removeAllActions()
        Prefs.lastWorkspace = nil
    }

    func clearRecents() {
        recentWorkspaces = []
        Prefs.recentWorkspaces = []
    }

    func revealWorkspace() {
        guard let ws = workspace else { return }
        Platform.reveal([ws.root])
    }

    /// Re-reads files that changed on disk (⌘R, and when the app becomes
    /// active).
    func refresh() {
        guard workspace != nil else { return }
        flushSaves()
        today = LocalDate.today()
        reload()
        loadInstructions()
    }

    func appBecameActive() {
        guard workspace != nil, activeSheet == nil, draggingNoteID == nil else { return }
        refresh()
    }

    func appWillResignActive() {
        flushSaves()
    }

    func dayChanged() {
        today = LocalDate.today()
    }

    private func reload() {
        guard let ws = workspace else { return }
        let result = ws.load()
        // A meeting with unsaved typing keeps its in-memory version.
        var loaded = result.meetings
        for i in loaded.indices {
            if let current = meeting(loaded[i].id), pendingSaves.contains(current.id) {
                loaded[i] = current
            }
        }
        // Keep the blank note being typed into, which is never written.
        if let id = selectedMeetingID, let current = meeting(id),
           let i = loaded.firstIndex(where: { $0.id == id }), current.notes.contains(where: \.isBlank) {
            var m = loaded[i]
            if m.notes.map(\.text) == current.notes.filter({ !$0.isBlank }).map(\.text) {
                m.notes = current.notes
                loaded[i] = m
            }
        }
        meetings = loaded
        failures = result.failures
        var byID: [UUID: [Attachment]] = [:]
        for m in loaded {
            if let path = m.relativePath, let list = result.attachments[path] { byID[m.id] = list }
        }
        attachments = byID
        rebuildIndexes()
        if let id = selectedMeetingID, meeting(id) == nil { selectedMeetingID = nil }
    }

    private func rebuildIndexes() {
        people = PeopleIndex(meetings: meetings)
        if case .person(let key) = sidebarSelection, people.person(forKey: key) == nil {
            sidebarSelection = viewMode == .list ? .dates(lastDateFilter) : nil
        }
    }

    func revealFailure(_ f: LoadFailure) {
        guard let ws = workspace else { return }
        Platform.reveal([ws.url(for: f.relativePath)])
    }

    // MARK: Platform instructions

    private func loadInstructions() {
        guard let ws = workspace else { return }
        do {
            instructions = try ws.loadPlatformInstructions()
            instructionsError = nil
        } catch {
            instructions = PlatformInstructions()
            instructionsError = String(describing: error)
        }
    }

    func setInstructions(_ text: String, for platform: ConferencePlatform) {
        guard let ws = workspace, instructions[platform] != text else { return }
        instructions[platform] = text
        do {
            try ws.savePlatformInstructions(instructions)
            instructionsError = nil
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Save Instructions", message: error.localizedDescription)
        }
    }

    func instructions(for m: Meeting) -> (ConferencePlatform, String)? {
        guard let p = m.locationKind.conferencePlatform else { return nil }
        let text = instructions[p].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (p, text)
    }

    // MARK: Lookups and filtering

    func meeting(_ id: UUID?) -> Meeting? {
        guard let id else { return nil }
        return meetings.first { $0.id == id }
    }

    private func index(_ id: UUID) -> Int? {
        meetings.firstIndex { $0.id == id }
    }

    var selectedMeeting: Meeting? { meeting(selectedMeetingID) }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedPersonKey: String? {
        if case .person(let k) = sidebarSelection { return k }
        return nil
    }

    var dateFilter: DateFilter? {
        if case .dates(let f) = sidebarSelection { return f }
        return nil
    }

    /// The meetings shown, before date filtering: a selected person's, and
    /// matches for the search.
    private var personAndSearchMatches: [Meeting] {
        var list = meetings
        if let key = selectedPersonKey { list = list.filter { $0.involves(personKey: key) } }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { list = list.filter { $0.matches(q) } }
        return list
    }

    /// The list's meetings in order. A search looks through every date, as
    /// Mail's search looks through every mailbox.
    var listMeetings: [Meeting] {
        var list = personAndSearchMatches
        var ascending = false
        if !isSearching, let f = dateFilter {
            list = list.filter { f.includes($0.date, today: today) }
            ascending = f.ascending
        }
        return list.sorted { ascending ? $0.sortKey < $1.sortKey : $0.sortKey > $1.sortKey }
    }

    var listSections: [ListSection] {
        let bucketer = DateBucketer(today: today)
        var sections: [ListSection] = []
        for m in listMeetings {
            let b = bucketer.bucket(for: m.date)
            if sections.last?.bucket == b {
                sections[sections.count - 1].meetings.append(m)
            } else {
                sections.append(ListSection(bucket: b, meetings: [m]))
            }
        }
        return sections
    }

    var listTitle: String {
        if isSearching { return "Search Results" }
        if let key = selectedPersonKey { return people.person(forKey: key)?.name ?? "Person" }
        return (dateFilter ?? .all).title
    }

    /// The calendar's meetings, by day, each day's in time order.
    var calendarMeetings: [LocalDate: [Meeting]] {
        var byDay: [LocalDate: [Meeting]] = [:]
        for m in personAndSearchMatches { byDay[m.date, default: []].append(m) }
        for (k, v) in byDay { byDay[k] = v.sorted { $0.sortKey < $1.sortKey } }
        return byDay
    }

    func count(_ filter: DateFilter) -> Int {
        meetings.filter { filter.includes($0.date, today: today) }.count
    }

    /// First names where unambiguous, for list rows.
    func shortPeople(_ m: Meeting) -> String {
        m.people.map { people.shortName($0) }.joined(separator: ", ")
    }

    // MARK: Navigation

    private func sidebarSelectionChanged() {
        if case .dates(let f) = sidebarSelection {
            lastDateFilter = f
            // The calendar is itself the date filter: choosing one shows the list.
            if viewMode == .calendar { viewMode = .list }
        }
        searchText = ""
    }

    private func viewModeChanged() {
        Prefs.viewMode = viewMode
        // Changing the sidebar selection below would clear the search.
        let search = searchText
        defer { searchText = search }
        switch viewMode {
        case .calendar:
            if case .dates = sidebarSelection { sidebarSelection = nil }
            if let m = selectedMeeting { displayedMonth = m.date.firstOfMonth }
        case .list:
            if sidebarSelection == nil { sidebarSelection = .dates(lastDateFilter) }
            if let id = selectedMeetingID, !listMeetings.contains(where: { $0.id == id }) {
                sidebarSelection = .dates(.all)
            }
        }
    }

    func selectPerson(_ name: String) {
        let key = People.key(name)
        guard people.person(forKey: key) != nil else { return }
        sidebarSelection = .person(key)
    }

    /// Calendar → list: shows the meeting under Upcoming (today onwards) or
    /// Past, selected, scrolled to and with its heading expanded.
    func showInList(_ id: UUID) {
        guard let m = meeting(id) else { return }
        let filter: DateFilter = m.date >= today ? .upcoming : .past
        collapsedBuckets.remove(DateBucketer(today: today).bucket(for: m.date).id)
        // Select first, so switching to the list keeps the selection.
        selectedMeetingID = id
        if sidebarSelection != .dates(filter) {
            sidebarSelection = .dates(filter)
        }
        viewMode = .list
        searchText = ""
        listScrollTarget = id
    }

    func showPreviousMonth() { displayedMonth = displayedMonth.adding(months: -1) }
    func showNextMonth() { displayedMonth = displayedMonth.adding(months: 1) }
    func showToday() {
        today = LocalDate.today()
        displayedMonth = today.firstOfMonth
    }

    private func selectionChanged(from old: UUID?) {
        flushSaves()
        focusedNoteID = nil
        if let old, let i = index(old), meetings[i].notes.contains(where: \.isBlank) {
            meetings[i].notes.removeAll(where: \.isBlank)
        }
    }

    // MARK: Saving and undo

    /// Changes a meeting in memory, writes it (now, or after a pause when
    /// `debounce` is set), and registers an undo if `undo` names the action.
    private func update(_ id: UUID, undo actionName: String? = nil, debounce: Bool = false,
                        _ change: (inout Meeting) -> Void) {
        guard let i = index(id) else { return }
        let before = meetings[i]
        var after = before
        change(&after)
        guard after != before else { return }
        meetings[i] = after
        if let actionName { registerUndo(before, actionName: actionName) }
        if debounce {
            scheduleSave(id)
        } else {
            persist(id)
        }
        if before.people != after.people
            || before.notes.map(\.activeAssignees) != after.notes.map(\.activeAssignees)
            || before.date != after.date {
            rebuildIndexes()
        }
    }

    private func registerUndo(_ previous: Meeting, actionName: String) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.restore(previous, actionName: actionName)
            }
        }
        um.setActionName(actionName)
    }

    /// Undo (and redo): put back an earlier state of a meeting.
    private func restore(_ snapshot: Meeting, actionName: String) {
        guard let i = index(snapshot.id) else { return }
        let current = meetings[i]
        registerUndo(current, actionName: actionName)
        var restored = snapshot
        restored.relativePath = current.relativePath
        meetings[i] = restored
        persist(snapshot.id)
        rebuildIndexes()
        if viewMode == .calendar, selectedMeetingID == snapshot.id {
            displayedMonth = restored.date.firstOfMonth
        }
    }

    private func persist(_ id: UUID) {
        pendingSaves.remove(id)
        guard let ws = workspace, let i = index(id) else { return }
        do {
            let before = meetings[i].relativePath
            let saved = try ws.save(meetings[i])
            meetings[i].relativePath = saved.relativePath
            // A rename moves the attachments folder too.
            if before != saved.relativePath, attachments[id] != nil { reloadAttachments(id) }
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Save \u{201C}\(meetings[i].title)\u{201D}",
                              message: error.localizedDescription)
        }
    }

    private func scheduleSave(_ id: UUID) {
        pendingSaves.insert(id)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.flushSaves()
        }
    }

    /// Writes any meeting with unsaved typing.
    func flushSaves() {
        saveTask?.cancel()
        saveTask = nil
        for id in pendingSaves { persist(id) }
        pendingSaves.removeAll()
    }

    // MARK: Meetings

    /// Opens the New Meeting sheet: on `day` at 09:00, or today at the next
    /// whole hour.
    func newMeeting(on day: LocalDate? = nil) {
        guard workspace != nil else { return }
        let date: LocalDate
        let time: LocalTime
        if let day {
            date = day
            time = LocalTime(hour: 9, minute: 0)!
        } else {
            let now = Date()
            let cal = Calendar.current
            let next = cal.date(byAdding: .hour, value: 1, to: now) ?? now
            date = LocalDate(next)
            time = LocalTime(hour: cal.component(.hour, from: next), minute: 0)!
        }
        let end: LocalTime? = defaultDuration > 0 ? time.adding(minutes: defaultDuration) : nil
        var m = Meeting(title: "", date: date, time: time, endTime: end)
        if let e = end, e <= time { m.endTime = nil }
        if case .person(let key) = sidebarSelection, let p = people.person(forKey: key) {
            m.people = [p.name]
        }
        activeSheet = .meeting(MeetingEditorRequest(meetingID: nil, original: m))
    }

    func editMeeting(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID) else { return }
        flushSaves()
        activeSheet = .meeting(MeetingEditorRequest(meetingID: m.id, original: m))
    }

    /// Saves the sheet's fields: a new meeting is added and selected.
    func commitEditor(_ request: MeetingEditorRequest, draft: MeetingDraft) {
        activeSheet = nil
        guard let ws = workspace else { return }
        if let id = request.meetingID {
            update(id, undo: "Edit Meeting") { draft.apply(to: &$0) }
            if viewMode == .calendar, let m = meeting(id) { displayedMonth = m.date.firstOfMonth }
        } else {
            var m = request.original
            draft.apply(to: &m)
            do {
                m = try ws.save(m)
            } catch {
                alert = AlertInfo(title: "Couldn\u{2019}t Add Meeting", message: error.localizedDescription)
                return
            }
            meetings.append(m)
            rebuildIndexes()
            reveal(m)
        }
    }

    /// Makes sure a meeting can be seen, then selects it.
    private func reveal(_ m: Meeting) {
        if viewMode == .list {
            if let key = selectedPersonKey, !m.involves(personKey: key) {
                sidebarSelection = .dates(.all)
            } else if let f = dateFilter, !f.includes(m.date, today: today) {
                sidebarSelection = .dates(.all)
            }
            if isSearching && !m.matches(searchText) { searchText = "" }
        } else {
            displayedMonth = m.date.firstOfMonth
        }
        selectedMeetingID = m.id
    }

    func duplicateMeeting(_ id: UUID?) {
        guard let ws = workspace, let original = meeting(id ?? selectedMeetingID) else { return }
        flushSaves()
        do {
            let copy = try ws.save(original.duplicated())
            meetings.append(copy)
            rebuildIndexes()
            reveal(copy)
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Duplicate Meeting", message: error.localizedDescription)
        }
    }

    func requestDelete(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID) else { return }
        pendingDeletion = m
    }

    /// Moves the meeting's file to the Trash.
    func confirmDelete() {
        guard let m = pendingDeletion, let ws = workspace else { return }
        pendingDeletion = nil
        pendingSaves.remove(m.id)
        if let path = m.relativePath {
            do {
                try Platform.trash(ws.url(for: path))
                let folder = ws.url(for: Workspace.attachmentsFolder(forMeetingPath: path))
                if FileManager.default.fileExists(atPath: folder.path) {
                    try Platform.trash(folder)
                }
            } catch {
                alert = AlertInfo(title: "Couldn\u{2019}t Delete Meeting", message: error.localizedDescription)
                return
            }
            ws.forget(path)
        }
        if selectedMeetingID == m.id { selectedMeetingID = nil }
        meetings.removeAll { $0.id == m.id }
        attachments[m.id] = nil
        rebuildIndexes()
    }

    /// Calendar drag and drop: the same time on another day.
    func moveMeeting(_ id: UUID, to day: LocalDate) {
        guard let m = meeting(id), m.date != day else { return }
        update(id, undo: "Move Meeting") { $0.date = day }
        selectedMeetingID = id
    }

    func revealMeetingFile(_ id: UUID?) {
        guard let ws = workspace, let m = meeting(id ?? selectedMeetingID), let path = m.relativePath else { return }
        flushSaves()
        Platform.reveal([ws.url(for: path)])
    }

    // MARK: Location

    func locationURL(_ m: Meeting) -> URL? {
        let text = m.location.trimmingCharacters(in: .whitespacesAndNewlines)
        switch m.locationKind {
        case .none: return nil
        case .text: return Platform.mapsSearchURL(text)
        case .link, .googleMaps, .teams, .zoom: return URL(string: text)
        }
    }

    func openLocation(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID), let url = locationURL(m) else { return }
        Platform.open(url)
    }

    func copyLocation(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID), !m.location.isEmpty else { return }
        Platform.copy(m.location.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Attachments

    func attachmentURL(_ a: Attachment) -> URL? {
        workspace?.url(for: a.relativePath)
    }

    private func reloadAttachments(_ id: UUID) {
        guard let ws = workspace, let path = meeting(id)?.relativePath else { return }
        let list = ws.attachments(forMeetingPath: path)
        attachments[id] = list.isEmpty ? nil : list
    }

    /// Add Attachments… (⇧⌘A): choose files to copy into the meeting's folder.
    func chooseAttachments(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        panel.message = "Choose files to attach to \u{201C}\(m.title)\u{201D}. They are copied into the meeting\u{2019}s folder."
        guard panel.runModal() == .OK else { return }
        addAttachments(panel.urls, to: m.id)
    }

    func addAttachments(_ urls: [URL], to id: UUID) {
        guard let ws = workspace, !urls.isEmpty else { return }
        flushSaves()
        guard let path = meeting(id)?.relativePath else { return }
        do {
            try ws.addAttachments(urls, toMeetingPath: path)
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Attach Files", message: error.localizedDescription)
        }
        reloadAttachments(id)
    }

    /// Files dropped on the meeting pane. False if the drop holds no files.
    func importDroppedFiles(_ providers: [NSItemProvider], to id: UUID) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, let model = self else { return }
                Task { @MainActor in model.addAttachments([url], to: id) }
            }
        }
        return true
    }

    func quickLook(_ a: Attachment, of id: UUID) {
        let urls = (attachments[id] ?? []).compactMap(attachmentURL)
        quickLookURLs = urls
        quickLookURL = attachmentURL(a)
    }

    func openAttachment(_ a: Attachment) {
        if let url = attachmentURL(a) { Platform.open(url) }
    }

    func revealAttachment(_ a: Attachment) {
        if let url = attachmentURL(a) { Platform.reveal([url]) }
    }

    /// Moves an attachment to the Trash (so it can be put back from Finder),
    /// and the folder too once it is empty.
    func removeAttachment(_ a: Attachment, from id: UUID) {
        guard let ws = workspace, let url = attachmentURL(a) else { return }
        do {
            try Platform.trash(url)
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Remove \u{201C}\(a.name)\u{201D}", message: error.localizedDescription)
            return
        }
        if let path = meeting(id)?.relativePath { ws.removeAttachmentsFolderIfEmpty(forMeetingPath: path) }
        reloadAttachments(id)
    }

    // MARK: Notes

    func note(_ meetingID: UUID, _ noteID: UUID) -> Note? {
        meeting(meetingID)?.notes.first { $0.id == noteID }
    }

    /// The meeting and note the Note menu acts on: the focused note.
    var focusedNote: (meeting: Meeting, note: Note)? {
        guard let m = selectedMeeting, let nid = focusedNoteID,
              let n = m.notes.first(where: { $0.id == nid }) else { return nil }
        return (m, n)
    }

    /// Adds an empty note after `noteID` (or at the end) and focuses it.
    @discardableResult
    func addNote(to meetingID: UUID? = nil, after noteID: UUID? = nil, kind: NoteKind = .note) -> UUID? {
        guard let mid = meetingID ?? selectedMeetingID, meeting(mid) != nil else { return nil }
        let new = Note(kind: kind)
        guard let i = index(mid) else { return nil }
        // Not written (blank notes never are) and not undoable until typed in.
        if let noteID, let at = meetings[i].notes.firstIndex(where: { $0.id == noteID }) {
            meetings[i].notes.insert(new, at: at + 1)
        } else {
            meetings[i].notes.append(new)
        }
        noteFocusRequest = new.id
        return new.id
    }

    func setNoteText(_ meetingID: UUID, _ noteID: UUID, _ text: String) {
        update(meetingID, debounce: true) { m in
            if let i = m.notes.firstIndex(where: { $0.id == noteID }) { m.notes[i].text = text }
        }
    }

    /// Return in a note: start the next one, or end the run if this one is
    /// empty (as in Reminders).
    func noteSubmitted(_ meetingID: UUID, _ noteID: UUID) {
        guard let n = note(meetingID, noteID) else { return }
        if n.isBlank {
            deleteNote(meetingID, noteID)
            noteFocusRequest = nil
            focusedNoteID = nil
        } else {
            flushSaves()
            addNote(to: meetingID, after: noteID)
        }
    }

    func setNoteKind(_ meetingID: UUID, _ noteID: UUID, _ kind: NoteKind) {
        update(meetingID, undo: "Change Note Kind") { m in
            if let i = m.notes.firstIndex(where: { $0.id == noteID }) { m.notes[i].kind = kind }
        }
    }

    func setAssignees(_ meetingID: UUID, _ noteID: UUID, _ names: [String]) {
        let canonical = People.merge(names.map { people.canonicalName($0) })
        update(meetingID, undo: "Assign") { m in
            if let i = m.notes.firstIndex(where: { $0.id == noteID }) { m.notes[i].assignees = canonical }
        }
    }

    func deleteNote(_ meetingID: UUID, _ noteID: UUID) {
        guard let n = note(meetingID, noteID) else { return }
        update(meetingID, undo: n.isBlank ? nil : "Delete Note") { m in
            m.notes.removeAll { $0.id == noteID }
        }
        // A blank note is not in the file, so `update` saw no change on disk;
        // remove it from memory regardless.
        if let i = index(meetingID) { meetings[i].notes.removeAll { $0.id == noteID } }
        if focusedNoteID == noteID { focusedNoteID = nil }
    }

    /// ⌥⌘↑ / ⌥⌘↓.
    func moveNote(_ meetingID: UUID, _ noteID: UUID, by offset: Int) {
        guard let m = meeting(meetingID), let from = m.notes.firstIndex(where: { $0.id == noteID }) else { return }
        let to = from + offset
        guard m.notes.indices.contains(to) else { return }
        update(meetingID, undo: "Move Note") { m in
            let n = m.notes.remove(at: from)
            m.notes.insert(n, at: to)
        }
        noteFocusRequest = noteID
    }

    func canMoveNote(_ meetingID: UUID, _ noteID: UUID, by offset: Int) -> Bool {
        guard let m = meeting(meetingID), let from = m.notes.firstIndex(where: { $0.id == noteID }) else { return false }
        return m.notes.indices.contains(from + offset)
    }

    // Drag and drop: the dragged note moves live as it passes over others;
    // the whole drag is one undoable action.

    func beginNoteDrag(_ meetingID: UUID, _ noteID: UUID) {
        flushSaves()
        dragSnapshot = meeting(meetingID)
        draggingNoteID = noteID
    }

    /// The dragged note takes the place of `targetID`.
    func dragNote(over targetID: UUID?, in meetingID: UUID) {
        guard let dragged = draggingNoteID, dragged != targetID, let i = index(meetingID),
              let from = meetings[i].notes.firstIndex(where: { $0.id == dragged }) else { return }
        var notes = meetings[i].notes
        let n = notes.remove(at: from)
        if let targetID, let to = meetings[i].notes.firstIndex(where: { $0.id == targetID }) {
            notes.insert(n, at: to)
        } else {
            notes.append(n)
        }
        guard notes.map(\.id) != meetings[i].notes.map(\.id) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            meetings[i].notes = notes
        }
    }

    func endNoteDrag(in meetingID: UUID) {
        draggingNoteID = nil
        guard let before = dragSnapshot, before.id == meetingID, let after = meeting(meetingID) else {
            dragSnapshot = nil
            return
        }
        dragSnapshot = nil
        guard before.notes.map(\.id) != after.notes.map(\.id) else { return }
        registerUndo(before, actionName: "Move Note")
        persist(meetingID)
    }

    // MARK: People

    func beginRenamePerson(_ key: String) {
        guard let p = people.person(forKey: key) else { return }
        flushSaves()
        activeSheet = .renamePerson(p)
    }

    /// Renames a person in every meeting that mentions them. Not undoable as
    /// one step (it may touch many files); renaming back restores them.
    func renamePerson(_ key: String, to newName: String) {
        activeSheet = nil
        let name = People.normalize(newName)
        guard !name.isEmpty else { return }
        let ids = meetings.map(\.id)
        for id in ids {
            guard let m = meeting(id), let renamed = People.renaming(m, from: key, to: name),
                  let i = index(id) else { continue }
            meetings[i] = renamed
            persist(id)
        }
        rebuildIndexes()
        if selectedPersonKey == key { sidebarSelection = .person(People.key(name)) }
        undoManager?.removeAllActions()
    }

    /// People suggestions for the meeting editor.
    func peopleSuggestions(_ query: String, excluding names: [String]) -> [String] {
        people.suggestions(matching: query, excluding: Set(names.map(People.key))).map(\.name)
    }

    /// Assignee suggestions: the meeting's people first.
    func assigneeSuggestions(_ query: String, meeting m: Meeting, excluding names: [String]) -> [String] {
        people.assigneeSuggestions(matching: query, meetingPeople: m.people,
                                   excluding: Set(names.map(People.key)))
    }

    // MARK: Export

    func exportWord(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID) else { return }
        flushSaves()
        guard let url = Platform.saveLocation(suggesting: Naming.exportFileName(for: m, extension: "docx"),
                                              type: .docx, message: "Export the notes of \u{201C}\(m.title)\u{201D} as a Word document.") else { return }
        write(DocxExport.document(m, formatter: formatter), to: url)
    }

    func exportMarkdown(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID) else { return }
        flushSaves()
        guard let url = Platform.saveLocation(suggesting: Naming.exportFileName(for: m, extension: "md"),
                                              type: .markdownText, message: "Export the notes of \u{201C}\(m.title)\u{201D} as Markdown.") else { return }
        write(Data(NotesExport.markdown(m, formatter: formatter).utf8), to: url)
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t Export Notes", message: error.localizedDescription)
        }
    }

    func copyPlainText(_ id: UUID?) {
        guard let m = meeting(id ?? selectedMeetingID) else { return }
        Platform.copy(NotesExport.plainText(m, formatter: formatter))
        justCopied = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.justCopied = false
        }
    }
}
