import XCTest
import PackStream
import NIOCore
import NIOPosix

#if os(Linux)
import Dispatch
#endif

@testable import Bolt

/// Connection and protocol tests
/// Based on patterns from neo4j-go-driver and neo4j-java-driver
final class ConnectionTests: XCTestCase {

    // MARK: - Connection Settings Tests

    func testConnectionSettingsDefaults() {
        let settings = ConnectionSettings()

        XCTAssertEqual(settings.username, "neo4j")
        XCTAssertEqual(settings.password, "neo4j")
        XCTAssertTrue(settings.userAgent.contains("Bolt-Swift"))
        XCTAssertEqual(settings.boltVersion, .v5_0)
        XCTAssertNil(settings.database)
        XCTAssertTrue(settings.keepAlive)
    }

    func testConnectionSettingsWithCredentials() {
        let settings = ConnectionSettings(
            username: "testuser",
            password: "testpass"
        )

        XCTAssertEqual(settings.username, "testuser")
        XCTAssertEqual(settings.password, "testpass")
    }

    func testConnectionSettingsWithEmptyCredentials() {
        let settings = ConnectionSettings(
            username: "",
            password: ""
        )

        XCTAssertTrue(settings.username.isEmpty)
        XCTAssertTrue(settings.password.isEmpty)
    }

    func testConnectionSettingsWithDatabase() {
        let settings = ConnectionSettings(
            database: "mydb"
        )

        XCTAssertEqual(settings.database, "mydb")
    }

    func testConnectionSettingsWithBoltVersion() {
        let settings = ConnectionSettings(
            boltVersion: .v4_4
        )

        XCTAssertEqual(settings.boltVersion, .v4_4)
    }

    func testConnectionSettingsWithTimeout() {
        let settings = ConnectionSettings(
            connectionTimeoutMs: 60000,
            socketTimeoutMs: 30000
        )

        XCTAssertEqual(settings.connectionTimeoutMs, 60000)
        XCTAssertEqual(settings.socketTimeoutMs, 30000)
    }

    func testConnectionSettingsWithBoltVersionUpdate() {
        let settings = ConnectionSettings(boltVersion: .v4_0)
        let updated = settings.withBoltVersion(.v5_4)

        XCTAssertEqual(settings.boltVersion, .v4_0)  // Original unchanged
        XCTAssertEqual(updated.boltVersion, .v5_4)  // New value
    }

    // MARK: - Bolt Version Tests

    func testBoltVersionComparison() {
        XCTAssertTrue(BoltVersion.v3 < BoltVersion.v4_0)
        XCTAssertTrue(BoltVersion.v4_0 < BoltVersion.v4_4)
        XCTAssertTrue(BoltVersion.v4_4 < BoltVersion.v5_0)
        XCTAssertTrue(BoltVersion.v5_0 < BoltVersion.v5_4)
    }

    func testBoltVersionEquality() {
        let v1 = BoltVersion.v5_0
        let v2 = BoltVersion.v5_0

        XCTAssertEqual(v1, v2)
    }

    func testBoltVersionMajorMinor() {
        XCTAssertEqual(BoltVersion.v3.major, 3)
        XCTAssertEqual(BoltVersion.v3.minor, 0)

        XCTAssertEqual(BoltVersion.v4_4.major, 4)
        XCTAssertEqual(BoltVersion.v4_4.minor, 4)

        XCTAssertEqual(BoltVersion.v5_4.major, 5)
        XCTAssertEqual(BoltVersion.v5_4.minor, 4)
    }

    func testBoltVersionRawValues() {
        // Test all supported Bolt versions
        let versions: [BoltVersion] = [.v3, .v4_0, .v4_1, .v4_2, .v4_3, .v4_4, .v5_0, .v5_1, .v5_2, .v5_3, .v5_4, .v5_5, .v5_6]

        for version in versions {
            XCTAssertGreaterThanOrEqual(version.major, 3)
            XCTAssertGreaterThanOrEqual(version.minor, 0)
        }
    }

    func testBoltVersionDescription() {
        let version = BoltVersion(major: 5, minor: 4)
        XCTAssertEqual(version.description, "5.4")

        let majorOnly = BoltVersion(major: 3)
        XCTAssertEqual(majorOnly.description, "3")
    }

    func testBoltVersionEncode() {
        let version = BoltVersion.v5_4
        let encoded = version.encode()

        XCTAssertEqual(encoded.count, 4)
        XCTAssertEqual(encoded[0], 4)  // minor
        XCTAssertEqual(encoded[3], 5)  // major
    }

