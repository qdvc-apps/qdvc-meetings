import Foundation

/// A meeting file that could not be read.
public struct LoadFailure: Equatable, Identifiable {
    public var id: String { relativePath }
    public let relativePath: String
    public let message: String
}

/// A file attached to a meeting, in the folder beside its meeting file.
public struct Attachment: Identifiable, Hashable {
    public var id: String { relativePath }
    public let name: String
    /// Relative to the workspace root.
    public let relativePath: String
    public let size: Int
    public let modified: Date?
    public let isFolder: Bool
}

/// The result of reading the workspace.
public struct LoadResult {
    public let meetings: [Meeting]
    public let failures: [LoadFailure]
    /// Each meeting's attachments, by the meeting's relative path. Meetings
    /// without attachments are absent.
    public let attachments: [String: [Attachment]]
}

/// A workspace folder (docs/FILE_FORMAT.md §1). Every write is atomic and
/// immediate. Reads are cached by modification date and size, so a refresh
/// re-parses only files that changed on disk.
public final class Workspace {
    public let root: URL
    public static let platformsFile = "platforms.yml"

    private struct Stamp: Equatable {
        let modified: Date?
        let size: Int?
    }

    private var cache: [String: (stamp: Stamp, meeting: Meeting)] = [:]
    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Whether the folder already holds a `meetings` folder.
    public static func looksLikeWorkspace(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let path = url.appendingPathComponent(Naming.meetingsFolder).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Creates `meetings/` if it is missing.
    public func ensureLayout() throws {
        try fm.createDirectory(at: root.appendingPathComponent(Naming.meetingsFolder), withIntermediateDirectories: true)
    }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    // MARK: Reading

    /// The attachments folder of a meeting file: its path without the
    /// extension (`meetings/2026/x.yml` → `meetings/2026/x`).
    public static func attachmentsFolder(forMeetingPath path: String) -> String {
        (path as NSString).deletingPathExtension
    }

    /// Every meeting file under `meetings/` (`*.yml` or `*.yaml`), as sorted
    /// relative paths, and every attachments folder: a folder with a meeting
    /// file of the same name beside it. Files inside attachments folders are
    /// never meetings. Hidden files and folders are skipped.
    public func scan() -> (meetingPaths: [String], attachmentFolders: Set<String>) {
        let base = root.appendingPathComponent(Naming.meetingsFolder)
        guard let e = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                    options: [.skipsHiddenFiles]) else { return ([], []) }
        let prefix = base.standardizedFileURL.resolvingSymlinksInPath().path
        var paths: [String] = []
        var folders = Set<String>()
        for case let url as URL in e {
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(prefix + "/") else { continue }
            let relative = Naming.meetingsFolder + "/" + String(full.dropFirst(prefix.count + 1))
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true {
                if fm.fileExists(atPath: full + ".yml") || fm.fileExists(atPath: full + ".yaml") {
                    folders.insert(relative)
                    e.skipDescendants()
                }
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "yml" || ext == "yaml", values?.isRegularFile == true else { continue }
            paths.append(relative)
        }
        return (paths.sorted(), folders)
    }

    public func meetingPaths() -> [String] { scan().meetingPaths }

    private func stamp(_ relativePath: String) -> Stamp {
        let attrs = try? fm.attributesOfItem(atPath: url(for: relativePath).path)
        return Stamp(modified: attrs?[.modificationDate] as? Date,
                     size: (attrs?[.size] as? NSNumber)?.intValue)
    }

    /// Reads every meeting, re-parsing only files that changed since the last
    /// load. A meeting keeps its `id` across loads while its path is the same.
    public func load() -> LoadResult {
        var meetings: [Meeting] = []
        var failures: [LoadFailure] = []
        var attachments: [String: [Attachment]] = [:]
        var seen = Set<String>()
        let (paths, folders) = scan()
        for path in paths {
            let folder = Workspace.attachmentsFolder(forMeetingPath: path)
            if folders.contains(folder) {
                let list = listAttachments(inFolder: folder)
                if !list.isEmpty { attachments[path] = list }
            }
            seen.insert(path)
            let s = stamp(path)
            if let cached = cache[path], cached.stamp == s {
                meetings.append(cached.meeting)
                continue
            }
            do {
                let data = try Data(contentsOf: url(for: path))
                guard let text = String(data: data, encoding: .utf8) else {
                    throw MeetingFileError.invalidYAML("not UTF-8 text")
                }
                let id = cache[path]?.meeting.id ?? UUID()
                let meeting = try MeetingFile.parse(text, relativePath: path, id: id)
                cache[path] = (s, meeting)
                meetings.append(meeting)
            } catch {
                cache[path] = nil
                failures.append(LoadFailure(relativePath: path, message: String(describing: error)))
            }
        }
        for key in cache.keys where !seen.contains(key) { cache[key] = nil }
        return LoadResult(meetings: meetings, failures: failures, attachments: attachments)
    }

    // MARK: Writing

    /// Writes the meeting, choosing or updating its file name: a new meeting
    /// gets the first free name for its date, time and title, and an existing
    /// one is renamed (and moved between year folders) when those change.
    /// Returns the meeting with its `relativePath` set.
    @discardableResult
    public func save(_ meeting: Meeting) throws -> Meeting {
        var m = meeting
        let stem = Naming.stem(for: m)
        let folder = Naming.folder(for: m)
        let oldPath = m.relativePath
        let newPath: String
        if let old = oldPath, Naming.path(old, fits: stem, in: folder) {
            newPath = old
        } else {
            var taken = Set(meetingPaths())
            // A folder of that name (attachments, or anything else) also
            // counts as taken, so a meeting never adopts a stranger's folder.
            if let names = try? fm.contentsOfDirectory(atPath: url(for: folder).path) {
                for name in names { taken.insert("\(folder)/\(name).\(Naming.fileExtension)") }
            }
            if let old = oldPath {
                taken.remove(old)
                taken.remove("\(Workspace.attachmentsFolder(forMeetingPath: old)).\(Naming.fileExtension)")
            }
            newPath = Naming.uniquePath(stem: stem, in: folder, taken: taken)
        }
        m.relativePath = newPath

        let target = url(for: newPath)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The attachments folder moves with its meeting, before anything else
        // changes, so a failure leaves both where they were.
        if let old = oldPath, old != newPath {
            let oldFolder = url(for: Workspace.attachmentsFolder(forMeetingPath: old))
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: oldFolder.path, isDirectory: &isDir), isDir.boolValue {
                try fm.moveItem(at: oldFolder, to: url(for: Workspace.attachmentsFolder(forMeetingPath: newPath)))
            }
        }
        try Data(MeetingFile.render(m).utf8).write(to: target, options: .atomic)
        if let old = oldPath, old != newPath {
            try? fm.removeItem(at: url(for: old))
            cache[old] = nil
            removeFolderIfEmpty(url(for: old).deletingLastPathComponent())
        }
        cache[newPath] = (stamp(newPath), m)
        return m
    }

