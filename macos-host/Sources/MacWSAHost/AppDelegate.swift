import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: Arguments
    private var window: NSWindow?
    private var connection: SocketConnection?

    init(arguments: Arguments) { self.arguments = arguments }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let connection = try SocketConnection(host: arguments.host, port: arguments.port)
            self.connection = connection
            connection.sendLine("HELLO \(arguments.packageName) \(arguments.width) \(arguments.height) \(arguments.density) \(arguments.bitrate)")
            let display = H264Display()
            let view = AndroidView(frame: NSRect(x: 0, y: 0, width: 432, height: 768),
                                   connection: connection, display: display,
                                   androidWidth: arguments.width, androidHeight: arguments.height,
                                   densityDpi: arguments.density)
            view.autoresizingMask = [.width, .height]
            let window = NSWindow(contentRect: view.frame,
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = arguments.packageName
            window.contentMinSize = NSSize(width: 216, height: 384)
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            self.window = window
            Task.detached { [weak self] in
                do {
                    let magic = try connection.readExactly(6)
                    guard magic == Data("MWSA1\n".utf8) else { throw SocketConnection.SocketError.closed }
                    while true {
                        let header = try connection.readExactly(14)
                        let kind = header[header.startIndex]
                        let flags = header[header.startIndex + 1]
                        let pts = header.uint64BE(at: 2)
                        let length = Int(header.uint32BE(at: 10))
                        guard length <= 16 * 1024 * 1024 else { throw SocketConnection.SocketError.closed }
                        let payload = try connection.readExactly(length)
                        await display.consume(payload: payload, ptsMicroseconds: pts,
                                              isKeyFrame: kind == 2 && (flags & 1) != 0)
                    }
                } catch {
                    await MainActor.run {
                        self?.window?.title = "\(self?.arguments.packageName ?? "MacWSA") — disconnected"
                    }
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText += "\nRun scripts/forward.sh first."
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { connection?.close() }
}

extension Data {
    func uint32BE(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
    }
    func uint64BE(at offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for byte in self[(startIndex + offset)..<(startIndex + offset + 8)] { result = (result << 8) | UInt64(byte) }
        return result
    }
}