    // MARK: - Bolt Capabilities Tests

    func testBoltCapabilitiesForVersion3() {
        let caps = BoltCapabilities.forVersion(.v3)

        XCTAssertTrue(caps.contains(.transactions))
        XCTAssertFalse(caps.contains(.streaming))
        XCTAssertFalse(caps.contains(.routing))
    }

    func testBoltCapabilitiesForVersion4() {
        let caps = BoltCapabilities.forVersion(.v4_0)

        XCTAssertTrue(caps.contains(.transactions))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.qid))
    }

    func testBoltCapabilitiesForVersion44() {
        let caps = BoltCapabilities.forVersion(.v4_4)

        XCTAssertTrue(caps.contains(.transactions))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.routing))
    }

    func testBoltCapabilitiesForVersion5() {
        let caps = BoltCapabilities.forVersion(.v5_0)

        XCTAssertTrue(caps.contains(.transactions))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.routing))
    }

    func testBoltCapabilitiesForVersion54() {
        let caps = BoltCapabilities.forVersion(.v5_4)

        XCTAssertTrue(caps.contains(.transactions))
        XCTAssertTrue(caps.contains(.telemetry))
    }

    func testBoltCapabilitiesOptionSet() {
        var caps: BoltCapabilities = [.transactions, .bookmarks]

        XCTAssertTrue(caps.contains(.transactions))
        XCTAssertTrue(caps.contains(.bookmarks))
        XCTAssertFalse(caps.contains(.routing))

        caps.insert(.routing)
        XCTAssertTrue(caps.contains(.routing))

        caps.remove(.bookmarks)
        XCTAssertFalse(caps.contains(.bookmarks))
    }

    // MARK: - Notification Severity Tests

    func testNotificationSeverityValues() {
        XCTAssertEqual(NotificationSeverity.off.rawValue, "OFF")
        XCTAssertEqual(NotificationSeverity.warning.rawValue, "WARNING")
        XCTAssertEqual(NotificationSeverity.information.rawValue, "INFORMATION")
    }

    // MARK: - Notification Category Tests

    func testNotificationCategoryValues() {
        XCTAssertEqual(NotificationCategory.hint.rawValue, "HINT")
        XCTAssertEqual(NotificationCategory.unrecognized.rawValue, "UNRECOGNIZED")
        XCTAssertEqual(NotificationCategory.unsupported.rawValue, "UNSUPPORTED")
        XCTAssertEqual(NotificationCategory.performance.rawValue, "PERFORMANCE")
        XCTAssertEqual(NotificationCategory.deprecation.rawValue, "DEPRECATION")
        XCTAssertEqual(NotificationCategory.security.rawValue, "SECURITY")
        XCTAssertEqual(NotificationCategory.topology.rawValue, "TOPOLOGY")
        XCTAssertEqual(NotificationCategory.generic.rawValue, "GENERIC")
    }

    func testNotificationCategoryAllCases() {
        let allCategories = NotificationCategory.allCases
        XCTAssertEqual(allCategories.count, 8)
    }

    // MARK: - Connection Settings with Notifications Tests

    func testConnectionSettingsWithNotifications() {
        let settings = ConnectionSettings(
            notificationsMinSeverity: NotificationSeverity.warning.rawValue,
            notificationsDisabledCategories: [
                NotificationCategory.hint.rawValue,
                NotificationCategory.deprecation.rawValue
            ]
        )

        XCTAssertEqual(settings.notificationsMinSeverity, "WARNING")
        XCTAssertEqual(settings.notificationsDisabledCategories?.count, 2)
        XCTAssertTrue(settings.notificationsDisabledCategories?.contains("HINT") ?? false)
    }

    // MARK: - Handshake Tests

    func testHandshakePreamble() {
        let preamble = BoltHandshake.preamble
        XCTAssertEqual(preamble.count, 4)
        XCTAssertEqual(preamble[0], 0x60)
        XCTAssertEqual(preamble[1], 0x60)
        XCTAssertEqual(preamble[2], 0xB0)
        XCTAssertEqual(preamble[3], 0x17)
    }

    func testHandshakeWithRanges() {
        let handshake = BoltHandshake.createHandshakeWithRanges()
        // 4 bytes preamble + 4 * 4 bytes version slots = 20 bytes
        XCTAssertEqual(handshake.count, 20)
    }

    func testHandshakeContainsPreamble() {
        let handshake = BoltHandshake.createHandshakeWithRanges()
        let preamble = Array(handshake[0..<4])
        XCTAssertEqual(preamble, BoltHandshake.preamble)
    }

    func testHandshakeWithPreferredVersions() {
        let handshake = BoltHandshake.createHandshake(preferredVersions: [.v5_4, .v4_4, .v3])
        XCTAssertEqual(handshake.count, 20)
    }

    func testParseVersionResponseSuccess() {
        // Server responds with 5.4
        let response: [Byte] = [4, 0, 0, 5]
        let version = BoltHandshake.parseVersionResponse(response)

        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 5)
        XCTAssertEqual(version?.minor, 4)
    }

    func testParseVersionResponseZero() {
        // Server responds with zero (no compatible version)
        let response: [Byte] = [0, 0, 0, 0]
        let version = BoltHandshake.parseVersionResponse(response)

        XCTAssertNil(version)
    }

    func testParseVersionResponseInvalidLength() {
        // Invalid response length
        let response: [Byte] = [4, 0, 5]
        let version = BoltHandshake.parseVersionResponse(response)

        XCTAssertNil(version)
    }

    // MARK: - Bolt Message Signatures Tests

    func testBoltMessageSignatures() {
        XCTAssertEqual(BoltMessageSignature.hello.rawValue, 0x01)
        XCTAssertEqual(BoltMessageSignature.run.rawValue, 0x10)
        XCTAssertEqual(BoltMessageSignature.begin.rawValue, 0x11)
        XCTAssertEqual(BoltMessageSignature.commit.rawValue, 0x12)
        XCTAssertEqual(BoltMessageSignature.rollback.rawValue, 0x13)
        XCTAssertEqual(BoltMessageSignature.pull.rawValue, 0x3F)
        XCTAssertEqual(BoltMessageSignature.discard.rawValue, 0x2F)
        XCTAssertEqual(BoltMessageSignature.reset.rawValue, 0x0F)
    }

    func testBoltResponseSignatures() {
        XCTAssertEqual(BoltMessageSignature.success.rawValue, 0x70)
        XCTAssertEqual(BoltMessageSignature.record.rawValue, 0x71)
        XCTAssertEqual(BoltMessageSignature.ignored.rawValue, 0x7E)
        XCTAssertEqual(BoltMessageSignature.failure.rawValue, 0x7F)
    }

    func testBoltMessageAliases() {
        XCTAssertEqual(BoltMessageSignature.initialize, .hello)
        XCTAssertEqual(BoltMessageSignature.discardAll, .discard)
        XCTAssertEqual(BoltMessageSignature.pullAll, .pull)
    }

    // MARK: - Response Category Tests

    func testResponseCategories() {
        XCTAssertEqual(ResponseCategory.success.rawValue, 0x70)
        XCTAssertEqual(ResponseCategory.record.rawValue, 0x71)
        XCTAssertEqual(ResponseCategory.ignored.rawValue, 0x7E)
        XCTAssertEqual(ResponseCategory.failure.rawValue, 0x7F)
    }

    // MARK: - Mock Socket Connection Tests

    func testConnectionInit() {
        let mockSocket = MockSocket()
        let settings = ConnectionSettings(username: "testuser", password: "testpass")
        let connection = Connection(socket: mockSocket, settings: settings)

        XCTAssertFalse(connection.isConnected)
        XCTAssertEqual(connection.negotiatedVersion, .zero)
        XCTAssertNil(connection.serverMetadata)
        XCTAssertNil(connection.currentTransactionBookmark)
    }

    func testConnectionCapabilities() {
        let mockSocket = MockSocket()
        let connection = Connection(socket: mockSocket)

        // Before connection, should have capabilities for default version
        let caps = connection.capabilities
        XCTAssertNotNil(caps)
    }

    func testConnectionDisconnect() {
        let mockSocket = MockSocket()
        let connection = Connection(socket: mockSocket)

        // Disconnect without connecting first
        connection.disconnect()

        XCTAssertTrue(mockSocket.disconnectCalled)
        XCTAssertFalse(connection.isConnected)
    }

    func testConnectionDisconnectWhenConnected() {
        let mockSocket = MockSocket()
        let settings = ConnectionSettings(boltVersion: .v5_0)
        let connection = Connection(socket: mockSocket, settings: settings)

        // Simulate connection state
        mockSocket.queueHandshakeResponse(version: .v5_0)
        mockSocket.queueSuccessResponse(metadata: ["server": "Neo4j/5.0.0"])

        let expectation = XCTestExpectation(description: "connect")

        do {
            try connection.connect { error in
                expectation.fulfill()
            }
        } catch {
            XCTFail("Connection threw: \(error)")
        }

        wait(for: [expectation], timeout: 5.0)

        // Now disconnect
        connection.disconnect()

        XCTAssertTrue(mockSocket.disconnectCalled)
        XCTAssertFalse(connection.isConnected)
    }

    func testMockSocketConnect() {
        let mockSocket = MockSocket()

        XCTAssertFalse(mockSocket.isConnected)

        let expectation = XCTestExpectation(description: "connect")

        do {
            try mockSocket.connect(timeout: 1000) { error in
                XCTAssertNil(error)
                expectation.fulfill()
            }
        } catch {
            XCTFail("Connect threw: \(error)")
        }

        wait(for: [expectation], timeout: 2.0)

        XCTAssertTrue(mockSocket.connectCalled)
        XCTAssertTrue(mockSocket.isConnected)
    }

    func testMockSocketConnectError() {
        let mockSocket = MockSocket()
        mockSocket.connectError = SocketError.connectionFailed("Test error")

        let expectation = XCTestExpectation(description: "connect")

        do {
            try mockSocket.connect(timeout: 1000) { error in
                XCTAssertNotNil(error)
                expectation.fulfill()
            }
        } catch {
            XCTFail("Connect threw: \(error)")
        }

        wait(for: [expectation], timeout: 2.0)

        XCTAssertFalse(mockSocket.isConnected)
    }

    func testMockSocketSend() {
        let mockSocket = MockSocket()
        let testData: [Byte] = [0x01, 0x02, 0x03]

        let future = mockSocket.send(bytes: testData)
        XCTAssertNotNil(future)

        // Wait for the future
        let expectation = XCTestExpectation(description: "send")
        future?.whenComplete { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Send failed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(mockSocket.sentData.count, 1)
        XCTAssertEqual(mockSocket.sentData.first, testData)
    }

    func testMockSocketReceive() {
        let mockSocket = MockSocket()
        let testResponse: [Byte] = [0x70, 0xA0]  // SUCCESS with empty map
        mockSocket.queueResponse(testResponse)

        let expectation = XCTestExpectation(description: "receive")

        do {
            let future = try mockSocket.receive(expectedNumberOfBytes: 100)
            future?.whenComplete { result in
                switch result {
                case .success(let bytes):
                    XCTAssertEqual(bytes, testResponse)
                case .failure(let error):
                    XCTFail("Receive failed: \(error)")
                }
                expectation.fulfill()
            }
        } catch {
            XCTFail("Receive threw: \(error)")
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testMockSocketQueueMultipleResponses() {
        let mockSocket = MockSocket()
        let response1: [Byte] = [0x01]
        let response2: [Byte] = [0x02]
        let response3: [Byte] = [0x03]

        mockSocket.queueResponse(response1)
        mockSocket.queueResponse(response2)
        mockSocket.queueResponse(response3)

        // Receive responses in order
        for (index, expected) in [response1, response2, response3].enumerated() {
            let expectation = XCTestExpectation(description: "receive \(index)")

            do {
                let future = try mockSocket.receive(expectedNumberOfBytes: 100)
                future?.whenComplete { result in
                    if case .success(let bytes) = result {
                        XCTAssertEqual(bytes, expected, "Response \(index) mismatch")
                    }
                    expectation.fulfill()
                }
            } catch {
                XCTFail("Receive threw: \(error)")
            }

            wait(for: [expectation], timeout: 2.0)
        }
    }

    func testMockSocketReset() {
        let mockSocket = MockSocket()

        mockSocket.queueResponse([0x01])
        _ = mockSocket.send(bytes: [0x02])

        mockSocket.reset()

        XCTAssertEqual(mockSocket.sentData.count, 0)
        XCTAssertFalse(mockSocket.isConnected)
        XCTAssertFalse(mockSocket.connectCalled)
    }

    func testMockSocketDisconnect() {
        let mockSocket = MockSocket()

        // Connect first
        let connectExp = XCTestExpectation(description: "connect")
        do {
            try mockSocket.connect(timeout: 1000) { _ in
                connectExp.fulfill()
            }
        } catch {
            XCTFail("Connect threw: \(error)")
        }
        wait(for: [connectExp], timeout: 2.0)

        XCTAssertTrue(mockSocket.isConnected)

        // Disconnect
        mockSocket.disconnect()

        XCTAssertFalse(mockSocket.isConnected)
        XCTAssertTrue(mockSocket.disconnectCalled)
    }

    func testMockSocketQueueSuccessResponse() {
        let mockSocket = MockSocket()
        mockSocket.queueSuccessResponse(metadata: ["server": "Neo4j/5.0.0"])

        let expectation = XCTestExpectation(description: "receive")

        do {
            let future = try mockSocket.receive(expectedNumberOfBytes: 100)
            future?.whenComplete { result in
                if case .success(let bytes) = result {
                    // Should have chunked SUCCESS response
                    XCTAssertGreaterThan(bytes.count, 0)
                    // Last two bytes should be 0x00 0x00 (message terminator)
                    XCTAssertEqual(bytes.suffix(2), [0x00, 0x00])
                }
                expectation.fulfill()
            }
        } catch {
            XCTFail("Receive threw: \(error)")
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testMockSocketQueueFailureResponse() {
        let mockSocket = MockSocket()
        mockSocket.queueFailureResponse(
            code: "Neo.ClientError.Security.Unauthorized",
            message: "Authentication failed"
        )

        let expectation = XCTestExpectation(description: "receive")

        do {
            let future = try mockSocket.receive(expectedNumberOfBytes: 100)
            future?.whenComplete { result in
                if case .success(let bytes) = result {
                    XCTAssertGreaterThan(bytes.count, 0)
                    // Last two bytes should be 0x00 0x00
                    XCTAssertEqual(bytes.suffix(2), [0x00, 0x00])
                }
                expectation.fulfill()
            }
        } catch {
            XCTFail("Receive threw: \(error)")
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testMockSocketQueueHandshakeResponse() {
        let mockSocket = MockSocket()
        mockSocket.queueHandshakeResponse(version: .v5_4)

        let expectation = XCTestExpectation(description: "receive")

        do {
            let future = try mockSocket.receive(expectedNumberOfBytes: 4)
            future?.whenComplete { result in
                if case .success(let bytes) = result {
                    XCTAssertEqual(bytes.count, 4)
                    XCTAssertEqual(bytes[0], 4)  // minor
                    XCTAssertEqual(bytes[3], 5)  // major
                }
                expectation.fulfill()
            }
        } catch {
            XCTFail("Receive threw: \(error)")
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testConnectionRequestWhenNotConnected() {
        let mockSocket = MockSocket()
        let connection = Connection(socket: mockSocket)

        // Should return nil when not connected
        let request = Request.reset()
        do {
            let future = try connection.request(request)
            XCTAssertNil(future, "Request should return nil when not connected")
        } catch {
            XCTFail("Request threw: \(error)")
        }
    }

    // MARK: - BoltConnectionMetadata Tests

    func testBoltConnectionMetadataFromMap() {
        let map = Map(dictionary: [
            "server": "Neo4j/5.4.0",
            "connection_id": "bolt-123",
            "hints": Map(dictionary: [
                "connection.recv_timeout_seconds": "120"
            ])
        ])

        let metadata = BoltConnectionMetadata(from: map)

        XCTAssertEqual(metadata.serverAgent, "Neo4j/5.4.0")
        XCTAssertEqual(metadata.connectionId, "bolt-123")
        XCTAssertEqual(metadata.serverVersion, "5.4.0")
        XCTAssertEqual(metadata.hints["connection.recv_timeout_seconds"], "120")
    }

    func testBoltConnectionMetadataEmpty() {
        let map = Map(dictionary: [:])
        let metadata = BoltConnectionMetadata(from: map)

        XCTAssertEqual(metadata.serverAgent, "Unknown")
        XCTAssertNil(metadata.connectionId)
        XCTAssertNil(metadata.serverVersion)
        XCTAssertTrue(metadata.hints.isEmpty)
    }

    // MARK: - SocketError Tests

    func testSocketErrorConnectionFailed() {
        let error = SocketError.connectionFailed("Test message")
        if case .connectionFailed(let message) = error {
            XCTAssertEqual(message, "Test message")
        } else {
            XCTFail("Wrong error type")
        }
    }

    func testSocketErrorSendFailed() {
        let error = SocketError.sendFailed("Send error")
        if case .sendFailed(let message) = error {
            XCTAssertEqual(message, "Send error")
        } else {
            XCTFail("Wrong error type")
        }
    }

    func testSocketErrorReceiveFailed() {
        let error = SocketError.receiveFailed("Receive error")
        if case .receiveFailed(let message) = error {
            XCTAssertEqual(message, "Receive error")
        } else {
            XCTFail("Wrong error type")
        }
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (ConnectionTests) -> () throws -> Void)] {
        return [
            ("testConnectionSettingsDefaults", testConnectionSettingsDefaults),
            ("testConnectionSettingsWithCredentials", testConnectionSettingsWithCredentials),
            ("testConnectionSettingsWithEmptyCredentials", testConnectionSettingsWithEmptyCredentials),
            ("testConnectionSettingsWithDatabase", testConnectionSettingsWithDatabase),
            ("testConnectionSettingsWithBoltVersion", testConnectionSettingsWithBoltVersion),
            ("testConnectionSettingsWithTimeout", testConnectionSettingsWithTimeout),
            ("testConnectionSettingsWithBoltVersionUpdate", testConnectionSettingsWithBoltVersionUpdate),
            ("testBoltVersionComparison", testBoltVersionComparison),
            ("testBoltVersionEquality", testBoltVersionEquality),
            ("testBoltVersionMajorMinor", testBoltVersionMajorMinor),
            ("testBoltVersionRawValues", testBoltVersionRawValues),
            ("testBoltVersionDescription", testBoltVersionDescription),
            ("testBoltVersionEncode", testBoltVersionEncode),
            ("testBoltCapabilitiesForVersion3", testBoltCapabilitiesForVersion3),
            ("testBoltCapabilitiesForVersion4", testBoltCapabilitiesForVersion4),
            ("testBoltCapabilitiesForVersion44", testBoltCapabilitiesForVersion44),
            ("testBoltCapabilitiesForVersion5", testBoltCapabilitiesForVersion5),
            ("testBoltCapabilitiesForVersion54", testBoltCapabilitiesForVersion54),
            ("testBoltCapabilitiesOptionSet", testBoltCapabilitiesOptionSet),
            ("testNotificationSeverityValues", testNotificationSeverityValues),
            ("testNotificationCategoryValues", testNotificationCategoryValues),
            ("testNotificationCategoryAllCases", testNotificationCategoryAllCases),
            ("testConnectionSettingsWithNotifications", testConnectionSettingsWithNotifications),
            ("testHandshakePreamble", testHandshakePreamble),
            ("testHandshakeWithRanges", testHandshakeWithRanges),
            ("testHandshakeContainsPreamble", testHandshakeContainsPreamble),
            ("testHandshakeWithPreferredVersions", testHandshakeWithPreferredVersions),
            ("testParseVersionResponseSuccess", testParseVersionResponseSuccess),
            ("testParseVersionResponseZero", testParseVersionResponseZero),
            ("testParseVersionResponseInvalidLength", testParseVersionResponseInvalidLength),
            ("testBoltMessageSignatures", testBoltMessageSignatures),
            ("testBoltResponseSignatures", testBoltResponseSignatures),
            ("testBoltMessageAliases", testBoltMessageAliases),
            ("testResponseCategories", testResponseCategories),
            ("testConnectionInit", testConnectionInit),
            ("testConnectionCapabilities", testConnectionCapabilities),
            ("testConnectionDisconnect", testConnectionDisconnect),
            ("testConnectionDisconnectWhenConnected", testConnectionDisconnectWhenConnected),
            ("testMockSocketConnect", testMockSocketConnect),
            ("testMockSocketConnectError", testMockSocketConnectError),
            ("testMockSocketSend", testMockSocketSend),
            ("testMockSocketReceive", testMockSocketReceive),
            ("testMockSocketQueueMultipleResponses", testMockSocketQueueMultipleResponses),
            ("testMockSocketReset", testMockSocketReset),
            ("testMockSocketDisconnect", testMockSocketDisconnect),
            ("testMockSocketQueueSuccessResponse", testMockSocketQueueSuccessResponse),
            ("testMockSocketQueueFailureResponse", testMockSocketQueueFailureResponse),
            ("testMockSocketQueueHandshakeResponse", testMockSocketQueueHandshakeResponse),
            ("testConnectionRequestWhenNotConnected", testConnectionRequestWhenNotConnected),
            ("testBoltConnectionMetadataFromMap", testBoltConnectionMetadataFromMap),
            ("testBoltConnectionMetadataEmpty", testBoltConnectionMetadataEmpty),
            ("testSocketErrorConnectionFailed", testSocketErrorConnectionFailed),
            ("testSocketErrorSendFailed", testSocketErrorSendFailed),
            ("testSocketErrorReceiveFailed", testSocketErrorReceiveFailed),
        ]
    }
}
