import Foundation
import PackStream
import NIOCore
import NIOPosix

#if os(Linux)
import Dispatch
#endif

// MARK: - Bolt Connection

/// A connection to a Neo4j server using the Bolt protocol
public final class Connection: @unchecked Sendable {
    private var settings: ConnectionSettings
    private let socket: SocketProtocol

    /// Current transaction bookmark
    private var _currentTransactionBookmark: String?
    public var currentTransactionBookmark: String? {
        get { lock.withLock { _currentTransactionBookmark } }
        set { lock.withLock { _currentTransactionBookmark = newValue } }
    }

    /// Whether the connection is currently active
    private var _isConnected = false
    public private(set) var isConnected: Bool {
        get { lock.withLock { _isConnected } }
        set { lock.withLock { _isConnected = newValue } }
    }

    /// Negotiated Bolt protocol version
    private var _negotiatedVersion: BoltVersion = .zero
    public private(set) var negotiatedVersion: BoltVersion {
        get { lock.withLock { _negotiatedVersion } }
        set { lock.withLock { _negotiatedVersion = newValue } }
    }

    /// Server metadata from HELLO response
    private var _serverMetadata: BoltConnectionMetadata?
    public private(set) var serverMetadata: BoltConnectionMetadata? {
        get { lock.withLock { _serverMetadata } }
        set { lock.withLock { _serverMetadata = newValue } }
    }

    /// Capabilities based on negotiated protocol version
    public var capabilities: BoltCapabilities {
        BoltCapabilities.forVersion(negotiatedVersion)
    }

    private var _currentEventLoop: EventLoop?
    private var currentEventLoop: EventLoop? {
        get { lock.withLock { _currentEventLoop } }
        set { lock.withLock { _currentEventLoop = newValue } }
    }
    private let lock = NSLock()

    public init(socket: SocketProtocol, settings: ConnectionSettings = ConnectionSettings()) {
        self.socket = socket
        self.settings = settings
    }

    // MARK: - Connection Lifecycle

    /// Connect to the Neo4j server
    public func connect(completion: @escaping @Sendable (_ error: Error?) throws -> Void) throws {
        try socket.connect(timeout: settings.connectionTimeoutMs) { error in
            if let error = error {
                try? completion(error)
                return
            }

            var eventLoop: EventLoop? = self.currentEventLoop ?? MultiThreadedEventLoopGroup.currentEventLoop
            if eventLoop == nil {
                let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                eventLoop = eventLoopGroup.next()
            }

            guard let currentEventLoop = eventLoop else {
                try? completion(BoltError.connection(message: "Failed to get event loop"))
                return
            }

            self.currentEventLoop = currentEventLoop

            // Perform Bolt handshake
            self.performHandshake(on: currentEventLoop).whenComplete { result in
                switch result {
                case .success(let version):
                    self.negotiatedVersion = version
                    self.settings = self.settings.withBoltVersion(version)

                    // Send HELLO message
                    self.sendHello(on: currentEventLoop).whenComplete { helloResult in
                        switch helloResult {
                        case .success(let response):
                            if let map = response.items.first as? Map {
                                self.serverMetadata = BoltConnectionMetadata(from: map)
                            }
                            self.isConnected = true
                            try? completion(nil)
                        case .failure(let error):
                            try? completion(error)
                        }
                    }

                case .failure(let error):
                    try? completion(error)
                }
            }
        }
    }

    /// Disconnect from the server
    public func disconnect() {
        // Send GOODBYE if connected (Bolt 3+)
        if isConnected && negotiatedVersion >= .v3 {
            let goodbye = Request.goodbye()
            _ = try? chunkAndSend(request: goodbye)
        }

        isConnected = false
        socket.disconnect()
    }

    // MARK: - Handshake

