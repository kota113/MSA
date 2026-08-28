import Foundation
import MSAHostCore

enum AndroidManifestPermissions {
    private static let locationPermissions = [
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
    ]

    static func hasLocationPermission(in packageDump: String) -> Bool {
        var isReadingRequestedPermissions = false
        for rawLine in packageDump.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "requested permissions:" {
                isReadingRequestedPermissions = true
                continue
            }
            guard isReadingRequestedPermissions else { continue }
            if line.hasSuffix(":") { return false }
            if locationPermissions.contains(line) { return true }
        }
        return false
    }
}

enum EmulatorLocationCommand {
    enum LocationError: LocalizedError {
        case invalidCoordinate

        var errorDescription: String? { "Core Location returned an invalid coordinate." }
    }

    static func arguments(serial: String, latitude: Double, longitude: Double,
                          altitude: Double) throws -> [String] {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw LocationError.invalidCoordinate
        }
        let safeAltitude = altitude.isFinite ? max(0, altitude) : 0
        let locale = Locale(identifier: "en_US_POSIX")
        return [
            "-s", serial, "emu", "geo", "fix",
            String(format: "%.8f", locale: locale, longitude),
            String(format: "%.8f", locale: locale, latitude),
            String(format: "%.3f", locale: locale, safeAltitude),
        ]
    }
}

struct EmulatorCamera: Equatable, Sendable {
    let id: String
    let name: String

    static func parseList(_ output: String) -> [EmulatorCamera] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard let idStart = text.range(of: "Camera '")?.upperBound,
                  let idEnd = text[idStart...].range(of: "' is connected to device '") else { return nil }
            let nameStart = idEnd.upperBound
            guard let nameEnd = text[nameStart...].range(of: "' on channel") else { return nil }
            return EmulatorCamera(id: String(text[idStart..<idEnd.lowerBound]),
                                  name: String(text[nameStart..<nameEnd.lowerBound]))
        }
    }
}

struct EmulatorConfiguration: Sendable {
    enum ConfigurationError: LocalizedError {
        case invalidSerial(String)

        var errorDescription: String? {
            switch self {
            case .invalidSerial(let serial):
                return "Invalid Android emulator serial: \(serial)"
            }
        }
    }

    let sdkRoot: String
    let serial: String
    let avdName: String
    let writableSystem: Bool
    let port: Int
    let frontCamera: String
    let backCamera: String
    let audioInputUID: String?

    init(sdkRoot: String, serial: String, avdName: String, writableSystem: Bool,
         frontCamera: String = "emulated", backCamera: String = "emulated",
         audioInputUID: String? = nil) throws {
        guard serial.hasPrefix("emulator-"),
              let port = Int(serial.dropFirst("emulator-".count)),
              (5554...5682).contains(port), port.isMultiple(of: 2) else {
            throw ConfigurationError.invalidSerial(serial)
        }
        self.sdkRoot = sdkRoot
        self.serial = serial
        self.avdName = avdName
        self.writableSystem = writableSystem
        self.port = port
        self.frontCamera = frontCamera
        self.backCamera = backCamera
        self.audioInputUID = audioInputUID
    }

    init(arguments: Arguments) throws {
        try self.init(sdkRoot: arguments.sdkRoot, serial: arguments.emulatorSerial,
                      avdName: arguments.avdName, writableSystem: arguments.writableSystem)
    }

    var adbURL: URL { URL(fileURLWithPath: sdkRoot).appendingPathComponent("platform-tools/adb") }
    var emulatorURL: URL { URL(fileURLWithPath: sdkRoot).appendingPathComponent("emulator/emulator") }
    func launchArguments(coldBoot: Bool) -> [String] {
        var result = ["-avd", avdName, "-port", String(port)]
        if writableSystem { result.append("-writable-system") }
        result += ["-no-window", "-no-boot-anim", "-gpu", "host",
                   "-audio", "coreaudio", "-allow-host-audio", "-camera-front", frontCamera,
                   "-camera-back", backCamera]
        if coldBoot { result.append("-no-snapshot-load") }
        return result
    }
}

