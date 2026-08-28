import Foundation

public struct Arguments: Sendable {
    public var isEmulatorManager = false
    public var packageName = "com.android.settings"
    public var displayName: String?
    public var host = "127.0.0.1"
    public var port: UInt16 = 27183
    public var width = 1080
    public var height = 1920
    public var density = 420
    public var bitrate = 8_000_000
    public var emulatorSerial = "emulator-5556"
    public var avdName = "msa-api36"
    public var writableSystem = true
    public var sdkRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Android/sdk").path

    public var windowTitle: String { displayName ?? packageName }

    public static func parse(_ values: [String]) -> Arguments {
        parse(
            values,
            bundlePackageName: Bundle.main.object(forInfoDictionaryKey: "MSAPackageName") as? String,
            bundleDisplayName: (Bundle.main.object(forInfoDictionaryKey: "MSADisplayName")
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName")) as? String,
            bundleIsEmulatorManager: Bundle.main.object(forInfoDictionaryKey: "MSAEmulatorManager") as? Bool,
            bundleEmulatorSerial: Bundle.main.object(forInfoDictionaryKey: "MSAEmulatorSerial") as? String,
            bundleAVDName: Bundle.main.object(forInfoDictionaryKey: "MSAAVDName") as? String,
            bundleWritableSystem: Bundle.main.object(forInfoDictionaryKey: "MSAWritableSystem") as? Bool,
            bundleSDKRoot: Bundle.main.object(forInfoDictionaryKey: "MSAAndroidSDKRoot") as? String
        )
    }

    public static func parse(
        _ values: [String],
        bundlePackageName: String?,
        bundleDisplayName: String?,
        bundleIsEmulatorManager: Bool? = nil,
        bundleEmulatorSerial: String? = nil,
        bundleAVDName: String? = nil,
        bundleWritableSystem: Bool? = nil,
        bundleSDKRoot: String? = nil
    ) -> Arguments {
        var result = Arguments()
        result.isEmulatorManager = bundleIsEmulatorManager ?? false
        if let bundlePackageName, !bundlePackageName.isEmpty {
            result.packageName = bundlePackageName
        }
        if let bundleDisplayName, !bundleDisplayName.isEmpty {
            result.displayName = bundleDisplayName
        }
        if let bundleEmulatorSerial, !bundleEmulatorSerial.isEmpty {
            result.emulatorSerial = bundleEmulatorSerial
        }
        if let bundleAVDName, !bundleAVDName.isEmpty {
            result.avdName = bundleAVDName
        }
        if let bundleWritableSystem {
            result.writableSystem = bundleWritableSystem
        }
        if let bundleSDKRoot, !bundleSDKRoot.isEmpty {
            result.sdkRoot = NSString(string: bundleSDKRoot).expandingTildeInPath
        }
        var index = 1
        while index + 1 < values.count {
            let value = values[index + 1]
            switch values[index] {
            case "--package": result.packageName = value
            case "--name": result.displayName = value
            case "--host": result.host = value
            case "--port": result.port = UInt16(value) ?? result.port
            case "--width": result.width = Int(value) ?? result.width
            case "--height": result.height = Int(value) ?? result.height
            case "--density": result.density = Int(value) ?? result.density
            case "--bitrate": result.bitrate = Int(value) ?? result.bitrate
            case "--serial": result.emulatorSerial = value
            case "--avd": result.avdName = value
            case "--writable-system": result.writableSystem = value == "true" || value == "1"
            case "--sdk-root": result.sdkRoot = NSString(string: value).expandingTildeInPath
            default: break
            }
            index += 2
        }
        return result
    }
}
