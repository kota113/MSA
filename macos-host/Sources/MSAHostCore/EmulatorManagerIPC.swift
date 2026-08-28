import Foundation

public enum EmulatorManagerIPC {
    public static let acquire = Notification.Name("dev.msa.emulator.acquire")
    public static let heartbeat = Notification.Name("dev.msa.emulator.heartbeat")
    public static let release = Notification.Name("dev.msa.emulator.release")
    public static let response = Notification.Name("dev.msa.emulator.response")

    public static let serialKey = "serial"
    public static let clientIDKey = "clientID"
    public static let packageNameKey = "packageName"
    public static let requestIDKey = "requestID"
    public static let errorKey = "error"
}