import SwiftUI
import MeetingsCore

/// The meetings in a month grid, as in Calendar's Month view
/// (docs/DESIGN.md §2.4). Weeks start on the day the system's region
/// settings say.
struct CalendarMonthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = Calendar.current
        let month = model.displayedMonth.firstOfMonth
        let gridStart = month.startOfWeek(firstWeekday: cal.firstWeekday)
        let lastDay = month.adding(days: month.daysInMonth - 1)
        let weeks = (lastDay.ordinal - gridStart.ordinal) / 7 + 1
        let byDay = model.calendarMeetings
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.formatter.monthTitle(month))
                    .font(.title2.weight(.semibold))
                Spacer()
                if model.isSearching || model.selectedPersonKey != nil {
                    Text(filterNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let symbols = cal.shortWeekdaySymbols
                    Text(symbols[(cal.firstWeekday - 1 + i) % 7])
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 6)
                }
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Divider() }

            GeometryReader { geo in
                let rowHeight = geo.size.height / CGFloat(weeks)
                // The day number takes about 22 pt; each chip about 18 pt.
                let chips = max(1, Int((rowHeight - 26) / 18))
                VStack(spacing: 0) {
                    ForEach(0..<weeks, id: \.self) { w in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { d in
                                let day = gridStart.adding(days: w * 7 + d)
                                DayCell(day: day,
                                        meetings: byDay[day] ?? [],
                                        inMonth: day.isSameMonth(as: month),
                                        maxChips: chips)
                            }
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
    }

    private var filterNote: String {
        if model.isSearching { return "Matching \u{201C}\(model.searchText)\u{201D}" }
        if let key = model.selectedPersonKey, let p = model.people.person(forKey: key) {
            return "Meetings with \(p.name)"
        }
        return ""
    }
}

private struct DayCell: View {
    @Environment(AppModel.self) private var model
    let day: LocalDate
    let meetings: [Meeting]
    let inMonth: Bool
    let maxChips: Int
    @State private var isTargeted = false
    @State private var showsMore = false

    var body: some View {
        let isToday = day == model.today
        // With more meetings than room, the last row says "+N more".
        let shown = meetings.count > maxChips ? max(0, maxChips - 1) : meetings.count
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Text("\(day.day)")
                    .font(.callout.weight(isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary))
                    .frame(minWidth: 20, minHeight: 20)
                    .background {
                        if isToday { Circle().fill(Color.accentColor) }
                    }
            }
            ForEach(meetings.prefix(shown)) { m in
                MeetingChip(meeting: m)
            }
            if meetings.count > shown {
                Button("\(meetings.count - shown) more") { showsMore = true }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .popover(isPresented: $showsMore, arrowEdge: .trailing) {
                        DayPopover(day: day, meetings: meetings)
                            .environment(model)
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(inMonth ? Color.clear : Color.secondary.opacity(0.06))
        .background(isTargeted ? Color.accentColor.opacity(0.14) : Color.clear)
        .overlay {
            Rectangle().strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.newMeeting(on: day) }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.compactMap(DragPayload.meetingID).first else { return false }
            model.moveMeeting(id, to: day)
            return true
        } isTargeted: { isTargeted = $0 }
        .help(meetings.isEmpty ? "Double-click to add a meeting on this day" : "")
    }
}

/// A meeting in the grid: time, title, the platform symbol, and a notes
/// symbol when it has notes. Clicking it shows it in the list (under
/// Upcoming or Past); dragging it to another day moves it.
struct MeetingChip: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting

    var body: some View {
        let m = meeting
        let selected = model.selectedMeetingID == m.id
        HStack(spacing: 3) {
            Text(model.formatter.time(m.time))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            Text(m.title)
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer(minLength: 0)
            if m.locationKind.conferencePlatform != nil {
                Image(systemName: "video.fill")
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
            if model.attachments[m.id] != nil {
                Image(systemName: "paperclip")
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
            if m.hasNotes {
                Image(systemName: "note.text")
                    .fontWeight(.semibold)
                    .foregroundStyle(selected ? Color.white : Color.accentColor)
            }
        }
        .font(.caption)
        .imageScale(.small)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(selected ? Color.accentColor : Color.accentColor.opacity(0.12)))
        .contentShape(Rectangle())
        .onTapGesture { model.showInList(m.id) }
        .draggable(DragPayload.meeting(m.id)) {
            Text(m.title)
                .font(.caption)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.3)))
        }
        .contextMenu { MeetingContextMenu(meetingID: m.id) }
        .help(chipHelp(m))
    }

    private func chipHelp(_ m: Meeting) -> String {
        var s = "\(model.formatter.timeRange(m)) \(m.title)"
        if let n = model.attachments[m.id]?.count {
            s += " \u{2014} \(n) attachment\(n == 1 ? "" : "s")"
        }
        if m.hasNotes {
            s += " \u{2014} \(m.noteCount) note\(m.noteCount == 1 ? "" : "s")"
        } else if m.date <= model.today {
            s += " \u{2014} no notes"
        }
        return s + "\nClick to show in the list; drag to another day to move it."
    }
}

/// Every meeting of a day, from "N more".
private struct DayPopover: View {
    @Environment(AppModel.self) private var model
    let day: LocalDate
    let meetings: [Meeting]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.formatter.longDate(day)).font(.headline).padding(.bottom, 4)
            ForEach(meetings) { m in
                MeetingChip(meeting: m)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

/// The text carried by drags inside the app.
enum DragPayload {
    static let meetingPrefix = "qdvc-meeting:"
    static let notePrefix = "qdvc-note:"

    static func meeting(_ id: UUID) -> String { meetingPrefix + id.uuidString }
    static func note(_ id: UUID) -> String { notePrefix + id.uuidString }

    static func meetingID(_ payload: String) -> UUID? {
        guard payload.hasPrefix(meetingPrefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(meetingPrefix.count)))
    }
}
