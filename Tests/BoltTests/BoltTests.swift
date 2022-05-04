import XCTest
import PackStream
import NIO

#if os(Linux)
import Dispatch
#endif

@testable import Bolt

class BoltTests: XCTestCase {
    
    var eventLoopGroup: MultiThreadedEventLoopGroup! = nil
    
    override func setUp() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    func testConnection() throws {
        let config = TestConfig.loadConfig()
        
        let connectionExp = expectation(description: "Login successful")
        
        let settings = ConnectionSettings(username: config.username, password: config.password)
        let socket = try UnencryptedSocket(hostname: config.hostname, port: config.port)
        let conn = Connection(socket: socket, settings: settings)
        try conn.connect { (error) in
            if let error = error {
                XCTFail("Could not connect successfully: \(String(describing: error))")
                connectionExp.fulfill()
            } else {
                self.createNode(connection: conn) { _ in
                    connectionExp.fulfill()
                }
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
        try conn.connect { (error) in
            if error == nil {
                self.unwind(connection: conn) { _ in
                    connectionExp.fulfill()
                }
            }
        }
        
        self.waitForExpectations(timeout: 10) { (_) in
            print("Done")
        }
        
    }
    
    func testUnwindEncrypted() throws {
        let config = TestConfig.loadConfig()
        let connectionExp = expectation(description: "Login successful")
        
        let settings = ConnectionSettings(username: config.username, password: config.password)
        let socket = try EncryptedSocket(hostname: config.hostname, port: config.port)
        socket.certificateValidator = UnsecureCertificateValidator(hostname: config.hostname, port: UInt(config.port))
        let conn = Connection(socket: socket, settings: settings)
        try conn.connect { (error) in
            if error == nil {
                self.unwind(connection: conn) { _ in
                    connectionExp.fulfill()
                }
            }
        }
        
        self.waitForExpectations(timeout: 10) { (_) in
            print("Done")
        }
        
    }
    
    func testPackstream1() throws {
        let bytes: [Byte] = [ 0xb1, 0x70, 0xa2, 0x86, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x8b, 0x4e, 0x65, 0x6f, 0x34, 0x6a, 0x2f, 0x34, 0x2e, 0x30, 0x2e, 0x34, 0x8d, 0x63, 0x6f, 0x6e, 0x6e, 0x65, 0x63, 0x74, 0x69, 0x6f, 0x6e, 0x5f, 0x69, 0x64, 0x88, 0x62, 0x6f, 0x6c, 0x74, 0x2d, 0x36, 0x37, 0x34, 0x00, 0x00]
        let s = try Structure.unpack(bytes)
        print(String(describing: s))
    }
    
    func testPackstream2() throws {
        let bytes: [Byte] = [ 0xb1, 0x01, 0xa4, 0x8a, 0x75, 0x73, 0x65, 0x72, 0x5f, 0x61, 0x67, 0x65, 0x6e, 0x74, 0xd0, 0x32, 0x6e, 0x65, 0x6f, 0x34, 0x6a, 0x2d, 0x70, 0x79, 0x74, 0x68, 0x6f, 0x6e, 0x2f, 0x34, 0x2e, 0x30, 0x2e, 0x30, 0x61, 0x33, 0x20, 0x50, 0x79, 0x74, 0x68, 0x6f, 0x6e, 0x2f, 0x33, 0x2e, 0x37, 0x2e, 0x37, 0x2d, 0x66, 0x69, 0x6e, 0x61, 0x6c, 0x2d, 0x30, 0x20, 0x28, 0x64, 0x61, 0x72, 0x77, 0x69, 0x6e, 0x29, 0x86, 0x73, 0x63, 0x68, 0x65, 0x6d, 0x65, 0x85, 0x62, 0x61, 0x73, 0x69, 0x63, 0x89, 0x70, 0x72, 0x69, 0x6e, 0x63, 0x69, 0x70, 0x61, 0x6c, 0x85, 0x6e, 0x65, 0x6f, 0x34, 0x6a, 0x8b, 0x63, 0x72, 0x65, 0x64, 0x65, 0x6e, 0x74, 0x69, 0x61, 0x6c, 0x73, 0x84, 0x74, 0x65, 0x73, 0x74, 0x00, 0x00]
        let s = try Structure.unpack(bytes)
        print(String(describing: s))
    }
    
    func unwind(connection conn: Connection, completion: @escaping (Bool) -> ()) {
        
        let statement = "UNWIND range(1, 10000) AS n RETURN n"
        
        let request = Request.run(statement: statement, parameters: Map(dictionary: [:]))
        conn.request(request).whenSuccess { _ in
            self.pullResultsExpectingAtLeastNumberOfResults(num: 10000 - 1, connection: conn) { success in
                completion(success)
            }
        }
        
        
    }
    
    func createNode(connection conn: Connection, completion: @escaping (Bool) -> ()) {
        
        conn.readOnlyMode {
            
            let statement = "CREATE (n:FirstNode {name:$name}) RETURN n"
            let parameters = Map(dictionary: [ "name": "Steven" ])
            let request = Request.run(statement: statement, parameters: parameters)
            conn.request(request).whenSuccess { _ in
                self.pullResults(connection: conn) { _ in
                    completion(true)
                }
            }
        }
    }
    
    func pullResults(connection conn: Connection, completion: @escaping (Bool) -> ()) {
        return pullResultsExpectingAtLeastNumberOfResults(num: 0, connection: conn, completion: completion)
    }
    
    func pullResultsExpectingAtLeastNumberOfResults(num: Int, connection conn: Connection, completion: @escaping (Bool) -> ()) {
        
        let request = Request.pullAll()
        conn.request(request).whenSuccess { responses in
            if responses.count > num {
                completion(true)
            } else {
                XCTFail("Did not find sufficient amount of results. Found \(responses.count) instead of \(num)")
                completion(false)
            }
        }
    }
    
    static var allTests: [(String, (BoltTests) -> () throws -> Void)] {
        return [
            ("testConnection", testConnection),
            ("testUnpackInitResponse", testUnpackInitResponse),
            ("testUnpackEmptyRequestResponse", testUnpackEmptyRequestResponse),
            ("testUnpackRequestResponseWithNode", testUnpackRequestResponseWithNode),
            ("testUnpackPullAllRequestAfterCypherRequest", testUnpackPullAllRequestAfterCypherRequest)
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
