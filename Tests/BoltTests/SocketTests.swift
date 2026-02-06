import Foundation
import XCTest
import PackStream
import NIO

#if os(Linux)
import Dispatch
#endif

@testable import Bolt

// Integration test helper - marked as unchecked Sendable since tests manage their own synchronization
final class SocketTests: @unchecked Sendable {
    var settings: ConnectionSettings
    var socket: SocketProtocol

    init(socket: SocketProtocol, settings: ConnectionSettings) {
        self.socket = socket
        self.settings = settings
    }
}

extension SocketTests {

    // source: http://jexp.de/blog/2014/03/quickly-create-a-100k-neo4j-graph-data-model-with-cypher-only/
    func templateMichaels100k(_ testcase: XCTestCase) throws {

        let exp = testcase.expectation(description: "Test successful")

        let stmt1 = "WITH [\"Andres\",\"Wes\",\"Rik\",\"Mark\",\"Peter\",\"Kenny\",\"Michael\",\"Stefan\",\"Max\",\"Chris\"] AS names " +
        "FOREACH (r IN range(0,100000) | CREATE (:User {id:r, name:names[r % size(names)]+\" \"+r}))"
        let stmt2 = "with [\"Mac\",\"iPhone\",\"Das Keyboard\",\"Kymera Wand\",\"HyperJuice Battery\",\"Peachy Printer\",\"HexaAirBot\"," +
            "\"AR-Drone\",\"Sonic Screwdriver\",\"Zentable\",\"PowerUp\"] as names " +
        "foreach (r in range(0,50) | create (:Product {id:r, name:names[r % size(names)]+\" \"+r}))"
        let stmt3 = "match (u:User),(p:Product) with u,p limit 500000 where rand() < 0.1 create (u)-[:OWN]->(p)"
        let stmt4 = "match (u:User),(p:Product)\n" +
            "with u,p\n" +
            "// increase skip value from 0 to 4M in 1M steps\n" +
            "skip 1000000\n" +
            "limit 5000000\n" +
            "where rand() < 0.1\n" +
            "with u,p\n" +
            "limit 100000\n" +
        "merge (u)-[:OWN]->(p);"
        let stmt5 = "create index on :User(id)"
        let stmt6 = "create index on :Product(id)"
        let stmt7 = "match (u:User {id:1})-[:OWN]->()<-[:OWN]-(other)\n" +
            "return other.name,count(*)\n" +
            "order by count(*) desc\n" +
        "limit 5;"
        let stmt8 = "match (u:User {id:3})-[:OWN]->()<-[:OWN]-(other)-[:OWN]->(p) " +
            "return p.name,count(*) " +
            "order by count(*) desc " +
        "limit 5;"
        let stmt9 = "DROP INDEX ON :User(id)"
        let stmt10 = "DROP INDEX ON :Product(id)"
        let stmt11 = "MATCH (n) DETACH DELETE n"


        let statements = [ stmt1, stmt2, stmt3, stmt4, stmt5, stmt6, stmt7, stmt8, stmt9, stmt10, stmt11 ]

        try performAsLoggedIn { conn in
            self.perform(conn: conn, exp: exp, statements: statements)
        }

        testcase.wait(for: [exp], timeout: 300000)
    }

    func perform(conn: Connection, exp: XCTestExpectation, statements: [String]) {

        guard let statement = statements.first else {
            return
        }

        let laterStatements = Array(statements.dropFirst())

        let request = Request.run(statement: statement, parameters: Map(dictionary: [:]))

        let promise = try? conn.request(request)
        promise?.whenSuccess{ responses in

            if responses.count == 0 {
                XCTFail("Unexpected response for \(statement)")
            }

            let request = Request.pullAll()
            let pullPromise = try? conn.request(request)
            pullPromise?.whenSuccess { responses in

                if responses.count == 0 {
                    XCTFail("Unexpected response")
                }

                if laterStatements.count > 0 {
                    self.perform(conn: conn, exp: exp, statements: laterStatements)
                } else {
                    exp.fulfill()
                }
            }
        }

        promise?.whenFailure({ (error) in
            if let responseError = error as? BoltError {
                switch responseError {
                case let .transaction(message):
                    XCTAssertTrue(message.contains("schema updates") || message.contains("transaction"))
                default:
                    XCTFail("Expected a transaction error")
                }
            } else {
                XCTFail(error.localizedDescription)
            }
            exp.fulfill()
        })
    }

