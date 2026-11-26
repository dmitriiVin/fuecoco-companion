import Foundation
import Darwin

// Browser temporary files carry a completion signal (rename). Very fast downloads may
// first be observed under their final name, with the download provenance supplied by macOS.
final class DownloadInbox {
    private struct Candidate {
        var file: DiskFile?
        var stableSince: Date
    }
    let folder: URL
    private var names: Set<String>?
    private var watches = [String: DownloadWatch]()
    private var candidates = [URL: Candidate]()
    private var reported = [URL:(DiskFile, Date)]()
    private var directoryStamp: Date?
    private var lastScan = Date.distantPast

    init(folder: URL) { self.folder = folder }
    static func hasOrigin(_ url: URL) -> Bool {
        let attributes: [String] = ["com.apple.metadata:kMDItemWhereFroms","com.apple.metadata:kMDItemDownloadedDate","com.apple.quarantine"]
        return attributes.contains {
            getxattr(url.path,$0,nil,0,0,XATTR_NOFOLLOW) > 0
        }
    }
    func poll(at now: Date) throws -> [URL] {
        let fm = FileManager.default
        let stamp = try fm.attributesOfItem(atPath:folder.path)[.modificationDate] as? Date
        if names == nil || stamp != directoryStamp || now.timeIntervalSince(lastScan) >= 15 {
            let latest = Set(try fm.contentsOfDirectory(atPath:folder.path).filter { !$0.hasPrefix(".") })
            let first = names == nil
            for name in latest.subtracting(names ?? []) {
                let url = folder.appendingPathComponent(name).standardizedFileURL
                if DownloadWatch.suffixes.contains(url.pathExtension.lowercased()) {
                    watches[name] = try? DownloadWatch(url)
                } else if !first, DiskFile.read(url) != nil {
                    candidates[url] = Candidate(file:nil,stableSince:now)
                }
            }
            names = latest
            directoryStamp = stamp
            lastScan = now
        }
        var ready = [URL]()
        for (name,watch) in watches {
            switch watch.check(now:now) {
            case .waiting: break
            case .gone: watches.removeValue(forKey:name)
            case .ready(let url):
                ready.append(url.standardizedFileURL)
                watches.removeValue(forKey:name)
            }
        }
        for url in ready { candidates.removeValue(forKey:url) }
        for (url,var pending) in candidates {
            guard let file = DiskFile.read(url) else { candidates.removeValue(forKey:url); continue }
            if watches.values.contains(where:{ $0.partial.deletingPathExtension().path == url.path }) { continue }
            if pending.file != file { pending.file = file; pending.stableSince = now; candidates[url] = pending }
            if now.timeIntervalSince(pending.stableSince) >= 3 && Self.hasOrigin(url) {
                candidates.removeValue(forKey:url)
                ready.append(url)
            } else if now.timeIntervalSince(pending.stableSince) > 30 {
                candidates.removeValue(forKey:url)
            }
        }
        reported = reported.filter { now.timeIntervalSince($0.value.1) < 90 }
        return ready.filter { url in
            guard let file = DiskFile.read(url), reported[url]?.0 != file else { return false }
            reported[url] = (file,now)
            return true
        }
    }
}

// Disk I/O and the macOS Downloads-folder access prompt must not block the pet's animation.
final class AutomaticDownloads {
    var completed: (URL) -> Void = { _ in }
    var onAccessError: () -> Void = {}
    private let worker = DispatchQueue(label:"local.fuecoco.download-inbox",qos:.utility)
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private(set) var enabled = false
    func setEnabled(_ enabled: Bool) {
        generation += 1
        self.enabled = enabled
        UserDefaults.standard.set(enabled,forKey:"automaticDownloads")
        timer?.cancel(); timer = nil
        guard enabled, let folder = FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first else { return }
        let inbox = DownloadInbox(folder:folder)
        let version = generation
        let source = DispatchSource.makeTimerSource(queue:worker)
        var nextAttempt = Date.distantPast
        var warned = false
        source.setEventHandler { [weak self] in
            let now = Date()
            guard now >= nextAttempt else { return }
            do {
                let ready = try inbox.poll(at:now)
                warned = false
                guard !ready.isEmpty else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == version else { return }
                    ready.forEach(self.completed)
                }
            } catch {
                nextAttempt = now.addingTimeInterval(15)
                if !warned {
                    warned = true
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == version else { return }
                        self.onAccessError()
                    }
                }
            }
        }
        source.schedule(deadline:.now(),repeating:1.1,leeway:.milliseconds(200))
        timer = source
        source.resume()
    }
}
