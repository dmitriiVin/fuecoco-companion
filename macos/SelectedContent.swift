import AppKit
import ApplicationServices
import Carbon

func spokenText(_ value: Any?) -> String? {
    let text = (value as? String) ?? (value as? NSAttributedString)?.string
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}

func selectedPasteboardText(_ board: NSPasteboard) -> String? {
    if let text = spokenText(board.string(forType: .string)) { return text }
    if let rich = board.readObjects(forClasses: [NSAttributedString.self], options: nil)?.first {
        return spokenText(rich)
    }
    return nil
}

private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var item: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &item) == .success ? item : nil
}
private func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
private func childrenOf(_ node: AXUIElement) -> [AXUIElement] {
    value(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

struct AppSelection {
    let pid: pid_t
    let app: AXUIElement
    init(pid: pid_t) {
        self.pid = pid
        app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
    }

    enum Result { case text(String), protected, unavailable }
    func inspect() -> Result {
        if IsSecureEventInputEnabled() { return .protected }
        let system = AXUIElementCreateSystemWide()
        var nodes = [AXUIElement]()
        var focused = element(value(app, kAXFocusedUIElementAttribute)) ?? element(value(system, kAXFocusedUIElementAttribute))
        while let current = focused, nodes.count < 12, !nodes.contains(where: { CFEqual($0,current) }) {
            var owner: pid_t = 0
            guard AXUIElementGetPid(current,&owner) == .success, owner == pid else { break }
            if value(current,kAXSubroleAttribute) as? String == "AXSecureTextField" ||
                (value(current,"AXProtectedContent") as? Bool == true) { return .protected }
            nodes.append(current)
            focused = element(value(current,kAXParentAttribute))
        }
        if let window = element(value(app,kAXFocusedWindowAttribute)) { nodes.append(window) }
        nodes.append(app)
        for node in nodes {
            if let text = spokenText(value(node,kAXSelectedTextAttribute)) { return .text(text) }
            for (attribute, parameter) in [(kAXSelectedTextRangeAttribute, kAXStringForRangeParameterizedAttribute),
                                            ("AXSelectedTextMarkerRange", "AXStringForTextMarkerRange")] {
                guard let range = value(node,attribute) else { continue }
                var text: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(node,parameter as CFString,range,&text) == .success,
                   let selected = spokenText(text) { return .text(selected) }
            }
        }
        return .unavailable
    }

    func copyItem() -> AXUIElement? {
        guard let bar = element(value(app,kAXMenuBarAttribute)) else { return nil }
        let menus = childrenOf(bar)
        // AppKit and Electron expose the ordinary Copy command through their application's Edit menu.
        for menu in menus {
            for submenu in childrenOf(menu) {
                for item in childrenOf(submenu) {
                    let key = (value(item,kAXMenuItemCmdCharAttribute) as? String)?.lowercased()
                    let modifiers = value(item,kAXMenuItemCmdModifiersAttribute) as? Int
                    if modifiers == 0 && (key == "c" || value(item,kAXMenuItemCmdVirtualKeyAttribute) as? Int == kVK_ANSI_C) {
                        return item
                    }
                }
            }
        }
        return nil
    }

    func copy(using item: AXUIElement?) -> Bool {
        if let item {
            guard value(item,kAXEnabledAttribute) as? Bool != false else { return false }
            if AXUIElementPerformAction(item,kAXPressAction as CFString) == .success { return true }
        }
        guard !IsSecureEventInputEnabled(), CGPreflightPostEventAccess(),
              let source = CGEventSource(stateID:.privateState),
              let down = CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_ANSI_C),keyDown:true),
              let up = CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_ANSI_C),keyDown:false) else { return false }
        for event in [down,up] { event.flags = .maskCommand; event.postToPid(pid) }
        return true
    }
}

// Snapshot only ordinary, fully materialized items. Never clear the clipboard to probe for a selection.
struct ClipboardSnapshot {
    let revision: Int
    private let items: [[(NSPasteboard.PasteboardType,Data)]]
    init?(_ board: NSPasteboard) {
        revision = board.changeCount
        let originals = board.pasteboardItems ?? []
        var saved = [[(NSPasteboard.PasteboardType,Data)]]()
        var size = 0
        for original in originals {
            let types = original.types
            guard !types.contains(where: {
                let name = $0.rawValue.lowercased()
                return name.contains("concealed") || name.contains("transient") || name.contains("promis") || name.contains("password")
            }) else { return nil }
            var entries = [(NSPasteboard.PasteboardType,Data)]()
            for type in types {
                guard let data = original.data(forType:type) else { return nil }
                size += data.count
                guard size <= 16 * 1024 * 1024 else { return nil }
                entries.append((type,data))
            }
            saved.append(entries)
        }
        guard revision == board.changeCount else { return nil }
        items = saved
    }
    func restore(_ board: NSPasteboard, ifRevision copied: Int) {
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type,data) in entries { item.setData(data,forType:type) }
            return item
        }
        guard board.changeCount == copied else { return }
        board.clearContents()
        if !restored.isEmpty { board.writeObjects(restored) }
    }
}
