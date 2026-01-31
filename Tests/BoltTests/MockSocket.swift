import Foundation
import PackStream
import NIOCore
import NIOPosix
@testable import Bolt

/// Mock socket for testing Connection without network I/O
final class MockSocket: SocketProtocol, @unchecked Sendable {
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let eventLoop: EventLoop
    private let lock = NSLock()

    // Response queue - what the mock server will respond with
    private var responseQueue: [[Byte]] = []
    private var responseIndex = 0

    // Sent data - what the client sent
    private(set) var sentData: [[Byte]] = []

    // Connection state
    private(set) var isConnected = false
    private(set) var connectCalled = false
    private(set) var disconnectCalled = false

    // Error simulation
    var connectError: Error?
    var sendError: Error?
    var receiveError: Error?

    init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoop = eventLoopGroup.next()
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    // MARK: - SocketProtocol Implementation

    func connect(timeout: Int, completion: @escaping @Sendable (Error?) -> Void) throws {
        connectCalled = true
        if let error = connectError {
            completion(error)
        } else {
            isConnected = true
            completion(nil)
        }
    }

    func send(bytes: [Byte]) -> EventLoopFuture<Void>? {
        lock.lock()
        sentData.append(bytes)
        lock.unlock()

        if let error = sendError {
            return eventLoop.makeFailedFuture(error)
        }
        return eventLoop.makeSucceededVoidFuture()
    }

    func receive(expectedNumberOfBytes: Int32) throws -> EventLoopFuture<[Byte]>? {
        if let error = receiveError {
            return eventLoop.makeFailedFuture(error)
        }

        lock.lock()
        defer { lock.unlock() }

        if responseIndex < responseQueue.count {
            let response = responseQueue[responseIndex]
            responseIndex += 1
            return eventLoop.makeSucceededFuture(response)
        }

        // No more responses - return empty
        return eventLoop.makeSucceededFuture([])
    }

    func disconnect() {
        disconnectCalled = true
        isConnected = false
    }

    // MARK: - Test Helpers

    /// Queue a raw byte response
    func queueResponse(_ bytes: [Byte]) {
        lock.lock()
        responseQueue.append(bytes)
        lock.unlock()
    }

    /// Queue a handshake version response (e.g., Bolt 5.4)
    func queueHandshakeResponse(version: BoltVersion) {
        let response: [Byte] = [
            Byte(version.minor),
            0,
            0,
            Byte(version.major)
        ]
        queueResponse(response)
    }

    /// Queue a SUCCESS response with metadata
    func queueSuccessResponse(metadata: [String: any PackProtocol] = [:]) {
        let map = Map(dictionary: metadata)
        let structure = Structure(signature: BoltMessageSignature.success.rawValue, items: [map])

        if let packed = try? structure.pack() {
            // Chunk the response: length prefix + data + terminator
            var chunked: [Byte] = []
            let length = UInt16(packed.count)
            chunked.append(Byte(length >> 8))
            chunked.append(Byte(length & 0xFF))
            chunked.append(contentsOf: packed)
            chunked.append(0x00)
            chunked.append(0x00)
            queueResponse(chunked)
        }
    }

    /// Queue a FAILURE response
    func queueFailureResponse(code: String, message: String) {
        let map = Map(dictionary: [
            "code": code,
            "message": message
        ])
        let structure = Structure(signature: BoltMessageSignature.failure.rawValue, items: [map])

        if let packed = try? structure.pack() {
            var chunked: [Byte] = []
            let length = UInt16(packed.count)
            chunked.append(Byte(length >> 8))
            chunked.append(Byte(length & 0xFF))
            chunked.append(contentsOf: packed)
            chunked.append(0x00)
            chunked.append(0x00)
            queueResponse(chunked)
        }
    }

    /// Queue a RECORD response
    func queueRecordResponse(fields: [any PackProtocol]) {
        let list = List(items: fields)
        let structure = Structure(signature: BoltMessageSignature.record.rawValue, items: [list])

        if let packed = try? structure.pack() {
            var chunked: [Byte] = []
            let length = UInt16(packed.count)
            chunked.append(Byte(length >> 8))
            chunked.append(Byte(length & 0xFF))
            chunked.append(contentsOf: packed)
            chunked.append(0x00)
            chunked.append(0x00)
            queueResponse(chunked)
        }
    }

    /// Reset the mock state
    func reset() {
        lock.lock()
        sentData = []
        responseQueue = []
        responseIndex = 0
        isConnected = false
        connectCalled = false
        disconnectCalled = false
        connectError = nil
        sendError = nil
        receiveError = nil
        lock.unlock()
    }

    /// Get all sent data as a flattened array
    var allSentBytes: [Byte] {
        lock.lock()
        defer { lock.unlock() }
        return sentData.flatMap { $0 }
    }
}