    private func performHandshake(on eventLoop: EventLoop) -> EventLoopFuture<BoltVersion> {
        let promise = eventLoop.makePromise(of: BoltVersion.self)

        // Send handshake with version negotiation
        let handshakeBytes = BoltHandshake.createHandshakeWithRanges()

        socket.send(bytes: handshakeBytes)?.whenSuccess { _ in
            do {
                try self.socket.receive(expectedNumberOfBytes: 4)?.map { bytes in
                    guard let version = BoltHandshake.parseVersionResponse(bytes) else {
                        promise.fail(BoltError.connection(message: "Server rejected all protocol versions"))
                        return
                    }
                    promise.succeed(version)
                }.cascadeFailure(to: promise)
            } catch {
                promise.fail(error)
            }
        }

        return promise.futureResult
    }

    private func sendHello(on eventLoop: EventLoop) -> EventLoopFuture<Response> {
        let hello = Request.hello(settings: settings)
        let helloFuture = sendRequest(hello, on: eventLoop)

        // For Bolt 5.1+, we need to send a separate LOGON message after HELLO
        if negotiatedVersion >= .v5_1 {
            return helloFuture.flatMap { _ in
                let logon = Request.logon(settings: self.settings)
                return self.sendRequest(logon, on: eventLoop)
            }
        }

        return helloFuture
    }

    // MARK: - Request/Response

    /// Send a request and receive responses
    public func request(_ request: Request) throws -> EventLoopFuture<[Response]>? {
        guard isConnected else {
            #if BOLT_DEBUG
            print("Bolt client is not connected")
            #endif
            return nil
        }

        var theEventLoop = MultiThreadedEventLoopGroup.currentEventLoop
        if theEventLoop == nil {
            theEventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        }

        guard let eventLoop = theEventLoop else {
            #if BOLT_DEBUG
            print("Error, could not get current eventloop")
            #endif
            return nil
        }

        let futures = try chunkAndSend(request: request)
        let future = futures.count == 1 ?
            futures.first! :
            EventLoopFuture<Void>.andAllComplete(futures, on: eventLoop)

        let maxChunkSize = Int32(Request.kMaxChunkSize)
        let promise = eventLoop.makePromise(of: [Response].self)
        var accumulatedData: [Byte] = []

        func loop() {
            do {
                let receiveFuture = try socket.receive(expectedNumberOfBytes: maxChunkSize)
                _ = receiveFuture?.map { responseData in
                    accumulatedData.append(contentsOf: responseData)

                    if responseData.count < 2 {
                        loop()
                        return
                    }

                    // Check for message termination (0x00 0x00)
                    let isTerminated = responseData[responseData.count - 1] == 0 &&
                                      responseData[responseData.count - 2] == 0

                    if !isTerminated {
                        loop()
                        return
                    }

                    // Parse responses
                    guard let unchunkedResponses = try? Response.unchunk(accumulatedData) else {
                        promise.fail(BoltError.protocol(message: "Failed to unchunk response"))
                        return
                    }

                    var responses = [Response]()
                    var success = true

                    for responseBytes in unchunkedResponses {
                        if let response = try? Response.unpack(responseBytes) {
                            responses.append(response)

                            if let error = response.asError() {
                                promise.fail(error)
                                return
                            }

                            // Parse metadata from non-record responses
                            if response.category != .record {
                                self.parseMeta(response.items)
                            }

                            success = success && response.category != .failure
                        } else {
                            #if BOLT_DEBUG
                            print("Error: failed to parse response")
                            #endif
                            return
                        }
                    }

                    // Continue if more records expected
                    if success && responses.count > 1 && responses.last?.category == .record {
                        loop()
                        return
                    }

                    promise.succeed(responses)
                }.cascadeFailure(to: promise)
            } catch {
                promise.fail(error)
            }
        }

        future.whenComplete { result in
            switch result {
            case .failure(let error):
                #if BOLT_DEBUG
                print("Send error: \(error)")
                #endif
                promise.fail(error)
            case .success:
                loop()
            }
        }

        return promise.futureResult
    }

