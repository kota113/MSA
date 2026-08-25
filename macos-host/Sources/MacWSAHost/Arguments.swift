import Foundation

struct Arguments: Sendable {
    var packageName = "com.android.settings"
    var displayName: String?
    var host = "127.0.0.1"
    var port: UInt16 = 27183
    var width = 1080
    var height = 1920
    var density = 420
    var bitrate = 8_000_000

    var windowTitle: String { displayName ?? packageName }

    static func parse(_ values: [String]) -> Arguments {
        parse(
            values,
            bundlePackageName: Bundle.main.object(forInfoDictionaryKey: "MacWSAPackageName") as? String,
            bundleDisplayName: (Bundle.main.object(forInfoDictionaryKey: "MacWSADisplayName")
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName")) as? String
        )
    }

    static func parse(
        _ values: [String],
        bundlePackageName: String?,
        bundleDisplayName: String?
    ) -> Arguments {
        var result = Arguments()
        if let bundlePackageName, !bundlePackageName.isEmpty {
            result.packageName = bundlePackageName
        }
        if let bundleDisplayName, !bundleDisplayName.isEmpty {
            result.displayName = bundleDisplayName
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
            default: break
            }
            index += 2
        }
        return result
    }
}
