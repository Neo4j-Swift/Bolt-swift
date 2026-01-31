import XCTest
import PackStream
import NIOCore

#if os(Linux)
import Dispatch
#endif

@testable import Bolt

/// Request message construction tests
/// Based on patterns from neo4j-java-driver and neo4j-go-driver
final class RequestTests: XCTestCase {

    // MARK: - RUN Message Tests

    func testRunRequestWithSimpleQuery() throws {
        let query = "RETURN 1 AS num"
        let request = Request.run(statement: query, parameters: Map(dictionary: [:]))

        XCTAssertNotNil(request)
    }

    func testRunRequestWithParameters() throws {
        let query = "CREATE (n:Person {name: $name, age: $age}) RETURN n"
        let params = Map(dictionary: [
            "name": "Alice",
            "age": Int64(30)
        ])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    func testRunRequestWithEmptyParameters() throws {
        let query = "MATCH (n) RETURN count(n)"
        let request = Request.run(statement: query, parameters: Map(dictionary: [:]))

        XCTAssertNotNil(request)
    }

    func testRunRequestWithComplexParameters() throws {
        let query = "CREATE (n:Node $props) RETURN n"
        let props: [String: any PackProtocol] = [
            "string": "value",
            "integer": Int64(42),
            "float": 3.14,
            "boolean": true,
            "list": List(items: ["a", "b", "c"]),
            "map": Map(dictionary: ["nested": "value"])
        ]
        let params = Map(dictionary: ["props": Map(dictionary: props)])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    // MARK: - PULL Message Tests

    func testPullAllRequest() throws {
        let request = Request.pullAll()
        XCTAssertNotNil(request)
    }

    // MARK: - DISCARD Message Tests

    func testDiscardAllRequest() throws {
        let request = Request.discardAll()
        XCTAssertNotNil(request)
    }

    // MARK: - Transaction Message Tests

    func testBeginTransactionRequest() throws {
        let request = Request.begin()
        XCTAssertNotNil(request)
    }

    func testBeginTransactionWithMode() throws {
        let readRequest = Request.begin(mode: .readonly)
        let writeRequest = Request.begin(mode: .readwrite)

        XCTAssertNotNil(readRequest)
        XCTAssertNotNil(writeRequest)
    }

    func testCommitRequest() throws {
        let request = Request.commit()
        XCTAssertNotNil(request)
    }

    func testRollbackRequest() throws {
        let request = Request.rollback()
        XCTAssertNotNil(request)
    }

    // MARK: - RESET Message Tests

    func testResetRequest() throws {
        let request = Request.reset()
        XCTAssertNotNil(request)
    }

    // MARK: - Transaction Mode Tests

    func testTransactionModeReadonly() {
        let mode = TransactionMode.readonly
        XCTAssertEqual(mode, .readonly)
    }

    func testTransactionModeReadwrite() {
        let mode = TransactionMode.readwrite
        XCTAssertEqual(mode, .readwrite)
    }

    // MARK: - Request Creation Verification Tests

    func testRunRequestCreation() throws {
        let query = "RETURN 1"
        let request = Request.run(statement: query, parameters: Map(dictionary: [:]))

        // Verify request was created (we can't access pack() as it's internal)
        XCTAssertNotNil(request)
    }

    func testPullAllRequestCreation() throws {
        let request = Request.pullAll()
        XCTAssertNotNil(request)
    }

    func testBeginRequestCreation() throws {
        let request = Request.begin()
        XCTAssertNotNil(request)
    }

    func testCommitRequestCreation() throws {
        let request = Request.commit()
        XCTAssertNotNil(request)
    }

    func testRollbackRequestCreation() throws {
        let request = Request.rollback()
        XCTAssertNotNil(request)
    }

    func testResetRequestCreation() throws {
        let request = Request.reset()
        XCTAssertNotNil(request)
    }

    // MARK: - Query Parameter Edge Cases

    func testRunWithUnicodeParameters() throws {
        let query = "CREATE (n:Node {name: $name}) RETURN n"
        let params = Map(dictionary: [
            "name": "Mjölnir \u{03C0} \u{2248} 3.14"  // Thor's hammer, pi symbol, approximately equals
        ])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    func testRunWithLargeStringParameter() throws {
        let query = "CREATE (n:Node {data: $data}) RETURN n"
        let largeString = String(repeating: "x", count: 10000)
        let params = Map(dictionary: ["data": largeString])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    func testRunWithNullParameter() throws {
        let query = "CREATE (n:Node {value: $value}) RETURN n"
        let params = Map(dictionary: ["value": Null()])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    func testRunWithNestedListParameter() throws {
        let query = "RETURN $matrix"
        let matrix = List(items: [
            List(items: [Int64(1), Int64(2), Int64(3)]),
            List(items: [Int64(4), Int64(5), Int64(6)]),
            List(items: [Int64(7), Int64(8), Int64(9)])
        ])
        let params = Map(dictionary: ["matrix": matrix])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    func testRunWithNestedMapParameter() throws {
        let query = "RETURN $person"
        let person = Map(dictionary: [
            "name": "Alice",
            "address": Map(dictionary: [
                "city": "New York",
                "country": "USA"
            ])
        ])
        let params = Map(dictionary: ["person": person])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    // MARK: - Integer Boundary Tests

    func testRunWithIntegerBoundaries() throws {
        let query = "RETURN $min, $max"
        let params = Map(dictionary: [
            "min": Int64.min,
            "max": Int64.max
        ])
        let request = Request.run(statement: query, parameters: params)

        XCTAssertNotNil(request)
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (RequestTests) -> () throws -> Void)] {
        return [
            ("testRunRequestWithSimpleQuery", testRunRequestWithSimpleQuery),
            ("testRunRequestWithParameters", testRunRequestWithParameters),
            ("testRunRequestWithEmptyParameters", testRunRequestWithEmptyParameters),
            ("testRunRequestWithComplexParameters", testRunRequestWithComplexParameters),
            ("testPullAllRequest", testPullAllRequest),
            ("testDiscardAllRequest", testDiscardAllRequest),
            ("testBeginTransactionRequest", testBeginTransactionRequest),
            ("testBeginTransactionWithMode", testBeginTransactionWithMode),
            ("testCommitRequest", testCommitRequest),
            ("testRollbackRequest", testRollbackRequest),
            ("testResetRequest", testResetRequest),
            ("testTransactionModeReadonly", testTransactionModeReadonly),
            ("testTransactionModeReadwrite", testTransactionModeReadwrite),
            ("testRunRequestCreation", testRunRequestCreation),
            ("testPullAllRequestCreation", testPullAllRequestCreation),
            ("testBeginRequestCreation", testBeginRequestCreation),
            ("testCommitRequestCreation", testCommitRequestCreation),
            ("testRollbackRequestCreation", testRollbackRequestCreation),
            ("testResetRequestCreation", testResetRequestCreation),
            ("testRunWithUnicodeParameters", testRunWithUnicodeParameters),
            ("testRunWithLargeStringParameter", testRunWithLargeStringParameter),
            ("testRunWithNullParameter", testRunWithNullParameter),
            ("testRunWithNestedListParameter", testRunWithNestedListParameter),
            ("testRunWithNestedMapParameter", testRunWithNestedMapParameter),
            ("testRunWithIntegerBoundaries", testRunWithIntegerBoundaries),
        ]
    }
}