    /// Send a single request and get single response
    private func sendRequest(_ request: Request, on eventLoop: EventLoop) -> EventLoopFuture<Response> {
        let promise = eventLoop.makePromise(of: Response.self)

        do {
            let futures = try chunkAndSend(request: request)
            let sendFuture = futures.count == 1 ?
                futures.first! :
                EventLoopFuture<Void>.andAllComplete(futures, on: eventLoop)

            let maxChunkSize = Int32(Request.kMaxChunkSize)
            var accumulatedData: [Byte] = []

            func loop() {
                do {
                    try socket.receive(expectedNumberOfBytes: maxChunkSize)?.map { responseData in
                        accumulatedData.append(contentsOf: responseData)

                        let isTerminated = responseData.count >= 2 &&
                            responseData[responseData.count - 1] == 0 &&
                            responseData[responseData.count - 2] == 0

                        if !isTerminated {
                            loop()
                            return
                        }

                        guard let unchunked = try? Response.unchunk(accumulatedData),
                              let responseBytes = unchunked.first,
                              let response = try? Response.unpack(responseBytes) else {
                            promise.fail(BoltError.protocol(message: "Failed to parse response"))
                            return
                        }

                        if response.category == .failure {
                            if let error = response.asError() {
                                promise.fail(error)
                            } else {
                                promise.fail(BoltError.authentication(message: "Authentication failed"))
                            }
                            return
                        }

                        promise.succeed(response)
                    }.cascadeFailure(to: promise)
                } catch {
                    promise.fail(error)
                }
            }

            sendFuture.whenSuccess {
                loop()
            }
            sendFuture.whenFailure { error in
                promise.fail(error)
            }

        } catch {
            promise.fail(error)
        }

        return promise.futureResult
    }

    // MARK: - Transaction Support

    /// Begin a transaction
    public func beginTransaction(
        mode: TransactionMode = .readwrite,
        database: String? = nil,
        bookmarks: [String] = [],
        metadata: [String: String] = [:],
        timeoutMs: Int? = nil
    ) throws -> EventLoopFuture<[Response]>? {
        let bookmark = currentTransactionBookmark.map { [$0] } ?? bookmarks
        let request = Request.begin(
            mode: mode,
            database: database ?? settings.database,
            bookmarks: bookmark,
            metadata: metadata,
            timeoutMs: timeoutMs
        )
        return try self.request(request)
    }

    /// Commit the current transaction
    public func commitTransaction() throws -> EventLoopFuture<[Response]>? {
        return try request(Request.commit())
    }

    /// Rollback the current transaction
    public func rollbackTransaction() throws -> EventLoopFuture<[Response]>? {
        return try request(Request.rollback())
    }

    // MARK: - Query Execution

    /// Execute a Cypher query
    public func run(
        _ statement: String,
        parameters: [String: any PackProtocol] = [:],
        database: String? = nil,
        mode: TransactionMode? = nil
    ) throws -> EventLoopFuture<[Response]>? {
        let request = Request.run(
            statement: statement,
            parameters: parameters,
            database: database ?? settings.database,
            mode: mode
        )
        return try self.request(request)
    }

    /// Pull results (Bolt 4+)
    public func pull(n: Int = -1, qid: Int = -1) throws -> EventLoopFuture<[Response]>? {
        if negotiatedVersion >= .v4_0 {
            return try request(Request.pull(n: n, qid: qid))
        } else {
            return try request(Request.pullAll())
        }
    }

    /// Discard results (Bolt 4+)
    public func discard(n: Int = -1, qid: Int = -1) throws -> EventLoopFuture<[Response]>? {
        if negotiatedVersion >= .v4_0 {
            return try request(Request.discard(n: n, qid: qid))
        } else {
            return try request(Request.discardAll())
        }
    }

    /// Reset the connection state
    public func reset() throws -> EventLoopFuture<[Response]>? {
        return try request(Request.reset())
    }

    // MARK: - Routing (Bolt 4.3+)

    /// Get routing table for a database
    public func route(
        routingContext: [String: String],
        database: String? = nil
    ) throws -> EventLoopFuture<[Response]>? {
        guard capabilities.contains(.routing) else {
            throw BoltError.protocol(message: "Routing not supported in Bolt \(negotiatedVersion)")
        }
        let request = Request.route(
            routingContext: routingContext,
            bookmarks: currentTransactionBookmark.map { [$0] } ?? [],
            database: database ?? settings.database
        )
        return try self.request(request)
    }

