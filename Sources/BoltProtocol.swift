import Foundation
import PackStream

// MARK: - Bolt Protocol Version

/// Represents a Bolt protocol version
public struct BoltVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: UInt8
    public let minor: UInt8

    public init(major: UInt8, minor: UInt8 = 0) {
        self.major = major
        self.minor = minor
    }

    /// Parse version from 4-byte server response
    public init(bytes: [Byte]) {
        precondition(bytes.count == 4)
        // Bolt version format: [minor, 0, 0, major] (little-endian style)
        self.minor = bytes[0]
        self.major = bytes[3]
    }

    /// Encode version for handshake (4 bytes)
    public func encode() -> [Byte] {
        return [minor, 0, 0, major]
    }

    /// Encode version with range support for handshake
    public func encodeWithRange(minorRange: UInt8 = 0) -> [Byte] {
        return [minor, minorRange, 0, major]
    }

    public var description: String {
        minor > 0 ? "\(major).\(minor)" : "\(major)"
    }

    public static func < (lhs: BoltVersion, rhs: BoltVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        return lhs.minor < rhs.minor
    }

    // Known versions
    public static let v3 = BoltVersion(major: 3)
    public static let v4_0 = BoltVersion(major: 4, minor: 0)
    public static let v4_1 = BoltVersion(major: 4, minor: 1)
    public static let v4_2 = BoltVersion(major: 4, minor: 2)
    public static let v4_3 = BoltVersion(major: 4, minor: 3)
    public static let v4_4 = BoltVersion(major: 4, minor: 4)
    public static let v5_0 = BoltVersion(major: 5, minor: 0)
    public static let v5_1 = BoltVersion(major: 5, minor: 1)
    public static let v5_2 = BoltVersion(major: 5, minor: 2)
    public static let v5_3 = BoltVersion(major: 5, minor: 3)
    public static let v5_4 = BoltVersion(major: 5, minor: 4)
    public static let v5_5 = BoltVersion(major: 5, minor: 5)
    public static let v5_6 = BoltVersion(major: 5, minor: 6)

    public static let zero = BoltVersion(major: 0)
}

// MARK: - Bolt Message Signatures

/// Message signatures for Bolt protocol
public enum BoltMessageSignature: Byte, Sendable {
    // Request messages
    case hello = 0x01       // Bolt 3+ (also INIT for Bolt 1-2)
    case logon = 0x6A       // Bolt 5.1+ (authentication)
    case logoff = 0x6B      // Bolt 5.1+ (logout)
    case goodbye = 0x02     // Bolt 3+
    case reset = 0x0F
    case run = 0x10
    case begin = 0x11       // Bolt 3+
    case commit = 0x12      // Bolt 3+
    case rollback = 0x13    // Bolt 3+
    case discard = 0x2F     // DISCARD_ALL (Bolt 1-3) / DISCARD (Bolt 4+)
    case pull = 0x3F        // PULL_ALL (Bolt 1-3) / PULL (Bolt 4+)
    case route = 0x66       // Bolt 4.3+
    case telemetry = 0x54   // Bolt 5.4+

    // Response messages
    case success = 0x70
    case record = 0x71
    case ignored = 0x7E
    case failure = 0x7F

    // Legacy (Bolt 1-2)
    case ackFailure = 0x0E  // Bolt 1-2 only

    // Aliases for backwards compatibility
    public static let initialize = hello
    public static let discardAll = discard
    public static let pullAll = pull
}

// MARK: - Bolt Handshake

/// Bolt protocol handshake handler
public struct BoltHandshake: Sendable {
    /// Magic preamble for Bolt protocol
    public static let preamble: [Byte] = [0x60, 0x60, 0xB0, 0x17]

    /// Create handshake bytes with preferred versions
    /// The server will select the highest mutually supported version
    public static func createHandshake(preferredVersions: [BoltVersion]) -> [Byte] {
        var bytes = preamble

        // Add up to 4 version proposals (padded with zeros)
        for i in 0..<4 {
            if i < preferredVersions.count {
                bytes.append(contentsOf: preferredVersions[i].encode())
            } else {
                bytes.append(contentsOf: [0, 0, 0, 0])
            }
        }

        return bytes
    }

