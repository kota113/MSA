import Foundation
import Network

enum PackageEventProtocol {
    static func isValidPackageName(_ packageName: String) -> Bool {
        packageName.range(of: #"^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$"#,
                          options: .regularExpression) != nil
    }

    static func parsePending(_ response: String) -> [String] {
        response.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("PACKAGE ") else { return nil }
            let packageName = String(line.dropFirst("PACKAGE ".count))
            return isValidPackageName(packageName) ? packageName : nil
        }
    }
}

final class PackageEventClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case invalidResponse(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let response): return "Invalid package event response: \(response)"
            case .timedOut: return "The package event service did not respond"
            }
        }
    }

    private let port = NWEndpoint.Port(rawValue: 27184)!

    func listPending() async throws -> [String] {
        let response = try await request("LIST_PENDING\n")
        guard response.split(whereSeparator: \.isNewline).last == "END" else {
            throw ClientError.invalidResponse(response)
        }
        return PackageEventProtocol.parsePending(response)
    }

    func acknowledge(_ packageName: String) async throws {
        guard PackageEventProtocol.isValidPackageName(packageName) else {
            throw ClientError.invalidResponse(packageName)
        }
        let response = try await request("ACK \(packageName)\n")
        guard response.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
            throw ClientError.invalidResponse(response)
        }
    }

    private func request(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            let state = ResponseState(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { status in
                switch status {
                case .ready:
                    connection.send(content: Data(command.utf8), completion: .contentProcessed { error in
                        if let error { state.finish(.failure(error)) } else { state.receive() }
                    })
                case .failed(let error): state.finish(.failure(error))
                case .cancelled: state.finish(.failure(ClientError.timedOut))
                default: break
                }
            }
            let queue = DispatchQueue(label: "dev.msa.package-events")
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { state.finish(.failure(ClientError.timedOut)) }
        }
    }
}

private final class ResponseState: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<String, Error>?
    private var data = Data()

    init(connection: NWConnection, continuation: CheckedContinuation<String, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, complete, error in
            guard let self else { return }
            if let chunk { lock.withLock { data.append(chunk) } }
            if let error {
                finish(.failure(error))
            } else if complete {
                finish(.success(lock.withLock { String(decoding: data, as: UTF8.self) }))
            } else {
                receive()
            }
        }
    }

    func finish(_ result: Result<String, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<String, Error>? in
            defer { continuation = nil }
            return continuation
        }
        guard let pending else { return }
        connection.cancel()
        pending.resume(with: result)
    }
}