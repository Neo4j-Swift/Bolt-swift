import Foundation
import NIOCore
import PackStream

// MARK: - Read Data Handler

/// NIO channel handler for reading Bolt protocol data
final class ReadDataHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var dataBuffer: [UInt8] = []
    private let lock = NSLock()

    var dataReceivedBlock: (@Sendable ([UInt8]) -> Void)?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)

        defer {
            context.fireChannelRead(data)
        }

        let readableBytes = buffer.readableBytes
        guard readableBytes > 0 else {
            context.close(promise: nil)
            return
        }

        let bytes = buffer.getBytes(at: 0, length: readableBytes) ?? []

        // Handle 4-byte init response
        if readableBytes == 4 && bytes[0] == 0 && bytes[1] == 0 {
            dataReceivedBlock?(bytes)
            return
        }

        lock.lock()
        dataBuffer.append(contentsOf: bytes)
        let currentBuffer = dataBuffer
        lock.unlock()

        // Check if we have a complete message
        guard messageIsTerminated(currentBuffer) else {
            return
        }

        if !messageIsError(currentBuffer),
           messageShouldEndInSummary(currentBuffer),
           !messageEndsInSummary(currentBuffer) {
            return
        }

        // Complete message received
        lock.lock()
        let receivedBuffer = dataBuffer
        dataBuffer = []
        lock.unlock()

        dataReceivedBlock?(receivedBuffer)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        #if BOLT_DEBUG
        print("Socket error: \(error)")
        #endif
        context.close(promise: nil)
    }

    // MARK: - Message Analysis

    private func messageIsTerminated(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2 else { return false }
        return bytes[bytes.count - 1] == 0 && bytes[bytes.count - 2] == 0
    }

    private func messageIsError(_ bytes: [UInt8]) -> Bool {
        guard bytes.count > 4 else { return false }
        return bytes[3] == ResponseCategory.failure.rawValue &&
               bytes[bytes.count - 1] == 0 &&
               bytes[bytes.count - 2] == 0
    }

    private func messageShouldEndInSummary(_ bytes: [UInt8]) -> Bool {
        lock.lock()
        let buffer = dataBuffer
        lock.unlock()

        guard buffer.count > 3 else { return false }

        if buffer[3] == ResponseCategory.record.rawValue {
            return true
        }
        return bytes.count > 256
    }

    private func findPositionOfTerminator(in bytes: ArraySlice<UInt8>) -> Int? {
        guard bytes.count >= 2 else { return nil }

        for i in bytes.startIndex..<(bytes.endIndex - 1) {
            if bytes[i] == 0 && bytes[i + 1] == 0 {
                return i
            }
        }
        return nil
    }

    private func messageEndsInSummary(_ bytes: [UInt8]) -> Bool {
        let byteCount = bytes.count
        let limiter = 400
        let slice = byteCount > limiter ?
            bytes[(byteCount - limiter)..<byteCount] :
            bytes[0..<byteCount]

        if let positionOfTerminator = findPositionOfTerminator(in: slice) {
            let fixedSlice = Array<UInt8>(bytes[(positionOfTerminator + 2)..<byteCount])
            if let chunks = try? Response.unchunk(fixedSlice),
               let lastChunk = chunks.last,
               let lastRecord = try? Response.unpack(lastChunk) {
                if lastRecord.category == .success {
                    return true
                }
            }
        }

        // Long path - parse all chunks
        lock.lock()
        let buffer = dataBuffer
        lock.unlock()

        do {
            let chunks = try Response.unchunk(buffer)
            let packs = try chunks.map { try Response.unpack($0) }
            if let lastResponse = packs.last {
                return lastResponse.category == .success
            }
        } catch {}

        return false
    }
}
