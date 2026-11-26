import AppKit
import ServiceManagement
import AVFoundation

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum Corner: String, CaseIterable {
    case lowerRight = "Справа внизу"
    case lowerLeft = "Слева внизу"
    case upperRight = "Справа вверху"
    case upperLeft = "Слева вверху"
}

final class Companion: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    let size = NSSize(width: 308, height: 252)
    private var panel: PetPanel!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var loginItem: NSMenuItem!
    private let banners = BannerMonitor()
    private let automatic = AutomaticDownloads()
    private var autoItem: NSMenuItem!
    private var growl: AVAudioPlayer?
    private var growlCount = 0
    private let downloads = Downloads()
    private let fileActions = FileActions()
    private let selection = SelectionReader()
    private var stopWatchItem: NSMenuItem!
    private var revealDownloadItem: NSMenuItem!
    private var idleDragCount = NSPasteboard(name:.drag).changeCount
    private let speechMenu = NSMenu()
    private let gesturesMenu = NSMenu()
    private let monitor = CodexActivity()
    private let reader = DispatchQueue(label: "local.fuecoco.activity", qos: .utility)
    private var reading = false
    private var activity = Activity()
    private let mood = fc_create()!
    private var build = FCBuild()
    deinit { fc_destroy(mood) }
    private var nextPoll = 0.0
    private var lastError = Date().timeIntervalSince1970
    private var lastFinish = Date().timeIntervalSince1970
    private var lastErrorBanner = 0.0
    private var unavailableSince: Double?
    private var corner: Corner {
        get { Corner(rawValue: UserDefaults.standard.string(forKey: "corner") ?? "") ?? .lowerLeft }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "corner") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let pet = PetView(size: size) else { NSApp.terminate(nil); return }
        panel = PetPanel(contentRect: pet.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Фуэкоко"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle, .stationary]
        panel.contentView = pet
        positionPanel()
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Фуэкоко")
        statusItem.button?.toolTip = "Фуэкоко"
        let menu = NSMenu()
        menu.delegate = self
        let report: (String) -> Void = { [weak pet] message in pet?.notify(message,now:Date().timeIntervalSince1970) }
        fileActions.report = report
        pet.onDrop = { [weak self] urls in self?.fileActions.handle(urls) }
        selection.message = report
        banners.display = report
        banners.clear = { [weak pet] in pet?.clearMessages() }
        if let clip = Bundle.main.url(forResource:"growl",withExtension:"wav") {
            growl = try? AVAudioPlayer(contentsOf:clip)
            growl?.prepareToPlay()
        }
        selection.registerShortcut()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        downloads.message = report
        downloads.complete = { [weak self] url in
            report("Скачано: " + url.lastPathComponent)
            self?.playGrowl()
        }
        automatic.completed = { [weak self] url in self?.downloads.finished(url) }
        automatic.onAccessError = { report("Нет доступа к папке «Загрузки». Проверьте «Файлы и папки» в настройках macOS.") }
        autoItem = menu.addItem(withTitle:"Автоматически следить за загрузками",action:#selector(toggleAutomatic),keyEquivalent:"")
        autoItem.target = self
        automatic.setEnabled(UserDefaults.standard.object(forKey:"automaticDownloads") as? Bool ?? true)
        let watchItem = menu.addItem(withTitle:"Когда скачается — позови…",action:#selector(Downloads.select),keyEquivalent:"")
        watchItem.target = downloads
        stopWatchItem = menu.addItem(withTitle:"Перестать ждать загрузку",action:#selector(Downloads.stop),keyEquivalent:"")
        stopWatchItem.target = downloads
        revealDownloadItem = menu.addItem(withTitle:"Показать загрузку в Finder",action:#selector(Downloads.reveal),keyEquivalent:"")
        revealDownloadItem.target = downloads
        let files = menu.addItem(withTitle:"Действия с файлами…",action:#selector(chooseImages),keyEquivalent:"")
        files.target = self
        let read = menu.addItem(withTitle:selection.hasShortcut ? "Прочитать / остановить выделенное   ⌃⇧R" : "Прочитать / остановить выделенное",action:#selector(SelectionReader.fromMenu),keyEquivalent:"")
        read.target = selection
        menu.addItem(.separator())
        menu.addItem(withTitle: "Анимации", action: nil, keyEquivalent: "").submenu = gesturesMenu
        for (name, action) in [("Помахать лапой", #selector(wavePaw)), ("Пробежаться", #selector(dash)),
                               ("Чихнуть", #selector(sneeze)), ("Пустить сердечки", #selector(hearts))] {
            gesturesMenu.addItem(withTitle: name, action: action, keyEquivalent: "").target = self
        }
        for item in Corner.allCases {
            let choice = menu.addItem(withTitle: item.rawValue, action: #selector(chooseCorner(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = item.rawValue
        }
        menu.addItem(.separator())
        let speechItem = menu.addItem(withTitle: "Текст уведомлений над Фуэкоко", action: nil, keyEquivalent: "")
        speechItem.submenu = speechMenu
        speechMenu.delegate = self
        for (title, mode) in [("Выключена", BannerMode.off), ("Только приложение", .app), ("Приложение и текст", .full)] {
            let item = speechMenu.addItem(withTitle: title, action: #selector(chooseSpeech(_:)), keyEquivalent: "")
            item.tag = mode.rawValue
            item.target = self
        }
        let access = speechMenu.addItem(withTitle: "Разрешить доступ в настройках…", action: #selector(openSpeechSettings), keyEquivalent: "")
        access.target = self
        menu.addItem(.separator())
        banners.start()
        loginItem = menu.addItem(withTitle: "Открывать при входе в систему", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Закрыть Фуэкоко", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu

        let animation = Timer(timeInterval: 0.10, repeats: true) { [weak self, weak pet] _ in
            guard let self = self, let pet = pet else { return }
            self.updateDropTarget()
            let now = Date().timeIntervalSince1970
            if now >= self.nextPoll && !self.reading {
                self.reading = true
                self.nextPoll = now + 2
                self.reader.async {
                    let localBuild = fc_sample_build()
                    let result = self.monitor.sample(at: now)
                    DispatchQueue.main.async {
                        self.build = localBuild
                        self.receive(result, pet: pet)
                        if localBuild.building { self.statusItem.button?.toolTip = "Фуэкоко · идёт локальная сборка" }
                    }
                }
            }
            let failed = self.build.failed || (self.activity.failedAt > 0 && now - self.activity.failedAt < 9)
            let right = self.corner == .lowerRight || self.corner == .upperRight
            let frame = fc_step(self.mood, ProcessInfo.processInfo.systemUptime,
                                self.build.building || self.activity.working, failed, right,
                                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            pet.step(frame, now: now)
        }
        animation.tolerance = 0.025
        RunLoop.main.add(animation, forMode: .common)
        timer = animation
    }

    @objc private func wavePaw() { fc_wave(mood) }
    @objc private func dash() { fc_dash(mood) }
    @objc private func sneeze() { fc_sneeze(mood) }
    @objc private func hearts() { fc_hearts(mood) }

    @objc private func chooseImages() { fileActions.chooseFiles() }

    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.async { self.fileActions.handle(urls) }
    }

    private func updateDropTarget() {
        let board = NSPasteboard(name:.drag)
        if NSEvent.pressedMouseButtons & 1 == 0 {
            idleDragCount = board.changeCount
            panel.ignoresMouseEvents = true
        } else {
            let fileDrag = board.changeCount != idleDragCount && board.types?.contains(.fileURL) == true
            panel.ignoresMouseEvents = !(fileDrag && panel.frame.insetBy(dx:-48,dy:-48).contains(NSEvent.mouseLocation))
        }
    }

    @objc func speakSelection(_ board: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = selectedPasteboardText(board) else {
            error.pointee = "Выделите текст." as NSString; return
        }
        selection.read(text)
    }

    @objc private func toggleAutomatic() { automatic.setEnabled(!automatic.enabled) }

    private func playGrowl() {
        guard let growl else { return }
        growlCount += 1
        guard growlCount == 1 else { return }
        func next() {
            growl.currentTime = 0
            growl.play()
            DispatchQueue.main.asyncAfter(deadline:.now()+growl.duration+0.03) {
                self.growlCount -= 1
                if self.growlCount > 0 { next() }
            }
        }
        next()
    }

    private func receive(_ sample: Activity?, pet: PetView) {
        reading = false
        let now = Date().timeIntervalSince1970
        guard let sample = sample else {
            unavailableSince = unavailableSince ?? now
            if now - (unavailableSince ?? now) > 5 {
                activity = Activity()
                statusItem.button?.toolTip = "Фуэкоко · ожидание данных Codex"
            }
            return
        }
        unavailableSince = nil
        activity = sample
        statusItem.button?.toolTip = sample.working ? "Фуэкоко · Codex работает" : "Фуэкоко · отдыхает"
        let freshError = sample.failedAt > lastError
        let freshFinish = sample.finishedAt > lastFinish
        lastError = max(lastError, sample.failedAt)
        lastFinish = max(lastFinish, sample.finishedAt)
        if freshError && (!freshFinish || sample.failedAt >= sample.finishedAt) {
            if now - lastErrorBanner >= 12 {
                post("Ошибка в Codex", pet: pet, now: now)
                lastErrorBanner = now
            }
        } else if freshFinish {
            post("Задача завершена", pet: pet, now: now)
        }
    }

    private func post(_ message: String, pet: PetView, now: Double) {
        pet.notify(message, now: now)
    }

    private func screenID(_ screen: NSScreen) -> Int? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
    }

    private func positionPanel() {
        guard let panel = panel else { return }
        let preferredID = UserDefaults.standard.object(forKey: "display") as? Int
        guard let screen = NSScreen.screens.first(where: { screenID($0) == preferredID }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let right = corner == .lowerRight || corner == .upperRight
        let top = corner == .upperLeft || corner == .upperRight
        panel.setFrameOrigin(NSPoint(x: right ? area.maxX - size.width - 8 : area.minX + 8,
                                     y: top ? area.maxY - size.height - 8 : area.minY + 8))
    }

    @objc func chooseCorner(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String, let choice = Corner(rawValue: label) else { return }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            UserDefaults.standard.set(screenID(screen), forKey: "display")
        }
        corner = choice
        positionPanel()
    }

    @objc private func chooseSpeech(_ sender: NSMenuItem) {
        guard let mode = BannerMode(rawValue: sender.tag) else { return }
        banners.set(mode, prompt: true)
    }

    @objc private func openSpeechSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func menuWillOpen(_ menu: NSMenu) { if menu === statusItem.menu { selection.menuWillOpen() } }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.menu === gesturesMenu {
            if item.action == #selector(dash) && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return false }
            let recentError = activity.failedAt > 0 && Date().timeIntervalSince1970 - activity.failedAt < 9
            return !(build.building || activity.working || build.failed || recentError)
        }
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === speechMenu {
            for item in menu.items where item.action == #selector(chooseSpeech(_:)) {
                item.state = item.tag == banners.mode.rawValue ? .on : .off
            }
            return
        }
        autoItem?.state = automatic.enabled ? .on : .off
        stopWatchItem?.isHidden = downloads.watch == nil
        if let file = downloads.watch?.partial { stopWatchItem?.toolTip = file.lastPathComponent }
        revealDownloadItem?.isHidden = !downloads.canReveal
        for item in menu.items where item.representedObject is String {
            item.state = (item.representedObject as? String == corner.rawValue) ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() }
            else if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) { positionPanel() }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}

let app = NSApplication.shared
let companion = Companion()
app.setActivationPolicy(.accessory)
app.delegate = companion
app.run()
