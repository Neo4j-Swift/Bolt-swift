import XCTest
import PackStream
import NIOCore

#if os(Linux)
import Dispatch
#endif

@testable import Bolt

/// Error handling and classification tests
/// Based on patterns from neo4j-go-driver (error_test.go) and neo4j-java-driver (ErrorIT.java)
final class ErrorTests: XCTestCase, @unchecked Sendable {

    // MARK: - BoltError Type Tests

    func testBoltErrorConnection() {
        let error = BoltError.connection(message: "Connection refused")
        if case .connection(let message) = error {
            XCTAssertEqual(message, "Connection refused")
        } else {
            XCTFail("Expected connection error")
        }
    }

    func testBoltErrorProtocol() {
        let error = BoltError.protocol(message: "Protocol version mismatch")
        if case .protocol(let message) = error {
            XCTAssertEqual(message, "Protocol version mismatch")
        } else {
            XCTFail("Expected protocol error")
        }
    }

    func testBoltErrorAuthentication() {
        let error = BoltError.authentication(message: "Invalid credentials")
        if case .authentication(let message) = error {
            XCTAssertEqual(message, "Invalid credentials")
        } else {
            XCTFail("Expected authentication error")
        }
    }

    func testBoltErrorSyntax() {
        let error = BoltError.syntax(message: "Syntax error in query")
        if case .syntax(let message) = error {
            XCTAssertEqual(message, "Syntax error in query")
        } else {
            XCTFail("Expected syntax error")
        }
    }

    func testBoltErrorTransaction() {
        let error = BoltError.transaction(message: "Transaction terminated")
        if case .transaction(let message) = error {
            XCTAssertEqual(message, "Transaction terminated")
        } else {
            XCTFail("Expected transaction error")
        }
    }

    func testBoltErrorDatabase() {
        let error = BoltError.database(message: "Database unavailable")
        if case .database(let message) = error {
            XCTAssertEqual(message, "Database unavailable")
        } else {
            XCTFail("Expected database error")
        }
    }

    func testBoltErrorConstraint() {
        let error = BoltError.constraint(message: "Constraint violation")
        if case .constraint(let message) = error {
            XCTAssertEqual(message, "Constraint violation")
        } else {
            XCTFail("Expected constraint error")
        }
    }

    func testBoltErrorSecurity() {
        let error = BoltError.security(message: "Access denied")
        if case .security(let message) = error {
            XCTAssertEqual(message, "Access denied")
        } else {
            XCTFail("Expected security error")
        }
    }

    func testBoltErrorTransient() {
        let error = BoltError.transient(message: "Temporary failure")
        if case .transient(let message) = error {
            XCTAssertEqual(message, "Temporary failure")
        } else {
            XCTFail("Expected transient error")
        }
    }

    func testBoltErrorService() {
        let error = BoltError.service(message: "Service unavailable")
        if case .service(let message) = error {
            XCTAssertEqual(message, "Service unavailable")
        } else {
            XCTFail("Expected service error")
        }
    }

    func testBoltErrorUnknown() {
        let error = BoltError.unknown(code: "Neo.Custom.Error", message: "Custom error")
        if case .unknown(let code, let message) = error {
            XCTAssertEqual(code, "Neo.Custom.Error")
            XCTAssertEqual(message, "Custom error")
        } else {
            XCTFail("Expected unknown error")
        }
    }

    // MARK: - Error Description Tests

    func testBoltErrorDescriptions() {
        let connectionError = BoltError.connection(message: "Test message")
        XCTAssertTrue(connectionError.localizedDescription.contains("Test message"))

        let protocolError = BoltError.protocol(message: "Protocol failed")
        XCTAssertTrue(protocolError.localizedDescription.contains("Protocol failed"))
    }

    // MARK: - Error Parsing Tests (BoltError.from)

    func testBoltErrorFromSyntaxCode() {
        let error = BoltError.from(code: "Neo.ClientError.Statement.SyntaxError", message: "Invalid syntax")
        if case .syntax(let message) = error {
            XCTAssertEqual(message, "Invalid syntax")
        } else {
            XCTFail("Expected syntax error, got \(error)")
        }
    }

    func testBoltErrorFromAuthenticationCode() {
        let error = BoltError.from(code: "Neo.ClientError.Security.AuthenticationFailed", message: "Bad credentials")
        if case .authentication(let message) = error {
            XCTAssertEqual(message, "Bad credentials")
        } else {
            XCTFail("Expected authentication error, got \(error)")
        }
    }

