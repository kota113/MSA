import AppKit
import CoreLocation
import MSAHostCore

@MainActor
final class EmulatorManagerAppDelegate: NSObject, NSApplicationDelegate {
    private enum CameraPosition: Int {
        case front
        case back
    }
    private static let pauseDelay: TimeInterval = 30
    private static let stopDelay: TimeInterval = 5 * 60
    private static let clientLeaseDuration: TimeInterval = 90

    private let arguments: Arguments
    private var controller: EmulatorController?
    private var clients = EmulatorClientRegistry(leaseDuration: clientLeaseDuration)
    private var pendingRequests: [String: String] = [:]
    private var statusItem: NSStatusItem?
    private var statusTitleItem: NSMenuItem?
    private var startOrRestartItem: NSMenuItem?
    private var stopItem: NSMenuItem?
    private var increaseStorageItem: NSMenuItem?
    private var frontCameraMenu: NSMenu?
    private var backCameraMenu: NSMenu?
    private var microphoneMenu: NSMenu?
    private var cameraDevices: [EmulatorCamera] = []
    private var audioInputDevices: [EmulatorAudioInput] = []
    private var frontCamera = "emulated"
    private var backCamera = "emulated"
    private var audioInputUID: String?
    private var statusTimer: Timer?
    private var pauseTimer: Timer?
    private var stopTimer: Timer?
    private var idleStartedAt: Date?
    private var isTransitioning = false
    private var packageAutoInstaller: PackageAutoInstaller?
    private var clientPackages: [String: String] = [:]
    private var locationPermissionByPackage: [String: Bool] = [:]
    private var locationDemandRefreshTask: Task<Void, Never>?
    private var locationDemandGeneration = 0
    private var locationInjectionTask: Task<Void, Never>?
    private var pendingLocation: CLLocation?
    private var locationMenuItem: NSMenuItem?
    private var useMacLocation: Bool
    private var emulatorAcceptsLocation = false
    private lazy var locationBridge = EmulatorLocationBridge { [weak self] location in
        self?.enqueueLocation(location)
    }

