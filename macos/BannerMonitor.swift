import AppKit
import ApplicationServices

enum BannerMode: Int { case off, app, full }

struct Banner {
    let id: String
    let header: String
    let lines: [String]
    func words(for mode: BannerMode) -> String? {
        let app = header.isEmpty ? "Новое уведомление" : header
        switch mode {
        case .off: return nil
        case .app: return app
        case .full: return ([app] + lines.filter { $0 != header }).joined(separator: ". ")
        }
    }
}

private func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
}

private func string(_ node: AXUIElement, _ key: String) -> String {
    (attr(node,key) as? String)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
}

private func children(_ node: AXUIElement) -> [AXUIElement] {
    attr(node,kAXChildrenAttribute) as? [AXUIElement] ?? []
}

private let bannerRoles: Set<String> = ["AXNotificationCenterAlert","AXNotificationCenterAlertStack",
                                       "AXNotificationCenterBanner","AXNotificationCenterBannerStack",
                                       "AXNotificationCenterBannerWindow"]

private func visibleBanners() -> [Banner]? {
    guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.notificationcenterui").first else { return nil }
    let app = AXUIElementCreateApplication(nc.processIdentifier)
    AXUIElementSetMessagingTimeout(app,0.2)
    guard let windows = attr(app,kAXWindowsAttribute) as? [AXUIElement] else { return nil }
    var found = [Banner]()
    func extract(_ node: AXUIElement) {
        var header = "", parts = [String]()
        func collect(_ current: AXUIElement, depth: Int) {
            guard depth < 8 else { return }
            if string(current,kAXRoleAttribute) == kAXStaticTextRole {
                let value = string(current,kAXValueAttribute)
                let text = value.isEmpty ? string(current,kAXTitleAttribute) : value
                if !text.isEmpty {
                    let id = string(current,kAXIdentifierAttribute).lowercased()
                    if id == "header" || id == "appname" { header = text }
                    else if !parts.contains(text) { parts.append(text) }
                }
                return
            }
            for child in children(current) { collect(child,depth:depth+1) }
        }
        collect(node,depth:0)
        guard !header.isEmpty || !parts.isEmpty else { return }
        let identifier = string(node,kAXIdentifierAttribute)
        let key = UUID(uuidString:identifier)?.uuidString ?? String(([header] + parts).joined(separator:"\n").hashValue)
        found.append(Banner(id:key,header:header,lines:parts))
    }
    func visit(_ node: AXUIElement, depth: Int) {
        guard depth < 9 else { return }
        if bannerRoles.contains(string(node,kAXSubroleAttribute)) {
            extract(node)
            return
        }
        for child in children(node) { visit(child,depth:depth+1) }
    }
    for window in windows where string(window,kAXSubroleAttribute) == "AXSystemDialog" {
        visit(window,depth:0)
    }
    return found
}

final class BannerMonitor {
    var display: (String) -> Void = { _ in }
    var clear: () -> Void = {}
    private let reader = DispatchQueue(label:"local.fuecoco.banner-reader",qos:.utility)
    private var reading = false
    private var generation = 0
    private var seen = [String: Date]()
    private var baselineNeeded = true
    private var timer: Timer?
    private(set) var mode: BannerMode = .off

    func set(_ choice: BannerMode, prompt: Bool = false) {
        generation += 1
        mode = choice
        UserDefaults.standard.set(choice.rawValue,forKey:"bannerDisplayMode")
        timer?.invalidate()
        timer = nil
        reset()
        guard mode != .off else { return }
        if prompt && !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt":true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        let poll = Timer(timeInterval:1.25,repeats:true) { [weak self] _ in self?.scan() }
        poll.tolerance = 0.15
        RunLoop.main.add(poll,forMode:.common)
        timer = poll
        scan()
    }

    func start() {
        let saved = UserDefaults.standard.object(forKey:"bannerDisplayMode") as? Int
        set(saved.flatMap(BannerMode.init(rawValue:)) ?? .full, prompt:saved == nil)
    }

    private func reset() {
        clear()
        seen.removeAll()
        baselineNeeded = true
    }

    private func canRead() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let session = CGSessionCopyCurrentDictionary() as? [String:Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool != true &&
               session["kCGSSessionOnConsoleKey"] as? Bool != false
    }

    private func scan() {
        guard mode != .off else { return }
        guard canRead() else {
            if !baselineNeeded { generation += 1; reset() }
            return
        }
        guard !reading else { return }
        reading = true
        let currentGeneration = generation
        reader.async { [weak self] in
            let results = visibleBanners()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.reading = false
                guard self.generation == currentGeneration, self.canRead(), let results = results else { return }
                let now = Date()
                self.seen = self.seen.filter { now.timeIntervalSince($0.value) < 60 }
                for banner in results {
                    let fresh = self.seen.updateValue(now,forKey:banner.id) == nil
                    if fresh && !self.baselineNeeded, let words = banner.words(for:self.mode) {
                        self.display(words)
                    }
                }
                self.baselineNeeded = false
            }
        }
    }
}
