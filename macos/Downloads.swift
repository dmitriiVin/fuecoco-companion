import AppKit

struct DiskFile: Equatable {
    let inode: UInt64
    let size: Int64
    let modified: Date
    static func read(_ url: URL) -> Self? {
        guard let a = try? FileManager.default.attributesOfItem(atPath:url.path),
              a[.type] as? FileAttributeType == .typeRegular,
              let id = a[.systemFileNumber] as? NSNumber,
              let bytes = a[.size] as? NSNumber,
              let time = a[.modificationDate] as? Date else { return nil }
        return Self(inode:id.uint64Value,size:bytes.int64Value,modified:time)
    }
}

enum DownloadEvent { case waiting, ready(URL), gone }

final class DownloadWatch {
    static let suffixes: Set<String> = ["crdownload","part","download"]
    let partial: URL
    private let expected: URL
    private let original: DiskFile?
    private var inodes: Set<UInt64> = []
    private var previous: DiskFile?
    private var previousURL: URL?
    private var missingSince: Date?
    init(_ partial: URL) throws {
        self.partial = partial.standardizedFileURL
        guard Self.suffixes.contains(partial.pathExtension.lowercased()), FileManager.default.fileExists(atPath:partial.path) else {
            throw PetError.message("Выберите незавершённую загрузку с расширением .download, .crdownload или .part.")
        }
        expected = partial.deletingPathExtension()
        original = DiskFile.read(expected)
        observePartial()
    }
    private func observePartial() {
        if let file = DiskFile.read(partial) { inodes.insert(file.inode); return }
        if partial.pathExtension.lowercased() == "download",
           let items = try? FileManager.default.contentsOfDirectory(at:partial,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) {
            for item in items where item.pathExtension.lowercased() != "plist" {
                if let file = DiskFile.read(item) { inodes.insert(file.inode) }
            }
        }
    }
    func check(now: Date = Date()) -> DownloadEvent {
        if FileManager.default.fileExists(atPath:partial.path) {
            observePartial()
            missingSince = nil
            previous = nil
            return .waiting
        }
        if missingSince == nil { missingSince = now }
        var candidate = expected
        var file = DiskFile.read(expected)
        // A cancelled download may leave an old file or a zero-byte placeholder at the final path.
        if file == nil || file == original || (file!.size == 0 && !inodes.contains(file!.inode)) {
            file = nil
            let folder = partial.deletingLastPathComponent()
            if !inodes.isEmpty, let entries = try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) {
                for url in entries where !Self.suffixes.contains(url.pathExtension.lowercased()) {
                    if let item = DiskFile.read(url), inodes.contains(item.inode) {
                        candidate = url; file = item; break
                    }
                }
            }
        }
        if let file = file {
            if previous == file && previousURL == candidate { return .ready(candidate) }
            previous = file; previousURL = candidate
        } else {
            previous = nil
            if let since = missingSince, now.timeIntervalSince(since) > 12 { return .gone }
        }
        return .waiting
    }
}

final class Downloads: NSObject {
    var message: (String) -> Void = { _ in }
    var complete: (URL) -> Void = { _ in }
    private(set) var watch: DownloadWatch?
    private var last = UserDefaults.standard.url(forKey:"lastCompletedDownload")
    var canReveal: Bool { last.map { FileManager.default.fileExists(atPath:$0.path) } ?? false }
    private var timer: Timer?
    @objc func select() {
        let panel = NSOpenPanel()
        panel.title = "Когда скачается — позови"
        panel.message = "Выберите файл текущей загрузки Safari, Chrome или Firefox (.download, .crdownload или .part)."
        panel.directoryURL = FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.canChooseDirectories = true
        panel.prompt = "Ждать"
        NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pending = try DownloadWatch(url)
            stop()
            watch = pending
            message("Жду загрузку")
            timer = Timer.scheduledTimer(withTimeInterval:1.2,repeats:true) { [weak self] _ in self?.tick() }
            timer?.tolerance = 0.2
        } catch {
            let alert = NSAlert(); alert.messageText = error.localizedDescription; alert.runModal()
        }
    }
    @objc func stop() {
        timer?.invalidate(); timer = nil; watch = nil
    }
    private var recentlyFinished = [String:(DiskFile, Date)]()
    func finished(_ url: URL) {
        let now = Date()
        recentlyFinished = recentlyFinished.filter { now.timeIntervalSince($0.value.1) < 90 }
        let key = url.resolvingSymlinksInPath().path
        guard let file = DiskFile.read(url), recentlyFinished[key]?.0 != file else { return }
        recentlyFinished[key] = (file,now)
        last = url
        UserDefaults.standard.set(url,forKey:"lastCompletedDownload")
        complete(url)
    }
    @objc func reveal() {
        if let url = last, canReveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    private func tick() {
        guard let watch = watch else { return }
        switch watch.check() {
        case .waiting: break
        case .gone:
            stop(); message("Загрузка исчезла")
        case .ready(let url):
            stop()
            finished(url)
        }
    }
}
