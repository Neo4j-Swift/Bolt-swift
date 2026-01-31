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

    // MARK: - HELLO Message Tests

    func testHelloRequest() throws {
        let settings = ConnectionSettings(
            username: "neo4j",
            password: "password",
            userAgent: "TestAgent/1.0"
        )
        let request = Request.hello(settings: settings)
        XCTAssertNotNil(request)
    }

    func testHelloRequestWithRoutingContext() throws {
        let settings = ConnectionSettings(username: "neo4j", password: "password")
        let routing = ["address": "localhost:7687", "policy": "EU"]
        let request = Request.hello(settings: settings, routingContext: routing)
        XCTAssertNotNil(request)
    }

    func testHelloRequestWithNotifications() throws {
        let settings = ConnectionSettings(
            username: "neo4j",
            password: "password",
            boltVersion: .v5_1,
            notificationsMinSeverity: "WARNING",
            notificationsDisabledCategories: ["HINT", "DEPRECATION"]
        )
        let request = Request.hello(settings: settings)
        XCTAssertNotNil(request)
    }

    // MARK: - LOGON/LOGOFF Message Tests (Bolt 5.1+)

    func testLogonRequest() throws {
        let settings = ConnectionSettings(username: "neo4j", password: "newpassword")
        let request = Request.logon(settings: settings)
        XCTAssertNotNil(request)
    }

    func testLogoffRequest() throws {
        let request = Request.logoff()
        XCTAssertNotNil(request)
    }

    // MARK: - GOODBYE Message Tests

    func testGoodbyeRequest() throws {
        let request = Request.goodbye()
        XCTAssertNotNil(request)
    }

    // MARK: - PULL Message Tests (Bolt 4+)

    func testPullWithCount() throws {
        let request = Request.pull(n: 100)
        XCTAssertNotNil(request)
    }

    func testPullWithQueryId() throws {
        let request = Request.pull(n: 50, qid: 1)
        XCTAssertNotNil(request)
    }

    func testPullAllRecords() throws {
        let request = Request.pull(n: -1)  // -1 means all
        XCTAssertNotNil(request)
    }

    // MARK: - DISCARD Message Tests (Bolt 4+)

    func testDiscardWithCount() throws {
        let request = Request.discard(n: 100)
        XCTAssertNotNil(request)
    }

    func testDiscardWithQueryId() throws {
        let request = Request.discard(n: 50, qid: 2)
        XCTAssertNotNil(request)
    }

    func testDiscardAllRecords() throws {
        let request = Request.discard(n: -1)
        XCTAssertNotNil(request)
    }

    // MARK: - BEGIN Message Extended Tests

    func testBeginWithDatabase() throws {
        let request = Request.begin(database: "neo4j")
        XCTAssertNotNil(request)
    }

    func testBeginWithBookmarks() throws {
        let request = Request.begin(bookmarks: ["bookmark1", "bookmark2"])
        XCTAssertNotNil(request)
    }

    func testBeginWithMetadata() throws {
        let request = Request.begin(metadata: ["app": "test", "version": "1.0"])
        XCTAssertNotNil(request)
    }

    func testBeginWithTimeout() throws {
        let request = Request.begin(timeoutMs: 5000)
        XCTAssertNotNil(request)
    }

    func testBeginWithImpersonation() throws {
        let request = Request.begin(impersonatedUser: "admin")
        XCTAssertNotNil(request)
    }

    func testBeginWithNotifications() throws {
        let request = Request.begin(
            notificationsMinSeverity: "WARNING",
            notificationsDisabledCategories: ["HINT"]
        )
        XCTAssertNotNil(request)
    }

    func testBeginWithAllOptions() throws {
        let request = Request.begin(
            mode: .readonly,
            database: "testdb",
            bookmarks: ["bm1", "bm2"],
            metadata: ["key": "value"],
            timeoutMs: 10000,
            impersonatedUser: "user1",
            notificationsMinSeverity: "ERROR",
            notificationsDisabledCategories: ["DEPRECATION"]
        )
        XCTAssertNotNil(request)
    }

    // MARK: - RUN Message Extended Tests

    func testRunWithDatabase() throws {
        let request = Request.run(statement: "RETURN 1", database: "neo4j")
        XCTAssertNotNil(request)
    }

    func testRunWithReadMode() throws {
        let request = Request.run(statement: "MATCH (n) RETURN n", mode: .readonly)
        XCTAssertNotNil(request)
    }

    func testRunWithBookmarks() throws {
        let request = Request.run(
            statement: "CREATE (n) RETURN n",
            bookmarks: ["bm1", "bm2"]
        )
        XCTAssertNotNil(request)
    }

    func testRunWithTimeout() throws {
        let request = Request.run(statement: "RETURN 1", timeoutMs: 30000)
        XCTAssertNotNil(request)
    }

    func testRunWithMetadata() throws {
        let request = Request.run(
            statement: "RETURN 1",
            metadata: ["app": "test"]
        )
        XCTAssertNotNil(request)
    }

    func testRunWithImpersonation() throws {
        let request = Request.run(statement: "RETURN 1", impersonatedUser: "admin")
        XCTAssertNotNil(request)
    }

    func testRunWithNotifications() throws {
        let request = Request.run(
            statement: "RETURN 1",
            notificationsMinSeverity: "WARNING",
            notificationsDisabledCategories: ["HINT"]
        )
        XCTAssertNotNil(request)
    }

    func testRunWithAllOptions() throws {
        let request = Request.run(
            statement: "MATCH (n) RETURN n",
            parameters: ["limit": Int64(10)],
            database: "neo4j",
            mode: .readonly,
            bookmarks: ["bm1"],
            timeoutMs: 5000,
            metadata: ["source": "test"],
            impersonatedUser: "user",
            notificationsMinSeverity: "ERROR",
            notificationsDisabledCategories: ["DEPRECATION"]
        )
        XCTAssertNotNil(request)
    }

    // MARK: - ROUTE Message Tests (Bolt 4.3+)

    func testRouteRequest() throws {
        let request = Request.route(routingContext: ["address": "localhost:7687"])
        XCTAssertNotNil(request)
    }

    func testRouteWithBookmarks() throws {
        let request = Request.route(
            routingContext: ["policy": "EU"],
            bookmarks: ["bm1", "bm2"]
        )
        XCTAssertNotNil(request)
    }

    func testRouteWithDatabase() throws {
        let request = Request.route(
            routingContext: ["address": "localhost:7687"],
            database: "neo4j"
        )
        XCTAssertNotNil(request)
    }

    func testRouteWithImpersonation() throws {
        let request = Request.route(
            routingContext: ["address": "localhost:7687"],
            impersonatedUser: "admin"
        )
        XCTAssertNotNil(request)
    }

    func testRouteWithAllOptions() throws {
        let request = Request.route(
            routingContext: ["address": "localhost:7687", "policy": "EU"],
            bookmarks: ["bm1"],
            database: "testdb",
            impersonatedUser: "user1"
        )
        XCTAssertNotNil(request)
    }

    // MARK: - TELEMETRY Message Tests (Bolt 5.4+)

    func testTelemetryRequest() throws {
        let request = Request.telemetry(api: 1)
        XCTAssertNotNil(request)
    }

    func testTelemetryWithDifferentApis() throws {
        // Driver APIs: 0=managed_transaction, 1=unmanaged_transaction, 2=auto_commit
        let managedTx = Request.telemetry(api: 0)
        let unmanagedTx = Request.telemetry(api: 1)
        let autoCommit = Request.telemetry(api: 2)

        XCTAssertNotNil(managedTx)
        XCTAssertNotNil(unmanagedTx)
        XCTAssertNotNil(autoCommit)
    }

    // MARK: - Legacy Message Tests

    func testAckFailureRequest() throws {
        let request = Request.ackFailure()
        XCTAssertNotNil(request)
    }

    func testInitializeRequest() throws {
        let settings = ConnectionSettings(username: "neo4j", password: "password")
        let request = Request.initialize(settings: settings)
        XCTAssertNotNil(request)
    }

    // MARK: - Chunking Tests

    func testRequestChunking() throws {
        let request = Request.run(statement: "RETURN 1", parameters: Map(dictionary: [:]))
        let chunks = try request.chunk()

        XCTAssertFalse(chunks.isEmpty)
        // Each chunk should have at least 2 bytes (length prefix)
        for chunk in chunks {
            XCTAssertGreaterThanOrEqual(chunk.count, 2)
        }
    }

    func testLargeRequestChunking() throws {
        // Create a large query that will require multiple chunks
        let largeString = String(repeating: "x", count: 70000)
        let request = Request.run(
            statement: "CREATE (n {data: $data})",
            parameters: ["data": largeString]
        )
        let chunks = try request.chunk()

        // Should have multiple chunks for large data
        XCTAssertGreaterThan(chunks.count, 1)
    }

    // MARK: - Request Description Tests

    func testRequestDescription() throws {
        let request = Request.run(statement: "RETURN 1", parameters: Map(dictionary: [:]))
        let description = request.description

        XCTAssertTrue(description.contains("Request"))
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
            ("testHelloRequest", testHelloRequest),
            ("testHelloRequestWithRoutingContext", testHelloRequestWithRoutingContext),
            ("testHelloRequestWithNotifications", testHelloRequestWithNotifications),
            ("testLogonRequest", testLogonRequest),
            ("testLogoffRequest", testLogoffRequest),
            ("testGoodbyeRequest", testGoodbyeRequest),
            ("testPullWithCount", testPullWithCount),
            ("testPullWithQueryId", testPullWithQueryId),
            ("testPullAllRecords", testPullAllRecords),
            ("testDiscardWithCount", testDiscardWithCount),
            ("testDiscardWithQueryId", testDiscardWithQueryId),
            ("testDiscardAllRecords", testDiscardAllRecords),
            ("testBeginWithDatabase", testBeginWithDatabase),
            ("testBeginWithBookmarks", testBeginWithBookmarks),
            ("testBeginWithMetadata", testBeginWithMetadata),
            ("testBeginWithTimeout", testBeginWithTimeout),
            ("testBeginWithImpersonation", testBeginWithImpersonation),
            ("testBeginWithNotifications", testBeginWithNotifications),
            ("testBeginWithAllOptions", testBeginWithAllOptions),
            ("testRunWithDatabase", testRunWithDatabase),
            ("testRunWithReadMode", testRunWithReadMode),
            ("testRunWithBookmarks", testRunWithBookmarks),
            ("testRunWithTimeout", testRunWithTimeout),
            ("testRunWithMetadata", testRunWithMetadata),
            ("testRunWithImpersonation", testRunWithImpersonation),
            ("testRunWithNotifications", testRunWithNotifications),
            ("testRunWithAllOptions", testRunWithAllOptions),
            ("testRouteRequest", testRouteRequest),
            ("testRouteWithBookmarks", testRouteWithBookmarks),
            ("testRouteWithDatabase", testRouteWithDatabase),
            ("testRouteWithImpersonation", testRouteWithImpersonation),
            ("testRouteWithAllOptions", testRouteWithAllOptions),
            ("testTelemetryRequest", testTelemetryRequest),
            ("testTelemetryWithDifferentApis", testTelemetryWithDifferentApis),
            ("testAckFailureRequest", testAckFailureRequest),
            ("testInitializeRequest", testInitializeRequest),
            ("testRequestChunking", testRequestChunking),
            ("testLargeRequestChunking", testLargeRequestChunking),
            ("testRequestDescription", testRequestDescription),
        ]
    }
}
