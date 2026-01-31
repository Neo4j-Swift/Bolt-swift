import Foundation
import XCTest
@testable import Bolt

#if !os(Linux)
import Security
#endif

class CertificateValidatorTests: XCTestCase {

    // MARK: - UnsecureCertificateValidator Tests

    func testUnsecureValidatorInit() {
        let validator = UnsecureCertificateValidator(hostname: "localhost", port: 7687)

        XCTAssertEqual(validator.hostname, "localhost")
        XCTAssertEqual(validator.port, 7687)
        XCTAssertTrue(validator.trustedCertificates.isEmpty)
    }

    func testUnsecureValidatorAlwaysTrusts() {
        let validator = UnsecureCertificateValidator(hostname: "localhost", port: 7687)

        // Should always return true regardless of SHA1
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: "abc123"))
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: "xyz789"))
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: ""))
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: "any-value-at-all"))
    }

    func testUnsecureValidatorDidTrustNoOp() {
        let validator = UnsecureCertificateValidator(hostname: "localhost", port: 7687)

        // Should not crash - just a no-op
        validator.didTrustCertificate(withSHA1: "abc123")
        validator.didTrustCertificate(withSHA1: "")
    }

    func testUnsecureValidatorWithDifferentPorts() {
        let validator1 = UnsecureCertificateValidator(hostname: "host1", port: 7687)
        let validator2 = UnsecureCertificateValidator(hostname: "host2", port: 7688)

        XCTAssertEqual(validator1.hostname, "host1")
        XCTAssertEqual(validator1.port, 7687)
        XCTAssertEqual(validator2.hostname, "host2")
        XCTAssertEqual(validator2.port, 7688)
    }

    // MARK: - macOS/iOS Only Tests

    #if !os(Linux)

    // MARK: - TrustRootOnlyCertificateValidator Tests

    func testTrustRootOnlyValidatorInit() {
        let validator = TrustRootOnlyCertificateValidator(hostname: "example.com", port: 443)

        XCTAssertEqual(validator.hostname, "example.com")
        XCTAssertEqual(validator.port, 443)
        XCTAssertTrue(validator.trustedCertificates.isEmpty)
    }

    func testTrustRootOnlyValidatorNeverTrustsCustomCerts() {
        let validator = TrustRootOnlyCertificateValidator(hostname: "example.com", port: 443)

        // Should always return false - only trusts system root certificates
        XCTAssertFalse(validator.shouldTrustCertificate(withSHA1: "abc123"))
        XCTAssertFalse(validator.shouldTrustCertificate(withSHA1: "xyz789"))
        XCTAssertFalse(validator.shouldTrustCertificate(withSHA1: ""))
    }

    func testTrustRootOnlyValidatorDidTrustNoOp() {
        let validator = TrustRootOnlyCertificateValidator(hostname: "example.com", port: 443)

        // Should not crash - just a no-op
        validator.didTrustCertificate(withSHA1: "abc123")
    }

    // MARK: - TrustSpecificOrRootCertificateValidator Tests

    func testTrustSpecificValidatorInitWithSingleCertificate() {
        // Create a test certificate
        guard let cert = createTestCertificate() else {
            // Skip if we can't create a test certificate
            return
        }

        let validator = TrustSpecificOrRootCertificateValidator(
            hostname: "secure.example.com",
            port: 7687,
            trustedCertificate: cert
        )

        XCTAssertEqual(validator.hostname, "secure.example.com")
        XCTAssertEqual(validator.port, 7687)
        XCTAssertEqual(validator.trustedCertificates.count, 1)
    }

    func testTrustSpecificValidatorInitWithMultipleCertificates() {
        guard let cert1 = createTestCertificate(),
              let cert2 = createTestCertificate() else {
            return
        }

        let validator = TrustSpecificOrRootCertificateValidator(
            hostname: "secure.example.com",
            port: 7687,
            trustedCertificates: [cert1, cert2]
        )

        XCTAssertEqual(validator.trustedCertificates.count, 2)
    }

    func testTrustSpecificValidatorInitWithEmptyArray() {
        let validator = TrustSpecificOrRootCertificateValidator(
            hostname: "secure.example.com",
            port: 7687,
            trustedCertificates: []
        )

        XCTAssertTrue(validator.trustedCertificates.isEmpty)
    }

    func testTrustSpecificValidatorInitWithInvalidPath() {
        let validator = TrustSpecificOrRootCertificateValidator(
            hostname: "secure.example.com",
            port: 7687,
            trustedCertificateAtPath: "/nonexistent/path/to/cert.der"
        )

        // Should gracefully handle invalid path with empty certificates
        XCTAssertTrue(validator.trustedCertificates.isEmpty)
    }

    func testTrustSpecificValidatorShouldTrustReturnsFalse() {
        let validator = TrustSpecificOrRootCertificateValidator(
            hostname: "secure.example.com",
            port: 7687,
            trustedCertificates: []
        )

        // This validator relies on the TLS stack for verification, not SHA1 checks
        XCTAssertFalse(validator.shouldTrustCertificate(withSHA1: "abc123"))
    }

    func testTrustSpecificValidatorDidTrustNoOp() {
        let validator = TrustSpecificOrRootCertificateValidator(
            hostname: "secure.example.com",
            port: 7687,
            trustedCertificates: []
        )

        // Should not crash
        validator.didTrustCertificate(withSHA1: "abc123")
    }

    // MARK: - StoreCertSignaturesInFileCertificateValidator Tests

    func testStoreSignaturesValidatorInit() {
        let tempPath = NSTemporaryDirectory() + "test_certs.plist"
        let validator = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )

        XCTAssertEqual(validator.hostname, "db.example.com")
        XCTAssertEqual(validator.port, 7687)
        XCTAssertEqual(validator.filePath, tempPath)
        XCTAssertTrue(validator.trustedCertificates.isEmpty)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorTrustOnFirstUse() {
        let tempPath = NSTemporaryDirectory() + "test_tofu_\(UUID().uuidString).plist"
        let validator = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )

        // First use - should trust and store
        let sha1 = "abcdef1234567890abcdef1234567890abcdef12"
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: sha1))

        // Verify the file was created with the SHA1
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorRejectsDifferentCert() {
        let tempPath = NSTemporaryDirectory() + "test_reject_\(UUID().uuidString).plist"
        let validator = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )

        // First use - trust this cert
        let originalSha1 = "original1234567890abcdef1234567890abcdef"
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: originalSha1))

        // Second use with different SHA1 - should reject
        let differentSha1 = "different234567890abcdef1234567890abcdef"
        XCTAssertFalse(validator.shouldTrustCertificate(withSHA1: differentSha1))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorAcceptsSameCert() {
        let tempPath = NSTemporaryDirectory() + "test_accept_\(UUID().uuidString).plist"
        let validator = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )

        let sha1 = "consistent234567890abcdef1234567890abcdef"

        // First use - trust
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: sha1))

        // Subsequent uses with same SHA1 - should still trust
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: sha1))
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: sha1))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorDidTrustStoresCert() {
        let tempPath = NSTemporaryDirectory() + "test_didtrust_\(UUID().uuidString).plist"
        let validator = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )

        let sha1 = "didtrust1234567890abcdef1234567890abcdef"

        // Call didTrustCertificate first
        validator.didTrustCertificate(withSHA1: sha1)

        // Now shouldTrust should match
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: sha1))

        // Different SHA1 should fail
        XCTAssertFalse(validator.shouldTrustCertificate(withSHA1: "different"))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorMultipleHosts() {
        let tempPath = NSTemporaryDirectory() + "test_multi_\(UUID().uuidString).plist"

        let validator1 = StoreCertSignaturesInFileCertificateValidator(
            hostname: "host1.example.com",
            port: 7687,
            filePath: tempPath
        )

        let validator2 = StoreCertSignaturesInFileCertificateValidator(
            hostname: "host2.example.com",
            port: 7687,
            filePath: tempPath
        )

        let sha1Host1 = "host1sha1234567890abcdef1234567890abcdef"
        let sha1Host2 = "host2sha1234567890abcdef1234567890abcdef"

        // Trust different certs for different hosts
        XCTAssertTrue(validator1.shouldTrustCertificate(withSHA1: sha1Host1))
        XCTAssertTrue(validator2.shouldTrustCertificate(withSHA1: sha1Host2))

        // Each validator should only trust its own host's cert
        XCTAssertTrue(validator1.shouldTrustCertificate(withSHA1: sha1Host1))
        XCTAssertFalse(validator1.shouldTrustCertificate(withSHA1: sha1Host2))
        XCTAssertTrue(validator2.shouldTrustCertificate(withSHA1: sha1Host2))
        XCTAssertFalse(validator2.shouldTrustCertificate(withSHA1: sha1Host1))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorMultiplePorts() {
        let tempPath = NSTemporaryDirectory() + "test_ports_\(UUID().uuidString).plist"

        let validator7687 = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )

        let validator7688 = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7688,
            filePath: tempPath
        )

        let sha7687 = "port7687sha1234567890abcdef12345678901234"
        let sha7688 = "port7688sha1234567890abcdef12345678901234"

        // Trust different certs for different ports on same host
        XCTAssertTrue(validator7687.shouldTrustCertificate(withSHA1: sha7687))
        XCTAssertTrue(validator7688.shouldTrustCertificate(withSHA1: sha7688))

        // Each port has its own trust
        XCTAssertTrue(validator7687.shouldTrustCertificate(withSHA1: sha7687))
        XCTAssertFalse(validator7687.shouldTrustCertificate(withSHA1: sha7688))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorPersistence() {
        let tempPath = NSTemporaryDirectory() + "test_persist_\(UUID().uuidString).plist"
        let sha1 = "persist1234567890abcdef1234567890abcdef12"

        // First validator instance - trust the cert
        let validator1 = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )
        XCTAssertTrue(validator1.shouldTrustCertificate(withSHA1: sha1))

        // New validator instance with same file path - should have the stored trust
        let validator2 = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )
        XCTAssertTrue(validator2.shouldTrustCertificate(withSHA1: sha1))
        XCTAssertFalse(validator2.shouldTrustCertificate(withSHA1: "different"))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    func testStoreSignaturesValidatorDidTrustDoesNotOverwrite() {
        let tempPath = NSTemporaryDirectory() + "test_nooverwrite_\(UUID().uuidString).plist"
        let validator = StoreCertSignaturesInFileCertificateValidator(
            hostname: "db.example.com",
            port: 7687,
            filePath: tempPath
        )

        let originalSha1 = "original1234567890abcdef1234567890abcdef"
        let newSha1 = "newssha1234567890abcdef1234567890abcdef"

        // Trust original
        validator.didTrustCertificate(withSHA1: originalSha1)

        // Try to trust new one via didTrustCertificate - should not overwrite
        validator.didTrustCertificate(withSHA1: newSha1)

        // Original should still be trusted, new one should not
        XCTAssertTrue(validator.shouldTrustCertificate(withSHA1: originalSha1))
        XCTAssertFalse(validator.shouldTrustCertificate(withSHA1: newSha1))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    // MARK: - Test Helpers

    private func createTestCertificate() -> SecCertificate? {
        // Create a minimal DER-encoded certificate for testing
        // This is a self-signed test certificate
        let certData = Data([
            0x30, 0x82, 0x01, 0x22, 0x30, 0x81, 0xcc, 0x02, 0x01, 0x01, 0x30, 0x0d,
            0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05,
            0x00, 0x30, 0x13, 0x31, 0x11, 0x30, 0x0f, 0x06, 0x03, 0x55, 0x04, 0x03,
            0x0c, 0x08, 0x54, 0x65, 0x73, 0x74, 0x43, 0x65, 0x72, 0x74, 0x30, 0x1e,
            0x17, 0x0d, 0x32, 0x34, 0x30, 0x31, 0x30, 0x31, 0x30, 0x30, 0x30, 0x30,
            0x30, 0x30, 0x5a, 0x17, 0x0d, 0x32, 0x35, 0x30, 0x31, 0x30, 0x31, 0x30,
            0x30, 0x30, 0x30, 0x30, 0x30, 0x5a, 0x30, 0x13, 0x31, 0x11, 0x30, 0x0f,
            0x06, 0x03, 0x55, 0x04, 0x03, 0x0c, 0x08, 0x54, 0x65, 0x73, 0x74, 0x43,
            0x65, 0x72, 0x74, 0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48,
            0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03,
            0x01, 0x07, 0x03, 0x42, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x0d,
            0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05,
            0x00, 0x03, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])

        return SecCertificateCreateWithData(nil, certData as CFData)
    }

    #endif

    // MARK: - Linux allTests

    static var allTests: [(String, (CertificateValidatorTests) -> () throws -> Void)] {
        var tests: [(String, (CertificateValidatorTests) -> () throws -> Void)] = [
            ("testUnsecureValidatorInit", testUnsecureValidatorInit),
            ("testUnsecureValidatorAlwaysTrusts", testUnsecureValidatorAlwaysTrusts),
            ("testUnsecureValidatorDidTrustNoOp", testUnsecureValidatorDidTrustNoOp),
            ("testUnsecureValidatorWithDifferentPorts", testUnsecureValidatorWithDifferentPorts),
        ]

        #if !os(Linux)
        tests += [
            ("testTrustRootOnlyValidatorInit", testTrustRootOnlyValidatorInit),
            ("testTrustRootOnlyValidatorNeverTrustsCustomCerts", testTrustRootOnlyValidatorNeverTrustsCustomCerts),
            ("testTrustRootOnlyValidatorDidTrustNoOp", testTrustRootOnlyValidatorDidTrustNoOp),
            ("testTrustSpecificValidatorInitWithSingleCertificate", testTrustSpecificValidatorInitWithSingleCertificate),
            ("testTrustSpecificValidatorInitWithMultipleCertificates", testTrustSpecificValidatorInitWithMultipleCertificates),
            ("testTrustSpecificValidatorInitWithEmptyArray", testTrustSpecificValidatorInitWithEmptyArray),
            ("testTrustSpecificValidatorInitWithInvalidPath", testTrustSpecificValidatorInitWithInvalidPath),
            ("testTrustSpecificValidatorShouldTrustReturnsFalse", testTrustSpecificValidatorShouldTrustReturnsFalse),
            ("testTrustSpecificValidatorDidTrustNoOp", testTrustSpecificValidatorDidTrustNoOp),
            ("testStoreSignaturesValidatorInit", testStoreSignaturesValidatorInit),
            ("testStoreSignaturesValidatorTrustOnFirstUse", testStoreSignaturesValidatorTrustOnFirstUse),
            ("testStoreSignaturesValidatorRejectsDifferentCert", testStoreSignaturesValidatorRejectsDifferentCert),
            ("testStoreSignaturesValidatorAcceptsSameCert", testStoreSignaturesValidatorAcceptsSameCert),
            ("testStoreSignaturesValidatorDidTrustStoresCert", testStoreSignaturesValidatorDidTrustStoresCert),
            ("testStoreSignaturesValidatorMultipleHosts", testStoreSignaturesValidatorMultipleHosts),
            ("testStoreSignaturesValidatorMultiplePorts", testStoreSignaturesValidatorMultiplePorts),
            ("testStoreSignaturesValidatorPersistence", testStoreSignaturesValidatorPersistence),
            ("testStoreSignaturesValidatorDidTrustDoesNotOverwrite", testStoreSignaturesValidatorDidTrustDoesNotOverwrite),
        ]
        #endif

        return tests
    }
}
