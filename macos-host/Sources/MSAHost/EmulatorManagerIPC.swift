import Foundation

enum EmulatorManagerIPC {
    static let acquire = Notification.Name("dev.msa.emulator.acquire")
    static let heartbeat = Notification.Name("dev.msa.emulator.heartbeat")
    static let release = Notification.Name("dev.msa.emulator.release")
    static let response = Notification.Name("dev.msa.emulator.response")

    static let serialKey = "serial"
    static let clientIDKey = "clientID"
    static let requestIDKey = "requestID"
    static let errorKey = "error"
}

struct EmulatorClientRegistry {
    let leaseDuration: TimeInterval
    private(set) var clients: [String: Date] = [:]

    var isEmpty: Bool { clients.isEmpty }

    func contains(_ clientID: String) -> Bool { clients[clientID] != nil }

    mutating func touch(_ clientID: String, at date: Date = Date()) {
        clients[clientID] = date
    }

    mutating func release(_ clientID: String) {
        clients.removeValue(forKey: clientID)
    }

    mutating func removeExpired(at date: Date = Date()) {
        clients = clients.filter { date.timeIntervalSince($0.value) < leaseDuration }
    }
}