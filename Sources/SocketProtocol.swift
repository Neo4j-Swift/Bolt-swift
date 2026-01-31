import Foundation
import PackStream
import NIOCore

// MARK: - Socket Protocol

/// Protocol for Bolt socket implementations
public protocol SocketProtocol: Sendable {
    /// Connect to the server
    func connect(timeout: Int, completion: @escaping @Sendable (Error?) -> Void) throws

    /// Send bytes to the server
    func send(bytes: [Byte]) -> EventLoopFuture<Void>?

    /// Receive bytes from the server
    func receive(expectedNumberOfBytes: Int32) throws -> EventLoopFuture<[Byte]>?

    /// Disconnect from the server
    func disconnect()
}

// MARK: - Socket Errors

/// Errors that can occur during socket operations
public enum SocketError: Error, Sendable {
    case connectionFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case timeout
    case disconnected
    case invalidState(String)
}

extension SocketError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        case .receiveFailed(let msg): return "Receive failed: \(msg)"
        case .timeout: return "Socket operation timed out"
        case .disconnected: return "Socket disconnected"
        case .invalidState(let msg): return "Invalid socket state: \(msg)"
        }
    }
}

// MARK: - Async/Await Support

/// Default async implementations that bridge to the callback/EventLoopFuture-based methods
public extension SocketProtocol {

    /// Connect to the server asynchronously
    func connectAsync(timeout: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try self.connect(timeout: timeout) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Send bytes to the server asynchronously
    func sendAsync(bytes: [Byte]) async throws {
        guard let future = self.send(bytes: bytes) else {
            throw SocketError.invalidState("No channel available for send")
        }
        try await future.get()
    }

    /// Receive bytes from the server asynchronously
    func receiveAsync(expectedNumberOfBytes: Int32) async throws -> [Byte] {
        guard let future = try self.receive(expectedNumberOfBytes: expectedNumberOfBytes) else {
            throw SocketError.invalidState("No channel available for receive")
        }
        return try await future.get()
    }
}
