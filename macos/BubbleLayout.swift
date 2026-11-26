import AppKit

enum BubbleLayout {
    static let attributes: [NSAttributedString.Key:Any] = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return [.font:NSFont.systemFont(ofSize:13,weight:.semibold), .foregroundColor:NSColor.white,.paragraphStyle:style]
    }()
    static let options: NSString.DrawingOptions = [.usesLineFragmentOrigin,.usesFontLeading]
    static func height(_ text: String, width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(with:NSSize(width:width,height:CGFloat.greatestFiniteMagnitude),
                                           options:options,attributes:attributes).height)
    }
    static func pages(_ message: String, width: CGFloat, maxHeight: CGFloat) -> [String] {
        var result = [String](), line = ""
        for word in message.split(whereSeparator: { $0.isWhitespace }) {
            let proposed = line.isEmpty ? String(word) : line + " " + word
            if height(proposed,width:width) <= maxHeight { line = proposed; continue }
            if !line.isEmpty { result.append(line); line = "" }
            for char in word {
                if !line.isEmpty && height(line + String(char),width:width) > maxHeight {
                    result.append(line); line = ""
                }
                line.append(char)
            }
        }
        if !line.isEmpty { result.append(line) }
        return result
    }
}
