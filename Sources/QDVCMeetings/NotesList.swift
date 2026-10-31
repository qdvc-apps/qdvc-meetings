import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MeetingsCore

/// A meeting's notes, edited in place as in Reminders (docs/DESIGN.md §3).
/// Return starts the next note; Return on an empty note ends the run.
/// Drag a note by its handle (≡) to move it; the others make room as it
/// passes, and the whole drag is one undoable step.
struct NotesList: View {
    @Environment(AppModel.self) private var model
    let meetingID: UUID
    @FocusState private var focused: UUID?

    var body: some View {
        let m = model.meeting(meetingID)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notes").font(.headline)
                Spacer()
                if let m, m.hasNotes {
                    NotesBadge(meeting: m)
                }
            }
            .padding(.bottom, 4)

            if let m {
                ForEach(m.notes) { note in
                    NoteRow(meeting: m, note: note, focused: $focused)
                        .opacity(model.draggingNoteID == note.id ? 0.35 : 1)
                        .onDrop(of: [.text, .fileURL], isTargeted: hoverBinding(over: note.id)) { finishDrop($0) }
                    Divider()
                }
                Button {
                    model.addNote(to: meetingID)
                } label: {
                    Label("New Note", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .help("Add a note (\u{21E7}\u{2318}N)")
                .onDrop(of: [.text, .fileURL], isTargeted: hoverBinding(over: nil)) { finishDrop($0) }
            }
        }
        // Hover events stop during a drag and resume after it, so a hover
        // with a drag still recorded means it ended outside a drop target.
        .onContinuousHover { phase in
            if case .active = phase, model.draggingNoteID != nil {
                model.endNoteDrag(in: meetingID)
            }
        }
        .onChange(of: focused) { _, new in model.focusedNoteID = new }
        .onChange(of: model.noteFocusRequest) { _, new in
            guard let new else { return }
            model.noteFocusRequest = nil
            // Let the new row appear before focusing it.
            Task { @MainActor in focused = new }
        }
    }

    /// Passing over a note (or, for nil, the New Note row at the end) moves
    /// the dragged note there.
    private func hoverBinding(over noteID: UUID?) -> Binding<Bool> {
        Binding(get: { false }, set: { inside in
            if inside { model.dragNote(over: noteID, in: meetingID) }
        })
    }

    /// Ends a note drag; anything else dropped here (files from Finder) is
    /// passed on to be attached, since the rows would otherwise swallow it.
    private func finishDrop(_ providers: [NSItemProvider]) -> Bool {
        if model.draggingNoteID != nil {
            model.endNoteDrag(in: meetingID)
            return true
        }
        return model.importDroppedFiles(providers, to: meetingID)
    }
}

private struct NoteRow: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    let note: Note
    var focused: FocusState<UUID?>.Binding
    @State private var hovering = false

    var body: some View {
        let mid = meeting.id
        let nid = note.id
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.callout)
                .foregroundStyle(hovering ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.quaternary)
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
                .onDrag {
                    model.beginNoteDrag(mid, nid)
                    return NSItemProvider(object: DragPayload.note(nid) as NSString)
                } preview: {
                    Text(note.text.isEmpty ? "Note" : note.text)
                        .lineLimit(2)
                        .padding(6)
                        .frame(maxWidth: 280, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
                }
                .help("Drag to move this note")
                .accessibilityLabel("Reorder")

            KindMenu(meetingID: mid, note: note)

            VStack(alignment: .leading, spacing: 4) {
                TextField(placeholder, text: textBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused(focused, equals: nid)
                    .onSubmit { model.noteSubmitted(mid, nid) }
                    .onKeyPress(.delete) {
                        guard note.text.isEmpty else { return .ignored }
                        model.deleteNote(mid, nid)
                        return .handled
                    }
                if note.kind == .action {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Assigned to")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        PeopleTokenField(
                            names: note.assignees,
                            placeholder: meeting.people.isEmpty ? "Add people" : "Add people (\(meeting.people.prefix(2).joined(separator: ", "))\(meeting.people.count > 2 ? ", \u{2026}" : ""))",
                            bordered: false,
                            suggestions: { query, current in
                                model.assigneeSuggestions(query, meeting: meeting, excluding: current)
                            },
                            isOutsider: { name in
                                !meeting.people.contains { People.key($0) == People.key(name) }
                            },
                            onChange: { names in model.setAssignees(mid, nid, names) })
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(NoteKind.allCases) { kind in
                Button {
                    model.setNoteKind(mid, nid, kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
                .disabled(note.kind == kind)
            }
            Divider()
            Button("Move Up") { model.moveNote(mid, nid, by: -1) }
                .disabled(!model.canMoveNote(mid, nid, by: -1))
            Button("Move Down") { model.moveNote(mid, nid, by: 1) }
                .disabled(!model.canMoveNote(mid, nid, by: 1))
            Divider()
            Button("Delete Note") { model.deleteNote(mid, nid) }
        }
    }

    private var placeholder: String {
        switch note.kind {
        case .note: return "Note"
        case .action: return "Action item"
        case .decision: return "Decision"
        }
    }

    private var textBinding: Binding<String> {
        let mid = meeting.id
        let nid = note.id
        return Binding(get: { model.note(mid, nid)?.text ?? "" },
                       set: { model.setNoteText(mid, nid, $0) })
    }
}

/// The note's leading symbol, which is also a menu to change its kind.
private struct KindMenu: View {
    @Environment(AppModel.self) private var model
    let meetingID: UUID
    let note: Note

    var body: some View {
        Menu {
            ForEach(NoteKind.allCases) { kind in
                Button {
                    model.setNoteKind(meetingID, note.id, kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        } label: {
            Image(systemName: note.kind.symbol)
                .font(.system(size: note.kind == .note ? 6 : 13, weight: .semibold))
                .foregroundStyle(note.kind.tint)
                .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(note.kind.title) \u{2014} click to change (Note \u{2325}\u{2318}0, Action Item \u{2325}\u{2318}A, Decision \u{2325}\u{2318}D)")
    }
}