    // MARK: - Private Helpers

    private func chunkAndSend(request: Request) throws -> [EventLoopFuture<Void>] {
        let chunks = try request.chunk()
        return chunks.compactMap { socket.send(bytes: $0) }
    }

    private func parseMeta(_ meta: [any PackProtocol]) {
        for item in meta {
            if let map = item as? Map {
                for (key, value) in map.dictionary {
                    switch key {
                    case "bookmark", "bookmarks":
                        currentTransactionBookmark = value as? String
                    default:
                        break
                    }
                }
            }
        }
    }

    // MARK: - Legacy Support

    @available(*, deprecated, message: "Use beginTransaction() instead")
    public func readOnlyMode(_ blockToBePerformed: @escaping () -> Void) {
        guard let currentEventLoop = currentEventLoop else {
            return
        }

        let request = Request.begin(mode: .readonly)
        let chunks = try? request.chunk()
        let sendFutures = chunks?.compactMap { socket.send(bytes: $0) }

        if let futures = sendFutures {
            let future = EventLoopFuture<Void>.andAllSucceed(futures, on: currentEventLoop)
            future.whenSuccess {
                blockToBePerformed()
            }
        }
    }
}

// MARK: - Async/Await API

extension Connection {
    /// Connect to the Neo4j server asynchronously
    public func connectAsync() async throws {
        try await socket.connectAsync(timeout: settings.connectionTimeoutMs)
        let version = try await performHandshakeAsync()
        self.negotiatedVersion = version
        self.settings = self.settings.withBoltVersion(version)
        let response = try await sendHelloAsync()
        if let map = response.items.first as? Map {
            self.serverMetadata = BoltConnectionMetadata(from: map)
        }
        self.isConnected = true
    }

    /// Perform Bolt protocol handshake asynchronously
    /// Supports both legacy (Bolt 4.x) and manifest (Bolt 5.x) negotiation
    private func performHandshakeAsync() async throws -> BoltVersion {
        let handshakeBytes = BoltHandshake.createHandshakeWithRanges()
        try await socket.sendAsync(bytes: handshakeBytes)
        let responseBytes = try await socket.receiveAsync(expectedNumberOfBytes: 4)

        // Check if server wants manifest negotiation (Bolt 5.x)
        if BoltHandshake.isManifestNegotiation(responseBytes) {
            return try await performManifestNegotiationAsync()
        }

        // Legacy negotiation (Bolt 4.x and earlier)
        guard let version = BoltHandshake.parseVersionResponse(responseBytes) else {
            throw BoltError.connection(message: "Server rejected all protocol versions")
        }
        return version
    }

    /// Perform manifest negotiation for Bolt 5.x servers
    private func performManifestNegotiationAsync() async throws -> BoltVersion {
        // Read the number of protocol offerings (varint)
        let countByte = try await socket.receiveAsync(expectedNumberOfBytes: 1)
        let offeringsCount = Int(countByte[0])

        // Read all protocol offerings (each is 4 bytes: [minor, range, 0, major])
        var offerings: [(major: UInt8, minor: UInt8, range: UInt8)] = []
        for _ in 0..<offeringsCount {
            let offeringBytes = try await socket.receiveAsync(expectedNumberOfBytes: 4)
            let minor = offeringBytes[0]
            let range = offeringBytes[1]
            let major = offeringBytes[3]
            offerings.append((major: major, minor: minor, range: range))
        }

        // Read capability mask (varint - for now we just consume it)
        _ = try await socket.receiveAsync(expectedNumberOfBytes: 1)

        // Select the best version we support from the offerings
        // Client supports: Bolt 5.6→5.0, Bolt 4.4→4.2, Bolt 3.0
        let clientVersions: [(major: UInt8, minor: UInt8, range: UInt8)] = [
            (major: 5, minor: 6, range: 6),  // 5.6 → 5.0
            (major: 4, minor: 4, range: 2),  // 4.4 → 4.2
            (major: 3, minor: 0, range: 0),  // 3.0
        ]

        var chosenVersion: BoltVersion?

        // Find highest mutually supported version
        outer: for clientVer in clientVersions {
            for clientMinor in stride(from: Int(clientVer.minor), through: Int(clientVer.minor) - Int(clientVer.range), by: -1) {
                for offer in offerings {
                    if offer.major == clientVer.major {
                        let offerMinorMax = Int(offer.minor)
                        let offerMinorMin = Int(offer.minor) - Int(offer.range)
                        if clientMinor >= offerMinorMin && clientMinor <= offerMinorMax {
                            chosenVersion = BoltVersion(major: clientVer.major, minor: UInt8(clientMinor))
                            break outer
                        }
                    }
                }
            }
        }

        guard let version = chosenVersion else {
            // Send invalid handshake to indicate failure
            try await socket.sendAsync(bytes: [0x00, 0x00, 0x00, 0x00])
            throw BoltError.connection(message: "No mutually supported Bolt version found")
        }

        // Send chosen version back to server (4 bytes: [minor, 0, 0, major])
        let chosenBytes: [Byte] = [version.minor, 0, 0, version.major]
        try await socket.sendAsync(bytes: chosenBytes)

        return version
    }

