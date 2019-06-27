import XCTest
import PackStream

#if os(Linux)
    import Dispatch
#endif

@testable import Bolt

class BoltTests: XCTestCase {

    func testConnection() throws {
        let config = TestConfig.loadConfig()

        let connectionExp = expectation(description: "Login successful")

        let settings = ConnectionSettings(username: config.username, password: config.password)
        let socket = try UnencryptedSocket(hostname: config.hostname, port: config.port)
        let conn = Connection(socket: socket, settings: settings)
        try conn.connect { (success) in
            do {
                if success == true {
                    connectionExp.fulfill()
                    let _ = try self.createNode(connection: conn)
                }
            } catch(let error) {
                XCTFail("Did not expect any errors, but got \(error)")
            }
        }

        self.waitForExpectations(timeout: 300000) { (_) in
            print("Done")
        }

    }
    
    func testMeasureUnwind() {
        measure {
            do {
                try testUnwind()
            } catch {
                XCTFail("Test failed")
            }
        }
    }
    
    func testUnwind() throws {
        let config = TestConfig.loadConfig()
        
        let connectionExp = expectation(description: "Login successful")
        
        let settings = ConnectionSettings(username: config.username, password: config.password)
        let socket = try UnencryptedSocket(hostname: config.hostname, port: config.port)
        let conn = Connection(socket: socket, settings: settings)
        try conn.connect { (success) in
            do {
                if success == true {
                    connectionExp.fulfill()
                    let _ = try self.unwind(connection: conn)
                }
            } catch(let error) {
                XCTFail("Did not expect any errors, but got \(error)")
            }
        }
        
        self.waitForExpectations(timeout: 10) { (_) in
            print("Done")
        }
        
    }
    
    func unwind(connection conn: Connection) throws -> XCTestExpectation {
        
        let cypherExp = expectation(description: "Perform cypher query")

        let statement = "UNWIND range(1, 10000) AS n RETURN n"
        
        let request = Request.run(statement: statement, parameters: Map(dictionary: [:]))
        try conn.request(request) { (success, _) in
            do {
                if success {
                    cypherExp.fulfill()
                    _ = try self.pullResultsExpectingAtLeastNumberOfResults(num: 10000 - 1, connection: conn)
                    
                }
            } catch(let error) {
                XCTFail("Did not expect any errors, but got \(error)")
            }
        }
        
        return cypherExp
    }

    func createNode(connection conn: Connection) throws -> XCTestExpectation {

        let cypherExp = expectation(description: "Perform cypher query")

        let statement = "CREATE (n:FirstNode {name:{name}}) RETURN n"
        let parameters = Map(dictionary: [ "name": "Steven" ])
        let request = Request.run(statement: statement, parameters: parameters)
        try conn.request(request) { (success, _) in
            do {
                if success {
                    cypherExp.fulfill()
                    let _ = try self.pullResults(connection: conn)
                }
            } catch(let error) {
                XCTFail("Did not expect any errors, but got \(error)")
            }
        }

        return cypherExp
    }

    func pullResults(connection conn: Connection) throws -> XCTestExpectation {
        return try pullResultsExpectingAtLeastNumberOfResults(num: 0, connection: conn)
    }
    
    
    func pullResultsExpectingAtLeastNumberOfResults(num: Int, connection conn: Connection) throws -> XCTestExpectation {

        let pullAllExp = expectation(description: "Perform pull All")

        let request = Request.pullAll()
        try conn.request(request) { (success, responses) in
            if responses.count > num && success == true {
                pullAllExp.fulfill()
            } else {
                XCTFail("Did not find sufficient amount of results. Found \(responses.count) instead of \(num)")
                pullAllExp.fulfill()
            }
        }

        return pullAllExp
    }

