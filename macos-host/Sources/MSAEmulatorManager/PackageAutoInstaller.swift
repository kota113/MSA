import AppKit
import Foundation
import MSAHostCore

@MainActor
final class PackageAutoInstaller {
    private let client = PackageEventClient()
    private let provider: AndroidAppMetadataProvider
    private let builder: AppBundleBuilder
    private let scanner: ManagedAppScanner
    private let registry: ManagedAppRegistry
    private let arguments: Arguments
    private let uninstall: @MainActor (String) async throws -> Void
    private var timer: Timer?
    private var isPolling = false
    private var pendingRemovalPrompts: Set<String> = []

    init?(arguments: Arguments, uninstall: @escaping @MainActor (String) async throws -> Void) {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let hostExecutableURL = resourcesURL.appendingPathComponent("MSAAppHost")
        guard FileManager.default.isExecutableFile(atPath: hostExecutableURL.path) else { return nil }
        let outputDirectoryURL = Bundle.main.bundleURL.deletingLastPathComponent()
        self.arguments = arguments
        self.uninstall = uninstall
        provider = AndroidAppMetadataProvider(sdkRoot: arguments.sdkRoot,
                                              serial: arguments.emulatorSerial)
        builder = AppBundleBuilder(hostExecutableURL: hostExecutableURL,
                                   outputDirectoryURL: outputDirectoryURL)
        scanner = ManagedAppScanner(directoryURL: outputDirectoryURL)
        registry = ManagedAppRegistry(key: "managedApps.\(arguments.emulatorSerial)")
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        Task {
            defer { isPolling = false }
            await pollInstallations()
            checkRemovedApps()
        }
    }

    private func pollInstallations() async {
        do {
            let packages = try await client.listPending()
            for packageName in packages {
                let provider = provider
                let builder = builder
                let arguments = arguments
                let appURL = try await Task.detached {
                    let request = try provider.request(for: packageName, arguments: arguments)
                    return try builder.build(request)
                }.value
                let displayName = Bundle(url: appURL)?
                    .object(forInfoDictionaryKey: "MSADisplayName") as? String ?? packageName
                registry.record(ManagedApp(packageName: packageName, displayName: displayName,
                                           path: appURL.path))
                try await client.acknowledge(packageName)
                NSLog("Generated app for %@ at %@", packageName, appURL.path)
            }
        } catch {
            // The management port is normally unavailable while the emulator is stopped or booting.
            if !(error is CancellationError) {
                NSLog("Package auto-generation is waiting: %@", error.localizedDescription)
            }
        }
    }

    private func checkRemovedApps() {
        do {
            let removedApps = registry.reconcile(discovered: try scanner.scan())
            for app in removedApps where !pendingRemovalPrompts.contains(app.packageName) {
                pendingRemovalPrompts.insert(app.packageName)
                Task { await confirmRemoval(of: app) }
            }
        } catch {
            NSLog("Could not inspect generated apps: %@", error.localizedDescription)
        }
    }

    private func confirmRemoval(of app: ManagedApp) async {
        defer { pendingRemovalPrompts.remove(app.packageName) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall \(app.displayName) from Android?"
        alert.informativeText = "The generated Mac app was removed. Uninstalling will also delete its Android app and data."
        alert.addButton(withTitle: "Uninstall from Android")
        alert.addButton(withTitle: "Keep Android App")
        guard alert.runModal() == .alertFirstButtonReturn else {
            registry.remove(packageName: app.packageName)
            return
        }
        do {
            try await uninstall(app.packageName)
            registry.remove(packageName: app.packageName)
            NSLog("Uninstalled Android package %@ after its Mac app was removed", app.packageName)
        } catch {
            registry.postpone(packageName: app.packageName)
            NSAlert(error: error).runModal()
        }
    }
}