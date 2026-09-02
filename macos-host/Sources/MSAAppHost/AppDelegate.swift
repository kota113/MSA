import AppKit
import Foundation
import MSAHostCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    enum ManagerError: LocalizedError {
        case appMissing(String)
        case requestTimedOut
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .appMissing(let path): return "MSA Emulator.app was not found at \(path)"
            case .requestTimedOut: return "MSA Emulator did not become ready in time."
            case .unavailable(let message): return message
            }
        }
    }

    private let arguments: Arguments
    private let emulatorClientID = UUID().uuidString
    private var window: NSWindow?
    private var connection: SocketConnection?
    private var clipboardBridge: ClipboardBridge?
    private var androidView: AndroidView?
    private var managerResponses: [String: String] = [:]
    private var heartbeatTimer: Timer?
    private var isTransitioning = false

    init(arguments: Arguments) { self.arguments = arguments }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMainMenu()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleManagerResponse),
            name: EmulatorManagerIPC.response, object: nil
        )
        ensureEmulatorAndOpenWindow()
    }

    private func createMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? ProcessInfo.processInfo.processName
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let androidMenuItem = NSMenuItem()
        let androidMenu = NSMenu(title: "Android")
        addAndroidKeyMenuItem(to: androidMenu, title: "Back", keyCode: 4, keyEquivalent: "[")
        androidMenu.addItem(.separator())
        addAndroidKeyMenuItem(to: androidMenu, title: "Volume Up", keyCode: 24)
        addAndroidKeyMenuItem(to: androidMenu, title: "Volume Down", keyCode: 25)
        addAndroidKeyMenuItem(to: androidMenu, title: "Mute", keyCode: 164)
        androidMenuItem.submenu = androidMenu
        mainMenu.addItem(androidMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func addAndroidKeyMenuItem(to menu: NSMenu, title: String, keyCode: Int,
                                       keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: #selector(sendAndroidKeyFromMenu(_:)),
                              keyEquivalent: keyEquivalent)
        item.target = self
        item.representedObject = keyCode
        menu.addItem(item)
    }

    @objc private func sendAndroidKeyFromMenu(_ sender: NSMenuItem) {
        guard let keyCode = sender.representedObject as? Int else { return }
        connection?.sendLine("KEY 0 \(keyCode)")
        connection?.sendLine("KEY 1 \(keyCode)")
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
        clipboardBridge?.stop()
        clipboardBridge = nil
        connection?.close()
        connection = nil
        androidView = nil
        window = nil
        releaseEmulator()
    }
    func applicationWillTerminate(_ notification: Notification) {
        clipboardBridge?.stop()
        connection?.close()
        releaseEmulator()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func ensureEmulatorAndOpenWindow() {
        guard !isTransitioning else { return }
        isTransitioning = true
        Task {
            do {
                try launchEmulatorManager()
                try await acquireEmulator()
                try await openAndroidWindow()
                isTransitioning = false
            } catch {
                isTransitioning = false
                presentFatalError(error)
            }
        }
    }

    private func launchEmulatorManager() throws {
        let adjacentURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("MSA Emulator.app")
        let installedURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/MSA Emulator.app")
        let managerURL = [adjacentURL, installedURL].first {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard let managerURL else {
            throw ManagerError.appMissing(adjacentURL.path)
        }
        NSWorkspace.shared.openApplication(
            at: managerURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func acquireEmulator() async throws {
        let requestID = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        let userInfo = [
            EmulatorManagerIPC.serialKey: arguments.emulatorSerial,
            EmulatorManagerIPC.clientIDKey: emulatorClientID,
            EmulatorManagerIPC.packageNameKey: arguments.packageName,
            EmulatorManagerIPC.requestIDKey: requestID,
        ]
        for _ in 0..<250 {
            center.postNotificationName(EmulatorManagerIPC.acquire, object: nil,
                                        userInfo: userInfo, deliverImmediately: true)
            try await Task.sleep(for: .seconds(1))
            if let response = managerResponses.removeValue(forKey: requestID) {
                if !response.isEmpty { throw ManagerError.unavailable(response) }
                startHeartbeat()
                return
            }
        }
        throw ManagerError.requestTimedOut
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(timeInterval: 30, target: self,
                                              selector: #selector(sendHeartbeat),
                                              userInfo: nil, repeats: true)
    }

    @objc private func sendHeartbeat() {
        postClientNotification(EmulatorManagerIPC.heartbeat)
    }

    private func releaseEmulator() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        postClientNotification(EmulatorManagerIPC.release)
    }

    private func postClientNotification(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil,
            userInfo: [
                EmulatorManagerIPC.serialKey: arguments.emulatorSerial,
                EmulatorManagerIPC.clientIDKey: emulatorClientID,
            ],
            deliverImmediately: true
        )
    }

    @objc private func handleManagerResponse(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              userInfo[EmulatorManagerIPC.serialKey] as? String == arguments.emulatorSerial,
              let requestID = userInfo[EmulatorManagerIPC.requestIDKey] as? String else { return }
        managerResponses[requestID] = userInfo[EmulatorManagerIPC.errorKey] as? String ?? ""
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
        let clipboardBridge = ClipboardBridge(connection: connection)
        self.clipboardBridge = clipboardBridge
        clipboardBridge.start()
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
                    if kind == 1 || kind == 2 {
                        await display.consume(payload: payload, ptsMicroseconds: pts,
                                              isKeyFrame: kind == 2 && (flags & 1) != 0)
                    } else if kind == 3 {
                        await MainActor.run {
                            guard self?.connection === connection else { return }
                            self?.clipboardBridge?.receive(flags: flags, payload: payload)
                        }
                    }
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
