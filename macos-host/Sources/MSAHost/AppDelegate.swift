import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let arguments: Arguments
    private var window: NSWindow?
    private var connection: SocketConnection?
    private var androidView: AndroidView?
    private var emulatorController: EmulatorController?
    private var isTransitioning = false

    init(arguments: Arguments) { self.arguments = arguments }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            emulatorController = EmulatorController(configuration: try EmulatorConfiguration(arguments: arguments))
            ensureEmulatorAndOpenWindow()
        } catch {
            presentFatalError(error)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window {
            sender.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        } else {
            ensureEmulatorAndOpenWindow()
        }
        return true
    }
    func windowDidResignKey(_ notification: Notification) { androidView?.releaseModifierKeys() }
    func windowWillClose(_ notification: Notification) {
        connection?.close()
        connection = nil
        androidView = nil
        window = nil
    }
    func applicationWillTerminate(_ notification: Notification) {
        connection?.close()
    }

    private func ensureEmulatorAndOpenWindow() {
        guard !isTransitioning, let emulatorController else { return }
        isTransitioning = true
        Task {
            do {
                try await Task.detached { try emulatorController.ensureRunning() }.value
                launchEmulatorManager()
                try await openAndroidWindow()
                isTransitioning = false
            } catch {
                isTransitioning = false
                presentFatalError(error)
            }
        }
    }

    private func launchEmulatorManager() {
        let managerURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("MSA Emulator.app")
        guard FileManager.default.fileExists(atPath: managerURL.path) else { return }
        NSWorkspace.shared.openApplication(
            at: managerURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func openAndroidWindow() async throws {
        let arguments = self.arguments
        let connection = try await Task.detached {
            var lastError: Error = SocketConnection.SocketError.connect
            for _ in 0..<30 {
                do { return try SocketConnection(host: arguments.host, port: arguments.port) }
                catch {
                    lastError = error
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            throw lastError
        }.value
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
        window.title = arguments.windowTitle
        window.contentMinSize = NSSize(width: 216, height: 384)
        window.contentView = view
        window.delegate = self
        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
        androidView = view
        readVideo(from: connection, into: display)
    }

    private func readVideo(from connection: SocketConnection, into display: H264Display) {
        Task.detached { [weak self] in
            do {
                let magic = try connection.readExactly(6)
                guard magic == Data("MSA01\n".utf8) else { throw SocketConnection.SocketError.closed }
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
                    guard self?.connection === connection else { return }
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }

    private func presentFatalError(_ error: Error) {
        presentError(error)
        NSApplication.shared.terminate(nil)
    }
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
