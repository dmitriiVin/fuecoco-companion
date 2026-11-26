import AppKit

final class PetView: NSView {
    var onDrop: (([URL]) -> Void)?
    private var cache: [String:[NSImage]] = [:]
    private var sprite = FCFrame(group: nil, frame: 0, dx: 0, dy: 0)
    private(set) var bubble = ""
    private var bubbleUntil = 0.0
    private var pendingPages = [String]()
    private var textWidth: CGFloat { bounds.width - 28 }

    init?(size: NSSize) {
        super.init(frame: NSRect(origin: .zero,size:size))
        registerForDraggedTypes([.fileURL])
        for (name,count) in [("idle",6),("flame",8),("tears",6),("sleep",6),("rare",6),("left",8),("right",8),("wave",3),("hop",5),("look",3),("sneeze",8),("hearts",11)] {
            let frames = (0..<count).compactMap { i in
                Bundle.main.url(forResource:"\(name)-\(i)",withExtension:"png").flatMap(NSImage.init(contentsOf:))
            }
            guard frames.count == count else { return nil }
            cache[name] = frames
        }
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],
              !urls.isEmpty else { return false }
        DispatchQueue.main.async { self.onDrop?(urls) }
        return true
    }
    func notify(_ message: String, now: Double) {
        let pages = BubbleLayout.pages(message,width:textWidth,maxHeight:83)
        pendingPages.append(contentsOf:pages)
        if bubble.isEmpty || now >= bubbleUntil { showNext(now) }
    }
    func clearMessages() {
        pendingPages.removeAll()
        bubble = ""
        bubbleUntil = 0
        needsDisplay = true
    }
    private func showNext(_ now: Double) {
        bubble = pendingPages.isEmpty ? "" : pendingPages.removeFirst()
        bubbleUntil = now + min(13,max(4,Double(bubble.count)/13))
        needsDisplay = true
    }
    func step(_ frame: FCFrame, now: Double) {
        sprite = frame
        if !bubble.isEmpty && now >= bubbleUntil { showNext(now) }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using:.copy)
        let name = sprite.group.map { String(cString: $0) } ?? "idle"
        NSGraphicsContext.current?.imageInterpolation = .none
        cache[name]?[Int(sprite.frame)].draw(in: NSRect(x:round((bounds.width-144)/2 + sprite.dx),y:round(sprite.dy),width:144,height:156),
                                           from:.zero,operation:.sourceOver,fraction:1)
        if !bubble.isEmpty {
            let label = bubble as NSString
            let width = min(textWidth,ceil(label.size(withAttributes:BubbleLayout.attributes).width)+1)
            let height = BubbleLayout.height(bubble,width:width)
            let plate = NSRect(x:floor((bounds.width-width-24)/2),y:149,width:width+24,height:height+14)
            NSColor(white:0.12,alpha:0.94).setFill()
            NSBezierPath(roundedRect:plate,xRadius:12,yRadius:12).fill()
            label.draw(with:plate.insetBy(dx:12,dy:7),options:BubbleLayout.options,attributes:BubbleLayout.attributes)
        }
    }
}
