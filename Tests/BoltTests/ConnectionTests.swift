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
        ]
    }
}