    init(arguments: Arguments) {
        self.arguments = arguments
        let key = "location.useMacLocation.\(arguments.emulatorSerial)"
        let defaults = UserDefaults.standard
        useMacLocation = defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        do {
            loadMediaConfiguration()
            controller = try makeController()
            registerIPCObservers()
            createStatusItem()
            packageAutoInstaller = PackageAutoInstaller(arguments: arguments) { [weak self] packageName in
                guard let self, let controller = self.controller else { return }
                self.cancelIdleTimers()
                defer { self.scheduleIdleActionsIfNeeded() }
                try await Task.detached { try controller.uninstall(packageName: packageName) }.value
            }
            packageAutoInstaller?.start()
            startEmulator()
        } catch {
            presentError(error)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if controller?.isPaused() == true {
            resumeEmulator()
        } else if controller?.isRunning() == false {
            startEmulator()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        stopLocationUpdates()
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Stopping…", actionEnabled: false, running: true)
        do {
            try controller.stop()
            return .terminateNow
        } catch {
            isTransitioning = false
            let running = controller.isRunning()
            emulatorAcceptsLocation = running && !controller.isPaused()
            reconcileLocationUpdates()
            updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: running)
            presentError(error)
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        packageAutoInstaller?.stop()
        stopLocationUpdates()
        cancelIdleTimers()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func registerIPCObservers() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(acquireEmulator(_:)),
                           name: EmulatorManagerIPC.acquire, object: nil)
        center.addObserver(self, selector: #selector(receiveHeartbeat(_:)),
                           name: EmulatorManagerIPC.heartbeat, object: nil)
        center.addObserver(self, selector: #selector(releaseEmulator(_:)),
                           name: EmulatorManagerIPC.release, object: nil)
    }

    @objc private func acquireEmulator(_ notification: Notification) {
        guard let values = clientValues(from: notification),
              let packageName = notification.userInfo?[EmulatorManagerIPC.packageNameKey] as? String,
              PackageEventProtocol.isValidPackageName(packageName),
              let requestID = notification.userInfo?[EmulatorManagerIPC.requestIDKey] as? String else { return }
        clients.touch(values.clientID)
        clientPackages[values.clientID] = packageName
        pendingRequests[requestID] = values.clientID
        cancelIdleTimers()
        guard !isTransitioning else { return }
        if controller?.isPaused() == true {
            resumeEmulator()
        } else if controller?.isRunning() == true {
            emulatorAcceptsLocation = true
            refreshLocationDemand()
        } else {
            startEmulator()
        }
    }

    @objc private func receiveHeartbeat(_ notification: Notification) {
        guard let values = clientValues(from: notification), clients.contains(values.clientID) else { return }
        clients.touch(values.clientID)
    }

    @objc private func releaseEmulator(_ notification: Notification) {
        guard let values = clientValues(from: notification) else { return }
        clients.release(values.clientID)
        clientPackages.removeValue(forKey: values.clientID)
        pendingRequests = pendingRequests.filter { $0.value != values.clientID }
        reconcileLocationUpdates()
        scheduleIdleActionsIfNeeded()
    }

    private func clientValues(from notification: Notification) -> (clientID: String, serial: String)? {
        guard let userInfo = notification.userInfo,
              let serial = userInfo[EmulatorManagerIPC.serialKey] as? String,
              serial == arguments.emulatorSerial,
              let clientID = userInfo[EmulatorManagerIPC.clientIDKey] as? String else { return nil }
        return (clientID, serial)
    }

    private func respondToPendingRequests(error: Error? = nil) {
        let center = DistributedNotificationCenter.default()
        for requestID in pendingRequests.keys {
            var userInfo = [
                EmulatorManagerIPC.serialKey: arguments.emulatorSerial,
                EmulatorManagerIPC.requestIDKey: requestID,
            ]
            if let error { userInfo[EmulatorManagerIPC.errorKey] = error.localizedDescription }
            center.postNotificationName(EmulatorManagerIPC.response, object: nil,
                                        userInfo: userInfo, deliverImmediately: true)
        }
        pendingRequests.removeAll()
    }

    private func scheduleIdleActionsIfNeeded() {
        guard clients.isEmpty, !isTransitioning, controller?.isRunning() == true else { return }
        guard idleStartedAt == nil else { return }
        idleStartedAt = Date()
        pauseTimer = Timer.scheduledTimer(timeInterval: Self.pauseDelay, target: self,
                                          selector: #selector(pauseTimeoutElapsed),
                                          userInfo: nil, repeats: false)
        stopTimer = Timer.scheduledTimer(timeInterval: Self.stopDelay, target: self,
                                         selector: #selector(stopTimeoutElapsed),
                                         userInfo: nil, repeats: false)
    }

    private func cancelIdleTimers() {
        pauseTimer?.invalidate()
        stopTimer?.invalidate()
        pauseTimer = nil
        stopTimer = nil
        idleStartedAt = nil
    }

    @objc private func pauseTimeoutElapsed() {
        pauseTimer = nil
        pauseEmulator()
    }

    @objc private func stopTimeoutElapsed() {
        stopTimer = nil
        stopEmulator()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let bundledImage = Bundle.main.url(forResource: "MSAMenuBarIcon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
        if let image = bundledImage ?? NSImage(systemSymbolName: "iphone.and.arrow.forward",
                                               accessibilityDescription: "MSA Emulator") {
            image.isTemplate = true
            image.size = NSSize(width: 22, height: 13)
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
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

        let increaseStorage = NSMenuItem(title: "Increase Storage…",
                                         action: #selector(promptToIncreaseStorage),
                                         keyEquivalent: "")
        increaseStorage.target = self
        increaseStorage.isEnabled = false
        menu.addItem(increaseStorage)

        menu.addItem(.separator())
        let location = NSMenuItem(title: "Use Mac Location", action: #selector(toggleMacLocation),
                                  keyEquivalent: "")
        location.target = self
        location.state = useMacLocation ? .on : .off
        menu.addItem(location)

        menu.addItem(.separator())
        let frontCameraItem = NSMenuItem(title: "Front Camera", action: nil, keyEquivalent: "")
        let frontMenu = NSMenu(title: "Front Camera")
        frontCameraItem.submenu = frontMenu
        menu.addItem(frontCameraItem)

        let backCameraItem = NSMenuItem(title: "Back Camera", action: nil, keyEquivalent: "")
        let backMenu = NSMenu(title: "Back Camera")
        backCameraItem.submenu = backMenu
        menu.addItem(backCameraItem)

        let microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let microphoneSubmenu = NSMenu(title: "Microphone")
        microphoneItem.submenu = microphoneSubmenu
        menu.addItem(microphoneItem)

        let refreshDevices = NSMenuItem(title: "Refresh Media Devices", action: #selector(refreshMediaDevices),
                                        keyEquivalent: "")
        refreshDevices.target = self
        menu.addItem(refreshDevices)

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
        increaseStorageItem = increaseStorage
        locationMenuItem = location
        frontCameraMenu = frontMenu
        backCameraMenu = backMenu
        microphoneMenu = microphoneSubmenu
        rebuildMediaMenus()
        statusTimer = Timer.scheduledTimer(timeInterval: 3, target: self,
                                           selector: #selector(checkEmulatorState),
                                           userInfo: nil, repeats: true)
    }

    private func loadMediaConfiguration() {
        cameraDevices = EmulatorController.availableCameras(sdkRoot: arguments.sdkRoot)
        audioInputDevices = EmulatorAudioInput.availableDevices()
        let defaults = UserDefaults.standard
        frontCamera = validCameraMode(defaults.string(forKey: cameraDefaultsKey(.front)))
            ?? cameraDevices.first?.id ?? "emulated"
        backCamera = validCameraMode(defaults.string(forKey: cameraDefaultsKey(.back))) ?? "emulated"
        let savedAudioInputUID = defaults.string(forKey: audioInputDefaultsKey)
        audioInputUID = validAudioInputUID(savedAudioInputUID) ?? EmulatorAudioInput.defaultDeviceUID()
    }

    private func validCameraMode(_ mode: String?) -> String? {
        guard let mode else { return nil }
        return mode == "emulated" || mode == "none" || cameraDevices.contains { $0.id == mode }
            ? mode : nil
    }

    private func cameraDefaultsKey(_ position: CameraPosition) -> String {
        "camera.\(position == .front ? "front" : "back").\(arguments.emulatorSerial)"
    }

    private var audioInputDefaultsKey: String { "audio.input.\(arguments.emulatorSerial)" }

    private var locationDefaultsKey: String { "location.useMacLocation.\(arguments.emulatorSerial)" }

    @objc private func toggleMacLocation() {
        useMacLocation.toggle()
        UserDefaults.standard.set(useMacLocation, forKey: locationDefaultsKey)
        locationMenuItem?.state = useMacLocation ? .on : .off
        guard useMacLocation else {
            stopLocationUpdates()
            return
        }
        if emulatorAcceptsLocation { locationBridge.requestInitialLocation() }
        reconcileLocationUpdates()
    }

    private func validAudioInputUID(_ uid: String?) -> String? {
        guard let uid, audioInputDevices.contains(where: { $0.uid == uid }) else { return nil }
        return uid
    }

    private func makeController() throws -> EmulatorController {
        let configuration = try EmulatorConfiguration(
            sdkRoot: arguments.sdkRoot, serial: arguments.emulatorSerial,
            avdName: arguments.avdName, writableSystem: arguments.writableSystem,
            frontCamera: frontCamera, backCamera: backCamera, audioInputUID: audioInputUID
        )
        return EmulatorController(configuration: configuration)
    }

    private func rebuildCameraMenus() {
        populateCameraMenu(frontCameraMenu, position: .front, selectedMode: frontCamera)
        populateCameraMenu(backCameraMenu, position: .back, selectedMode: backCamera)
    }

    private func rebuildMediaMenus() {
        rebuildCameraMenus()
        guard let microphoneMenu else { return }
        microphoneMenu.removeAllItems()
        for device in audioInputDevices {
            let item = NSMenuItem(title: device.name, action: #selector(selectAudioInput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = device.uid == audioInputUID ? .on : .off
            microphoneMenu.addItem(item)
        }
        if audioInputDevices.isEmpty {
            let item = NSMenuItem(title: "No Input Devices", action: nil, keyEquivalent: "")
            item.isEnabled = false
            microphoneMenu.addItem(item)
        }
    }

    private func populateCameraMenu(_ menu: NSMenu?, position: CameraPosition, selectedMode: String) {
        guard let menu else { return }
        menu.removeAllItems()
        addCameraMenuItem(title: "Emulated", mode: "emulated", position: position,
                          selectedMode: selectedMode, to: menu)
        addCameraMenuItem(title: "Disabled", mode: "none", position: position,
                          selectedMode: selectedMode, to: menu)
        if !cameraDevices.isEmpty { menu.addItem(.separator()) }
        for camera in cameraDevices {
            addCameraMenuItem(title: camera.name, mode: camera.id, position: position,
                              selectedMode: selectedMode, to: menu)
        }
    }

    private func addCameraMenuItem(title: String, mode: String, position: CameraPosition,
                                   selectedMode: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selectCamera(_:)), keyEquivalent: "")
        item.target = self
        item.tag = position.rawValue
        item.representedObject = mode
        item.state = mode == selectedMode ? .on : .off
        menu.addItem(item)
    }

    @objc private func refreshMediaDevices() {
        guard !isTransitioning else { return }
        let previousAudioInputUID = audioInputUID
        cameraDevices = EmulatorController.availableCameras(sdkRoot: arguments.sdkRoot)
        audioInputDevices = EmulatorAudioInput.availableDevices()
        if validAudioInputUID(audioInputUID) == nil {
            audioInputUID = validAudioInputUID(EmulatorAudioInput.defaultDeviceUID())
            if let audioInputUID {
                UserDefaults.standard.set(audioInputUID, forKey: audioInputDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: audioInputDefaultsKey)
            }
        }
        rebuildMediaMenus()
        if audioInputUID != previousAudioInputUID { applyMediaConfiguration() }
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        guard !isTransitioning,
              let position = CameraPosition(rawValue: sender.tag),
              let mode = sender.representedObject as? String else { return }
        let previous = position == .front ? frontCamera : backCamera
        guard mode != previous else { return }
        if position == .front { frontCamera = mode } else { backCamera = mode }
        UserDefaults.standard.set(mode, forKey: cameraDefaultsKey(position))
        rebuildCameraMenus()
        applyMediaConfiguration()
    }

    @objc private func selectAudioInput(_ sender: NSMenuItem) {
        guard !isTransitioning, let uid = sender.representedObject as? String,
              uid != audioInputUID else { return }
        let alert = NSAlert()
        alert.messageText = "Change the Default Microphone?"
        alert.informativeText = "Selecting \(sender.title) will change the default microphone for all apps on this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Change Default Microphone")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        audioInputUID = uid
        UserDefaults.standard.set(uid, forKey: audioInputDefaultsKey)
        rebuildMediaMenus()
        applyMediaConfiguration()
    }

    private func applyMediaConfiguration() {
        guard let previousController = controller else { return }
        do {
            let replacement = try makeController()
            let wasRunning = previousController.isRunning() || previousController.isPaused()
            controller = replacement
            guard wasRunning else { return }
            cancelIdleTimers()
            suspendLocationForEmulator()
            isTransitioning = true
            updateMenu(status: "\(arguments.avdName) — Applying devices…",
                       actionEnabled: false, running: true)
            Task {
                do {
                    try await Task.detached {
                        try previousController.stop()
                        try replacement.ensureRunning()
                    }.value
                    emulatorAcceptsLocation = true
                    if useMacLocation { locationBridge.requestInitialLocation() }
                    refreshLocationDemand()
                    isTransitioning = false
                    updateMenu(status: "\(arguments.avdName) — Running", actionEnabled: true, running: true)
                    scheduleIdleActionsIfNeeded()
                } catch {
                    isTransitioning = false
                    let running = replacement.isRunning()
                    emulatorAcceptsLocation = running && !replacement.isPaused()
                    reconcileLocationUpdates()
                    updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true,
                               running: running)
                    respondToPendingRequests(error: error)
                    presentError(error)
                }
            }
        } catch {
            presentError(error)
        }
    }

