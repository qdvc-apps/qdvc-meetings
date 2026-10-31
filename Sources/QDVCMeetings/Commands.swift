import AppKit
import SwiftUI
import MeetingsCore

/// Menu-bar commands. Standard items (Edit, Window, Help, Settings…, Quit,
/// Hide) come from the system; these add the workspace, view, meeting and
/// note commands (docs/DESIGN.md §2–4).
@MainActor
struct MeetingsCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Meeting") { model.newMeeting() }
                .keyboardShortcut("n")
                .disabled(model.workspace == nil)
            Button("New Note") { newNote() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.selectedMeeting == nil)
            Divider()
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentWorkspaces, id: \.self) { path in
                    Button((path as NSString).abbreviatingWithTildeInPath) {
                        model.open(URL(fileURLWithPath: path, isDirectory: true))
                    }
                }
                if !model.recentWorkspaces.isEmpty {
                    Divider()
                    Button("Clear Menu") { model.clearRecents() }
                }
            }
            Button("Reveal Workspace in Finder") { model.revealWorkspace() }
                .disabled(model.workspace == nil)
            Divider()
            Button("Close Workspace") { model.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
        }

        CommandGroup(after: .saveItem) {
            Menu("Export Notes") {
                Button("As Word Document\u{2026}") { model.exportWord(nil) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Button("As Markdown\u{2026}") { model.exportMarkdown(nil) }
            }
            .disabled(model.selectedMeeting == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Search Meetings") {
                Platform.focusSearchField(in: NSApp.keyWindow ?? NSApp.mainWindow)
            }
            .keyboardShortcut("f")
            .disabled(model.workspace == nil)
            Button("Copy Notes as Plain Text") { model.copyPlainText(nil) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.selectedMeeting == nil)
        }

        CommandGroup(after: .toolbar) {
            ForEach(ViewMode.allCases) { mode in
                Toggle("as \(mode.title)", isOn: Binding(
                    get: { model.viewMode == mode },
                    set: { if $0 { model.viewMode = mode } }))
                    .keyboardShortcut(KeyEquivalent(mode == .list ? "1" : "2"))
                    .disabled(model.workspace == nil)
            }
            Divider()
            Button("Previous Month") { model.showPreviousMonth() }
                .keyboardShortcut("[")
                .disabled(model.workspace == nil || model.viewMode != .calendar)
            Button("Today") { model.showToday() }
                .keyboardShortcut("t")
                .disabled(model.workspace == nil || model.viewMode != .calendar)
            Button("Next Month") { model.showNextMonth() }
                .keyboardShortcut("]")
                .disabled(model.workspace == nil || model.viewMode != .calendar)
            Divider()
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(model.workspace == nil)
            Divider()
        }

        CommandMenu("Meeting") {
            let m = model.selectedMeeting
            Button("Edit Meeting\u{2026}") { model.editMeeting(nil) }
                .keyboardShortcut("e")
                .disabled(m == nil)
            Button("Duplicate Meeting") { model.duplicateMeeting(nil) }
                .keyboardShortcut("d")
                .disabled(m == nil)
            Button("Add Attachments\u{2026}") { model.chooseAttachments(nil) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(m == nil)
            Divider()
            Button(m?.locationKind.actionTitle ?? "Join") { model.openLocation(nil) }
                .keyboardShortcut("j")
                .disabled(m?.locationKind.actionTitle == nil)
            Button(m?.locationKind.isLink == true ? "Copy Link" : "Copy Location") { model.copyLocation(nil) }
                .disabled(m == nil || m?.locationKind == LocationKind.none)
            Divider()
            Button("Reveal in Finder") { model.revealMeetingFile(nil) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(m?.relativePath == nil)
            Divider()
            Button("Delete Meeting\u{2026}") {
                // ⌘⌫ also deletes to the start of the line in text; pass it on.
                if Platform.isEditingText {
                    NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                } else {
                    model.requestDelete(nil)
                }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(m == nil)
        }

        CommandMenu("Note") {
            let focused = model.focusedNote
            Button("New Note") { newNote() }
                .disabled(model.selectedMeeting == nil)
            Divider()
            ForEach(NoteKind.allCases) { kind in
                Toggle(kind.title, isOn: Binding(
                    get: { focused?.note.kind == kind },
                    set: { on in
                        if on, let f = model.focusedNote { model.setNoteKind(f.meeting.id, f.note.id, kind) }
                    }))
                    .keyboardShortcut(kind.shortcutKey, modifiers: [.command, .option])
                    .disabled(focused == nil)
            }
            Divider()
            Button("Move Up") {
                if let f = model.focusedNote { model.moveNote(f.meeting.id, f.note.id, by: -1) }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(focused.map { !model.canMoveNote($0.meeting.id, $0.note.id, by: -1) } ?? true)
            Button("Move Down") {
                if let f = model.focusedNote { model.moveNote(f.meeting.id, f.note.id, by: 1) }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(focused.map { !model.canMoveNote($0.meeting.id, $0.note.id, by: 1) } ?? true)
            Divider()
            Button("Delete Note") {
                if let f = model.focusedNote { model.deleteNote(f.meeting.id, f.note.id) }
            }
            .disabled(focused == nil)
        }
    }

    /// New Note: after the focused note, or at the end.
    private func newNote() {
        guard let m = model.selectedMeeting else { return }
        let after = model.focusedNote?.meeting.id == m.id ? model.focusedNoteID : nil
        model.addNote(to: m.id, after: after)
    }
}
