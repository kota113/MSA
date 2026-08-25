import AppKit

@MainActor
final class EmulatorManagerAppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: Arguments
    private var controller: EmulatorController?
    private var statusItem: NSStatusItem?
    private var statusTitleItem: NSMenuItem?
    private var startOrRestartItem: NSMenuItem?
    private var stopItem: NSMenuItem?
    private var statusTimer: Timer?
    private var isTransitioning = false

    init(arguments: Arguments) { self.arguments = arguments }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        do {
            controller = EmulatorController(configuration: try EmulatorConfiguration(arguments: arguments))
            createStatusItem()
            startEmulator()
        } catch {
            presentError(error)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if controller?.isRunning() == false { startEmulator() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Stopping…", actionEnabled: false, running: true)
        do {
            try controller.stop()
            return .terminateNow
        } catch {
            isTransitioning = false
            updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true,
                       running: controller.isRunning())
            presentError(error)
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "iphone.and.arrow.forward",
                               accessibilityDescription: "MSA Emulator") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "A"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "\(arguments.avdName) — Starting…", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let startOrRestart = NSMenuItem(title: "Restart Emulator", action: #selector(startOrRestartEmulator),
                                        keyEquivalent: "r")
        startOrRestart.target = self
        startOrRestart.isEnabled = false
        menu.addItem(startOrRestart)

        let stop = NSMenuItem(title: "Stop Emulator", action: #selector(stopEmulator), keyEquivalent: "s")
        stop.target = self
        stop.isEnabled = false
        menu.addItem(stop)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MSA Emulator", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        statusTitleItem = title
        startOrRestartItem = startOrRestart
        stopItem = stop
        statusTimer = Timer.scheduledTimer(timeInterval: 3, target: self,
                                           selector: #selector(checkEmulatorState),
                                           userInfo: nil, repeats: true)
    }

    private func startEmulator() {
        guard !isTransitioning, let controller else { return }
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Starting…", actionEnabled: false, running: false)
        Task {
            do {
                try await Task.detached { try controller.ensureRunning() }.value
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Running", actionEnabled: true, running: true)
            } catch {
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: false)
                presentError(error)
            }
        }
    }

    private func updateMenu(status: String, actionEnabled: Bool, running: Bool) {
        statusTitleItem?.title = status
        startOrRestartItem?.title = running ? "Restart Emulator" : "Start Emulator"
        startOrRestartItem?.isEnabled = actionEnabled
        stopItem?.isEnabled = actionEnabled && running
    }

    @objc private func startOrRestartEmulator() {
        guard !isTransitioning, let controller else { return }
        if !controller.isRunning() {
            startEmulator()
            return
        }
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Restarting…", actionEnabled: false, running: true)
        Task {
            do {
                try await Task.detached { try controller.restart() }.value
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Running", actionEnabled: true, running: true)
            } catch {
                isTransitioning = false
                let running = controller.isRunning()
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: running)
                presentError(error)
            }
        }
    }

    @objc private func stopEmulator() {
        guard !isTransitioning, let controller else { return }
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Stopping…", actionEnabled: false, running: true)
        Task {
            do {
                try await Task.detached { try controller.stop() }.value
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Stopped", actionEnabled: true, running: false)
            } catch {
                isTransitioning = false
                let running = controller.isRunning()
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: running)
                presentError(error)
            }
        }
    }

    @objc private func checkEmulatorState() {
        guard !isTransitioning, let controller else { return }
        Task {
            let running = await Task.detached { controller.isRunning() }.value
            updateMenu(status: "\(arguments.avdName) — \(running ? "Running" : "Stopped")",
                       actionEnabled: true, running: running)
        }
    }

    private func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}