import AppKit
import Carbon
import AVFoundation
import NaturalLanguage

final class SelectionReader: NSObject, AVSpeechSynthesizerDelegate {
    var message: (String) -> Void = { _ in }
    var onReading: (Bool) -> Void = { _ in }
    private let synth = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let lookup = DispatchQueue(label:"local.fuecoco.selection",qos:.userInitiated)
    private var menuSource: NSRunningApplication?
    private var acquiring = false
    private var lastExternal: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private let selfPID = ProcessInfo.processInfo.processIdentifier
    var hasShortcut: Bool { hotKey != nil }
    override init() {
        super.init()
        synth.delegate = self
        remember(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main
        ) { [weak self] note in self?.remember(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
    }
    func registerShortcut() {
        var type = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),
                                    nil,MemoryLayout<EventHotKeyID>.size,nil,&id) == noErr,
                  id.signature == 0x46554543, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let reader = Unmanaged<SelectionReader>.fromOpaque(context).takeUnretainedValue()
            reader.toggle()
            return noErr
        }
        let target = GetApplicationEventTarget()
        guard InstallEventHandler(target,callback,1,&type,Unmanaged.passUnretained(self).toOpaque(),&eventHandler) == noErr else { return }
        let id = EventHotKeyID(signature:0x46554543,id:1)
        _ = RegisterEventHotKey(UInt32(kVK_ANSI_R),UInt32(controlKey | shiftKey),id,target,0,&hotKey)
    }
    deinit {
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
    }
    private func remember(_ app: NSRunningApplication?) {
        if let app, app.processIdentifier != selfPID, app.activationPolicy == .regular { lastExternal = app }
    }

    func menuWillOpen() {
        let front = NSWorkspace.shared.frontmostApplication
        menuSource = front?.activationPolicy == .regular && front?.processIdentifier != selfPID ? front : lastExternal
    }

    @objc func fromMenu() {
        let source = menuSource ?? NSWorkspace.shared.frontmostApplication
        // AppKit must finish dismissing the status menu before the source app can answer AX queries.
        DispatchQueue.main.asyncAfter(deadline:.now()+0.16) { self.begin(source) }
    }
    @objc func toggle() { begin(NSWorkspace.shared.frontmostApplication) }

    private func begin(_ source: NSRunningApplication?) {
        if stopIfSpeaking() || acquiring { return }
        guard let source, source.processIdentifier != selfPID, !source.isTerminated else {
            message("Откройте окно с выделением"); return
        }
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary) else {
            message("Нужен доступ: настройки macOS"); return
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == selfPID || front?.activationPolicy != .regular { source.activate(options:[]) }
        else if front?.processIdentifier != source.processIdentifier { message("Активное окно сменилось"); return }
        acquiring = true
        let target = source.processIdentifier
        lookup.asyncAfter(deadline:.now()+0.08) {
            let selection = AppSelection(pid:target)
            let result = selection.inspect()
            let copy: AXUIElement?
            if case .unavailable = result { copy = selection.copyItem() } else { copy = nil }
            DispatchQueue.main.async {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { self.acquiring = false; self.message("Активное окно сменилось"); return }
                switch result {
                case .text(let text): self.acquiring = false; self.read(text)
                case .protected: self.acquiring = false; self.message("Защищённое поле")
                case .unavailable: self.copySelection(selection, item:copy)
                }
            }
        }
    }
    private func stillActive(_ pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && !IsSecureEventInputEnabled()
    }
    private func copySelection(_ selection: AppSelection, item: AXUIElement?) {
        let board = NSPasteboard.general
        guard let snapshot = ClipboardSnapshot(board) else {
            acquiring = false; message("Используйте службу чтения"); return
        }
        guard stillActive(selection.pid), board.changeCount == snapshot.revision,
              selection.copy(using:item) else {
            acquiring = false; message("Копирование недоступно"); return
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        func poll() {
            guard stillActive(selection.pid) else { acquiring = false; return }
            let copied = board.changeCount
            if copied != snapshot.revision {
                let text = selectedPasteboardText(board)
                if text == nil && (board.types ?? []).isEmpty && ProcessInfo.processInfo.systemUptime < deadline {
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.02,execute:poll)
                    return
                }
                guard board.changeCount == copied else { acquiring = false; return }
                snapshot.restore(board,ifRevision:copied)
                acquiring = false
                if let text { read(text) } else { message("В выделении нет текста") }
            } else if ProcessInfo.processInfo.systemUptime < deadline {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.025,execute:poll)
            } else { acquiring = false; message("Приложение не передало текст") }
        }
        poll()
    }
    @discardableResult func stopIfSpeaking() -> Bool {
        guard utterance != nil else { return false }
        utterance = nil
        synth.stopSpeaking(at:.immediate)
        onReading(false)
        return true
    }
    func read(_ text: String) {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        _ = stopIfSpeaking()
        let words = AVSpeechUtterance(string:text)
        let language = NLLanguageRecognizer.dominantLanguage(for:String(text.prefix(1200)))?.rawValue ?? "ru"
        words.voice = AVSpeechSynthesisVoice(language:language)
        utterance = words
        onReading(true)
        synth.speak(words)
    }
    private func ended(_ item: AVSpeechUtterance) {
        if utterance === item { utterance = nil; onReading(false) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { ended(utterance) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { ended(utterance) }
}