    private func refreshLocationDemand() {
        guard emulatorAcceptsLocation, let controller else {
            reconcileLocationUpdates()
            return
        }
        guard locationDemandRefreshTask == nil else { return }
        let packages = Set(clientPackages.values)
        let generation = locationDemandGeneration
        locationDemandRefreshTask = Task { [weak self] in
            let permissions = await Task.detached { () -> [String: Bool] in
                var result: [String: Bool] = [:]
                for packageName in packages {
                    result[packageName] = (try? controller.packageDeclaresLocationPermission(packageName)) ?? false
                }
                return result
            }.value
            guard let self, generation == self.locationDemandGeneration else { return }
            for (packageName, hasPermission) in permissions {
                self.locationPermissionByPackage[packageName] = hasPermission
            }
            self.locationDemandRefreshTask = nil
            self.reconcileLocationUpdates()
            if Set(self.clientPackages.values) != packages {
                self.refreshLocationDemand()
            } else {
                self.respondToPendingRequests()
            }
        }
    }

    private func reconcileLocationUpdates() {
        let hasLocationSession = clientPackages.values.contains {
            locationPermissionByPackage[$0] == true
        }
        locationBridge.setContinuousUpdatesEnabled(
            useMacLocation && emulatorAcceptsLocation && hasLocationSession
        )
    }