    func performAsLoggedIn(block: @escaping @Sendable (Connection) throws -> Void) throws {

        let conn = Connection(socket: socket, settings: settings)

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        try conn.connect { success in
            defer {
                dispatchGroup.leave()
            }

            XCTAssertTrue(success != nil, "Must be logged in successfully")

            try block(conn)
        }
        dispatchGroup.wait()
    }

    /// Async version of performAsLoggedIn that avoids DispatchGroup deadlock with NIO
    func withConnection<T>(_ block: @Sendable (Connection) async throws -> T) async throws -> T {
        let conn = Connection(socket: socket, settings: settings)
        try await conn.connectAsync()
        XCTAssertTrue(conn.isConnected, "Must be logged in successfully")
        return try await block(conn)
    }

    func templateMichaels100kCannotFitInATransaction(_ testcase: XCTestCase) throws {
        let stmt1 = "WITH [\"Andres\",\"Wes\",\"Rik\",\"Mark\",\"Peter\",\"Kenny\",\"Michael\",\"Stefan\",\"Max\",\"Chris\"] AS names " +
        "FOREACH (r IN range(0,100000) | CREATE (:User {id:r, name:names[r % size(names)]+\" \"+r}))"
        let stmt2 = "create index on :User(id)"
        let stmt3 = "DROP INDEX ON :User(id)"

        let statements = [ "BEGIN", stmt1, stmt2, stmt3, "ROLLBACK" ]

        let exp = testcase.expectation(description: "Test successful")

        try performAsLoggedIn { conn in
            self.perform(conn: conn, exp: exp, statements: statements)
        }

        testcase.wait(for: [exp], timeout: 300000)
    }

    func templateRubbishCypher(_ testcase: XCTestCase) throws {
        let stmt = "42"

        let exp = testcase.expectation(description: "Test successful")

        try performAsLoggedIn { conn in

            let request = Request.run(statement: stmt, parameters: Map(dictionary: [:]))
            let promise = try? conn.request(request)
            promise?.whenSuccess{ _ in
                XCTFail("Unexpected response")
                exp.fulfill()
            }
            promise?.whenFailure { _ in
                // Happy path
                exp.fulfill()
            }
        }

        testcase.wait(for: [exp], timeout: 300000)
    }

    func templateUnwind(_ testcase: XCTestCase) {

        let exp = testcase.expectation(description: "Test successful")

        let stmt = "UNWIND RANGE(1, 10000) AS n RETURN n"

        try? performAsLoggedIn { conn in

            let request = Request.run(statement: stmt, parameters: Map(dictionary: [:]))
            let promise = try? conn.request(request)

            promise?.whenSuccess { (responses) in

                let request = Request.pullAll()
                try? conn.request(request)?.whenSuccess { (responses) in

                    let records = responses.filter { $0.category == .record }
                    XCTAssertEqual(10000, records.count)
                    exp.fulfill()
                }
            }

            promise?.whenFailure{ error in
                XCTFail(String(describing: error))
                exp.fulfill()
            }
        }

        testcase.wait(for: [exp], timeout: 300000)
    }

    func templateUnwindWithToNodes(_ testcase: XCTestCase) {

        let exp = testcase.expectation(description: "Test successful")

        let stmt = "UNWIND RANGE(1, 10) AS n RETURN n, n * n as n_sq"

        try? performAsLoggedIn { conn in

            let request = Request.run(statement: stmt, parameters: Map(dictionary: [:]))
            let promise = try? conn.request(request)

            promise?.whenSuccess { (responses) in

                XCTAssertEqual(1, responses.count)
                let fields = (responses[0].items[0] as! Map).dictionary["fields"] as! List
                XCTAssertEqual(2, fields.items.count)


                let request = Request.pullAll()
                try? conn.request(request)?.whenSuccess { (responses) in


                    let records = responses.filter { $0.category == .record && ($0.items[0] as! List).items.count == 2 }
                    XCTAssertEqual(10, records.count)

                    exp.fulfill()
                }
            }

            promise?.whenFailure{ error in
                XCTFail(String(describing: error))
                exp.fulfill()
            }
        }

        testcase.wait(for: [exp], timeout: 300000)
    }

