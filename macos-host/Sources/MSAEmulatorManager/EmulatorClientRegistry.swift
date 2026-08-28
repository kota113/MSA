import Foundation

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

    @discardableResult
    mutating func removeExpired(at date: Date = Date()) -> Set<String> {
        let previousIDs = Set(clients.keys)
        clients = clients.filter { date.timeIntervalSince($0.value) < leaseDuration }
        return previousIDs.subtracting(clients.keys)
    }
}