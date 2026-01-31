import Foundation

#if os(Linux)
import NIOSSL
#endif

// MARK: - Unsecure Certificate Validator

/// Certificate validator that accepts all certificates (for development only)
public final class UnsecureCertificateValidator: CertificateValidatorProtocol {
    public let hostname: String
    public let port: UInt

    #if os(Linux)
    public let trustedCertificates: [NIOSSLCertificateSource]
    #else
    public let trustedCertificates: [SecCertificate]
    #endif

    public init(hostname: String, port: UInt) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = []
    }

    public func shouldTrustCertificate(withSHA1: String) -> Bool {
        return true
    }

    public func didTrustCertificate(withSHA1: String) {
        // No-op
    }
}

// MARK: - macOS/iOS Only Validators

#if !os(Linux)

/// Certificate validator that only trusts system root certificates
public final class TrustRootOnlyCertificateValidator: CertificateValidatorProtocol {
    public let hostname: String
    public let port: UInt
    public let trustedCertificates: [SecCertificate]

    public init(hostname: String, port: UInt) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = []
    }

    public func shouldTrustCertificate(withSHA1: String) -> Bool {
        return false
    }

    public func didTrustCertificate(withSHA1: String) {
        // No-op
    }
}

/// Certificate validator that trusts specific certificates in addition to root
public final class TrustSpecificOrRootCertificateValidator: CertificateValidatorProtocol {
    public let hostname: String
    public let port: UInt
    public let trustedCertificates: [SecCertificate]

    public init(hostname: String, port: UInt, trustedCertificate: SecCertificate) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = [trustedCertificate]
    }

    public init(hostname: String, port: UInt, trustedCertificates: [SecCertificate]) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = trustedCertificates
    }

    public init(hostname: String, port: UInt, trustedCertificateAtPath path: String) {
        self.hostname = hostname
        self.port = port

        if let data = FileManager.default.contents(atPath: path),
           let cert = SecCertificateCreateWithData(nil, data as CFData) {
            self.trustedCertificates = [cert]
        } else {
            print("Bolt: Path '\(path)' did not contain a valid certificate, continuing without")
            self.trustedCertificates = []
        }
    }

    public func shouldTrustCertificate(withSHA1: String) -> Bool {
        return false
    }

    public func didTrustCertificate(withSHA1: String) {
        // No-op
    }
}

/// Certificate validator that stores trusted certificate signatures in a file
public final class StoreCertSignaturesInFileCertificateValidator: CertificateValidatorProtocol {
    public let hostname: String
    public let port: UInt
    public let trustedCertificates: [SecCertificate]
    public let filePath: String

    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init(hostname: String, port: UInt, filePath path: String) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = []
        self.filePath = path
    }

    public func shouldTrustCertificate(withSHA1 testSHA1: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let keysForHosts = readKeysForHosts()
        let key = "\(hostname):\(port)"

        if let trueSHA1 = keysForHosts[key] {
            return trueSHA1 == testSHA1
        }

        // Trust on first use
        trustSHA1(key: key, testSHA1)
        return true
    }

    public func didTrustCertificate(withSHA1 testSHA1: String) {
        lock.lock()
        defer { lock.unlock() }

        let keysForHosts = readKeysForHosts()
        let key = "\(hostname):\(port)"

        if keysForHosts[key] == nil {
            trustSHA1(key: key, testSHA1)
        }
    }

    private func readKeysForHosts() -> [String: String] {
        var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
        var keysForHosts: [String: String] = [:]

        if let plistXML = fileManager.contents(atPath: filePath) {
            do {
                keysForHosts = try PropertyListSerialization.propertyList(
                    from: plistXML,
                    options: .mutableContainersAndLeaves,
                    format: &propertyListFormat
                ) as? [String: String] ?? [:]
            } catch {
                #if BOLT_DEBUG
                print("Error reading plist: \(error)")
                #endif
            }
        }

        return keysForHosts
    }

    private func trustSHA1(key: String, _ sha1: String) {
        var keysForHosts = readKeysForHosts()
        keysForHosts[key] = sha1

        if let data = try? PropertyListSerialization.data(
            fromPropertyList: keysForHosts,
            format: .xml,
            options: 0
        ) {
            let url = URL(fileURLWithPath: filePath)
            try? data.write(to: url)
        }
    }
}

#endif
