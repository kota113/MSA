import Foundation

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

    init(sdkRoot: String, serial: String, avdName: String, writableSystem: Bool) throws {
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
    }

    init(arguments: Arguments) throws {
        try self.init(sdkRoot: arguments.sdkRoot, serial: arguments.emulatorSerial,
                      avdName: arguments.avdName, writableSystem: arguments.writableSystem)
    }

    var adbURL: URL { URL(fileURLWithPath: sdkRoot).appendingPathComponent("platform-tools/adb") }
    var emulatorURL: URL { URL(fileURLWithPath: sdkRoot).appendingPathComponent("emulator/emulator") }
    var launchArguments: [String] {
        var result = ["-avd", avdName, "-port", String(port)]
        if writableSystem { result.append("-writable-system") }
        result += ["-no-window", "-no-snapshot", "-no-boot-anim", "-gpu", "host"]
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

}

final class EmulatorController: @unchecked Sendable {
    enum ControllerError: LocalizedError {
        case executableMissing(String)
        case commandFailed(String, String)
        case startTimedOut
        case stopTimedOut

        var errorDescription: String? {
            switch self {
            case .executableMissing(let path): return "Required executable was not found: \(path)"
            case .commandFailed(let command, let output): return "\(command) failed: \(output)"
            case .startTimedOut: return "Android Emulator did not finish starting within 120 seconds."
            case .stopTimedOut: return "Android Emulator did not stop within 30 seconds."
            }
        }
    }

    let configuration: EmulatorConfiguration
    private let processLock = NSLock()
    private var launchedProcess: Process?

    init(configuration: EmulatorConfiguration) { self.configuration = configuration }

    func isRunning() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: configuration.adbURL.path) else { return false }
        let result = run(configuration.adbURL, ["-s", configuration.serial, "get-state"])
        return EmulatorState.isRunning(output: result.output, terminationStatus: result.status)
    }

    func ensureRunning() throws {
        guard FileManager.default.isExecutableFile(atPath: configuration.adbURL.path) else {
            throw ControllerError.executableMissing(configuration.adbURL.path)
        }
        if !isPresent() { try launchEmulator() }

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

    func restart() throws {
        try stop()
        try ensureRunning()
    }

    private func launchEmulator() throws {
        guard FileManager.default.isExecutableFile(atPath: configuration.emulatorURL.path) else {
            throw ControllerError.executableMissing(configuration.emulatorURL.path)
        }
        let process = Process()
        process.executableURL = configuration.emulatorURL
        process.arguments = configuration.launchArguments
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
        _ = run(configuration.adbURL, ["-s", configuration.serial,
                                      "forward", "--remove", "tcp:27183"])
        let result = run(configuration.adbURL, ["-s", configuration.serial,
                                                "forward", "tcp:27183", "tcp:27183"])
        guard result.status == 0 else {
            throw ControllerError.commandFailed("adb forward", result.output)
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
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}