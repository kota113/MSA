import Foundation

struct ManagedApp: Codable, Equatable, Sendable {
    let packageName: String
    let displayName: String
    let path: String
}

final class ManagedAppRegistry {
    private struct Record: Codable {
        var app: ManagedApp
        var missingSince: Date?
    }

    private let defaults: UserDefaults
    private let key: String
    private let graceInterval: TimeInterval
    private var records: [String: Record]

    init(defaults: UserDefaults = .standard, key: String = "managedApps",
         graceInterval: TimeInterval = 6) {
        self.defaults = defaults
        self.key = key
        self.graceInterval = graceInterval
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func reconcile(discovered: [ManagedApp], now: Date = Date()) -> [ManagedApp] {
        let discoveredByPackage = Dictionary(discovered.map { ($0.packageName, $0) },
                                             uniquingKeysWith: { _, latest in latest })
        for app in discovered {
            records[app.packageName] = Record(app: app, missingSince: nil)
        }
        var removed: [ManagedApp] = []
        for packageName in records.keys.sorted() where discoveredByPackage[packageName] == nil {
            guard var record = records[packageName] else { continue }
            if let missingSince = record.missingSince {
                if now.timeIntervalSince(missingSince) >= graceInterval { removed.append(record.app) }
            } else {
                record.missingSince = now
                records[packageName] = record
            }
        }
        save()
        return removed
    }

    func record(_ app: ManagedApp) {
        records[app.packageName] = Record(app: app, missingSince: nil)
        save()
    }

    func postpone(packageName: String, now: Date = Date()) {
        guard var record = records[packageName] else { return }
        record.missingSince = now
        records[packageName] = record
        save()
    }

    func remove(packageName: String) {
        records.removeValue(forKey: packageName)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}

struct ManagedAppScanner {
    let directoryURL: URL

    func scan() throws -> [ManagedApp] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            guard url.pathExtension == "app", let bundle = Bundle(url: url),
                  let packageName = bundle.object(forInfoDictionaryKey: "MSAPackageName") as? String,
                  PackageEventProtocol.isValidPackageName(packageName) else { return nil }
            let displayName = (bundle.object(forInfoDictionaryKey: "MSADisplayName")
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")) as? String
                ?? url.deletingPathExtension().lastPathComponent
            return ManagedApp(packageName: packageName, displayName: displayName, path: url.path)
        }
    }
}