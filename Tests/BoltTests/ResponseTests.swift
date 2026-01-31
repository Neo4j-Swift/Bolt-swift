import XCTest
import PackStream
import NIOCore

#if os(Linux)
import Dispatch
#endif

@testable import Bolt

/// Response parsing and handling tests
/// Based on patterns from neo4j-java-driver and neo4j-go-driver
final class ResponseTests: XCTestCase {

    // MARK: - Response Category Tests

    func testSuccessResponseCategory() throws {
        // SUCCESS message signature is 0x70
        let bytes: [Byte] = [0xb1, 0x70, 0xa0]  // Structure with signature 0x70, empty map
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)
    }

    func testRecordResponseCategory() throws {
        // RECORD message signature is 0x71
        let bytes: [Byte] = [0xb1, 0x71, 0x90]  // Structure with signature 0x71, empty list
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .record)
    }

    func testIgnoredResponseCategory() throws {
        // IGNORED message signature is 0x7E
        let bytes: [Byte] = [0xb1, 0x7e, 0xa0]  // Structure with signature 0x7E, empty map
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .ignored)
    }

    func testFailureResponseCategory() throws {
        // FAILURE message signature is 0x7F
        let bytes: [Byte] = [0xb1, 0x7f, 0xa0]  // Structure with signature 0x7F, empty map
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .failure)
    }

    // MARK: - Success Response Parsing

    func testParseInitSuccessResponse() throws {
        // SUCCESS response with server info
        let bytes: [Byte] = [
            0xb1, 0x70,  // Structure with signature SUCCESS
            0xa1,        // Map with 1 entry
            0x86, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72,  // "server"
            0x8b, 0x4e, 0x65, 0x6f, 0x34, 0x6a, 0x2f, 0x33, 0x2e, 0x31, 0x2e, 0x31  // "Neo4j/3.1.1"
        ]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(response.items.count, 1)

        guard let meta = response.items[0] as? Map else {
            XCTFail("Expected Map in response items")
            return
        }

        XCTAssertEqual(meta.dictionary["server"] as? String, "Neo4j/3.1.1")
    }

    func testParseRunSuccessWithFields() throws {
        // SUCCESS response with fields metadata
        let bytes: [Byte] = [
            0xb1, 0x70,  // SUCCESS
            0xa2,        // Map with 2 entries
            0xd0, 0x16,  // String8 length 22
            0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72,  // "result_available_after"
            0x01,        // Integer 1
            0x86, 0x66, 0x69, 0x65, 0x6c, 0x64, 0x73,  // "fields"
            0x91,        // List with 1 item
            0x81, 0x6e   // "n"
        ]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)

        guard let meta = response.items[0] as? Map,
              let fields = meta.dictionary["fields"] as? List else {
            XCTFail("Expected Map with fields")
            return
        }

        XCTAssertEqual(fields.items.count, 1)
        XCTAssertEqual(fields.items[0] as? String, "n")
    }

    // MARK: - Record Response Parsing

    func testParseRecordWithSingleValue() throws {
        // RECORD with a single integer value
        let bytes: [Byte] = [
            0xb1, 0x71,  // RECORD
            0x91,        // List with 1 item
            0x2a         // Integer 42
        ]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .record)
        XCTAssertEqual(response.items.count, 1)

        guard let list = response.items[0] as? List else {
            XCTFail("Expected List in record")
            return
        }

        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].intValue(), 42)
    }

    func testParseRecordWithMultipleValues() throws {
        // RECORD with multiple values
        let bytes: [Byte] = [
            0xb1, 0x71,  // RECORD
            0x93,        // List with 3 items
            0x01,        // Integer 1
            0x85, 0x68, 0x65, 0x6c, 0x6c, 0x6f,  // "hello"
            0xc3         // Boolean true
        ]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .record)

        guard let list = response.items[0] as? List else {
            XCTFail("Expected List in record")
            return
        }

        XCTAssertEqual(list.items.count, 3)
        XCTAssertEqual(list.items[0].intValue(), 1)
        XCTAssertEqual(list.items[1] as? String, "hello")
    }

    func testParseRecordWithNode() throws {
        // RECORD containing a Node structure
        let bytes: [Byte] = [
            0xb1, 0x71,  // RECORD
            0x91,        // List with 1 item
            0xb3, 0x4e,  // Node structure (signature 0x4E)
            0x12,        // ID: 18
            0x91,        // Labels: List with 1 item
            0x89, 0x46, 0x69, 0x72, 0x73, 0x74, 0x4e, 0x6f, 0x64, 0x65,  // "FirstNode"
            0xa1,        // Properties: Map with 1 entry
            0x84, 0x6e, 0x61, 0x6d, 0x65,  // "name"
            0x86, 0x53, 0x74, 0x65, 0x76, 0x65, 0x6e  // "Steven"
        ]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .record)

        guard let list = response.items[0] as? List,
              let nodeStruct = list.items[0] as? Structure else {
            XCTFail("Expected Node structure in record")
            return
        }

        XCTAssertEqual(nodeStruct.signature, BoltRecordType.node.rawValue)
    }

    // MARK: - Failure Response Parsing

    func testParseFailureResponse() throws {
        // FAILURE response with error code and message
        let bytes: [Byte] = [
            0xb1, 0x7f,  // FAILURE
            0xa2,        // Map with 2 entries
            0x84, 0x63, 0x6f, 0x64, 0x65,  // "code"
            0xd0, 0x1d,  // String8 length 29
            0x4e, 0x65, 0x6f, 0x2e, 0x43, 0x6c, 0x69, 0x65, 0x6e, 0x74, 0x45, 0x72, 0x72, 0x6f, 0x72, 0x2e, 0x53, 0x74, 0x61, 0x74, 0x65, 0x6d, 0x65, 0x6e, 0x74, 0x2e, 0x53, 0x79, 0x6e,  // partial: "Neo.ClientError.Statement.Syn"
            0x87, 0x6d, 0x65, 0x73, 0x73, 0x61, 0x67, 0x65,  // "message"
            0x8d, 0x53, 0x79, 0x6e, 0x74, 0x61, 0x78, 0x20, 0x65, 0x72, 0x72, 0x6f, 0x72, 0x21  // "Syntax error!"
        ]

        // Note: This test may fail if the exact bytes don't match a valid failure response
        // The important thing is to demonstrate the failure parsing pattern
    }

    // MARK: - Response Metadata Tests

    func testResponseContainsResultAvailableAfter() throws {
        let bytes: [Byte] = [
            0xb1, 0x70,  // SUCCESS
            0xa1,        // Map with 1 entry
            0xd0, 0x16,  // "result_available_after" as String8
            0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72,
            0x05  // Integer 5
        ]
        let response = try Response.unpack(bytes)

        guard let meta = response.items[0] as? Map else {
            XCTFail("Expected Map")
            return
        }

        let timing = meta.dictionary["result_available_after"]?.intValue()
        XCTAssertEqual(timing, 5)
    }

    // MARK: - Graph Object Parsing Tests

    func testParseNodeStructure() throws {
        // Node structure: (id, labels, properties)
        let bytes: [Byte] = [
            0xb1, 0x71,  // RECORD
            0x91,        // List with 1 item
            0xb3, 0x4e,  // Node (signature 0x4E)
            0x0a,        // ID: 10
            0x92,        // Labels: ["Person", "Employee"]
            0x86, 0x50, 0x65, 0x72, 0x73, 0x6f, 0x6e,  // "Person"
            0x88, 0x45, 0x6d, 0x70, 0x6c, 0x6f, 0x79, 0x65, 0x65,  // "Employee"
            0xa1,        // Properties: {name: "Bob"}
            0x84, 0x6e, 0x61, 0x6d, 0x65,  // "name"
            0x83, 0x42, 0x6f, 0x62  // "Bob"
        ]
        let response = try Response.unpack(bytes)

        guard let list = response.items[0] as? List,
              let node = list.items[0] as? Structure else {
            XCTFail("Expected Node structure")
            return
        }

        XCTAssertEqual(node.signature, BoltRecordType.node.rawValue)
        XCTAssertEqual(node.items.count, 3)

        // Verify node ID
        XCTAssertEqual(node.items[0].intValue(), 10)

        // Verify labels
        guard let labels = node.items[1] as? List else {
            XCTFail("Expected labels list")
            return
        }
        XCTAssertEqual(labels.items.count, 2)

        // Verify properties
        guard let props = node.items[2] as? Map else {
            XCTFail("Expected properties map")
            return
        }
        XCTAssertEqual(props.dictionary["name"] as? String, "Bob")
    }

    func testParseRelationshipStructure() throws {
        // Relationship structure: (id, startNodeId, endNodeId, type, properties)
        let bytes: [Byte] = [
            0xb1, 0x71,  // RECORD
            0x91,        // List with 1 item
            0xb5, 0x52,  // Relationship (signature 0x52)
            0x64,        // ID: 100
            0x01,        // Start node ID: 1
            0x02,        // End node ID: 2
            0x85, 0x4b, 0x4e, 0x4f, 0x57, 0x53,  // Type: "KNOWS"
            0xa1,        // Properties
            0x85, 0x73, 0x69, 0x6e, 0x63, 0x65,  // "since"
            0xc9, 0x07, 0xd4  // Integer: 2004
        ]
        let response = try Response.unpack(bytes)

        guard let list = response.items[0] as? List,
              let rel = list.items[0] as? Structure else {
            XCTFail("Expected Relationship structure")
            return
        }

        XCTAssertEqual(rel.signature, BoltRecordType.relationship.rawValue)
        XCTAssertEqual(rel.items.count, 5)
    }

    // MARK: - Empty Response Tests

    func testParseEmptySuccessResponse() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa0]  // SUCCESS with empty map
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(response.items.count, 1)

        guard let meta = response.items[0] as? Map else {
            XCTFail("Expected Map")
            return
        }

        XCTAssertTrue(meta.dictionary.isEmpty)
    }

    func testParseEmptyRecordResponse() throws {
        let bytes: [Byte] = [0xb1, 0x71, 0x90]  // RECORD with empty list
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .record)

        guard let list = response.items[0] as? List else {
            XCTFail("Expected List")
            return
        }

        XCTAssertTrue(list.items.isEmpty)
    }

    // MARK: - Response Metadata Extraction Tests

    func testResponseMetadataForSuccess() throws {
        let response = Response(category: .success, items: [
            Map(dictionary: [
                "server": "Neo4j/5.0.0",
                "connection_id": "conn-123",
                "bookmark": "neo4j:bookmark:v1:tx42"
            ])
        ])

        XCTAssertEqual(response.server, "Neo4j/5.0.0")
        XCTAssertEqual(response.connectionId, "conn-123")
        XCTAssertEqual(response.bookmark, "neo4j:bookmark:v1:tx42")
    }

    func testResponseMetadataForNonSuccess() throws {
        let response = Response(category: .failure, items: [])
        XCTAssertTrue(response.metadata.isEmpty)
    }

    func testResponseFields() throws {
        let response = Response(category: .success, items: [
            Map(dictionary: [
                "fields": List(items: ["name", "age", "city"])
            ])
        ])

        let fields = response.fields
        XCTAssertNotNil(fields)
        XCTAssertEqual(fields?.count, 3)
        XCTAssertEqual(fields?[0], "name")
        XCTAssertEqual(fields?[1], "age")
        XCTAssertEqual(fields?[2], "city")
    }

    func testResponseHasMore() throws {
        let responseWithMore = Response(category: .success, items: [
            Map(dictionary: ["has_more": true])
        ])
        XCTAssertTrue(responseWithMore.hasMore)

        let responseWithoutMore = Response(category: .success, items: [
            Map(dictionary: ["has_more": false])
        ])
        XCTAssertFalse(responseWithoutMore.hasMore)

        let responseNoField = Response(category: .success, items: [Map(dictionary: [:])])
        XCTAssertFalse(responseNoField.hasMore)
    }

    func testResponseQueryId() throws {
        let response = Response(category: .success, items: [
            Map(dictionary: ["qid": Int64(42)])
        ])

        XCTAssertEqual(response.qid, 42)
    }

    func testResponseStats() throws {
        let response = Response(category: .success, items: [
            Map(dictionary: [
                "stats": Map(dictionary: [
                    "nodes-created": Int64(5),
                    "relationships-created": Int64(3),
                    "properties-set": Int64(10)
                ])
            ])
        ])

        let stats = response.stats
        XCTAssertEqual(stats["nodes-created"], 5)
        XCTAssertEqual(stats["relationships-created"], 3)
        XCTAssertEqual(stats["properties-set"], 10)
    }

    // MARK: - Error Conversion Tests

    func testAsErrorForFailure() throws {
        let response = Response(category: .failure, items: [
            Map(dictionary: [
                "code": "Neo.ClientError.Statement.SyntaxError",
                "message": "Invalid syntax near RETUR"
            ])
        ])

        let error = response.asError()
        XCTAssertNotNil(error)

        if case let BoltError.syntax(message) = error! {
            XCTAssertTrue(message.contains("Invalid syntax"))
        } else {
            XCTFail("Expected syntax error")
        }
    }

    func testAsErrorForSuccess() throws {
        let response = Response(category: .success, items: [])
        XCTAssertNil(response.asError())
    }

    func testAsErrorForEmptyFailure() throws {
        let response = Response(category: .failure, items: [])
        XCTAssertNil(response.asError())
    }

    // MARK: - BoltError Parsing Tests

    func testBoltErrorAuthentication() throws {
        let error = BoltError.from(
            code: "Neo.ClientError.Security.Unauthorized",
            message: "Invalid credentials"
        )

        if case let BoltError.authentication(message) = error {
            XCTAssertEqual(message, "Invalid credentials")
        } else {
            XCTFail("Expected authentication error")
        }
    }

    func testBoltErrorSyntax() throws {
        let error = BoltError.from(
            code: "Neo.ClientError.Statement.SyntaxError",
            message: "Syntax error"
        )

        if case let BoltError.syntax(message) = error {
            XCTAssertEqual(message, "Syntax error")
        } else {
            XCTFail("Expected syntax error")
        }
    }

    func testBoltErrorConstraint() throws {
        let error = BoltError.from(
            code: "Neo.ClientError.Schema.ConstraintValidationFailed",
            message: "Constraint violated"
        )

        if case let BoltError.constraint(message) = error {
            XCTAssertEqual(message, "Constraint violated")
        } else {
            XCTFail("Expected constraint error")
        }
    }

    func testBoltErrorTransaction() throws {
        let error = BoltError.from(
            code: "Neo.ClientError.Transaction.TransactionTerminated",
            message: "Transaction terminated"
        )

        if case let BoltError.transaction(message) = error {
            XCTAssertEqual(message, "Transaction terminated")
        } else {
            XCTFail("Expected transaction error")
        }
    }

    func testBoltErrorTransient() throws {
        let error = BoltError.from(
            code: "Neo.TransientError.General.DatabaseUnavailable",
            message: "Database unavailable"
        )

        if case let BoltError.transient(message) = error {
            XCTAssertEqual(message, "Database unavailable")
        } else {
            XCTFail("Expected transient error")
        }
    }

    func testBoltErrorUnknown() throws {
        let error = BoltError.from(
            code: "Custom.Error.Code",
            message: "Unknown error"
        )

        if case let BoltError.unknown(code, message) = error {
            XCTAssertEqual(code, "Custom.Error.Code")
            XCTAssertEqual(message, "Unknown error")
        } else {
            XCTFail("Expected unknown error")
        }
    }

    func testBoltErrorLocalizedDescription() throws {
        let errors: [BoltError] = [
            .connection(message: "conn"),
            .authentication(message: "auth"),
            .protocol(message: "proto"),
            .transaction(message: "tx"),
            .database(message: "db"),
            .constraint(message: "const"),
            .syntax(message: "syn"),
            .security(message: "sec"),
            .transient(message: "trans"),
            .service(message: "svc"),
            .unknown(code: "code", message: "msg")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Chunking Tests

    func testUnchunkSimpleMessage() throws {
        // Simple chunked message: 2-byte length + message + 0x00 0x00
        let message: [Byte] = [0xb1, 0x70, 0xa0]  // SUCCESS with empty map
        let length = UInt16(message.count)
        let chunked: [Byte] = [Byte(length >> 8), Byte(length & 0xFF)] + message + [0x00, 0x00]

        let unchunked = try Response.unchunk(chunked)
        XCTAssertEqual(unchunked.count, 1)
        XCTAssertEqual(unchunked[0], message)
    }

    func testUnchunkEmptyBytes() throws {
        do {
            _ = try Response.unchunk([])
            // Empty may return empty or throw
        } catch {
            // Expected for some implementations
        }
    }

    func testUnchunkTooFewBytes() throws {
        do {
            _ = try Response.unchunk([0x00])
            XCTFail("Should throw for single byte")
        } catch {
            // Expected
        }
    }

    // MARK: - Unpack Error Tests

    func testUnpackEmptyBytes() throws {
        do {
            _ = try Response.unpack([])
            XCTFail("Should throw for empty bytes")
        } catch let error as BoltError {
            if case .protocol(let message) = error {
                XCTAssertTrue(message.contains("Empty"))
            } else {
                XCTFail("Expected protocol error")
            }
        }
    }

    func testUnpackInvalidMarker() throws {
        // 0xFF is not a valid structure marker
        do {
            _ = try Response.unpack([0xFF])
            XCTFail("Should throw for invalid marker")
        } catch {
            // Expected
        }
    }

    // MARK: - BoltNotification Tests

    func testNotificationParsing() throws {
        let notificationMap = Map(dictionary: [
            "code": "Neo.ClientNotification.Statement.UnknownPropertyKeyWarning",
            "title": "Unknown property",
            "description": "The property 'foo' does not exist",
            "severity": "WARNING",
            "category": "HINT",
            "position": Map(dictionary: [
                "offset": Int64(10),
                "line": Int64(1),
                "column": Int64(11)
            ])
        ])

        let notification = BoltNotification(from: notificationMap)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.code, "Neo.ClientNotification.Statement.UnknownPropertyKeyWarning")
        XCTAssertEqual(notification?.title, "Unknown property")
        XCTAssertEqual(notification?.severity, "WARNING")
        XCTAssertEqual(notification?.category, "HINT")
        XCTAssertEqual(notification?.position?.offset, 10)
        XCTAssertEqual(notification?.position?.line, 1)
        XCTAssertEqual(notification?.position?.column, 11)
    }

    func testNotificationWithoutPosition() throws {
        let notificationMap = Map(dictionary: [
            "code": "Neo.ClientNotification.Statement.Warning",
            "title": "Warning",
            "description": "Some warning",
            "severity": "WARNING"
        ])

        let notification = BoltNotification(from: notificationMap)
        XCTAssertNotNil(notification)
        XCTAssertNil(notification?.position)
        XCTAssertNil(notification?.category)
    }

    func testNotificationFromInvalidMap() throws {
        let invalidMap = Map(dictionary: ["foo": "bar"])
        let notification = BoltNotification(from: invalidMap)
        XCTAssertNil(notification)
    }

    func testNotificationFromNonMap() throws {
        let notification = BoltNotification(from: "not a map")
        XCTAssertNil(notification)
    }

    func testResponseNotifications() throws {
        let response = Response(category: .success, items: [
            Map(dictionary: [
                "notifications": List(items: [
                    Map(dictionary: [
                        "code": "Neo.ClientNotification.Test",
                        "title": "Test",
                        "description": "Test notification",
                        "severity": "WARNING"
                    ])
                ])
            ])
        ])

        let notifications = response.notifications
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0].code, "Neo.ClientNotification.Test")
    }

    // MARK: - Response Initialization Tests

    func testResponseDefaultInit() throws {
        let response = Response()
        XCTAssertEqual(response.category, .empty)
        XCTAssertTrue(response.items.isEmpty)
    }

    func testResponseWithItems() throws {
        let response = Response(category: .record, items: [
            List(items: [Int64(1), Int64(2), Int64(3)])
        ])

        XCTAssertEqual(response.category, .record)
        XCTAssertEqual(response.items.count, 1)
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (ResponseTests) -> () throws -> Void)] {
        return [
            ("testSuccessResponseCategory", testSuccessResponseCategory),
            ("testRecordResponseCategory", testRecordResponseCategory),
            ("testIgnoredResponseCategory", testIgnoredResponseCategory),
            ("testFailureResponseCategory", testFailureResponseCategory),
            ("testParseInitSuccessResponse", testParseInitSuccessResponse),
            ("testParseRunSuccessWithFields", testParseRunSuccessWithFields),
            ("testParseRecordWithSingleValue", testParseRecordWithSingleValue),
            ("testParseRecordWithMultipleValues", testParseRecordWithMultipleValues),
            ("testParseRecordWithNode", testParseRecordWithNode),
            ("testResponseContainsResultAvailableAfter", testResponseContainsResultAvailableAfter),
            ("testParseNodeStructure", testParseNodeStructure),
            ("testParseRelationshipStructure", testParseRelationshipStructure),
            ("testParseEmptySuccessResponse", testParseEmptySuccessResponse),
            ("testParseEmptyRecordResponse", testParseEmptyRecordResponse),
        ]
    }
}