enum EmulatorState {
    static func isRunning(output: String, terminationStatus: Int32) -> Bool {
        terminationStatus == 0 && output.trimmingCharacters(in: .whitespacesAndNewlines) == "device"
    }

    static func isPresent(output: String, terminationStatus: Int32) -> Bool {
        guard terminationStatus == 0 else { return false }
        let state = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return state == "device" || state == "offline"
    }

    static func isPaused(output: String, terminationStatus: Int32) -> Bool {
        terminationStatus == 0 && output.contains("virtual device is stopped")
    }

}

final class EmulatorController: @unchecked Sendable {
    enum ControllerError: LocalizedError {
        case executableMissing(String)
        case commandFailed(String, String)
        case startFailed
        case startTimedOut
        case pauseTimedOut
        case resumeTimedOut
        case stopTimedOut

        var errorDescription: String? {
            switch self {
            case .executableMissing(let path): return "Required executable was not found: \(path)"
            case .commandFailed(let command, let output): return "\(command) failed: \(output)"
            case .startFailed: return "Android Emulator exited before it finished starting."
            case .startTimedOut: return "Android Emulator did not finish starting within 120 seconds."
            case .pauseTimedOut: return "Android Emulator did not pause within 10 seconds."
            case .resumeTimedOut: return "Android Emulator did not resume within 30 seconds."
            case .stopTimedOut: return "Android Emulator did not stop within 30 seconds."
            }
        }
    }

    let configuration: EmulatorConfiguration
    private let processLock = NSLock()
    private var launchedProcess: Process?

    init(configuration: EmulatorConfiguration) { self.configuration = configuration }

    static func availableCameras(sdkRoot: String) -> [EmulatorCamera] {
        let emulatorURL = URL(fileURLWithPath: sdkRoot).appendingPathComponent("emulator/emulator")
        guard FileManager.default.isExecutableFile(atPath: emulatorURL.path) else { return [] }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = emulatorURL
        process.arguments = ["-webcam-list"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return process.terminationStatus == 0 ? EmulatorCamera.parseList(output) : []
        } catch {
            return []
        }
    }

