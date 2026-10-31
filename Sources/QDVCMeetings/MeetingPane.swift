import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
import MeetingsCore

/// The selected meeting, laid out like Calendar's event inspector, then its
/// notes (docs/DESIGN.md §2.5).
struct MeetingPane: View {
    @Environment(AppModel.self) private var model
    @State private var isFileTarget = false

    var body: some View {
        if let m = model.selectedMeeting {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MeetingHeader(meeting: m)
                    if m.locationKind != .none {
                        LocationRow(meeting: m)
                    }
                    if let callout = model.instructions(for: m) {
                        PlatformCallout(platform: callout.0, text: callout.1)
                    }
                    if !m.people.isEmpty {
                        PeopleChips(names: m.people)
                    }
                    if !m.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(m.details)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let files = model.attachments[m.id], !files.isEmpty {
                        AttachmentsSection(meetingID: m.id, attachments: files)
                    }
                    Divider().padding(.vertical, 2)
                    NotesList(meetingID: m.id)
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(m.id)
            // Files dropped from Finder (or Mail, Photos…) are attached.
            .onDrop(of: [.fileURL], isTargeted: $isFileTarget) { providers in
                model.importDroppedFiles(providers, to: m.id)
            }
            .overlay {
                if isFileTarget {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.06)))
                        .overlay(alignment: .top) {
                            Label("Drop to attach to this meeting", systemImage: "paperclip")
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.regularMaterial))
                                .padding(.top, 12)
                        }
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Meeting Selected", systemImage: "calendar")
            } description: {
                Text("Choose a meeting to see its details and notes.")
            }
        }
    }
}

private struct MeetingHeader: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting

    var body: some View {
        let m = meeting
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.formatter.longDate(m.date) + " \u{00B7} " + model.formatter.timeRange(m))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button {
                model.chooseAttachments(m.id)
            } label: {
                Label("Add Attachments", systemImage: "paperclip")
                    .labelStyle(.iconOnly)
            }
            .help("Attach files to this meeting (\u{21E7}\u{2318}A), or drop them on the meeting")
            Button("Edit") { model.editMeeting(m.id) }
                .help("Edit the meeting\u{2019}s title, time, location, people and description (\u{2318}E)")
            Menu {
                Button("Duplicate Meeting") { model.duplicateMeeting(m.id) }
                Button("Add Attachments\u{2026}") { model.chooseAttachments(m.id) }
                Divider()
                ExportMenuItems(meetingID: m.id)
                Divider()
                Button("Reveal in Finder") { model.revealMeetingFile(m.id) }
                Divider()
                Button("Delete Meeting\u{2026}") { model.requestDelete(m.id) }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions for this meeting")
        }
    }
}

/// The location's symbol and text, with Join, Open Map or Show in Maps.
private struct LocationRow: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting

    var body: some View {
        let m = meeting
        let kind = m.locationKind
        let text = m.location.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                if let service = kind.serviceName {
                    Text(kind == .googleMaps ? service : "\(service) meeting")
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(text).textSelection(.enabled).lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            if let title = kind.actionTitle {
                if kind.conferencePlatform != nil {
                    Button(title) { model.openLocation(m.id) }
                        .buttonStyle(.borderedProminent)
                        .help("Open the meeting link (\u{2318}J)")
                } else {
                    Button(title) { model.openLocation(m.id) }
                        .help(kind == .text ? "Search for this place in Maps (\u{2318}J)" : "Open the link (\u{2318}J)")
                }
            }
        }
        .contextMenu {
            Button(kind.isLink ? "Copy Link" : "Copy Location") { model.copyLocation(m.id) }
        }
    }
}

/// The short instructions for the meeting's platform, from Settings.
struct PlatformCallout: View {
    let platform: ConferencePlatform
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            (Text("\(platform.title): ").fontWeight(.semibold) + Text(text))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }
}

/// The meeting's people as tokens; clicking one shows their meetings.
private struct PeopleChips: View {
    @Environment(AppModel.self) private var model
    let names: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            FlowLayout(spacing: 5) {
                ForEach(names, id: \.self) { name in
                    Button {
                        model.selectPerson(name)
                    } label: {
                        Text(name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("Show meetings with \(name)")
                }
            }
        }
    }
}

/// Lays its children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The meeting's attachments as Quick Look thumbnails. Click one to Quick
/// Look it (← / → move between them); drag it out to copy it elsewhere; its
/// context menu opens it, reveals it in Finder or moves it to the Trash.
private struct AttachmentsSection: View {
    @Environment(AppModel.self) private var model
    let meetingID: UUID
    let attachments: [Attachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Attachments", systemImage: "paperclip")
                    .font(.headline)
                Spacer()
                Button("Add\u{2026}") { model.chooseAttachments(meetingID) }
                    .buttonStyle(.link)
                    .help("Attach more files (\u{21E7}\u{2318}A)")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 120), alignment: .top)],
                      alignment: .leading, spacing: 10) {
                ForEach(attachments) { a in
                    AttachmentTile(meetingID: meetingID, attachment: a)
                }
            }
        }
    }
}

private struct AttachmentTile: View {
    @Environment(AppModel.self) private var model
    let meetingID: UUID
    let attachment: Attachment
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        let a = attachment
        let url = model.attachmentURL(a)
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 64, height: 64)
            Text(a.name)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            Text(a.isFolder ? "Folder" : ByteCountFormatter.string(fromByteCount: Int64(a.size), countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.secondary.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.quickLook(a, of: meetingID) }
        .onDrag {
            url.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
        }
        .contextMenu {
            Button("Quick Look") { model.quickLook(a, of: meetingID) }
            Button("Open") { model.openAttachment(a) }
            Button("Reveal in Finder") { model.revealAttachment(a) }
            Divider()
            Button("Move to Trash") { model.removeAttachment(a, from: meetingID) }
        }
        .help("\(a.name) \u{2014} click to Quick Look; right-click to open it or reveal it in Finder")
        .task(id: a) {
            guard let url else { return }
            thumbnail = await Thumbnails.image(for: url, side: 64)
        }
    }
}

/// Quick Look thumbnails of attachments; nil when Quick Look has none (the
/// file's icon is shown instead).
@MainActor
enum Thumbnails {
    static func image(for url: URL, side: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        do {
            return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        } catch {
            return nil
        }
    }
}