    static var allTests: [(String, (BoltTests) -> () throws -> Void)] {
        return [
            ("testConnection", testConnection),
            ("testUnpackInitResponse", testUnpackInitResponse),
            ("testUnpackEmptyRequestResponse", testUnpackEmptyRequestResponse),
            ("testUnpackRequestResponseWithNode", testUnpackRequestResponseWithNode),
            ("testUnpackPullAllRequestAfterCypherRequest", testUnpackPullAllRequestAfterCypherRequest),
        ]
    }

    func testUnpackInitResponse() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa1, 0x86, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x8b, 0x4e, 0x65, 0x6f, 0x34, 0x6a, 0x2f, 0x33, 0x2e, 0x31, 0x2e, 0x31]
        let response = try Response.unpack(bytes)

        // Expected: SUCCESS
        // server: Neo4j/3.1.1

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)
        guard let properties = response.items[0] as? Map else {
            XCTFail("Response metadata should be a Map")
            return
        }

        XCTAssertEqual(1, properties.dictionary.count)
        XCTAssertEqual("Neo4j/3.1.1", properties.dictionary["server"] as! String)
    }

    func testUnpackEmptyRequestResponse() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa2, 0xd0, 0x16, 0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72, 0x1, 0x86, 0x66, 0x69, 0x65, 0x6c, 0x64, 0x73, 0x90]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)

        // Expected: SUCCESS
        // result_available_after: 1 (ms)
        // fields: [] (empty List)

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)
        guard let properties = response.items[0] as? Map,
            let fields = properties.dictionary["fields"] as? List else {
                XCTFail("Response metadata should be a Map")
                return
        }

        XCTAssertEqual(0, fields.items.count)
        XCTAssertEqual(1, properties.dictionary["result_available_after"]?.asUInt64())

    }

    func testUnpackRequestResponseWithNode() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa2, 0xd0, 0x16, 0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72, 0x2, 0x86, 0x66, 0x69, 0x65, 0x6c, 0x64, 0x73, 0x91, 0x81, 0x6e]
        let response = try Response.unpack(bytes)

        // Expected: SUCCESS
        // result_available_after: 2 (ms)
        // fields: ["n"]

        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)
        guard let properties = response.items[0] as? Map,
            let fields = properties.dictionary["fields"] as? List else {
                XCTFail("Response metadata should be a Map")
                return
        }

        XCTAssertEqual(1, fields.items.count)
        XCTAssertEqual("n", fields.items[0] as! String)
        XCTAssertEqual(2, properties.dictionary["result_available_after"]?.asUInt64())

    }

    func testUnpackPullAllRequestAfterCypherRequest() throws {
        let bytes: [Byte] = [0xb1, 0x71, 0x91, 0xb3, 0x4e, 0x12, 0x91, 0x89, 0x46, 0x69, 0x72, 0x73, 0x74, 0x4e, 0x6f, 0x64, 0x65, 0xa1, 0x84, 0x6e, 0x61, 0x6d, 0x65, 0x86, 0x53, 0x74, 0x65, 0x76, 0x65, 0x6e]
        let response = try Response.unpack(bytes)

        // Expected: Record with one Node (ID 18)
        // label: FirstNode
        // props: "name" = "Steven"

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
        XCTAssertEqual("Steven", propertyValue as! String)
    }

}

struct Node {

    public let id: UInt64
    public let labels: [String]
    public let properties: [String: PackProtocol]

}


extension Response {
    func asNode() -> Node? {
        if category != .record ||
            items.count != 1 {
            return nil
        }

        let list = items[0] as? List
        guard let items = list?.items,
            items.count == 1,

            let structure = items[0] as? Structure,
            structure.signature == Response.RecordType.node,
            structure.items.count == 3,

            let nodeId = structure.items.first?.asUInt64(),
            let labelList = structure.items[1] as? List,
            let labels = labelList.items as? [String],
            let propertyMap = structure.items[2] as? Map
            else {
                return nil
        }

        let properties = propertyMap.dictionary

        let node = Node(id: UInt64(nodeId), labels: labels, properties: properties)
        return node
    }
}
