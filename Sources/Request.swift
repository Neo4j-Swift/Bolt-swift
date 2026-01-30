import Foundation
import PackStream

// MARK: - Bolt Request

/// A Bolt protocol request message
public struct Request: Sendable {
    public let signature: BoltMessageSignature
    public let items: [any PackProtocol]

    public static let kMaxChunkSize = 65536

    private init(signature: BoltMessageSignature, items: [any PackProtocol]) {
        self.signature = signature
        self.items = items
    }

    // MARK: - Authentication Messages

    /// HELLO message (Bolt 3+)
    /// Initializes connection and authenticates
    public static func hello(settings: ConnectionSettings, routingContext: [String: String]? = nil) -> Request {
        var extra: [String: any PackProtocol] = [
            "user_agent": settings.userAgent,
            "scheme": "basic",
            "principal": settings.username,
            "credentials": settings.password,
        ]

        // Add routing context for cluster connections (Bolt 4.1+)
        if let routing = routingContext {
            extra["routing"] = Map(dictionary: routing)
        }

        // Bolt version features
        if settings.boltVersion >= .v5_1 {
            // Bolt 5.1+ supports notifications configuration
            if let minSeverity = settings.notificationsMinSeverity {
                extra["notifications_minimum_severity"] = minSeverity
            }
            if let disabledCategories = settings.notificationsDisabledCategories {
                extra["notifications_disabled_categories"] = List(items: disabledCategories)
            }
        }

        return Request(signature: .hello, items: [Map(dictionary: extra)])
    }

    /// LOGON message (Bolt 5.1+)
    /// Re-authenticates on an existing connection
    public static func logon(settings: ConnectionSettings) -> Request {
        let auth: [String: any PackProtocol] = [
            "scheme": "basic",
            "principal": settings.username,
            "credentials": settings.password,
        ]
        return Request(signature: .logon, items: [Map(dictionary: auth)])
    }

    /// LOGOFF message (Bolt 5.1+)
    /// Logs off from current session
    public static func logoff() -> Request {
        return Request(signature: .logoff, items: [])
    }

    /// GOODBYE message (Bolt 3+)
    /// Gracefully closes the connection
    public static func goodbye() -> Request {
        return Request(signature: .goodbye, items: [])
    }

    // MARK: - Transaction Control

    /// BEGIN message - starts an explicit transaction
    public static func begin(
        mode: TransactionMode = .readwrite,
        database: String? = nil,
        bookmarks: [String] = [],
        metadata: [String: String] = [:],
        timeoutMs: Int? = nil,
        impersonatedUser: String? = nil,
        notificationsMinSeverity: String? = nil,
        notificationsDisabledCategories: [String]? = nil
    ) -> Request {
        var extra: [String: any PackProtocol] = [:]

        if mode == .readonly {
            extra["mode"] = "r"
        }

        if let db = database {
            extra["db"] = db
        }

        if !bookmarks.isEmpty {
            extra["bookmarks"] = List(items: bookmarks)
        }

        if !metadata.isEmpty {
            extra["tx_metadata"] = Map(dictionary: metadata)
        }

        if let timeout = timeoutMs {
            extra["tx_timeout"] = timeout
        }

        // Bolt 4.4+ impersonation
        if let user = impersonatedUser {
            extra["imp_user"] = user
        }

        // Bolt 5.2+ notification filtering
        if let minSeverity = notificationsMinSeverity {
            extra["notifications_minimum_severity"] = minSeverity
        }
        if let disabledCategories = notificationsDisabledCategories {
            extra["notifications_disabled_categories"] = List(items: disabledCategories)
        }

        return Request(signature: .begin, items: [Map(dictionary: extra)])
    }

    /// COMMIT message - commits the current transaction
    public static func commit() -> Request {
        return Request(signature: .commit, items: [])
    }

    /// ROLLBACK message - rolls back the current transaction
    public static func rollback() -> Request {
        return Request(signature: .rollback, items: [])
    }

    // MARK: - Query Execution

    /// RUN message - submits a query for execution
    public static func run(
        statement: String,
        parameters: [String: any PackProtocol] = [:],
        database: String? = nil,
        mode: TransactionMode? = nil,
        bookmarks: [String] = [],
        timeoutMs: Int? = nil,
        metadata: [String: String] = [:],
        impersonatedUser: String? = nil,
        notificationsMinSeverity: String? = nil,
        notificationsDisabledCategories: [String]? = nil
    ) -> Request {
        var extra: [String: any PackProtocol] = [:]

        if let db = database {
            extra["db"] = db
        }

        if let m = mode, m == .readonly {
            extra["mode"] = "r"
        }

        if !bookmarks.isEmpty {
            extra["bookmarks"] = List(items: bookmarks)
        }

        if let timeout = timeoutMs {
            extra["tx_timeout"] = timeout
        }

        if !metadata.isEmpty {
            extra["tx_metadata"] = Map(dictionary: metadata)
        }

        // Bolt 4.4+ impersonation
        if let user = impersonatedUser {
            extra["imp_user"] = user
        }

        // Bolt 5.2+ notification filtering
        if let minSeverity = notificationsMinSeverity {
            extra["notifications_minimum_severity"] = minSeverity
        }
        if let disabledCategories = notificationsDisabledCategories {
            extra["notifications_disabled_categories"] = List(items: disabledCategories)
        }

        return Request(
            signature: .run,
            items: [statement, Map(dictionary: parameters), Map(dictionary: extra)]
        )
    }