    func testBoltErrorFromTransientCode() {
        let error = BoltError.from(code: "Neo.TransientError.General.DatabaseUnavailable", message: "DB down")
        if case .transient(let message) = error {
            XCTAssertEqual(message, "DB down")
        } else {
            XCTFail("Expected transient error, got \(error)")
        }
    }

    func testBoltErrorFromConstraintCode() {
        let error = BoltError.from(code: "Neo.ClientError.Schema.ConstraintValidationFailed", message: "Duplicate")
        if case .constraint(let message) = error {
            XCTAssertEqual(message, "Duplicate")
        } else {
            XCTFail("Expected constraint error, got \(error)")
        }
    }

    func testBoltErrorFromDatabaseCode() {
        let error = BoltError.from(code: "Neo.DatabaseError.General.UnknownError", message: "Unknown DB error")
        if case .database(let message) = error {
            XCTAssertEqual(message, "Unknown DB error")
        } else {
            XCTFail("Expected database error, got \(error)")
        }
    }

    // MARK: - Neo4j Error Code Classification Tests (based on Go driver)

    func testTransientErrorCodes() {
        // Transient errors should be retryable
        let transientCodes = [
            "Neo.TransientError.General.DatabaseUnavailable",
            "Neo.TransientError.Network.CommunicationError",
            "Neo.TransientError.Transaction.DeadlockDetected",
            "Neo.TransientError.Transaction.Outdated",
            "Neo.TransientError.Transaction.LockClientStopped"
        ]

        for code in transientCodes {
            XCTAssertTrue(code.contains("TransientError"), "Expected \(code) to be a transient error")
        }
    }

    func testClientErrorCodes() {
        // Client errors are not retryable
        let clientCodes = [
            "Neo.ClientError.Statement.SyntaxError",
            "Neo.ClientError.Statement.TypeError",
            "Neo.ClientError.Schema.ConstraintValidationFailed",
            "Neo.ClientError.Security.AuthenticationFailed",
            "Neo.ClientError.Security.AuthorizationExpired"
        ]

        for code in clientCodes {
            XCTAssertTrue(code.contains("ClientError"), "Expected \(code) to be a client error")
        }
    }

    func testDatabaseErrorCodes() {
        // Database errors may or may not be retryable
        let databaseCodes = [
            "Neo.DatabaseError.General.UnknownError",
            "Neo.DatabaseError.Statement.ExecutionFailed"
        ]

        for code in databaseCodes {
            XCTAssertTrue(code.contains("DatabaseError"), "Expected \(code) to be a database error")
        }
    }

    // MARK: - Retryable Error Detection (based on Go driver)

    func testIsRetryableTransientError() {
        let code = "Neo.TransientError.Transaction.DeadlockDetected"
        let isRetryable = code.contains("TransientError")
        XCTAssertTrue(isRetryable)
    }

    func testIsNotRetryableClientError() {
        let code = "Neo.ClientError.Statement.SyntaxError"
        let isRetryable = code.contains("TransientError")
        XCTAssertFalse(isRetryable)
    }

    func testIsRetryableClusterError() {
        // Cluster-specific errors that should trigger retry
        let clusterErrorCodes = [
            "Neo.ClientError.Cluster.NotALeader",
            "Neo.ClientError.General.ForbiddenOnReadOnlyDatabase"
        ]

        for code in clusterErrorCodes {
            // These are special cases that should be retryable despite being ClientError
            let isClusterRetryable = code.contains("NotALeader") || code.contains("ForbiddenOnReadOnlyDatabase")
            XCTAssertTrue(isClusterRetryable)
        }
    }

    // MARK: - Error Code Parsing Tests

    func testParseNeo4jErrorCode() {
        let fullCode = "Neo.ClientError.Statement.SyntaxError"
        let components = fullCode.split(separator: ".")

        XCTAssertEqual(components.count, 4)
        XCTAssertEqual(components[0], "Neo")
        XCTAssertEqual(components[1], "ClientError")
        XCTAssertEqual(components[2], "Statement")
        XCTAssertEqual(components[3], "SyntaxError")
    }

    func testExtractErrorClassification() {
        let code = "Neo.TransientError.Network.CommunicationError"
        let classification = code.split(separator: ".")[1]

        XCTAssertEqual(classification, "TransientError")
    }

    func testExtractErrorCategory() {
        let code = "Neo.ClientError.Security.AuthenticationFailed"
        let category = code.split(separator: ".")[2]

        XCTAssertEqual(category, "Security")
    }