    /// Send HELLO message asynchronously
    /// For Bolt 5.1+, also sends LOGON message after HELLO
    private func sendHelloAsync() async throws -> Response {
        let hello = Request.hello(settings: settings)
        let helloResponse = try await sendRequestAsync(hello)

        // For Bolt 5.1+, we need to send a separate LOGON message after HELLO
        if negotiatedVersion >= .v5_1 {
            let logon = Request.logon(settings: settings)
            return try await sendRequestAsync(logon)
        }

        return helloResponse
    }

    /// Send a single request and receive a single response asynchronously
    private func sendRequestAsync(_ request: Request) async throws -> Response {
        let chunks = try request.chunk()
        for chunk in chunks {
            try await socket.sendAsync(bytes: chunk)
        }
        return try await receiveResponseAsync()
    }

    /// Receive a single response asynchronously
    private func receiveResponseAsync() async throws -> Response {
        var accumulatedData: [Byte] = []
        let maxChunkSize = Int32(Request.kMaxChunkSize)

        while true {
            let responseData = try await socket.receiveAsync(expectedNumberOfBytes: maxChunkSize)
            accumulatedData.append(contentsOf: responseData)

            // Check for message termination (0x00 0x00)
            let isTerminated = responseData.count >= 2 &&
                responseData[responseData.count - 1] == 0 &&
                responseData[responseData.count - 2] == 0

            if isTerminated {
                break
            }
        }

        guard let unchunked = try? Response.unchunk(accumulatedData),
              let responseBytes = unchunked.first,
              let response = try? Response.unpack(responseBytes) else {
            throw BoltError.protocol(message: "Failed to parse response")
        }

        if response.category == .failure {
            if let error = response.asError() {
                throw error
            }
            throw BoltError.authentication(message: "Authentication failed")
        }

        return response
    }

    /// Send a request and receive multiple responses asynchronously
    public func requestAsync(_ request: Request) async throws -> [Response] {
        guard isConnected else {
            throw BoltError.connection(message: "Bolt client is not connected")
        }

        let chunks = try request.chunk()
        for chunk in chunks {
            try await socket.sendAsync(bytes: chunk)
        }

        return try await receiveAllResponsesAsync()
    }

