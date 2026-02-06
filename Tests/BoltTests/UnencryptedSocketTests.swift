import Foundation
import XCTest
import PackStream

@testable import Bolt

/// Legacy synchronous socket tests using DispatchGroup pattern.
/// Note: These tests have threading issues on macOS due to DispatchGroup/NIO event loop conflicts.
/// The async versions in AsyncSocketTests provide the same coverage and work correctly.
/// These tests are skipped on macOS - use AsyncSocketTests for unencrypted socket integration testing.
class UnencryptedSocketTests: XCTestCase, @unchecked Sendable {

    var socketTests: SocketTests?
    var skipTests = false

    override func setUp() {
        self.continueAfterFailure = false
        super.setUp()

        // Skip on macOS due to DispatchGroup/NIO threading conflicts
        // The AsyncSocketTests provide equivalent coverage with proper async/await
        #if !os(Linux)
        skipTests = true
        return
        #endif

        do {
            let config = TestConfig.loadConfig()
            let socket = try UnencryptedSocket(hostname: config.hostname, port: config.port)
            let settings = ConnectionSettings(username: config.username, password: config.password, userAgent: "BoltTests")

            self.socketTests = SocketTests(socket: socket, settings: settings)

        } catch {
            XCTFail("Cannot have exceptions during socket initialization")
        }
    }

    static var allTests: [(String, (UnencryptedSocketTests) -> () throws -> Void)] {
        return [
            ("testMichaels100k", testMichaels100k),
            ("testMichaels100kCannotFitInATransaction", testMichaels100kCannotFitInATransaction),
            ("testRubbishCypher", testRubbishCypher),
            ("testUnwind", testUnwind),
            ("testUnwindWithToNodes", testUnwindWithToNodes)
        ]
    }

    func testMichaels100k() throws {
        try XCTSkipIf(skipTests, "Skipping sync tests on macOS - use AsyncSocketTests instead")
        XCTAssertNotNil(socketTests)
        try socketTests?.templateMichaels100k(self)
    }

    func testMichaels100kCannotFitInATransaction() throws {
        try XCTSkipIf(skipTests, "Skipping sync tests on macOS - use AsyncSocketTests instead")
        XCTAssertNotNil(socketTests)
        try socketTests?.templateMichaels100kCannotFitInATransaction(self)
    }

    func testRubbishCypher() throws {
        try XCTSkipIf(skipTests, "Skipping sync tests on macOS - use AsyncSocketTests instead")
        XCTAssertNotNil(socketTests)
        try socketTests?.templateRubbishCypher(self)
    }

    func testUnwind() throws {
        try XCTSkipIf(skipTests, "Skipping sync tests on macOS - use AsyncSocketTests instead")
        XCTAssertNotNil(socketTests)
        socketTests?.templateUnwind(self)
    }

    func testUnwindWithToNodes() throws {
        try XCTSkipIf(skipTests, "Skipping sync tests on macOS - use AsyncSocketTests instead")
        XCTAssertNotNil(socketTests)
        socketTests?.templateUnwindWithToNodes(self)
    }

}