    /// Create handshake bytes with version ranges (Bolt 4.1+)
    public static func createHandshakeWithRanges() -> [Byte] {
        var bytes = preamble

        // Propose versions with ranges for better negotiation
        // Slot 1: Bolt 5.6 with range to 5.0
        bytes.append(contentsOf: [6, 6, 0, 5]) // 5.6 down to 5.0

        // Slot 2: Bolt 4.4 with range to 4.2
        bytes.append(contentsOf: [4, 2, 0, 4]) // 4.4 down to 4.2

        // Slot 3: Bolt 4.1 with range to 4.0
        bytes.append(contentsOf: [1, 1, 0, 4]) // 4.1 down to 4.0

        // Slot 4: Bolt 3
        bytes.append(contentsOf: BoltVersion.v3.encode())

        return bytes
    }

    /// Parse server's version response
    public static func parseVersionResponse(_ bytes: [Byte]) -> BoltVersion? {
        guard bytes.count == 4 else { return nil }
        let version = BoltVersion(bytes: bytes)
        return version.major > 0 ? version : nil
    }
}

// MARK: - Response Category

/// Categories of Bolt responses
public enum ResponseCategory: Byte, Sendable {
    case empty = 0x00
    case success = 0x70
    case record = 0x71
    case ignored = 0x7E
    case failure = 0x7F
}

// MARK: - Record Types

/// Types of records in Bolt responses
public enum BoltRecordType: Byte, Sendable {
    case node = 0x4E            // 'N'
    case relationship = 0x52    // 'R'
    case path = 0x50            // 'P'
    case unboundRelationship = 0x72  // 'r'

    // Temporal types (Bolt 3+)
    case date = 0x44            // 'D'
    case time = 0x54            // 'T'
    case localTime = 0x74       // 't'
    case dateTime = 0x49        // 'I' (with timezone ID)
    case dateTimeZoneId = 0x69  // 'i' (legacy)
    case localDateTime = 0x64   // 'd'
    case duration = 0x45        // 'E'

    // Spatial types (Bolt 3+)
    case point2D = 0x58         // 'X'
    case point3D = 0x59         // 'Y'
}

// MARK: - Protocol Capabilities

/// Capabilities supported by different Bolt versions
public struct BoltCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // Basic capabilities
    public static let transactions = BoltCapabilities(rawValue: 1 << 0)
    public static let bookmarks = BoltCapabilities(rawValue: 1 << 1)
    public static let notifications = BoltCapabilities(rawValue: 1 << 2)

    // Streaming capabilities (Bolt 4+)
    public static let qid = BoltCapabilities(rawValue: 1 << 3)  // Query ID
    public static let streaming = BoltCapabilities(rawValue: 1 << 4)  // PULL/DISCARD with n

    // Routing (Bolt 4.3+)
    public static let routing = BoltCapabilities(rawValue: 1 << 5)

    // Authentication (Bolt 5.1+)
    public static let reauth = BoltCapabilities(rawValue: 1 << 6)  // Re-authentication

    // Telemetry (Bolt 5.4+)
    public static let telemetry = BoltCapabilities(rawValue: 1 << 7)

    // Notification filtering (Bolt 5.2+)
    public static let notificationFiltering = BoltCapabilities(rawValue: 1 << 8)

    /// Get capabilities for a Bolt version
    public static func forVersion(_ version: BoltVersion) -> BoltCapabilities {
        var caps: BoltCapabilities = [.transactions, .bookmarks]

        if version >= .v4_0 {
            caps.insert(.qid)
            caps.insert(.streaming)
        }

        if version >= .v4_1 {
            caps.insert(.notifications)
        }

        if version >= .v4_3 {
            caps.insert(.routing)
        }

        if version >= .v5_1 {
            caps.insert(.reauth)
        }

        if version >= .v5_2 {
            caps.insert(.notificationFiltering)
        }

        if version >= .v5_4 {
            caps.insert(.telemetry)
        }

        return caps
    }
}

// MARK: - Connection Metadata

/// Metadata from Bolt connection handshake
public struct BoltConnectionMetadata: Sendable {
    public let serverAgent: String
    public let connectionId: String?
    public let serverVersion: String?
    public let hints: [String: String]

    public init(from map: Map) {
        self.serverAgent = map.dictionary["server"] as? String ?? "Unknown"
        self.connectionId = map.dictionary["connection_id"] as? String

        // Extract server version from agent string (e.g., "Neo4j/5.0.0")
        if let agent = map.dictionary["server"] as? String,
           let slashIndex = agent.firstIndex(of: "/") {
            self.serverVersion = String(agent[agent.index(after: slashIndex)...])
        } else {
            self.serverVersion = nil
        }

        // Collect any hints
        var hints: [String: String] = [:]
        if let hintsMap = map.dictionary["hints"] as? Map {
            for (key, value) in hintsMap.dictionary {
                if let strValue = value as? String {
                    hints[key] = strValue
                }
            }
        }
        self.hints = hints
    }
}