    /// Forgets a meeting whose file has been moved away (to the Trash), and
    /// removes its year folder if that is now empty.
    public func forget(_ relativePath: String) {
        cache[relativePath] = nil
        removeFolderIfEmpty(url(for: relativePath).deletingLastPathComponent())
    }

    private func removeFolderIfEmpty(_ folder: URL) {
        let meetings = root.appendingPathComponent(Naming.meetingsFolder).standardizedFileURL
        guard folder.standardizedFileURL != meetings,
              folder.standardizedFileURL.path.hasPrefix(meetings.path + "/"),
              let items = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        // A folder holding only Finder's .DS_Store counts as empty.
        guard items.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? fm.removeItem(at: folder)
    }

    // MARK: Attachments

    /// A meeting's attachments, sorted by name as Finder sorts them.
    public func attachments(forMeetingPath path: String) -> [Attachment] {
        listAttachments(inFolder: Workspace.attachmentsFolder(forMeetingPath: path))
    }

    private func listAttachments(inFolder folder: String) -> [Attachment] {
        let dir = url(for: folder)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [Attachment] = []
        for name in names where !name.hasPrefix(".") {
            let path = dir.appendingPathComponent(name).path
            let attrs = try? fm.attributesOfItem(atPath: path)
            out.append(Attachment(name: name, relativePath: "\(folder)/\(name)",
                                  size: (attrs?[.size] as? NSNumber)?.intValue ?? 0,
                                  modified: attrs?[.modificationDate] as? Date,
                                  isFolder: (attrs?[.type] as? FileAttributeType) == .typeDirectory))
        }
        return out.sorted { $0.name.compare($1.name, options: [.caseInsensitive, .numeric]) == .orderedAscending }
    }

    /// Copies files into a meeting's attachments folder, creating it if
    /// needed. Names are kept; a taken name gets a number, as Finder does
    /// ("photo 2.png"). Files already in the folder are skipped. Returns the
    /// names given.
    @discardableResult
    public func addAttachments(_ sources: [URL], toMeetingPath path: String) throws -> [String] {
        let dir = url(for: Workspace.attachmentsFolder(forMeetingPath: path))
        let dirPath = dir.standardizedFileURL.resolvingSymlinksInPath().path
        let todo = sources.filter {
            !$0.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(dirPath + "/")
        }
        guard !todo.isEmpty else { return [] }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var taken = Set(((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).map { $0.lowercased() })
        var added: [String] = []
        for source in todo {
            let name = Workspace.uniqueAttachmentName(source.lastPathComponent, taken: taken)
            try fm.copyItem(at: source, to: dir.appendingPathComponent(name))
            taken.insert(name.lowercased())
            added.append(name)
        }
        return added
    }

    /// `name`, or Finder's "name 2.ext", "name 3.ext"… if taken (compared
    /// case-insensitively).
    public static func uniqueAttachmentName(_ name: String, taken: Set<String>) -> String {
        if !taken.contains(name.lowercased()) { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }

    /// Removes a meeting's attachments folder if nothing (but .DS_Store) is
    /// left in it.
    public func removeAttachmentsFolderIfEmpty(forMeetingPath path: String) {
        let dir = url(for: Workspace.attachmentsFolder(forMeetingPath: path))
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path),
              items.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? fm.removeItem(at: dir)
    }

    // MARK: Platform instructions

    public var platformsURL: URL { root.appendingPathComponent(Workspace.platformsFile) }

    /// The instructions, or empty ones if the file is missing.
    public func loadPlatformInstructions() throws -> PlatformInstructions {
        guard fm.fileExists(atPath: platformsURL.path) else { return PlatformInstructions() }
        let data = try Data(contentsOf: platformsURL)
        return try MeetingFile.parsePlatforms(String(decoding: data, as: UTF8.self))
    }

    public func savePlatformInstructions(_ p: PlatformInstructions) throws {
        try Data(MeetingFile.renderPlatforms(p).utf8).write(to: platformsURL, options: .atomic)
    }
}
