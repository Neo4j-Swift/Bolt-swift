import Foundation

// MARK: - Connection Settings

/// Configuration for Bolt connections
public struct ConnectionSettings: Sendable {
    public let username: String
    public let password: String
    public let userAgent: String

    /// Target Bolt protocol version (negotiated during handshake)
    public var boltVersion: BoltVersion

    /// Default database (nil = use default from server)
    public let database: String?

    /// Minimum severity for notifications (Bolt 5.2+)
    public let notificationsMinSeverity: String?

    /// Disabled notification categories (Bolt 5.2+)
    public let notificationsDisabledCategories: [String]?

    /// Connection timeout in milliseconds
    public let connectionTimeoutMs: Int

    /// Socket read/write timeout in milliseconds
    public let socketTimeoutMs: Int

    /// Maximum connection lifetime in milliseconds (for pooling)
    public let maxConnectionLifetimeMs: Int?

    /// Enable TCP keep-alive
    public let keepAlive: Bool

    public init(
        username: String = "neo4j",
        password: String = "neo4j",
        userAgent: String = "Bolt-Swift/6.0.0",
        boltVersion: BoltVersion = .v5_0,
        database: String? = nil,
        notificationsMinSeverity: String? = nil,
        notificationsDisabledCategories: [String]? = nil,
        connectionTimeoutMs: Int = 30000,
        socketTimeoutMs: Int = 0,  // 0 = no timeout
        maxConnectionLifetimeMs: Int? = nil,
        keepAlive: Bool = true
    ) {
        self.username = username
        self.password = password
        self.userAgent = userAgent
        self.boltVersion = boltVersion
        self.database = database
        self.notificationsMinSeverity = notificationsMinSeverity
        self.notificationsDisabledCategories = notificationsDisabledCategories
        self.connectionTimeoutMs = connectionTimeoutMs
        self.socketTimeoutMs = socketTimeoutMs
        self.maxConnectionLifetimeMs = maxConnectionLifetimeMs
        self.keepAlive = keepAlive
    }

    /// Create settings with updated Bolt version (after handshake)
    public func withBoltVersion(_ version: BoltVersion) -> ConnectionSettings {
        var copy = self
        copy.boltVersion = version
        return copy
    }
}

// MARK: - Notification Severity Levels

/// Standard notification severity levels
public enum NotificationSeverity: String, Sendable {
    case off = "OFF"
    case warning = "WARNING"
    case information = "INFORMATION"
}

// MARK: - Notification Categories

/// Standard notification categories that can be disabled
public enum NotificationCategory: String, Sendable, CaseIterable {
    case hint = "HINT"
    case unrecognized = "UNRECOGNIZED"
    case unsupported = "UNSUPPORTED"
    case performance = "PERFORMANCE"
    case deprecation = "DEPRECATION"
    case security = "SECURITY"
    case topology = "TOPOLOGY"
    case generic = "GENERIC"
}
