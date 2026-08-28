import AppKit
import Foundation

struct AppBundleRequest: Sendable {
    let packageName: String
    let displayName: String
    let emulatorSerial: String
    let avdName: String
    let sdkRoot: String
    let writableSystem: Bool
    let iconData: Data?
}

struct AppBundleBuilder: @unchecked Sendable {
    enum BuildError: LocalizedError {
        case invalidPackageName(String)
        case signingFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidPackageName(let packageName):
                return "Invalid Android package name: \(packageName)"
            case .signingFailed(let output):
                return "Could not sign the generated app: \(output)"
            }
        }
    }

    let hostExecutableURL: URL
    let outputDirectoryURL: URL
    var signer: @Sendable (URL) throws -> Void = Self.adHocSign

    func build(_ request: AppBundleRequest) throws -> URL {
        guard PackageEventProtocol.isValidPackageName(request.packageName) else {
            throw BuildError.invalidPackageName(request.packageName)
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        let fileName = request.displayName.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let targetURL = outputDirectoryURL.appendingPathComponent("\(fileName).app", isDirectory: true)
        let stagedURL = outputDirectoryURL.appendingPathComponent(".msa-\(UUID().uuidString).app",
                                                                   isDirectory: true)
        defer { try? fileManager.removeItem(at: stagedURL) }

        let contentsURL = stagedURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: hostExecutableURL,
                                 to: macOSURL.appendingPathComponent("MSAAppHost"))

        var info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": request.displayName,
            "CFBundleExecutable": "MSAAppHost",
            "CFBundleIdentifier": "dev.msa.android.\(request.packageName.replacingOccurrences(of: "_", with: "-"))",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": request.displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1",
            "CFBundleVersion": Self.bundleVersion(),
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
            "MSAPackageName": request.packageName,
            "MSADisplayName": request.displayName,
            "MSAEmulatorSerial": request.emulatorSerial,
            "MSAAVDName": request.avdName,
            "MSAAndroidSDKRoot": request.sdkRoot,
            "MSAWritableSystem": request.writableSystem,
        ]
        if let iconData = request.iconData, NSImage(data: iconData) != nil {
            try iconData.write(to: resourcesURL.appendingPathComponent("AppIcon.png"), options: .atomic)
            info["CFBundleIconFile"] = "AppIcon.png"
        } else {
            let genericIcon = URL(fileURLWithPath:
                "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
            if fileManager.fileExists(atPath: genericIcon.path) {
                try fileManager.copyItem(at: genericIcon,
                                         to: resourcesURL.appendingPathComponent("AppIcon.icns"))
                info["CFBundleIconFile"] = "AppIcon"
            }
        }
        let plistData = try PropertyListSerialization.data(fromPropertyList: info,
                                                           format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)
        try signer(stagedURL)

        let targetPath = targetURL.standardizedFileURL.path
        let previousMatches = try existingApps(for: request.packageName).filter {
            $0.standardizedFileURL.path != targetPath
        }
        let backupURL = outputDirectoryURL.appendingPathComponent(".msa-backup-\(UUID().uuidString).app")
        var movedTarget = false
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.moveItem(at: targetURL, to: backupURL)
            movedTarget = true
        }
        do {
            try fileManager.moveItem(at: stagedURL, to: targetURL)
            if movedTarget { try? fileManager.removeItem(at: backupURL) }
            for oldURL in previousMatches { try? fileManager.removeItem(at: oldURL) }
        } catch {
            if movedTarget { try? fileManager.moveItem(at: backupURL, to: targetURL) }
            throw error
        }
        return targetURL
    }

    private func existingApps(for packageName: String) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: outputDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return urls.filter { url in
            guard url.pathExtension == "app",
                  let bundle = Bundle(url: url) else { return false }
            return bundle.object(forInfoDictionaryKey: "MSAPackageName") as? String == packageName
        }
    }

    private static func bundleVersion() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }

    private static func adHocSign(_ appURL: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BuildError.signingFailed(String(decoding: output, as: UTF8.self))
        }
    }
}