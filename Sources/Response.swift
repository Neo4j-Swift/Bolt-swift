import Foundation
import PackStream

// MARK: - Bolt Response

/// A Bolt protocol response message
public struct Response: Sendable {
    public let category: ResponseCategory
    public let items: [any PackProtocol]

    public init(category: ResponseCategory = .empty, items: [any PackProtocol] = []) {
        self.category = category
        self.items = items
    }

    // MARK: - Error Handling

    /// Convert failure response to an error
    public func asError() -> Error? {
        guard category == .failure else { return nil }

        for item in items {
            if let map = item as? Map,
               let message = map.dictionary["message"] as? String,
               let code = map.dictionary["code"] as? String {
                return BoltError.from(code: code, message: message)
            }
        }

        return nil
    }

    // MARK: - Metadata Extraction

    /// Extract metadata from SUCCESS response
    public var metadata: [String: any PackProtocol] {
        guard category == .success, let map = items.first as? Map else {
            return [:]
        }
        return map.dictionary
    }

    /// Extract bookmark from response
    public var bookmark: String? {
        metadata["bookmark"] as? String
    }

    /// Extract server info
    public var server: String? {
        metadata["server"] as? String
    }

    /// Extract connection ID
    public var connectionId: String? {
        metadata["connection_id"] as? String
    }

    /// Extract field names from RUN response
    public var fields: [String]? {
        guard let list = metadata["fields"] as? List else { return nil }
        return list.items.compactMap { $0 as? String }
    }

    /// Extract query statistics
    public var stats: [String: Int] {
        guard let statsMap = metadata["stats"] as? Map else { return [:] }
        var result: [String: Int] = [:]
        for (key, value) in statsMap.dictionary {
            if let intValue = value.intValue() {
                result[key] = Int(intValue)
            }
        }
        return result
    }

    /// Check if there are more records available
    public var hasMore: Bool {
        metadata["has_more"] as? Bool ?? false
    }

    /// Extract query ID (Bolt 4+)
    public var qid: Int? {
        metadata["qid"]?.intValue().map { Int($0) }
    }

    /// Extract notifications
    public var notifications: [BoltNotification] {
        guard let list = metadata["notifications"] as? List else { return [] }
        return list.items.compactMap { BoltNotification(from: $0) }
    }

    // MARK: - Chunking

    /// Parse multiple messages from chunked data
    public static func unchunk(_ bytes: [Byte]) throws -> [[Byte]] {
        var pos = 0
        var responses = [[Byte]]()

        while pos < bytes.count {
            let (responseBytes, endPos) = try unchunk(bytes[pos..<bytes.count], fromPos: pos)
            if !responseBytes.isEmpty {
                responses.append(responseBytes)
            }
            pos = endPos
        }

        return responses
    }

    private static func unchunk(_ bytes: ArraySlice<Byte>, fromPos: Int = 0) throws -> ([Byte], Int) {
        guard bytes.count >= 2 else {
            throw BoltError.protocol(message: "Too few bytes for chunk header")
        }

        var chunks = [[Byte]]()
        var hasMoreChunks = true
        var pos = fromPos

        while hasMoreChunks {
            let sizeBytes = bytes[pos..<(pos + 2)]
            pos += 2
            let size = Int(try UInt16.unpack(sizeBytes))

            if (pos + size >= bytes.endIndex) || (size == 0) {
                hasMoreChunks = false
            } else {
                let chunk = bytes[pos..<(pos + size)]
                pos += size
                if size > 0 {
                    chunks.append(Array(chunk))
                }
            }
        }

        let unchunkedBytes = chunks.flatMap { $0 }
        return (unchunkedBytes, pos)
    }

    // MARK: - Unpacking

    /// Unpack a response from bytes
    public static func unpack(_ bytes: [Byte]) throws -> Response {
        guard !bytes.isEmpty else {
            throw BoltError.protocol(message: "Empty response bytes")
        }

        let marker = Packer.Representations.typeFrom(representation: bytes[0])
        guard marker == .structure else {
            throw BoltError.protocol(message: "Expected structure marker, got \(marker)")
        }

        let structure = try Structure.unpack(bytes[0..<bytes.count])

        guard let category = ResponseCategory(rawValue: structure.signature) else {
            throw BoltError.protocol(message: "Invalid response signature: \(structure.signature)")
        }

        return Response(category: category, items: structure.items)
    }
}

