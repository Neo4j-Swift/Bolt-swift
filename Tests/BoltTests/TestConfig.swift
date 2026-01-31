import Foundation
import Bolt

struct TestConfig {
    var username: String
    var password: String
    var hostname: String
    let port: Int
    let temporarySSLKeyPath: String
    let hostUsesSelfSignedCertificate: Bool
    let sslConfig: SSLConfiguration

    init(pathToFile: String) {

        do {
            let filePathURL = URL(fileURLWithPath: pathToFile)
            let jsonData = try Data(contentsOf: filePathURL)
            let jsonConfig = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]

            self.username = jsonConfig?["username"] as? String ?? "neo4j"
            self.password = jsonConfig?["password"] as? String ?? "neo4j"
            self.hostname = jsonConfig?["hostname"] as? String ?? "localhost"
            self.port     = jsonConfig?["port"] as? Int ?? 7687
            self.hostUsesSelfSignedCertificate = jsonConfig?["hostUsesSelfSignedCertificate"] as? Bool ?? true
            self.temporarySSLKeyPath = jsonConfig?["temporarySSLKeyPath"] as? String ?? "/tmp/boltTestKeys"
            self.sslConfig = SSLConfiguration(json: jsonConfig?["certificateProperties"] as? [String: Any] ?? [:])

        } catch {

            self.username = "neo4j"
            self.password = "neo4j"
            self.hostname = "localhost"
            self.port     = 7687
            self.hostUsesSelfSignedCertificate = true
            self.temporarySSLKeyPath = "/tmp/boltTestKeys"
            self.sslConfig = SSLConfiguration(json: [:])

            print("Config load failed: \(error)\nUsing default config values")
        }
    }

    static func loadConfig() -> TestConfig {
        // Try multiple locations for the config file
        let possiblePaths = [
            // Source directory (when running in Xcode or from source)
            URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("BoltSwiftTestConfig.json").path,
            // Package root (when running swift test)
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/BoltTests/BoltSwiftTestConfig.json").path,
            // Relative from working directory
            "Tests/BoltTests/BoltSwiftTestConfig.json"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return TestConfig(pathToFile: path)
            }
        }

        // Fall back to first path even if it doesn't exist (will use defaults)
        return TestConfig(pathToFile: possiblePaths[0])
    }

}
