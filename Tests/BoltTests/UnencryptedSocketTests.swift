import Foundation
import XCTest
import PackStream

@testable import Bolt

class UnencryptedSocketTests: XCTestCase {

    var socketTests: SocketTests?

    override func setUp() {
        self.continueAfterFailure = false
        super.setUp()

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
        XCTAssertNotNil(socketTests)
        try socketTests?.templateMichaels100k(self)
    }

    func testMichaels100kCannotFitInATransaction() throws {
        XCTAssertNotNil(socketTests)
        try socketTests?.templateMichaels100kCannotFitInATransaction(self)
    }

    func testRubbishCypher() throws {
        XCTAssertNotNil(socketTests)
        try socketTests?.templateRubbishCypher(self)
    }

    func testUnwind() throws {
        XCTAssertNotNil(socketTests)
        socketTests?.templateUnwind(self)
    }

    func testUnwindWithToNodes() {
        XCTAssertNotNil(socketTests)
        socketTests?.templateUnwindWithToNodes(self)
    }

}

