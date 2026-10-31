import AppKit
import SwiftUI
import MeetingsCore

/// The main window: the welcome screen, or a source-list sidebar with the
/// meetings (list or month calendar) and the meeting pane side by side.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        Group {
            if model.workspace == nil {
                WelcomeView()
            } else {
                MainSplitView()
            }
        }
        .navigationTitle(model.windowTitle)
        .quickLookPreview($model.quickLookURL, in: model.quickLookURLs)
        .sheet(item: $model.activeSheet) { sheet in
            SheetContent(sheet: sheet)
                .environment(model)
        }
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
        .confirmationDialog(deleteTitle,
                            isPresented: Binding(get: { model.pendingDeletion != nil },
                                                 set: { if !$0 { model.pendingDeletion = nil } })) {
            Button("Move to Trash", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
        } message: {
            Text("The meeting and its notes go to the Trash, where you can put them back from Finder.")
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.appBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            model.appWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            model.dayChanged()
        }
    }

    private var deleteTitle: String {
        guard let m = model.pendingDeletion else { return "" }
        return "Delete \u{201C}\(m.title)\u{201D}?"
    }
}

struct SheetContent: View {
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .meeting(let request):
            MeetingSheet(request: request)
        case .renamePerson(let person):
            RenamePersonSheet(person: person)
        }
    }
}

struct MainSplitView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                BannerStack()
                switch model.viewMode {
                case .list:
                    // The list and the meeting pane side by side, as in Mail.
                    HSplitView {
                        MeetingListView()
                            .frame(minWidth: 300, idealWidth: 380, maxWidth: 600, maxHeight: .infinity)
                        MeetingPane()
                            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .calendar:
                    // The calendar alone, using the full width; clicking a
                    // meeting shows it in the list.
                    CalendarMonthView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search meetings"))
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        MainToolbar(model: model).content
    }
}

/// The window's toolbar (no title, icon-only buttons, every one also in the
/// menu bar; see docs/DESIGN.md §2.1).
@MainActor
struct MainToolbar {
    @Bindable var model: AppModel

    @ToolbarContentBuilder
    var content: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $model.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .help("Show meetings as a list (\u{2318}1) or a month calendar (\u{2318}2)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.viewMode == .calendar {
                ControlGroup {
                    Button {
                        model.showPreviousMonth()
                    } label: {
                        Label("Previous Month", systemImage: "chevron.left")
                    }
                    .help("Previous month (\u{2318}[)")
                    Button("Today") { model.showToday() }
                        .help("Go to this month (\u{2318}T)")
                    Button {
                        model.showNextMonth()
                    } label: {
                        Label("Next Month", systemImage: "chevron.right")
                    }
                    .help("Next month (\u{2318}])")
                }
            }

            Button {
                model.newMeeting()
            } label: {
                Label("New Meeting", systemImage: "plus")
            }
            .help("New meeting (\u{2318}N)")

            if model.viewMode == .list {
                Menu {
                    ExportMenuItems(meetingID: model.selectedMeetingID)
                } label: {
                    Label("Export Notes", systemImage: model.justCopied ? "checkmark" : "square.and.arrow.up")
                }
                .help("Export the selected meeting\u{2019}s notes as Word or Markdown, or copy them as plain text")
                .disabled(model.selectedMeeting == nil)
            }
        }
    }
}

/// Export as Word…, Export as Markdown…, Copy Notes as Plain Text. Shared by
/// the toolbar, the meeting pane's menu and context menus.
struct ExportMenuItems: View {
    @Environment(AppModel.self) private var model
    let meetingID: UUID?

    var body: some View {
        Button("Export as Word Document\u{2026}") { model.exportWord(meetingID) }
        Button("Export as Markdown\u{2026}") { model.exportMarkdown(meetingID) }
        Divider()
        Button("Copy Notes as Plain Text") { model.copyPlainText(meetingID) }
    }
}

/// Notices above the content: meeting files that could not be read, and a
/// `platforms.yml` that could not be read.
struct BannerStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let first = model.failures.first {
                let n = model.failures.count
                Banner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       text: n == 1
                           ? "\(first.relativePath) could not be read: \(first.message)"
                           : "\(n) meeting files could not be read, starting with \(first.relativePath): \(first.message)",
                       action: "Reveal in Finder") { model.revealFailure(first) }
            }
            if let error = model.instructionsError {
                Banner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       text: "platforms.yml could not be read, so no platform instructions are shown: \(error)",
                       action: "Refresh") { model.refresh() }
            }
        }
    }
}

struct Banner: View {
    let symbol: String
    let tint: Color
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).lineLimit(2).truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action, action: perform).controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("QDVC Meetings")
                .font(.largeTitle.weight(.semibold))
            Text("Open a meetings workspace, or choose an empty folder to start one. Each meeting is kept there as a small text file you can sync, back up or read anywhere.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if !model.recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(Array(model.recentWorkspaces.prefix(5)), id: \.self) { path in
                        Button((path as NSString).abbreviatingWithTildeInPath) {
                            model.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
