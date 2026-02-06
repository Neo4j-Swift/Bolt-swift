import XCTest

#if !os(macOS) && !os(iOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(BoltTests.allTests),
        testCase(UnencryptedSocketTests.allTests),
        testCase(EncryptedSocketTests.allTests),
        testCase(ResponseTests.allTests),
        testCase(RequestTests.allTests),
        testCase(ErrorTests.allTests),
        testCase(ConnectionTests.allTests),
        testCase(CertificateValidatorTests.allTests)
        // Note: AsyncSocketTests uses async/await and requires XCTest discovery
        // Run with: swift test --enable-test-discovery
    ]
}
#endif
