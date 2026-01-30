import Foundation
import PackStream
import NIOCore
import NIOPosix
import NIOTransportServices

// MARK: - Bootstrap Protocol

internal protocol Bootstrap {
    func connect(host: String, port: Int) -> EventLoopFuture<Channel>
}

#if os(Linux)
extension ClientBootstrap: Bootstrap {}
#else
extension NIOTSConnectionBootstrap: Bootstrap {}
#endif

// MARK: - Promise Holder

struct PromiseHolder: Sendable {
    let uuid: UUID = UUID()
    let promise: EventLoopPromise<[UInt8]>
}

// MARK: - Unencrypted Socket

/// Unencrypted Bolt socket implementation using SwiftNIO
public class UnencryptedSocket: @unchecked Sendable {
    let hostname: String
    let port: Int

    private var group: EventLoopGroup?
    private var bootstrap: Bootstrap?
    private var channel: Channel?

    private var activePromises: [PromiseHolder] = []
    private let promiseLock = NSLock()

    private let dataHandler = ReadDataHandler()

    public init(hostname: String, port: Int) throws {
        self.hostname = hostname
        self.port = port
    }

    #if os(Linux)
    func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> Bootstrap {
        return ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(dataHandler)
            }
    }
    #else
    func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> Bootstrap {
        let tsGroup = NIOTSEventLoopGroup(loopCount: 1, defaultQoS: .utility)
        return NIOTSConnectionBootstrap(group: tsGroup)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([dataHandler], position: .last)
            }
    }
    #endif
}

// MARK: - SocketProtocol Conformance

extension UnencryptedSocket: SocketProtocol {
    public func connect(timeout: Int, completion: @escaping @Sendable (Error?) -> Void) throws {
        dataHandler.dataReceivedBlock = { [weak self] data in
            guard let self = self else { return }
            self.promiseLock.lock()
            let promise = self.activePromises.first?.promise
            self.promiseLock.unlock()
            promise?.succeed(data)
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        #if os(Linux)
        var bootstrap = setupBootstrap(group, dataHandler) as! ClientBootstrap
        bootstrap = bootstrap.connectTimeout(TimeAmount.milliseconds(Int64(timeout)))
        #else
        var bootstrap = setupBootstrap(group, dataHandler) as! NIOTSConnectionBootstrap
        bootstrap = bootstrap.connectTimeout(TimeAmount.milliseconds(Int64(timeout)))
        #endif

        self.bootstrap = bootstrap

        bootstrap.connect(host: hostname, port: port).map { theChannel -> Void in
            self.channel = theChannel
        }.whenComplete { result in
            switch result {
            case .failure(let error):
                completion(error)
            case .success:
                completion(nil)
            }
        }
    }

    public func disconnect() {
        try? channel?.close(mode: .all).wait()
        try? group?.syncShutdownGracefully()
    }

    public func send(bytes: [Byte]) -> EventLoopFuture<Void>? {
        guard let channel = channel else { return nil }

        let promise: EventLoopPromise<Void> = channel.eventLoop.makePromise()

        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)

        channel.writeAndFlush(buffer).whenComplete { result in
            switch result {
            case .failure(let error):
                #if BOLT_DEBUG
                print("Send error: \(error)")
                #endif
                promise.fail(error)
            case .success:
                promise.succeed(())
            }
        }

        return promise.futureResult
    }

    public func receive(expectedNumberOfBytes: Int32) throws -> EventLoopFuture<[Byte]>? {
        guard let readPromise = channel?.eventLoop.makePromise(of: [Byte].self) else {
            return nil
        }

        let holder = PromiseHolder(promise: readPromise)

        promiseLock.lock()
        activePromises.append(holder)
        promiseLock.unlock()

        channel?.read()

        readPromise.futureResult.whenComplete { [weak self] _ in
            guard let self = self else { return }
            self.promiseLock.lock()
            self.activePromises = self.activePromises.filter { $0.uuid != holder.uuid }
            self.promiseLock.unlock()
        }

        return readPromise.futureResult
    }
}

// MARK: - Byte Array Extensions

extension Array where Element == Byte {
    func toString() -> String {
        return self.reduce("") { (oldResult, i) -> String in
            return oldResult + (oldResult == "" ? "" : ":") + String(format: "%02x", i)
        }
    }
}

// MARK: - Data Hex Encoding

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let hexDigits = Array((options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef").utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * count)
        for byte in self {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
            chars.append(contentsOf: ", 0x".utf16)
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}
