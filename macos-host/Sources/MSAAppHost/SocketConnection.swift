import Darwin
import Foundation

final class SocketConnection: @unchecked Sendable {
    enum SocketError: Error { case resolution, connect, closed, system(Int32) }
    private var descriptor: Int32 = -1
    private let sendLock = NSLock()

    init(host: String, port: UInt16) throws {
        var hints = addrinfo(
            ai_flags: AI_NUMERICSERV,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0 else {
            throw SocketError.resolution
        }
        defer { freeaddrinfo(result) }
        var cursor = result
        while let info = cursor?.pointee {
            let fd = Darwin.socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if fd >= 0, Darwin.connect(fd, info.ai_addr, info.ai_addrlen) == 0 {
                descriptor = fd
                var yes: Int32 = 1
                setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
                return
            }
            if fd >= 0 { Darwin.close(fd) }
            cursor = info.ai_next
        }
        throw SocketError.connect
    }

    func sendLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        sendLock.lock()
        defer { sendLock.unlock() }
        do { try writeAll(data) } catch { }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let count = Darwin.send(descriptor, pointer, remaining, 0)
                if count <= 0 { throw SocketError.system(errno) }
                remaining -= count
                pointer = pointer.advanced(by: count)
            }
        }
    }

    func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = count
            while remaining > 0 {
                let received = Darwin.recv(descriptor, pointer, remaining, 0)
                if received == 0 { throw SocketError.closed }
                if received < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.system(errno)
                }
                remaining -= received
                pointer = pointer.advanced(by: received)
            }
        }
        return data
    }

    func close() {
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    deinit { close() }
}
