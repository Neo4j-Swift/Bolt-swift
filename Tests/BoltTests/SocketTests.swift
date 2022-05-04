import Foundation
import XCTest
import PackStream
import NIO

#if os(Linux)
     import Dispatch
#endif

@testable import Bolt

class SocketTests {
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

        try performAsLoggedIn { (conn) in

            self.perform(conn: conn, exp: exp, statements: statements)
            
        }
        
        testcase.waitForExpectations(timeout: 300000) { (_) in
            print("Done")
        }
    }
    
    func perform(conn: Connection, exp: XCTestExpectation, statements: [String]) {
        
        guard let statement = statements.first else {
            return
        }

        let laterStatements = Array(statements.dropFirst())

        let request = Request.run(statement: statement, parameters: Map(dictionary: [:]))
        
        let promise =  conn.request(request)
        promise.whenSuccess{ responses in

            if responses.count == 0 {
                XCTFail("Unexpected response for \(statement)")
            }

            let request = Request.pullAll()
            let pullPromise = conn.request(request)
            pullPromise.whenSuccess { responses in

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
        
        promise.whenFailure({ (error) in
            if let responseError = error as? Response.ResponseError {
                switch responseError {
                case let Response.ResponseError.forbiddenDueToTransactionType(message):
                    XCTAssertEqual("Cannot perform schema updates in a transaction that has performed data updates.", message)
                default:
                    XCTFail("Expected a response error")
                }
            } else {
                XCTFail(error.localizedDescription)
            }
            exp.fulfill()
        })
    }

    func performAsLoggedIn(block: @escaping (Connection) throws -> Void) throws {

        let conn = Connection(socket: socket, settings: settings)

        do {
            try conn.connect { (error) in
                if let error = error {
                    print("Unknown error while connecting: \(error.localizedDescription)")
                    XCTFail()
                } else {
                    try block(conn)
                }
            }
        } catch let error as Connection.ConnectionError {
            print("Connection error while connecting: \(error.localizedDescription)")
            XCTFail()
        } catch let error {
            print("Unknown error while connecting: \(error.localizedDescription)")
            XCTFail()
        }
    }
    
    func templateMichaels100kCannotFitInATransaction(_ testcase: XCTestCase) throws {
        let stmt1 = "WITH [\"Andres\",\"Wes\",\"Rik\",\"Mark\",\"Peter\",\"Kenny\",\"Michael\",\"Stefan\",\"Max\",\"Chris\"] AS names " +
        "FOREACH (r IN range(0,100000) | CREATE (:User {id:r, name:names[r % size(names)]+\" \"+r}))"
        let stmt2 = "create index on :User(id)"
        let stmt3 = "DROP INDEX ON :User(id)"
        
        let statements = [ "BEGIN", stmt1, stmt2, stmt3, "ROLLBACK" ]

        let exp = testcase.expectation(description: "Test successful")

        try performAsLoggedIn { (conn) in

            self.perform(conn: conn, exp: exp, statements: statements)
            
        }
        
        testcase.waitForExpectations(timeout: 300000) { (_) in
            print("Done")
        }


        /*
        try performAsLoggedIn { (conn: Connection, dispatchGroup) in
            do {
                for statement in [ "BEGIN", stmt1, stmt2, stmt3, "ROLLBACK" ] {

                    if statement == "ROLLBACK" {
                        XCTFail("Should never get here")
                    }

                    let request: Request = Request.run(statement: statement, parameters: Map(dictionary: [:]))
                    dispatchGroup.enter()
                    try conn.request(request)?.whenSuccess { (reponses) in
                        defer {
                            dispatchGroup.leave()
                        }

                        let request = Request.pullAll()
                        dispatchGroup.enter()
                        do {
                            try conn.request(request)?.whenSuccess{ (responses) in
                                dispatchGroup.leave()
                            }
                        } catch(let error) {
                            dispatchGroup.leave()
                            print("Unexpected error while pulling: \(error)")
                        }
                    }
                }
            } catch (let error) {
                dispatchGroup.leave()

                switch error {
                case let Response.ResponseError.forbiddenDueToTransactionType(message):
                    XCTAssertEqual("Cannot perform schema updates in a transaction that has performed data updates.", message)
                default:
                    XCTFail("Expected a response error")
                }
            }

        }
         */
    }

    func templateRubbishCypher(_ testcase: XCTestCase) throws {
        let stmt = "42"
        
        let exp = testcase.expectation(description: "Test successful")

        try performAsLoggedIn { (conn) in

            let request = Request.run(statement: stmt, parameters: Map(dictionary: [:]))
            let promise = conn.request(request)
            promise.whenSuccess{ _ in
                XCTFail("Unexpected response")
                exp.fulfill()
            }
            promise.whenFailure { _ in
                // Happy path
                exp.fulfill()
            }
        }
        
        testcase.waitForExpectations(timeout: 300000) { (_) in
            print("Done")
        }

    }

    func templateUnwind(_ testcase: XCTestCase) {
        
        let exp = testcase.expectation(description: "Test successful")
        
        let stmt = "UNWIND RANGE(1, 10000) AS n RETURN n"

        try? performAsLoggedIn { (conn) in

            let request = Request.run(statement: stmt, parameters: Map(dictionary: [:]))
            let promise = conn.request(request)
            
            promise.whenSuccess { (responses) in

                let request = Request.pullAll()
                conn.request(request).whenSuccess { (responses) in

                    let records = responses.filter { $0.category == .record }
                    XCTAssertEqual(10000, records.count)
                    exp.fulfill()
                }
            }
            
            promise.whenFailure{ error in
                XCTFail(String(describing: error))
                exp.fulfill()
            }
        }

        testcase.waitForExpectations(timeout: 300000) { (_) in
            print("Done")
        }

    }

    func templateUnwindWithToNodes(_ testcase: XCTestCase) {
        
        let exp = testcase.expectation(description: "Test successful")

        let stmt = "UNWIND RANGE(1, 10) AS n RETURN n, n * n as n_sq"

        try? performAsLoggedIn { (conn) in

            let request = Request.run(statement: stmt, parameters: Map(dictionary: [:]))
            let promise = conn.request(request)
            
            promise.whenSuccess { (responses) in
                
                XCTAssertEqual(1, responses.count)
                let fields = (responses[0].items[0] as! Map).dictionary["fields"] as! List
                XCTAssertEqual(2, fields.items.count)


                let request = Request.pullAll()
                conn.request(request).whenSuccess { (responses) in

                    
                    let records = responses.filter { $0.category == .record && ($0.items[0] as! List).items.count == 2 }
                    XCTAssertEqual(10, records.count)

                    exp.fulfill()
                }
            }
            
            promise.whenFailure{ error in
                XCTFail(String(describing: error))
                exp.fulfill()
            }
        }

        testcase.waitForExpectations(timeout: 300000) { (_) in
            print("Done")
        }
    }

}
