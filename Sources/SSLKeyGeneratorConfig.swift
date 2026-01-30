import Foundation

// MARK: - SSL Key Generator Configuration

/// Configuration for generating SSL keys
public struct SSLKeyGeneratorConfig: Sendable {
    public let signingRequestFileName: String
    public let countryName: String
    public let stateOrProvinceName: String
    public let localityName: String
    public let organizationName: String
    public let orgUnitName: String
    public let commonName: String
    public let emailAddress: String
    public let companyName: String

    public init(
        signingRequestFileName: String,
        countryName: String,
        stateOrProvinceName: String,
        localityName: String,
        organizationName: String,
        orgUnitName: String,
        commonName: String,
        emailAddress: String,
        companyName: String
    ) {
        self.signingRequestFileName = signingRequestFileName
        self.countryName = countryName
        self.stateOrProvinceName = stateOrProvinceName
        self.localityName = localityName
        self.organizationName = organizationName
        self.orgUnitName = orgUnitName
        self.commonName = commonName
        self.emailAddress = emailAddress
        self.companyName = companyName
    }

    public init(json: [String: Any]) {
        signingRequestFileName = json["signingRequestFileName"] as? String ?? "csr.csr"
        countryName = json["countryName"] as? String ?? "DK"
        stateOrProvinceName = json["stateOrProvinceName"] as? String ?? "Esbjerg"
        localityName = json["localityName"] as? String ?? ""
        organizationName = json["organizationName"] as? String ?? "Bolt-swift"
        orgUnitName = json["orgUnitName"] as? String ?? ""
        commonName = json["commonName"] as? String ?? ""
        emailAddress = json["emailAddress"] as? String ?? ""
        companyName = json["companyName"] as? String ?? ""
    }
}
