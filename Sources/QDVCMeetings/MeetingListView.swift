import SwiftUI
import MeetingsCore

/// The meetings as a list under date headings (docs/DESIGN.md §2.3).
struct MeetingListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let sections = model.listSections
        VStack(spacing: 0) {
            ListHeader(title: model.listTitle, count: sections.reduce(0) { $0 + $1.meetings.count })
            if sections.isEmpty {
                EmptyListView()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedMeetingID) {
                        ForEach(sections) { section in
                            Section(isExpanded: expanded(section.id)) {
                                ForEach(section.meetings) { m in
                                    MeetingRow(meeting: m, showsDate: !section.bucket.isSingleDay)
                                        .tag(m.id)
                                        .id(m.id)
                                }
                            } header: {
                                Text(section.bucket.title)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let id = ids.first {
                            MeetingContextMenu(meetingID: id)
                        }
                    } primaryAction: { ids in
                        model.editMeeting(ids.first)
                    }
                    .onAppear { scroll(proxy) }
                    .onChange(of: model.listScrollTarget) { _, _ in scroll(proxy) }
                }
            }
        }
    }

    /// Scrolls to a meeting sent from the calendar, once the rows exist.
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = model.listScrollTarget else { return }
        Task { @MainActor in
            proxy.scrollTo(id, anchor: .center)
            model.listScrollTarget = nil
        }
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(get: { !model.collapsedBuckets.contains(id) },
                set: { open in
                    if open { model.collapsedBuckets.remove(id) } else { model.collapsedBuckets.insert(id) }
                })
    }
}

private struct ListHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold)).lineLimit(1)
            Spacer()
            Text("\(count) meeting\(count == 1 ? "" : "s")").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct EmptyListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isSearching {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            ContentUnavailableView {
                Label("No Meetings", systemImage: "calendar")
            } description: {
                Text(model.dateFilter == .upcoming || model.dateFilter == .today
                     ? "Nothing is scheduled. Add a meeting to get started."
                     : "There are no meetings here yet.")
            } actions: {
                Button("New Meeting") { model.newMeeting() }
            }
        }
    }
}

/// One row: title and time (and date, under multi-day headings); the
/// location; the people, and the notes badge.
struct MeetingRow: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    let showsDate: Bool

    var body: some View {
        let m = meeting
        let kind = m.locationKind
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(m.title).fontWeight(.semibold).lineLimit(1)
                if let n = model.attachments[m.id]?.count {
                    Image(systemName: "paperclip")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .help("\(n) attachment\(n == 1 ? "" : "s")")
                }
                Spacer(minLength: 6)
                Text(showsDate ? "\(model.formatter.shortDate(m.date)), \(model.formatter.time(m.time))"
                               : model.formatter.time(m.time))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if kind != .none {
                Label {
                    Text(kind.serviceName ?? m.location)
                } icon: {
                    Image(systemName: kind.symbol)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 6) {
                Text(m.people.isEmpty ? "No people" : model.shortPeople(m))
                    .font(.callout)
                    .foregroundStyle(m.people.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                NotesBadge(meeting: m, isPast: m.date <= model.today)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Shows at a glance whether a meeting has notes: a tinted capsule with the
/// number of notes (and of action items and decisions), or, for a meeting
/// that has happened, a faint "No notes".
struct NotesBadge: View {
    @Environment(\.backgroundProminence) private var prominence
    let meeting: Meeting
    var isPast = false

    var body: some View {
        let selected = prominence == .increased
        if meeting.hasNotes {
            HStack(spacing: 6) {
                part("note.text", meeting.noteCount)
                if meeting.actionItemCount > 0 { part(NoteKind.action.symbol, meeting.actionItemCount) }
                if meeting.decisionCount > 0 { part(NoteKind.decision.symbol, meeting.decisionCount) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.15)))
            .help(summary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
        } else if isPast {
            Text("No notes")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func part(_ symbol: String, _ n: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
            Text("\(n)").monospacedDigit()
        }
    }

    private var summary: String {
        var parts = ["\(meeting.noteCount) note\(meeting.noteCount == 1 ? "" : "s")"]
        let a = meeting.actionItemCount, d = meeting.decisionCount
        if a > 0 { parts.append("\(a) action item\(a == 1 ? "" : "s")") }
        if d > 0 { parts.append("\(d) decision\(d == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

/// The Meeting menu's commands for one meeting, for context menus.
struct MeetingContextMenu: View {
    @Environment(AppModel.self) private var model
    let meetingID: UUID

    var body: some View {
        let m = model.meeting(meetingID)
        Button("Edit Meeting\u{2026}") { model.editMeeting(meetingID) }
        Button("Duplicate Meeting") { model.duplicateMeeting(meetingID) }
        Button("Add Attachments\u{2026}") { model.chooseAttachments(meetingID) }
        if let m, let title = m.locationKind.actionTitle {
            Divider()
            Button(title) { model.openLocation(meetingID) }
            Button(m.locationKind.isLink ? "Copy Link" : "Copy Location") { model.copyLocation(meetingID) }
        }
        Divider()
        Menu("Export Notes") {
            ExportMenuItems(meetingID: meetingID)
        }
        Button("Reveal in Finder") { model.revealMeetingFile(meetingID) }
        Divider()
        Button("Delete Meeting\u{2026}") { model.requestDelete(meetingID) }
    }
}
