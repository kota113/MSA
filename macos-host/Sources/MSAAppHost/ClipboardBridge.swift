import AppKit
import Foundation

enum ClipboardContent: Equatable, Sendable {
    case clear
    case text(Data)
    case image(mimeType: String, data: Data)
}

enum ClipboardWire {
    static let maximumBytes = 8 * 1024 * 1024

    static func command(for content: ClipboardContent) -> String? {
        switch content {
        case .clear:
            return "CLIPBOARD CLEAR"
        case .text(let data):
            guard data.count <= maximumBytes else { return nil }
            return "CLIPBOARD text/plain \(data.base64EncodedString())"
        case .image(let mimeType, let data):
            guard mimeType.hasPrefix("image/"), data.count <= maximumBytes else { return nil }
            return "CLIPBOARD \(mimeType) \(data.base64EncodedString())"
        }
    }

    static func decode(_ payload: Data) -> ClipboardContent? {
        guard payload.count <= maximumBytes + 128,
              let separator = payload.firstIndex(of: 0x0a),
              let mimeType = String(data: payload[..<separator], encoding: .utf8) else { return nil }
        let data = Data(payload[payload.index(after: separator)...])
        guard data.count <= maximumBytes else { return nil }
        if mimeType == "text/plain" { return .text(data) }
        if mimeType.hasPrefix("image/") { return .image(mimeType: mimeType, data: data) }
        return nil
    }
}

@MainActor
final class ClipboardBridge {
    private let connection: SocketConnection
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastSentContent: ClipboardContent?

    init(connection: SocketConnection, pasteboard: NSPasteboard = .general) {
        self.connection = connection
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        sendCurrentClipboard()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForChanges() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func receive(flags: UInt8, payload: Data) {
        let content: ClipboardContent
        if flags == 0 {
            content = .clear
        } else {
            guard let decoded = ClipboardWire.decode(payload) else { return }
            content = decoded
        }
        guard content != lastSentContent else { return }
        switch content {
        case .clear:
            pasteboard.clearContents()
        case .text(let data):
            guard let text = String(data: data, encoding: .utf8) else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .image(_, let data):
            guard let png = pngData(from: data) else { return }
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
        }
        lastChangeCount = pasteboard.changeCount
        lastSentContent = content
    }

    private func checkForChanges() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        sendCurrentClipboard()
    }

    private func sendCurrentClipboard() {
        guard let content = readPasteboard(), content != lastSentContent,
              let command = ClipboardWire.command(for: content) else { return }
        connection.sendLine(command)
        lastSentContent = content
    }

    private func readPasteboard() -> ClipboardContent? {
        if let png = pasteboard.data(forType: .png), png.count <= ClipboardWire.maximumBytes {
            return .image(mimeType: "image/png", data: png)
        }
        if let tiff = pasteboard.data(forType: .tiff), let png = pngData(from: tiff),
           png.count <= ClipboardWire.maximumBytes {
            return .image(mimeType: "image/png", data: png)
        }
        if let string = pasteboard.string(forType: .string), let data = string.data(using: .utf8),
           data.count <= ClipboardWire.maximumBytes {
            return .text(data)
        }
        return pasteboard.types?.isEmpty != false ? .clear : nil
    }

    private func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }
}