    // MARK: - Async Test Templates

    /// Async version of unwind test - no DispatchGroup deadlock
    func templateUnwindAsync() async throws {
        try await withConnection { conn in
            // Run the query
            let runResponses = try await conn.run("UNWIND RANGE(1, 10000) AS n RETURN n")
            XCTAssertEqual(1, runResponses.count)

            // Pull results
            let pullResponses = try await conn.pull()
            let records = pullResponses.filter { $0.category == .record }
            XCTAssertEqual(10000, records.count)
        }
    }

    /// Async version of unwind with nodes test
    func templateUnwindWithToNodesAsync() async throws {
        try await withConnection { conn in
            let stmt = "UNWIND RANGE(1, 10) AS n RETURN n, n * n as n_sq"

            // Run the query
            let runResponses = try await conn.run(stmt)
            XCTAssertEqual(1, runResponses.count)

            let fields = (runResponses[0].items[0] as! Map).dictionary["fields"] as! List
            XCTAssertEqual(2, fields.items.count)

            // Pull results
            let pullResponses = try await conn.pull()
            let records = pullResponses.filter { $0.category == .record && ($0.items[0] as! List).items.count == 2 }
            XCTAssertEqual(10, records.count)
        }
    }

    /// Async version of rubbish cypher test
    func templateRubbishCypherAsync() async throws {
        try await withConnection { conn in
            do {
                _ = try await conn.run("42")
                XCTFail("Expected error for invalid Cypher")
            } catch {
                // Expected - invalid Cypher should throw
            }
        }
    }

    /// Simple connection test - verifies async connect works
    func templateSimpleConnectionAsync() async throws {
        try await withConnection { conn in
            XCTAssertTrue(conn.isConnected)
            XCTAssertTrue(conn.negotiatedVersion >= .v3)
        }
    }

    /// Test basic query execution with async API
    func templateBasicQueryAsync() async throws {
        try await withConnection { conn in
            // Create a test node
            _ = try await conn.run("CREATE (n:AsyncTest {name: 'test'}) RETURN n")
            _ = try await conn.pull()

            // Query the node
            let runResponses = try await conn.run("MATCH (n:AsyncTest) RETURN n.name as name")
            XCTAssertEqual(1, runResponses.count)

            let pullResponses = try await conn.pull()
            let records = pullResponses.filter { $0.category == .record }
            XCTAssertGreaterThanOrEqual(records.count, 1)

            // Clean up
            _ = try await conn.run("MATCH (n:AsyncTest) DELETE n")
            _ = try await conn.pull()
        }
    }

}

// MARK: - Async Integration Test Class

/// Async integration tests using the new async/await API
class AsyncSocketTests: XCTestCase, @unchecked Sendable {
    var socketTests: SocketTests?

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        do {
            let config = TestConfig.loadConfig()
            let socket = try UnencryptedSocket(hostname: config.hostname, port: config.port)
            let settings = ConnectionSettings(username: config.username, password: config.password, userAgent: "BoltAsyncTests")
            self.socketTests = SocketTests(socket: socket, settings: settings)
        } catch {
            XCTFail("Cannot have exceptions during socket initialization: \(error)")
        }
    }

    // Note: allTests not needed for async tests - XCTest discovers them automatically

    func testSimpleConnectionAsync() async throws {
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateSimpleConnectionAsync()
    }

    func testUnwindAsync() async throws {
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateUnwindAsync()
    }

    func testUnwindWithToNodesAsync() async throws {
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateUnwindWithToNodesAsync()
    }

    func testRubbishCypherAsync() async throws {
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateRubbishCypherAsync()
    }

    func testBasicQueryAsync() async throws {
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateBasicQueryAsync()
    }
}