    func isRunning() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: configuration.adbURL.path) else { return false }
        let result = run(configuration.adbURL, ["-s", configuration.serial, "get-state"])
        return EmulatorState.isRunning(output: result.output, terminationStatus: result.status)
    }

    func isPaused() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: configuration.adbURL.path) else { return false }
        let result = run(configuration.adbURL, ["-s", configuration.serial, "emu", "avd", "status"])
        return EmulatorState.isPaused(output: result.output, terminationStatus: result.status)
    }

    func ensureRunning() throws {
        guard FileManager.default.isExecutableFile(atPath: configuration.adbURL.path) else {
            throw ControllerError.executableMissing(configuration.adbURL.path)
        }
        do {
            try ensureRunning(coldBoot: false)
        } catch ControllerError.startFailed {
            try retryWithColdBoot()
        } catch ControllerError.startTimedOut {
            try retryWithColdBoot()
        }
    }

    func uninstall(packageName: String) throws {
        guard PackageEventProtocol.isValidPackageName(packageName) else {
            throw ControllerError.commandFailed("adb uninstall", "Invalid package name")
        }
        if isPaused() { try resume() } else { try ensureRunning() }
        let result = run(configuration.adbURL, ["-s", configuration.serial, "uninstall", packageName])
        guard result.status == 0,
              result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "Success" else {
            throw ControllerError.commandFailed("adb uninstall \(packageName)", result.output)
        }
    }

    func packageDeclaresLocationPermission(_ packageName: String) throws -> Bool {
        guard PackageEventProtocol.isValidPackageName(packageName) else {
            throw ControllerError.commandFailed("adb dumpsys package", "Invalid package name")
        }
        let result = run(configuration.adbURL, [
            "-s", configuration.serial, "shell", "dumpsys", "package", packageName,
        ])
        guard result.status == 0 else {
            throw ControllerError.commandFailed("adb dumpsys package \(packageName)", result.output)
        }
        return AndroidManifestPermissions.hasLocationPermission(in: result.output)
    }

    func setLocation(latitude: Double, longitude: Double, altitude: Double) throws {
        let arguments = try EmulatorLocationCommand.arguments(
            serial: configuration.serial, latitude: latitude,
            longitude: longitude, altitude: altitude
        )
        let result = run(configuration.adbURL, arguments)
        guard result.status == 0 else {
            throw ControllerError.commandFailed("adb emu geo fix", result.output)
        }
    }

    private func retryWithColdBoot() throws {
        try stop()
        try ensureRunning(coldBoot: true)
    }

    private func ensureRunning(coldBoot: Bool) throws {
        if !isPresent() { try launchEmulator(coldBoot: coldBoot) }

        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if isRunning() {
                let boot = run(configuration.adbURL, ["-s", configuration.serial,
                                                       "shell", "getprop", "sys.boot_completed"])
                if boot.status == 0 && boot.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                    try configureForward()
                    return
                }
            }
            let exited = processLock.withLock {
                launchedProcess.map { !$0.isRunning } ?? false
            }
            if exited && !isPresent() { throw ControllerError.startFailed }
            Thread.sleep(forTimeInterval: 1)
        }
        throw ControllerError.startTimedOut
    }

    func stop() throws {
        let launchedProcess = processLock.withLock { self.launchedProcess }
        guard isPresent() || launchedProcess?.isRunning == true else { return }
        let result = run(configuration.adbURL, ["-s", configuration.serial, "emu", "kill"])
        if result.status != 0 {
            if launchedProcess?.isRunning == true {
                launchedProcess?.terminate()
            } else {
                throw ControllerError.commandFailed("adb emu kill", result.output)
            }
        }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if !isPresent(), launchedProcess?.isRunning != true { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ControllerError.stopTimedOut
    }

    func pause() throws {
        guard isPresent(), !isPaused() else { return }
        let result = run(configuration.adbURL, ["-s", configuration.serial, "emu", "avd", "stop"])
        guard result.status == 0 else {
            throw ControllerError.commandFailed("adb emu avd stop", result.output)
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if isPaused() { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw ControllerError.pauseTimedOut
    }

    func resume() throws {
        guard isPresent() else {
            try ensureRunning()
            return
        }
        guard isPaused() else { return }
        let result = run(configuration.adbURL, ["-s", configuration.serial, "emu", "avd", "start"])
        guard result.status == 0 else {
            throw ControllerError.commandFailed("adb emu avd start", result.output)
        }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if !isPaused(), isRunning() {
                try configureForward()
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw ControllerError.resumeTimedOut
    }

    func restart() throws {
        try stop()
        try ensureRunning()
    }

    private func launchEmulator(coldBoot: Bool) throws {
        guard FileManager.default.isExecutableFile(atPath: configuration.emulatorURL.path) else {
            throw ControllerError.executableMissing(configuration.emulatorURL.path)
        }
        let process = Process()
        if let audioInputUID = configuration.audioInputUID {
            try EmulatorAudioInput.selectDevice(uid: audioInputUID)
        }
        process.executableURL = configuration.emulatorURL
        process.arguments = configuration.launchArguments(coldBoot: coldBoot)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        processLock.withLock { launchedProcess = process }
    }

    private func isPresent() -> Bool {
        let result = run(configuration.adbURL, ["-s", configuration.serial, "get-state"])
        return EmulatorState.isPresent(output: result.output, terminationStatus: result.status)
    }

    private func configureForward() throws {
        for port in [27183, 27184] {
            _ = run(configuration.adbURL, ["-s", configuration.serial,
                                           "forward", "--remove", "tcp:\(port)"])
            let result = run(configuration.adbURL, ["-s", configuration.serial,
                                                    "forward", "tcp:\(port)", "tcp:\(port)"])
            guard result.status == 0 else {
                throw ControllerError.commandFailed("adb forward tcp:\(port)", result.output)
            }
        }
    }

    private func run(_ executableURL: URL, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}