    /// Convenience method for simple queries
    public static func run(statement: String, parameters: Map) -> Request {
        return run(statement: statement, parameters: parameters.dictionary)
    }

    // MARK: - Result Streaming

    /// PULL message (Bolt 4+) - pulls records with streaming control
    public static func pull(n: Int = -1, qid: Int = -1) -> Request {
        var extra: [String: any PackProtocol] = ["n": n]
        if qid >= 0 {
            extra["qid"] = qid
        }
        return Request(signature: .pull, items: [Map(dictionary: extra)])
    }

    /// PULL_ALL message (Bolt 1-3) - pulls all remaining records
    public static func pullAll() -> Request {
        return Request(signature: .pullAll, items: [])
    }

    /// DISCARD message (Bolt 4+) - discards records with streaming control
    public static func discard(n: Int = -1, qid: Int = -1) -> Request {
        var extra: [String: any PackProtocol] = ["n": n]
        if qid >= 0 {
            extra["qid"] = qid
        }
        return Request(signature: .discard, items: [Map(dictionary: extra)])
    }

    /// DISCARD_ALL message (Bolt 1-3) - discards all remaining records
    public static func discardAll() -> Request {
        return Request(signature: .discardAll, items: [])
    }

    // MARK: - Connection Management

    /// RESET message - resets connection to clean state
    public static func reset() -> Request {
        return Request(signature: .reset, items: [])
    }

    // MARK: - Routing (Bolt 4.3+)

    /// ROUTE message - get routing table for a database
    public static func route(
        routingContext: [String: String],
        bookmarks: [String] = [],
        database: String? = nil,
        impersonatedUser: String? = nil
    ) -> Request {
        var items: [any PackProtocol] = [
            Map(dictionary: routingContext),
            List(items: bookmarks),
        ]

        // Bolt 4.3 includes database name
        if let db = database {
            items.append(db)
        } else {
            items.append(Null())
        }

        // Bolt 4.4+ includes impersonated user
        if let user = impersonatedUser {
            items.append(user)
        }

        return Request(signature: .route, items: items)
    }

    // MARK: - Telemetry (Bolt 5.4+)

    /// TELEMETRY message - sends client telemetry
    public static func telemetry(api: Int) -> Request {
        return Request(signature: .telemetry, items: [api])
    }

    // MARK: - Legacy Support

    /// INIT message (Bolt 1-2 style)
    @available(*, deprecated, message: "Use hello() for Bolt 3+")
    public static func initialize(settings: ConnectionSettings) -> Request {
        // For backwards compatibility
        return hello(settings: settings)
    }

    /// ACK_FAILURE message (Bolt 1-2 only)
    @available(*, deprecated, message: "Use reset() for Bolt 3+")
    public static func ackFailure() -> Request {
        return Request(signature: .ackFailure, items: [])
    }

    // MARK: - Chunking

    /// Split the message into protocol chunks
    public func chunk() throws -> [[Byte]] {
        let bytes = try pack()
        var chunks = [[Byte]]()
        let numChunks = ((bytes.count + 2) / Request.kMaxChunkSize) + 1

        for i in 0..<numChunks {
            let start = i * (Request.kMaxChunkSize - 2)
            var end = i == (numChunks - 1) ?
                start + (Request.kMaxChunkSize - 4) :
                start + (Request.kMaxChunkSize - 2) - 1

            if end >= bytes.count {
                end = bytes.count - 1
            }

            let count = UInt16(end - start + 1)
            let countBytes = try count.pack()

            if i == (numChunks - 1) {
                chunks.append(countBytes + bytes[start...end] + [0x00, 0x00])
            } else {
                chunks.append(countBytes + bytes[start...end])
            }
        }

        return chunks
    }

    /// Pack the message as a PackStream structure
    private func pack() throws -> [Byte] {
        let s = Structure(signature: signature.rawValue, items: items)
        return try s.pack()
    }
}

// MARK: - Transaction Mode

public enum TransactionMode: String, Sendable {
    case readonly = "r"
    case readwrite = "w"
}

// MARK: - CustomStringConvertible

extension Request: CustomStringConvertible {
    public var description: String {
        return "Request(\(signature), items: \(items.count))"
    }
}
