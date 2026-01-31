import Foundation

// MARK: - SSL Configuration

/// Configuration for TLS/SSL connections
public struct SSLConfiguration: Sendable {
    public let temporarySSLKeyPath: String
    public let certificatePKCS12FileName: String
    public let certificatePKCS12Password: String
    public let keyFileName: String
    public let certificatePEMFilename: String
    public let generator: SSLKeyGeneratorConfig

    public init(
        temporarySSLKeyPath: String,
        certificatePKCS12FileName: String,
        certificatePKCS12Password: String,
        keyFileName: String,
        certificatePEMFilename: String,
        generator: SSLKeyGeneratorConfig
    ) {
        self.temporarySSLKeyPath = temporarySSLKeyPath
        self.certificatePKCS12FileName = certificatePKCS12FileName
        self.certificatePKCS12Password = certificatePKCS12Password
        self.keyFileName = keyFileName
        self.certificatePEMFilename = certificatePEMFilename
        self.generator = generator
    }

    public init(json: [String: Any]) {
        temporarySSLKeyPath = json["temporarySSLKeyPath"] as? String ?? "/tmp/boltTestKeys"
        certificatePKCS12FileName = json["certificatePKCS12FileName"] as? String ?? "cert.pfx"
        certificatePKCS12Password = json["certificatePKCS12Password"] as? String ?? "1234"
        keyFileName = json["keyFileName"] as? String ?? "key.pem"
        certificatePEMFilename = json["certificatePEMFilename"] as? String ?? "cert.pem"
        generator = SSLKeyGeneratorConfig(json: json["generator"] as? [String: Any] ?? [:])
    }
}
