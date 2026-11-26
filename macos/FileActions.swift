import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

enum PetError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum ImageTools {
    static func image(_ url: URL, maxSide: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw PetError.message("Не удалось открыть изображение «\(url.lastPathComponent)».")
        }
        let edge = min(maxSide ?? max(width,height),max(width,height))
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,
                                      kCGImageSourceCreateThumbnailWithTransform:true,
                                      kCGImageSourceThumbnailMaxPixelSize:edge]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else {
            throw PetError.message("Не удалось прочитать изображение.")
        }
        return image
    }

    static func recognize(_ url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["ru-RU","en-US"].filter { supported.contains($0) }
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage:try image(url),options:[:]).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n")
        guard !text.isEmpty else { throw PetError.message("На картинке не найден текст.") }
        return text
    }

    static func encode(_ url: URL, jpeg: Bool, maxSide: Int?) throws -> Data {
        var raster = try image(url,maxSide:maxSide)
        if jpeg {
            guard let canvas = CGContext(data:nil,width:raster.width,height:raster.height,bitsPerComponent:8,bytesPerRow:0,
                                         space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw PetError.message("Не удалось подготовить JPEG.")
            }
            let rect = CGRect(x:0,y:0,width:raster.width,height:raster.height)
            canvas.setFillColor(CGColor(gray:1,alpha:1))
            canvas.fill(rect)
            canvas.draw(raster,in:rect)
            guard let flat = canvas.makeImage() else { throw PetError.message("Не удалось создать JPEG.") }
            raster = flat
        }
        let bytes = NSMutableData()
        let type: UTType = jpeg ? .jpeg : .png
        guard let dest = CGImageDestinationCreateWithData(bytes,type.identifier as CFString,1,nil) else {
            throw PetError.message("Не удалось создать файл.")
        }
        CGImageDestinationAddImage(dest,raster,[kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw PetError.message("Не удалось сохранить изображение.") }
        return bytes as Data
    }

    static func pdf(_ urls: [URL]) throws -> Data {
        let bytes = NSMutableData()
        guard let sink = CGDataConsumer(data:bytes), let context = CGContext(consumer:sink,mediaBox:nil,nil) else {
            throw PetError.message("Не удалось создать PDF.")
        }
        for url in urls {
            try autoreleasepool {
                let picture = try image(url)
                var box = CGRect(x:0,y:0,width:picture.width,height:picture.height)
                let info = Data(bytes:&box,count:MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox:info] as CFDictionary)
                context.draw(picture,in:box)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return bytes as Data
    }
}

final class FileActions {
    var report: (String) -> Void = { _ in }
    private var busy = false
    private enum Action: Int { case ocr, jpeg, resize, pdf }
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Выбрать"
        NSApp.activate(ignoringOtherApps:true)
        if panel.runModal() == .OK { handle(panel.urls) }
    }
    func handle(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard !busy else { report("Дождитесь обработки"); return }
        let inputs = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard inputs.allSatisfy({ $0.isFileURL && (try? $0.resourceValues(forKeys:[.contentTypeKey]).contentType?.conforms(to:.image)) == true }) else {
            alertError("Выберите изображения, например PNG, JPEG или HEIC.")
            return
        }
        NSApp.activate(ignoringOtherApps:true)
        let alert = NSAlert()
        alert.messageText = inputs.count == 1 ? inputs[0].lastPathComponent : "Собрать изображения в PDF?"
        let actions: [(String,Action)] = inputs.count > 1 ? [("Собрать в PDF",.pdf)] :
            [("Скопировать текст",.ocr),("Сохранить в JPEG",.jpeg),("Уменьшить изображение…",.resize),("Сохранить в PDF",.pdf)]
        let picker = NSPopUpButton(frame:NSRect(x:0,y:0,width:250,height:26))
        if inputs.count == 1 {
            picker.addItems(withTitles:actions.map { $0.0 })
            alert.accessoryView = picker
        } else {
            alert.informativeText = "По одной картинке на страницу, по имени файла: " + inputs.map { $0.lastPathComponent }.joined(separator:", ")
        }
        alert.addButton(withTitle:"Продолжить")
        alert.addButton(withTitle:"Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let action = inputs.count == 1 ? actions[picker.indexOfSelectedItem].1 : .pdf
        var side: Int?
        if action == .resize {
            let dialog = NSAlert()
            dialog.messageText = "Максимальная длина стороны"
            let lengths = [640,1280,1920,2560]
            let menu = NSPopUpButton(frame:NSRect(x:0,y:0,width:160,height:26))
            menu.addItems(withTitles:lengths.map { "\($0) пикселей" })
            menu.selectItem(at:1)
            dialog.accessoryView = menu
            dialog.addButton(withTitle:"Далее")
            dialog.addButton(withTitle:"Отмена")
            guard dialog.runModal() == .alertFirstButtonReturn else { return }
            side = lengths[menu.indexOfSelectedItem]
        }
        var target: URL?
        if action != .ocr {
            let type: UTType = action == .pdf ? .pdf : action == .jpeg ? .jpeg : .png
            let save = NSSavePanel()
            save.allowedContentTypes = [type]
            save.directoryURL = inputs[0].deletingLastPathComponent()
            let base = inputs[0].deletingPathExtension().lastPathComponent
            let name = action == .resize ? "\(base)-\(side!)" : inputs.count > 1 ? "Изображения" : "\(base)-копия"
            save.nameFieldStringValue = name + "." + (type.preferredFilenameExtension ?? "png")
            guard save.runModal() == .OK, let dest = save.url else { return }
            guard !inputs.contains(where:{ $0.resolvingSymlinksInPath().standardizedFileURL == dest.resolvingSymlinksInPath().standardizedFileURL }) else {
                alertError("Для результата выберите другое имя."); return
            }
            target = dest
        }
        busy = true
        let destination = target, maxSide = side
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                if action == .ocr {
                    let text = try ImageTools.recognize(inputs[0])
                    DispatchQueue.main.async {
                        NSPasteboard.general.clearContents()
                        let success = NSPasteboard.general.setString(text,forType:.string)
                        self.busy = false
                        self.report(success ? "Текст скопирован" : "Ошибка буфера обмена")
                    }
                } else if let dest = destination {
                    let data = try action == .pdf ? ImageTools.pdf(inputs) : ImageTools.encode(inputs[0],jpeg:action == .jpeg,maxSide:maxSide)
                    try data.write(to:dest,options:.atomic)
                    DispatchQueue.main.async { self.busy = false; self.report("Файл сохранён") }
                }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.alertError(error.localizedDescription) }
            }
        }
    }

    private func alertError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate(ignoringOtherApps:true)
        alert.runModal()
    }
}
