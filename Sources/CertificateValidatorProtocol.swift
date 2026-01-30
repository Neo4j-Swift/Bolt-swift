import Foundation

#if os(Linux)
import NIOSSL
#endif

// MARK: - Certificate Validator Protocol

/// Protocol for custom TLS certificate validation
public protocol CertificateValidatorProtocol: AnyObject {
    /// Hostname being connected to
    var hostname: String { get }

    /// Port being connected to
    var port: UInt { get }

    #if os(Linux)
    /// Trusted certificates for verification
    var trustedCertificates: [NIOSSLCertificateSource] { get }
    #else
    /// Trusted certificates for verification
    var trustedCertificates: [SecCertificate] { get }
    #endif

    /// Determine if a certificate should be trusted based on its SHA1 hash
    func shouldTrustCertificate(withSHA1: String) -> Bool

    /// Called when a certificate has been trusted
    func didTrustCertificate(withSHA1: String)
}
