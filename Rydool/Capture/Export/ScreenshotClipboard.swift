import AppKit

enum PasteboardWriteFailure: LocalizedError {
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            L("Rydool couldn't prepare the image. Please try again.")
        case .writeFailed:
            L("Rydool couldn't copy the screenshot to the clipboard. Please try again.")
        }
    }
}

/// Writes a screenshot to a pasteboard and reports the write to history.
enum ScreenshotClipboard {
    // AppKit can request TIFF after the initial write, so retain the provider.
    private static var currentProvider: ScreenshotRepresentations?

    @MainActor
    static func copy(_ screenshot: RenderedScreenshot, source: String?) throws {
        let history = ClipboardHistory.shared
        try copy(screenshot, to: history.pasteboard) { png, count in
            history.recordScreenshot(png, source: source, ownershipCount: count)
        }
    }

    @MainActor
    static func copy(_ screenshot: RenderedScreenshot, to pasteboard: NSPasteboard,
                     onWritten: (Data, Int) -> Void) throws {
        guard let png = screenshot.pngData() else { throw PasteboardWriteFailure.encodingFailed }
        let image = ScreenshotRepresentations(image: screenshot.image, logicalSize: screenshot.pointSize)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setDataProvider(image, forTypes: [.tiff])
        let count = pasteboard.clearContents()
        currentProvider = image
        guard pasteboard.writeObjects([item]) else { throw PasteboardWriteFailure.writeFailed }
        onWritten(png, count)
    }
}

/// Provides the compatibility representation only if another app asks for it.
private final class ScreenshotRepresentations: NSObject, NSPasteboardItemDataProvider {
    private let image: CGImage
    private let logicalSize: CGSize

    init(image: CGImage, logicalSize: CGSize) {
        self.image = image
        self.logicalSize = logicalSize
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff else { return }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = logicalSize
        guard let data = bitmap.tiffRepresentation(using: .lzw, factor: 0) else { return }
        item.setData(data, forType: type)
    }
}
