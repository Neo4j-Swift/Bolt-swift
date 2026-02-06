import XCTest
import PackStream
import NIOCore
import NIOPosix

#if os(Linux)
import Dispatch
#endif

@testable import Bolt

final class BoltTests: XCTestCase, @unchecked Sendable {

    var eventLoopGroup: MultiThreadedEventLoopGroup! = nil

    override func setUp() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override func tearDown() {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    // MARK: - PackStream Tests

    func testPackstream1() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa2, 0x86, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x8b, 0x4e, 0x65, 0x6f, 0x34, 0x6a, 0x2f, 0x34, 0x2e, 0x30, 0x2e, 0x34, 0x8d, 0x63, 0x6f, 0x6e, 0x6e, 0x65, 0x63, 0x74, 0x69, 0x6f, 0x6e, 0x5f, 0x69, 0x64, 0x88, 0x62, 0x6f, 0x6c, 0x74, 0x2d, 0x36, 0x37, 0x34, 0x00, 0x00]
        let s = try Structure.unpack(bytes)
        XCTAssertEqual(s.signature, 0x70)
    }

    func testPackstream2() throws {
        let bytes: [Byte] = [0xb1, 0x01, 0xa4, 0x8a, 0x75, 0x73, 0x65, 0x72, 0x5f, 0x61, 0x67, 0x65, 0x6e, 0x74, 0xd0, 0x32, 0x6e, 0x65, 0x6f, 0x34, 0x6a, 0x2d, 0x70, 0x79, 0x74, 0x68, 0x6f, 0x6e, 0x2f, 0x34, 0x2e, 0x30, 0x2e, 0x30, 0x61, 0x33, 0x20, 0x50, 0x79, 0x74, 0x68, 0x6f, 0x6e, 0x2f, 0x33, 0x2e, 0x37, 0x2e, 0x37, 0x2d, 0x66, 0x69, 0x6e, 0x61, 0x6c, 0x2d, 0x30, 0x20, 0x28, 0x64, 0x61, 0x72, 0x77, 0x69, 0x6e, 0x29, 0x86, 0x73, 0x63, 0x68, 0x65, 0x6d, 0x65, 0x85, 0x62, 0x61, 0x73, 0x69, 0x63, 0x89, 0x70, 0x72, 0x69, 0x6e, 0x63, 0x69, 0x70, 0x61, 0x6c, 0x85, 0x6e, 0x65, 0x6f, 0x34, 0x6a, 0x8b, 0x63, 0x72, 0x65, 0x64, 0x65, 0x6e, 0x74, 0x69, 0x61, 0x6c, 0x73, 0x84, 0x74, 0x65, 0x73, 0x74, 0x00, 0x00]
        let s = try Structure.unpack(bytes)
        XCTAssertEqual(s.signature, 0x01)
    }

    // MARK: - Response Parsing Tests

    func testUnpackInitResponse() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa1, 0x86, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x8b, 0x4e, 0x65, 0x6f, 0x34, 0x6a, 0x2f, 0x33, 0x2e, 0x31, 0x2e, 0x31]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)

        guard let properties = response.items[0] as? Map else {
            XCTFail("Response metadata should be a Map")
            return
        }

        XCTAssertEqual(1, properties.dictionary.count)
        XCTAssertEqual("Neo4j/3.1.1", properties.dictionary["server"] as? String)
    }

    func testUnpackEmptyRequestResponse() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa2, 0xd0, 0x16, 0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72, 0x1, 0x86, 0x66, 0x69, 0x65, 0x6c, 0x64, 0x73, 0x90]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)

        guard let properties = response.items[0] as? Map,
              let fields = properties.dictionary["fields"] as? List else {
            XCTFail("Response metadata should be a Map with fields")
            return
        }

        XCTAssertEqual(0, fields.items.count)
    }

    func testUnpackRequestResponseWithNode() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa2, 0xd0, 0x16, 0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72, 0x2, 0x86, 0x66, 0x69, 0x65, 0x6c, 0x64, 0x73, 0x91, 0x81, 0x6e]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)

        guard let properties = response.items[0] as? Map,
              let fields = properties.dictionary["fields"] as? List else {
            XCTFail("Response metadata should be a Map with fields")
            return
        }

        XCTAssertEqual(1, fields.items.count)
        XCTAssertEqual("n", fields.items[0] as? String)
    }

    func testUnpackPullAllRequestAfterCypherRequest() throws {
        let bytes: [Byte] = [0xb1, 0x71, 0x91, 0xb3, 0x4e, 0x12, 0x91, 0x89, 0x46, 0x69, 0x72, 0x73, 0x74, 0x4e, 0x6f, 0x64, 0x65, 0xa1, 0x84, 0x6e, 0x61, 0x6d, 0x65, 0x86, 0x53, 0x74, 0x65, 0x76, 0x65, 0x6e]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .record)
        guard let node = response.asNode() else {
            XCTFail("Expected response to be a node")
            return
        }

        XCTAssertEqual(18, node.id)
        XCTAssertEqual(1, node.labels.count)
        XCTAssertEqual("FirstNode", node.labels[0])
        XCTAssertEqual(1, node.properties.count)

        let (propertyKey, propertyValue) = node.properties.first!
        XCTAssertEqual("name", propertyKey)
        XCTAssertEqual("Steven", propertyValue as? String)
    }

    // MARK: - Protocol Tests

    func testBoltVersion() {
        let v5 = BoltVersion(major: 5, minor: 3)
        let v4 = BoltVersion(major: 4, minor: 4)

        XCTAssertTrue(v5 > v4)
        XCTAssertEqual(v5.description, "5.3")
        XCTAssertEqual(v4.description, "4.4")
    }

    func testBoltHandshake() {
        let handshake = BoltHandshake.createHandshakeWithRanges()
        XCTAssertEqual(handshake.count, 20) // 4 byte preamble + 4*4 byte versions

        // Check preamble
        XCTAssertEqual(Array(handshake[0..<4]), BoltHandshake.preamble)
    }

    func testBoltCapabilities() {
        let v3Caps = BoltCapabilities.forVersion(.v3)
        let v5Caps = BoltCapabilities.forVersion(.v5_4)

        XCTAssertTrue(v3Caps.contains(.transactions))
        XCTAssertFalse(v3Caps.contains(.streaming))

        XCTAssertTrue(v5Caps.contains(.streaming))
        XCTAssertTrue(v5Caps.contains(.routing))
        XCTAssertTrue(v5Caps.contains(.telemetry))
    }

    static var allTests: [(String, (BoltTests) -> () throws -> Void)] {
        return [
            ("testPackstream1", testPackstream1),
            ("testPackstream2", testPackstream2),
            ("testUnpackInitResponse", testUnpackInitResponse),
            ("testUnpackEmptyRequestResponse", testUnpackEmptyRequestResponse),
            ("testUnpackRequestResponseWithNode", testUnpackRequestResponseWithNode),
            ("testUnpackPullAllRequestAfterCypherRequest", testUnpackPullAllRequestAfterCypherRequest),
            ("testBoltVersion", testBoltVersion),
            ("testBoltHandshake", testBoltHandshake),
            ("testBoltCapabilities", testBoltCapabilities),
        ]
    }
}

// MARK: - Node Helper

struct Node {
    public let id: UInt64
    public let labels: [String]
    public let properties: [String: any PackProtocol]
}

extension Response {
    func asNode() -> Node? {
        if category != .record || items.count != 1 {
            return nil
        }

        guard let list = items[0] as? List,
              list.items.count == 1,
              let structure = list.items[0] as? Structure,
              structure.signature == BoltRecordType.node.rawValue,
              structure.items.count == 3,
              let nodeId = structure.items.first?.intValue().map({ UInt64($0) }),
              let labelList = structure.items[1] as? List,
              let labels = labelList.items as? [String],
              let propertyMap = structure.items[2] as? Map else {
            return nil
        }

        return Node(id: nodeId, labels: labels, properties: propertyMap.dictionary)
    }
}