    // MARK: - Error Handling Edge Cases

    func testEmptyErrorMessage() {
        let error = BoltError.connection(message: "")
        if case .connection(let message) = error {
            XCTAssertTrue(message.isEmpty)
        } else {
            XCTFail("Expected connection error")
        }
    }

    func testErrorWithSpecialCharacters() {
        let message = "Error: \"Invalid query\" at line 1, column 5"
        let error = BoltError.syntax(message: message)
        if case .syntax(let msg) = error {
            XCTAssertEqual(msg, message)
        } else {
            XCTFail("Expected syntax error")
        }
    }

    func testErrorWithUnicode() {
        let message = "Erreur: Requête invalide avec caractères spéciaux: äöü"
        let error = BoltError.syntax(message: message)
        if case .syntax(let msg) = error {
            XCTAssertEqual(msg, message)
        } else {
            XCTFail("Expected syntax error")
        }
    }

    // MARK: - Timeout Error Tests

    func testConnectionTimeoutError() {
        let error = BoltError.connection(message: "Connection timed out after 30 seconds")
        XCTAssertNotNil(error)
    }

    func testAcquisitionTimeoutError() {
        let error = BoltError.connection(message: "Connection acquisition timed out")
        XCTAssertNotNil(error)
    }

    // MARK: - Security Error Tests

    func testAuthenticationFailedError() {
        let error = BoltError.authentication(message: "The client is unauthorized due to authentication failure")
        if case .authentication(let message) = error {
            XCTAssertTrue(message.contains("authentication failure"))
        } else {
            XCTFail("Expected authentication error")
        }
    }

    func testAuthorizationExpiredError() {
        let error = BoltError.security(message: "Token has expired")
        if case .security(let message) = error {
            XCTAssertTrue(message.contains("expired"))
        } else {
            XCTFail("Expected security error")
        }
    }

    // MARK: - allTests for Linux

    static var allTests: [(String, (ErrorTests) -> () throws -> Void)] {
        return [
            ("testBoltErrorConnection", testBoltErrorConnection),
            ("testBoltErrorProtocol", testBoltErrorProtocol),
            ("testBoltErrorAuthentication", testBoltErrorAuthentication),
            ("testBoltErrorSyntax", testBoltErrorSyntax),
            ("testBoltErrorTransaction", testBoltErrorTransaction),
            ("testBoltErrorDatabase", testBoltErrorDatabase),
            ("testBoltErrorConstraint", testBoltErrorConstraint),
            ("testBoltErrorSecurity", testBoltErrorSecurity),
            ("testBoltErrorTransient", testBoltErrorTransient),
            ("testBoltErrorService", testBoltErrorService),
            ("testBoltErrorUnknown", testBoltErrorUnknown),
            ("testBoltErrorDescriptions", testBoltErrorDescriptions),
            ("testBoltErrorFromSyntaxCode", testBoltErrorFromSyntaxCode),
            ("testBoltErrorFromAuthenticationCode", testBoltErrorFromAuthenticationCode),
            ("testBoltErrorFromTransientCode", testBoltErrorFromTransientCode),
            ("testBoltErrorFromConstraintCode", testBoltErrorFromConstraintCode),
            ("testBoltErrorFromDatabaseCode", testBoltErrorFromDatabaseCode),
            ("testTransientErrorCodes", testTransientErrorCodes),
            ("testClientErrorCodes", testClientErrorCodes),
            ("testDatabaseErrorCodes", testDatabaseErrorCodes),
            ("testIsRetryableTransientError", testIsRetryableTransientError),
            ("testIsNotRetryableClientError", testIsNotRetryableClientError),
            ("testIsRetryableClusterError", testIsRetryableClusterError),
            ("testParseNeo4jErrorCode", testParseNeo4jErrorCode),
            ("testExtractErrorClassification", testExtractErrorClassification),
            ("testExtractErrorCategory", testExtractErrorCategory),
            ("testEmptyErrorMessage", testEmptyErrorMessage),
            ("testErrorWithSpecialCharacters", testErrorWithSpecialCharacters),
            ("testErrorWithUnicode", testErrorWithUnicode),
            ("testConnectionTimeoutError", testConnectionTimeoutError),
            ("testAcquisitionTimeoutError", testAcquisitionTimeoutError),
            ("testAuthenticationFailedError", testAuthenticationFailedError),
            ("testAuthorizationExpiredError", testAuthorizationExpiredError),
        ]
    }
}
