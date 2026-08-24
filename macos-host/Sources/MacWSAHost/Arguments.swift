import Foundation

struct Arguments: Sendable {
    var packageName = "com.android.settings"
    var host = "127.0.0.1"
    var port: UInt16 = 27183
    var width = 1080
    var height = 1920
    var density = 420
    var bitrate = 8_000_000

    static func parse(_ values: [String]) -> Arguments {
        var result = Arguments()
        var index = 1
        while index + 1 < values.count {
            let value = values[index + 1]
            switch values[index] {
            case "--package": result.packageName = value
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
