import AppKit
import Foundation
import MSAHostCore

struct AndroidAppMetadataProvider: @unchecked Sendable {
    enum MetadataError: LocalizedError {
        case executableMissing(String)
        case commandFailed(String, String)
        case packageNotInstalled(String)

        var errorDescription: String? {
            switch self {
            case .executableMissing(let path): return "Required executable was not found: \(path)"
            case .commandFailed(let command, let output): return "\(command) failed: \(output)"
            case .packageNotInstalled(let packageName): return "\(packageName) is not installed"
            }
        }
    }

    let sdkRoot: String
    let serial: String

    func request(for packageName: String, arguments: Arguments) throws -> AppBundleRequest {
        let adbURL = URL(fileURLWithPath: sdkRoot).appendingPathComponent("platform-tools/adb")
        guard FileManager.default.isExecutableFile(atPath: adbURL.path) else {
            throw MetadataError.executableMissing(adbURL.path)
        }
        let packagePathResult = try run(adbURL, ["-s", serial, "shell", "pm", "path", packageName])
        guard packagePathResult.status == 0,
              let packagePath = String(decoding: packagePathResult.output, as: UTF8.self)
                .split(whereSeparator: \.isNewline).first.map(String.init),
              packagePath.hasPrefix("package:") else {
            throw MetadataError.packageNotInstalled(packageName)
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("msa-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let apkURL = temporaryURL.appendingPathComponent("base.apk")
        let pull = try run(adbURL, ["-s", serial, "pull",
                                    String(packagePath.dropFirst("package:".count)), apkURL.path])
        guard pull.status == 0 else {
            throw MetadataError.commandFailed("adb pull", String(decoding: pull.output, as: UTF8.self))
        }
        let aaptURL = try latestAAPT2URL()
        let badging = try run(aaptURL, ["dump", "badging", apkURL.path])
        guard badging.status == 0 else {
            throw MetadataError.commandFailed("aapt2 dump badging",
                                              String(decoding: badging.output, as: UTF8.self))
        }
        let displayName = parseDisplayName(String(decoding: badging.output, as: UTF8.self)) ?? packageName
        let icon = try? run(adbURL, ["-s", serial, "exec-out", "content", "read", "--uri",
                                     "content://dev.msa.agent.icons/icon/\(packageName)"])
        let iconData = icon.flatMap { $0.status == 0 && NSImage(data: $0.output) != nil ? $0.output : nil }
        return AppBundleRequest(packageName: packageName, displayName: displayName,
                                emulatorSerial: serial, avdName: arguments.avdName,
                                sdkRoot: sdkRoot, writableSystem: arguments.writableSystem,
                                iconData: iconData)
    }

    private func latestAAPT2URL() throws -> URL {
        let buildToolsURL = URL(fileURLWithPath: sdkRoot).appendingPathComponent("build-tools")
        let versions = try FileManager.default.contentsOfDirectory(at: buildToolsURL,
                                                                   includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
        guard let result = versions.map({ $0.appendingPathComponent("aapt2") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw MetadataError.executableMissing("\(buildToolsURL.path)/*/aapt2")
        }
        return result
    }

    private func parseDisplayName(_ badging: String) -> String? {
        let prefix = "application-label:'"
        guard let line = badging.split(whereSeparator: \.isNewline)
            .map(String.init).first(where: { $0.hasPrefix(prefix) && $0.hasSuffix("'") }) else { return nil }
        return String(line.dropFirst(prefix.count).dropLast())
    }

    private func run(_ executableURL: URL, _ arguments: [String]) throws
        -> (status: Int32, output: Data) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}