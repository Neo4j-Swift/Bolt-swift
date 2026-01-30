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