    /// Receive all responses until completion asynchronously
    private func receiveAllResponsesAsync() async throws -> [Response] {
        var accumulatedData: [Byte] = []
        let maxChunkSize = Int32(Request.kMaxChunkSize)

        while true {
            let responseData = try await socket.receiveAsync(expectedNumberOfBytes: maxChunkSize)
            accumulatedData.append(contentsOf: responseData)

            if responseData.count < 2 {
                continue
            }

            // Check for message termination (0x00 0x00)
            let isTerminated = responseData[responseData.count - 1] == 0 &&
                responseData[responseData.count - 2] == 0

            if !isTerminated {
                continue
            }

            // Parse responses
            guard let unchunkedResponses = try? Response.unchunk(accumulatedData) else {
                throw BoltError.protocol(message: "Failed to unchunk response")
            }

            var responses = [Response]()
            var success = true

            for responseBytes in unchunkedResponses {
                guard let response = try? Response.unpack(responseBytes) else {
                    throw BoltError.protocol(message: "Failed to parse response")
                }

                responses.append(response)

                if let error = response.asError() {
                    throw error
                }

                // Parse metadata from non-record responses
                if response.category != .record {
                    self.parseMeta(response.items)
                }

                success = success && response.category != .failure
            }

            // Continue if more records expected
            if success && responses.count > 1 && responses.last?.category == .record {
                continue
            }

            return responses
        }
    }

    // MARK: - Async Transaction Support

    /// Begin a transaction asynchronously
    public func beginTransaction(
        mode: TransactionMode = .readwrite,
        database: String? = nil,
        bookmarks: [String] = [],
        metadata: [String: String] = [:],
        timeoutMs: Int? = nil
    ) async throws -> [Response] {
        let bookmark = currentTransactionBookmark.map { [$0] } ?? bookmarks
        let request = Request.begin(
            mode: mode,
            database: database ?? settings.database,
            bookmarks: bookmark,
            metadata: metadata,
            timeoutMs: timeoutMs
        )
        return try await requestAsync(request)
    }

    /// Commit the current transaction asynchronously
    public func commitTransaction() async throws -> [Response] {
        return try await requestAsync(Request.commit())
    }

    /// Rollback the current transaction asynchronously
    public func rollbackTransaction() async throws -> [Response] {
        return try await requestAsync(Request.rollback())
    }

    // MARK: - Async Query Execution

    /// Execute a Cypher query asynchronously
    public func run(
        _ statement: String,
        parameters: [String: any PackProtocol] = [:],
        database: String? = nil,
        mode: TransactionMode? = nil
    ) async throws -> [Response] {
        let request = Request.run(
            statement: statement,
            parameters: parameters,
            database: database ?? settings.database,
            mode: mode
        )
        return try await requestAsync(request)
    }

    /// Pull results asynchronously (Bolt 4+)
    public func pull(n: Int = -1, qid: Int = -1) async throws -> [Response] {
        if negotiatedVersion >= .v4_0 {
            return try await requestAsync(Request.pull(n: n, qid: qid))
        } else {
            return try await requestAsync(Request.pullAll())
        }
    }

    /// Discard results asynchronously (Bolt 4+)
    public func discard(n: Int = -1, qid: Int = -1) async throws -> [Response] {
        if negotiatedVersion >= .v4_0 {
            return try await requestAsync(Request.discard(n: n, qid: qid))
        } else {
            return try await requestAsync(Request.discardAll())
        }
    }

    /// Reset the connection state asynchronously
    public func reset() async throws -> [Response] {
        return try await requestAsync(Request.reset())
    }

    // MARK: - Async Routing (Bolt 4.3+)

    /// Get routing table for a database asynchronously
    public func route(
        routingContext: [String: String],
        database: String? = nil
    ) async throws -> [Response] {
        guard capabilities.contains(.routing) else {
            throw BoltError.protocol(message: "Routing not supported in Bolt \(negotiatedVersion)")
        }
        let request = Request.route(
            routingContext: routingContext,
            bookmarks: currentTransactionBookmark.map { [$0] } ?? [],
            database: database ?? settings.database
        )
        return try await requestAsync(request)
    }
}

// MARK: - Connection Errors (Legacy)

extension Connection {
    @available(*, deprecated, renamed: "BoltError")
    public enum ConnectionError: Error {
        case unknownVersion
        case authenticationError
        case requestError
        case unknownError
    }

    @available(*, deprecated, renamed: "ResponseCategory")
    public enum CommandResponse: Byte {
        case success = 0x70
        case record = 0x71
        case ignored = 0x7e
        case failure = 0x7f
    }
}