    private func stopLocationUpdates() {
        pendingLocation = nil
        locationBridge.stop()
    }

    private func suspendLocationForEmulator() {
        emulatorAcceptsLocation = false
        locationDemandGeneration += 1
        locationDemandRefreshTask?.cancel()
        locationDemandRefreshTask = nil
        stopLocationUpdates()
    }

    private func enqueueLocation(_ location: CLLocation) {
        guard useMacLocation, emulatorAcceptsLocation, let controller else { return }
        pendingLocation = location
        guard locationInjectionTask == nil else { return }
        locationInjectionTask = Task { [weak self] in
            guard let self else { return }
            while let location = self.pendingLocation {
                self.pendingLocation = nil
                let coordinate = location.coordinate
                do {
                    try await Task.detached {
                        try controller.setLocation(
                            latitude: coordinate.latitude, longitude: coordinate.longitude,
                            altitude: location.altitude
                        )
                    }.value
                } catch {
                    NSLog("Failed to inject Mac location into Android Emulator: %@",
                          error.localizedDescription)
                }
            }
            self.locationInjectionTask = nil
        }
    }

    private func startEmulator() {
        guard !isTransitioning, let controller else { return }
        cancelIdleTimers()
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Starting…", actionEnabled: false, running: false)
        Task {
            do {
                try await Task.detached { try controller.ensureRunning() }.value
                emulatorAcceptsLocation = true
                if useMacLocation { locationBridge.requestInitialLocation() }
                refreshLocationDemand()
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Running", actionEnabled: true, running: true)
                scheduleIdleActionsIfNeeded()
            } catch {
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: false)
                respondToPendingRequests(error: error)
                presentError(error)
            }
        }
    }

    private func updateMenu(status: String, actionEnabled: Bool, running: Bool) {
        statusTitleItem?.title = status
        statusItem?.button?.toolTip = status
        startOrRestartItem?.title = running ? "Restart Emulator" : "Start Emulator"
        startOrRestartItem?.isEnabled = actionEnabled
        stopItem?.isEnabled = actionEnabled && running
        increaseStorageItem?.isEnabled = actionEnabled
    }

    @objc private func promptToIncreaseStorage() {
        guard !isTransitioning, let controller else { return }
        do {
            let bytesPerGiB: UInt64 = 1024 * 1024 * 1024
            let currentBytes = try controller.currentStorageSizeBytes()
            let currentGiB = Double(currentBytes) / Double(bytesPerGiB)
            let field = NSTextField(string: String(Int(currentGiB.rounded(.up)) + 1))
            field.placeholderString = "16"
            field.alignment = .right
            field.setAccessibilityLabel("New maximum storage size in GiB")

            let inputLabel = NSTextField(labelWithString: "New maximum:")
            let unitLabel = NSTextField(labelWithString: "GiB")
            let inputRow = NSStackView(views: [inputLabel, field, unitLabel])
            inputRow.spacing = 8
            inputRow.alignment = .centerY
            field.widthAnchor.constraint(equalToConstant: 120).isActive = true

            let currentLabel = NSTextField(labelWithString:
                String(format: "Current maximum: %.1f GiB", currentGiB))
            let allocationLabel = NSTextField(labelWithString:
                "This is a maximum capacity. Host disk space is allocated dynamically as Android uses it.")
            allocationLabel.textColor = .secondaryLabelColor
            allocationLabel.maximumNumberOfLines = 0
            allocationLabel.lineBreakMode = .byWordWrapping
            allocationLabel.preferredMaxLayoutWidth = 340

            let topSpacer = NSView()
            topSpacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
            let accessoryStack = NSStackView(views: [topSpacer, currentLabel, inputRow, allocationLabel])
            accessoryStack.orientation = .vertical
            accessoryStack.alignment = .leading
            accessoryStack.spacing = 8
            accessoryStack.setCustomSpacing(14, after: inputRow)
            accessoryStack.frame = NSRect(x: 0, y: 0, width: 340, height: 98)
            allocationLabel.widthAnchor.constraint(equalToConstant: 340).isActive = true

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Increase Android Storage"
            alert.accessoryView = accessoryStack
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let requestedGiB = UInt64(input), requestedGiB > 0 else {
                throw AVDStorageConfiguration.StorageError.invalidSize(input)
            }
            let (requestedBytes, overflow) = requestedGiB.multipliedReportingOverflow(by: bytesPerGiB)
            guard !overflow else { throw AVDStorageConfiguration.StorageError.invalidSize(input) }
            guard requestedBytes > currentBytes else {
                throw AVDStorageConfiguration.StorageError.notAnIncrease(
                    current: currentBytes, requested: requestedBytes
                )
            }

            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = "Confirm Storage Increase"
            confirmation.informativeText = String(
                format: "Increase the maximum capacity to %llu GiB?\n\nThis change cannot be undone. The emulator will restart with a cold boot.",
                requestedGiB
            )
            confirmation.addButton(withTitle: "Increase and Restart")
            confirmation.addButton(withTitle: "Cancel")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }

            increaseStorage(to: requestedBytes)
        } catch {
            presentError(error)
        }
    }

    private func increaseStorage(to requestedBytes: UInt64) {
        guard !isTransitioning, let controller else { return }
        cancelIdleTimers()
        suspendLocationForEmulator()
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Increasing storage…",
                   actionEnabled: false, running: true)
        Task {
            do {
                try await Task.detached { try controller.increaseStorage(to: requestedBytes) }.value
                emulatorAcceptsLocation = true
                if useMacLocation { locationBridge.requestInitialLocation() }
                refreshLocationDemand()
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Running", actionEnabled: true, running: true)
                scheduleIdleActionsIfNeeded()
            } catch {
                isTransitioning = false
                let running = controller.isRunning()
                emulatorAcceptsLocation = running && !controller.isPaused()
                reconcileLocationUpdates()
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: running)
                respondToPendingRequests(error: error)
                presentError(error)
            }
        }
    }

    private func pauseEmulator() {
        guard !isTransitioning, clients.isEmpty, let controller else { return }
        suspendLocationForEmulator()
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Pausing…", actionEnabled: false, running: true)
        Task {
            do {
                try await Task.detached { try controller.pause() }.value
                isTransitioning = false
                if clients.isEmpty {
                    updateIdleMenu(paused: true)
                } else {
                    resumeEmulator()
                }
            } catch {
                emulatorAcceptsLocation = true
                reconcileLocationUpdates()
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: true)
                presentError(error)
            }
        }
    }

    private func resumeEmulator() {
        guard !isTransitioning, let controller else { return }
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Resuming…", actionEnabled: false, running: true)
        Task {
            do {
                try await Task.detached { try controller.resume() }.value
                emulatorAcceptsLocation = true
                refreshLocationDemand()
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Running", actionEnabled: true, running: true)
                scheduleIdleActionsIfNeeded()
            } catch {
                let running = controller.isRunning()
                emulatorAcceptsLocation = running && !controller.isPaused()
                reconcileLocationUpdates()
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true,
                           running: running)
                respondToPendingRequests(error: error)
                presentError(error)
            }
        }
    }

    private func updateIdleMenu(paused: Bool) {
        guard let idleStartedAt else {
            updateMenu(status: "\(arguments.avdName) — \(paused ? "Paused" : "Running")",
                       actionEnabled: true, running: true)
            return
        }
        let elapsed = Date().timeIntervalSince(idleStartedAt)
        if paused {
            let seconds = max(0, Int((Self.stopDelay - elapsed).rounded(.up)))
            updateMenu(status: "\(arguments.avdName) — Paused; snapshot shutdown in \(seconds / 60)m \(seconds % 60)s",
                       actionEnabled: true, running: true)
        } else {
            let seconds = max(0, Int((Self.pauseDelay - elapsed).rounded(.up)))
            updateMenu(status: "\(arguments.avdName) — Idle; pausing in \(seconds)s",
                       actionEnabled: true, running: true)
        }
    }

    @objc private func startOrRestartEmulator() {
        guard !isTransitioning, let controller else { return }
        if !controller.isRunning() {
            startEmulator()
            return
        }
        cancelIdleTimers()
        suspendLocationForEmulator()
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Restarting…", actionEnabled: false, running: true)
        Task {
            do {
                try await Task.detached { try controller.restart() }.value
                emulatorAcceptsLocation = true
                if useMacLocation { locationBridge.requestInitialLocation() }
                refreshLocationDemand()
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Running", actionEnabled: true, running: true)
                scheduleIdleActionsIfNeeded()
            } catch {
                isTransitioning = false
                let running = controller.isRunning()
                emulatorAcceptsLocation = running && !controller.isPaused()
                reconcileLocationUpdates()
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: running)
                respondToPendingRequests(error: error)
                presentError(error)
            }
        }
    }

    @objc private func stopEmulator() {
        guard !isTransitioning, let controller else { return }
        cancelIdleTimers()
        suspendLocationForEmulator()
        isTransitioning = true
        updateMenu(status: "\(arguments.avdName) — Saving snapshot and stopping…",
                   actionEnabled: false, running: true)
        Task {
            do {
                try await Task.detached { try controller.stop() }.value
                isTransitioning = false
                updateMenu(status: "\(arguments.avdName) — Stopped", actionEnabled: true, running: false)
                if !pendingRequests.isEmpty { startEmulator() }
            } catch {
                isTransitioning = false
                let running = controller.isRunning()
                emulatorAcceptsLocation = running && !controller.isPaused()
                reconcileLocationUpdates()
                updateMenu(status: "\(arguments.avdName) — Error", actionEnabled: true, running: running)
                presentError(error)
            }
        }
    }

    @objc private func checkEmulatorState() {
        guard !isTransitioning, let controller else { return }
        let hadClients = !clients.isEmpty
        let expiredClientIDs = clients.removeExpired()
        for clientID in expiredClientIDs { clientPackages.removeValue(forKey: clientID) }
        if !expiredClientIDs.isEmpty { reconcileLocationUpdates() }
        if hadClients && clients.isEmpty { scheduleIdleActionsIfNeeded() }
        Task {
            let state = await Task.detached { (controller.isRunning(), controller.isPaused()) }.value
            if !state.0 || state.1 { suspendLocationForEmulator() }
            if state.1 {
                updateIdleMenu(paused: true)
            } else if state.0, clients.isEmpty, idleStartedAt != nil {
                updateIdleMenu(paused: false)
            } else {
                updateMenu(status: "\(arguments.avdName) — \(state.0 ? "Running" : "Stopped")",
                           actionEnabled: true, running: state.0)
            }
        }
    }

    private func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}