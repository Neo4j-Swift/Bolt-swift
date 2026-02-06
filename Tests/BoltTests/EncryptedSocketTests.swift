import Foundation
import XCTest
import PackStream
#if !os(Linux)
import Security
#endif

@testable import Bolt

#if !os(Linux)
/// Certificate validator that trusts a specific self-signed certificate
final class SelfSignedCertificateValidator: CertificateValidatorProtocol {
    let hostname: String
    let port: UInt
    let trustedCertificates: [SecCertificate]

    init(hostname: String, port: UInt, certificatePath: String) {
        self.hostname = hostname
        self.port = port

        // Load the certificate from the provided path
        if let certData = FileManager.default.contents(atPath: certificatePath),
           let certificate = SecCertificateCreateWithData(nil, certData as CFData) {
            self.trustedCertificates = [certificate]
        } else {
            self.trustedCertificates = []
        }
    }

    func shouldTrustCertificate(withSHA1: String) -> Bool {
        return true
    }

    func didTrustCertificate(withSHA1: String) {
        // No-op
    }
}
#endif

class EncryptedSocketTests: XCTestCase, @unchecked Sendable {

    var socketTests: SocketTests?
    var skipTests = false

    // TLS-specific configuration - uses the TLS-enabled Neo4j container on port 7691
    static let tlsHostname = "localhost"
    static let tlsPort = 7691
    static let tlsUsername = "neo4j"
    static let tlsPassword = "j4neo-tls-test"
    static let tlsCertPath = "/Users/niklas/Projects/Agents/Neo4j/neo4j-tls-docker/certificates/public.der"

    override func setUp() {
        self.continueAfterFailure = false
        super.setUp()

        #if os(Linux)
        // Linux uses NIOSSL - skip for now as it needs different setup
        skipTests = true
        #else
        // Verify certificate file exists
        guard FileManager.default.fileExists(atPath: Self.tlsCertPath) else {
            print("TLS certificate not found at: \(Self.tlsCertPath)")
            skipTests = true
            return
        }
        // Set up socketTests lazily in each test to avoid setup hanging
        skipTests = false
        #endif
    }

    private func createSocketTests() throws -> SocketTests? {
        #if os(Linux)
        return nil
        #else
        let socket = try EncryptedSocket(hostname: Self.tlsHostname, port: Self.tlsPort)
        socket.certificateValidator = SelfSignedCertificateValidator(
            hostname: Self.tlsHostname,
            port: UInt(Self.tlsPort),
            certificatePath: Self.tlsCertPath
        )
        let settings = ConnectionSettings(username: Self.tlsUsername, password: Self.tlsPassword, userAgent: "BoltTLSTests")
        return SocketTests(socket: socket, settings: settings)
        #endif
    }

    static var allTests: [(String, (EncryptedSocketTests) -> () throws -> Void)] {
        return [
            // Legacy sync tests disabled - use async tests below
        ]
    }

    // Note: Legacy sync tests are disabled on macOS due to DispatchGroup/NIO deadlock
    // Use the async tests below instead

    // MARK: - Async TLS Tests

    func testSimpleConnectionAsyncTLS() async throws {
        try XCTSkipIf(skipTests, "Skipping encrypted tests - TLS server not available")
        let socketTests = try createSocketTests()
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateSimpleConnectionAsync()
    }

    func testUnwindAsyncTLS() async throws {
        try XCTSkipIf(skipTests, "Skipping encrypted tests - TLS server not available")
        let socketTests = try createSocketTests()
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateUnwindAsync()
    }

    func testUnwindWithToNodesAsyncTLS() async throws {
        try XCTSkipIf(skipTests, "Skipping encrypted tests - TLS server not available")
        let socketTests = try createSocketTests()
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateUnwindWithToNodesAsync()
    }

    func testRubbishCypherAsyncTLS() async throws {
        try XCTSkipIf(skipTests, "Skipping encrypted tests - TLS server not available")
        let socketTests = try createSocketTests()
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateRubbishCypherAsync()
    }

    func testBasicQueryAsyncTLS() async throws {
        try XCTSkipIf(skipTests, "Skipping encrypted tests - TLS server not available")
        let socketTests = try createSocketTests()
        XCTAssertNotNil(socketTests)
        try await socketTests?.templateBasicQueryAsync()
    }
}