// MARK: - Bolt Errors

/// Errors from Bolt protocol operations
public enum BoltError: Error, Sendable {
    case connection(message: String)
    case authentication(message: String)
    case `protocol`(message: String)
    case transaction(message: String)
    case database(message: String)
    case constraint(message: String)
    case syntax(message: String)
    case security(message: String)
    case transient(message: String)
    case service(message: String)
    case unknown(code: String, message: String)

    /// Parse Neo4j error code into appropriate error type
    public static func from(code: String, message: String) -> BoltError {
        // Parse error classification from code like "Neo.ClientError.Statement.SyntaxError"
        let parts = code.split(separator: ".")

        if parts.count >= 3 {
            let classification = String(parts[1])
            let category = parts.count >= 4 ? String(parts[2]) : ""

            switch classification {
            case "ClientError":
                switch category {
                case "Security":
                    if code.contains("Unauthorized") || code.contains("Authentication") {
                        return .authentication(message: message)
                    }
                    return .security(message: message)
                case "Statement":
                    if code.contains("SyntaxError") {
                        return .syntax(message: message)
                    }
                    return .database(message: message)
                case "Schema":
                    if code.contains("Constraint") {
                        return .constraint(message: message)
                    }
                    return .database(message: message)
                case "Transaction":
                    return .transaction(message: message)
                case "Request":
                    return .protocol(message: message)
                default:
                    return .database(message: message)
                }

            case "TransientError":
                return .transient(message: message)

            case "DatabaseError":
                return .database(message: message)

            default:
                break
            }
        }

        return .unknown(code: code, message: message)
    }
}

extension BoltError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connection(let message): return "Connection error: \(message)"
        case .authentication(let message): return "Authentication error: \(message)"
        case .protocol(let message): return "Protocol error: \(message)"
        case .transaction(let message): return "Transaction error: \(message)"
        case .database(let message): return "Database error: \(message)"
        case .constraint(let message): return "Constraint error: \(message)"
        case .syntax(let message): return "Syntax error: \(message)"
        case .security(let message): return "Security error: \(message)"
        case .transient(let message): return "Transient error: \(message)"
        case .service(let message): return "Service error: \(message)"
        case .unknown(let code, let message): return "[\(code)] \(message)"
        }
    }
}

// MARK: - Bolt Notification

/// A notification from Neo4j query execution
public struct BoltNotification: Sendable {
    public let code: String
    public let title: String
    public let description: String
    public let severity: String
    public let category: String?
    public let position: Position?

    public struct Position: Sendable {
        public let offset: Int
        public let line: Int
        public let column: Int
    }

    init?(from value: any PackProtocol) {
        guard let map = value as? Map else { return nil }

        guard let code = map.dictionary["code"] as? String,
              let title = map.dictionary["title"] as? String,
              let description = map.dictionary["description"] as? String,
              let severity = map.dictionary["severity"] as? String else {
            return nil
        }

        self.code = code
        self.title = title
        self.description = description
        self.severity = severity
        self.category = map.dictionary["category"] as? String

        if let posMap = map.dictionary["position"] as? Map {
            self.position = Position(
                offset: posMap.dictionary["offset"]?.intValue().map { Int($0) } ?? 0,
                line: posMap.dictionary["line"]?.intValue().map { Int($0) } ?? 0,
                column: posMap.dictionary["column"]?.intValue().map { Int($0) } ?? 0
            )
        } else {
            self.position = nil
        }
    }
}

// MARK: - Legacy Response Error (Deprecated)

extension Response {
    @available(*, deprecated, renamed: "BoltError")
    public enum ResponseError: Error {
        case tooFewBytes
        case invalidResponseType
        case syntaxError(message: String)
        case indexNotFound(message: String)
        case forbiddenDueToTransactionType(message: String)
        case constraintVerificationFailed(message: String)
        case requestInvalid(message: String)
        case serverOutOfMemory
    }

    @available(*, deprecated, renamed: "BoltRecordType")
    public struct RecordType {
        public static let node: Byte = 0x4E
        public static let relationship: Byte = 0x52
        public static let path: Byte = 0x50
        public static let unboundRelationship: Byte = 0x72
    }
}
