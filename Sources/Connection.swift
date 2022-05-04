import Foundation
import PackStream
import NIO

#if os(Linux)
import Dispatch
#endif

public class Connection: NSObject {

    private let settings: ConnectionSettings

    private var socket: SocketProtocol
    public var currentTransactionBookmark: String?
    public var isConnected = false
    
    private var currentEventLoop: EventLoop? = nil
    
    public init(socket: SocketProtocol,
                settings: ConnectionSettings = ConnectionSettings() ) {

        self.socket = socket
        self.settings = settings

        super.init()
    }

    public func connect(completion: @escaping (_ error: Error?) throws -> Void) throws {
        try socket.connect(timeout: 2500 /* in ms */) { error in
            
            if let error = error {
                try? completion(error)
                return
            }
            
            var eventLoop: EventLoop? = self.currentEventLoop ?? MultiThreadedEventLoopGroup.currentEventLoop
            if eventLoop == nil {
                let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                eventLoop = eventLoopGroup.next()
            }
            guard let currentEventLoop = eventLoop else {
                print("Error getting current eventloop")
                return
            }
            
            self.currentEventLoop = currentEventLoop
            
            self.initBolt(on: currentEventLoop).whenSuccess { wasSuccess in
                
                if wasSuccess == false {
                    #if BOLT_DEBUG
                    print("Hmm, this was no success")
                    #endif
                    try? completion(ConnectionError.unknownError)
                    return
                }
            
                let initFuture = self.initialize(on: currentEventLoop)
                initFuture.map { (response) in
                    self.isConnected = true
                    try? completion(nil)
                }.whenFailure { error in
                    try? completion(ConnectionError.unknownError)
                }
            }
        }
    }

    public func disconnect() {
        isConnected = false
        socket.disconnect()
    }

    private func initBolt(on eventLoop: EventLoop) -> EventLoopFuture<Bool> {
        
        let initPromise = eventLoop.makePromise(of: Bool.self)
        
        self.socket.send(bytes: [0x60, 0x60, 0xB0, 0x17, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])?.whenSuccess { promise in

            var version: UInt32 = 0
            _ = try? self.socket.receive(expectedNumberOfBytes: 4).map { response -> (Bool) in
                _ = response.map { bytes -> Void in
                    do {
                        version = try UInt32.unpack(bytes[0..<bytes.count])
                        initPromise.succeed(version != 0)
                    } catch {
                        version = 0
                        initPromise.succeed(false)
                    }
                }
                
                return version == 1
            }
        }
        
        return initPromise.futureResult
        
    }
    
    public func readOnlyMode(_ blockToBePerformed: @escaping () -> ()) {
        guard let currentEventLoop = self.currentEventLoop else {
            #if BOLT_DEBUG
            print("Event loop is missing")
            #endif
            return
        }
        
        let readonlyTransactionRequest = Request.begin(mode: .readonly)
        
        let chunks = try? readonlyTransactionRequest.chunk()
        let sendFutures = chunks?.compactMap({ (chunk) -> EventLoopFuture<Void>? in
            socket.send(bytes: chunk)
        })
        
        // let maxChunkSize = Int32(Request.kMaxChunkSize)
        
        // let promise = currentEventLoop.makePromise(of: Response.self)
        // var accumulatedData: [Byte] = []
        
        func loop(message: Request) {
            // First, we call `read` to read in the next chunk and hop
            // over to `eventLoop` so we can safely write to `accumulatedChunks`
            // without a lock.
            blockToBePerformed()
            /*
            do {
                
                try socket.receive(expectedNumberOfBytes: maxChunkSize)?.hop(to: eventLoop).map { responseData in
                    print("loop() got \(responseData.count) bytes")
                    // Next, we just append the chunk to the accumulation
                    accumulatedData.append(contentsOf: responseData)
                    
                    // chunk terminated by 0x00 0x00
                    if (responseData[responseData.count - 1] == 0 && responseData[responseData.count - 2] == 0) == false {
                        loop(message: message)
                    } else {
                        
                        let unchunkedResponseDatas = try? Response.unchunk(accumulatedData)
                        for unchunkedResponseData in unchunkedResponseDatas ?? [] {
                            if let unpackedResponse = try? Response.unpack(unchunkedResponseData) {
                                if unpackedResponse.category != .success {
                                    promise.fail(ConnectionError.authenticationError)
                                    return
                                }
                                promise.succeed(unpackedResponse)
                            }
                        }
                    }
                }.cascadeFailure(to: promise) // if anything goes wrong, we fail the whole thing.

            } catch {
                promise.fail(error)
            }
            */
            
        }

        if let futures = sendFutures {
            let future =  EventLoopFuture<Void>.andAllSucceed(futures, on: currentEventLoop)
            future.whenSuccess {
                blockToBePerformed()
                // loop(message: readOnlyModeRequest)
            }
            future.whenFailure { error in
                print("Sending chunks gave an error: \(error)")
            }
        }
        
        // return promise.futureResult
    }
    
    /*
    public func setReadOnlyMode() {
           do {
               let setReadOnlyMode = Request.setMode("r")
               let chunks = try setReadOnlyMode.chunk()
               for chunk in chunks {
                   try socket.send(bytes: chunk)
               }
               
               let maxChunkSize = Int32(Request.kMaxChunkSize)
               var responseData = try socket.receive(expectedNumberOfBytes: maxChunkSize)
               while (responseData[responseData.count - 1] == 0 && responseData[responseData.count - 2] == 0) == false { // chunk terminated by 0x00 0x00
                   let additionalResponseData = try socket.receive(expectedNumberOfBytes: maxChunkSize)
                   responseData.append(contentsOf: additionalResponseData)
               }

               let unchunkedResponseDatas = try Response.unchunk(responseData)
               for unchunkedResponseData in unchunkedResponseDatas {
                   let unpackedResponse = try Response.unpack(unchunkedResponseData)
                   if unpackedResponse.category != .success {
                       throw ConnectionError.authenticationError
                   }
               }

               
           } catch {
               print("Got error when setting read only mode")
           }
       }*/
    
    private func initialize(on eventLoop: EventLoop) -> EventLoopFuture<Response> {
        let message = Request.initialize(settings: settings)
        // print("--v--> \(String(describing: message)))")
        let chunks = try? message.chunk()
        let sendFutures = chunks?.compactMap({ (chunk) -> EventLoopFuture<Void>? in
            socket.send(bytes: chunk)
        })
        
        let maxChunkSize = Int32(Request.kMaxChunkSize)
        
        let promise = eventLoop.makePromise(of: Response.self)
        var accumulatedData: [Byte] = []
        
        func loop(message: Request) {
            // print("_x_loop for \(message.command)")
            // First, we call `read` to read in the next chunk and hop
            // over to `eventLoop` so we can safely write to `accumulatedChunks`
            // without a lock.
            do {
                try socket.receive(expectedNumberOfBytes: maxChunkSize)?.hop(to: eventLoop).map { responseData in
                    // print("loop() got \(responseData.count) bytes")
                    // Next, we just append the chunk to the accumulation
                    accumulatedData.append(contentsOf: responseData)
                    
                    // chunk terminated by 0x00 0x00
                    if (responseData[responseData.count - 1] == 0 && responseData[responseData.count - 2] == 0) == false {
                        loop(message: message)
                    } else {
                        
                        let unchunkedResponseDatas = try? Response.unchunk(accumulatedData)
                        for unchunkedResponseData in unchunkedResponseDatas ?? [] {
                            if let unpackedResponse = try? Response.unpack(unchunkedResponseData) {
                                if unpackedResponse.category != .success {
                                    promise.fail(ConnectionError.authenticationError)
                                    return
                                }
                                promise.succeed(unpackedResponse)
                            }
                        }
                    }
                }.cascadeFailure(to: promise) // if anything goes wrong, we fail the whole thing.

            } catch {
                promise.fail(error)
            }
            
        }

        if let futures = sendFutures {
            let future =  EventLoopFuture<Void>.andAllSucceed(futures, on: eventLoop)
            future.whenSuccess {
                loop(message: message)
            }
            future.whenFailure { error in
                print("Sending chunks gave an error: \(error)")
            }
        }
        
        return promise.futureResult
    }

    public enum ConnectionError: Error {
        case unknownVersion
        case noConnection
        case authenticationError
        case requestError
        case unknownError
    }

    public enum CommandResponse: Byte {
        case success = 0x70
        case record = 0x71
        case ignored = 0x7e
        case failure = 0x7f
    }

    private func chunkAndSend(request: Request) throws -> [EventLoopFuture<Void>] {

        let chunks = try request.chunk()

        let futures = chunks.compactMap { socket.send(bytes: $0) }

        return futures
    }

    private func parseMeta(_ meta: [PackProtocol]) {
        for item in meta {
            if let map = item as? Map {
                for (key, value) in map.dictionary {
                    switch key {
                    case "bookmark", "bookmarks":
                        self.currentTransactionBookmark = value as? String
                    case "stats":
                        break
                    case "result_available_after", "t_first":
                        break
                    case "result_consumed_after", "t_last":
                        break
                    case "type":
                        break
                    case "fields":
                        break
                    default:
                        print("Couldn't parse metadata \(key): \(value)")
                    }
                }
            }
        }
    }

    public func request(_ request: Request) -> EventLoopFuture<[Response]> {

        #if BOLT_DEBUG
        print("-> " + String(describing: request))
        #endif
        
        // print("MultiThreadedEventLoopGroup.currentEventLoop = \(MultiThreadedEventLoopGroup.currentEventLoop == nil ? "nil" : "not nil")")
        let theEventLoop = MultiThreadedEventLoopGroup.currentEventLoop ?? MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        // print("Request running on event loop thread: \(theEventLoop.description)")
        
        if isConnected == false {
            print("Bolt client is not connected")
            return theEventLoop.makeFailedFuture(ConnectionError.noConnection)
        }
        
        var futures: [EventLoopFuture<Void>] = []
        do {
            futures = try chunkAndSend(request: request)
        } catch {
            return theEventLoop.makeFailedFuture(ConnectionError.requestError)
        }
        let future = futures.count == 1 ? futures.first! : EventLoopFuture<Void>.andAllComplete(futures, on: theEventLoop)

        let maxChunkSize = Int32(Request.kMaxChunkSize)
        var accumulatedData: [Byte] = []
        
        let promise = theEventLoop.makePromise(of: [Response].self)
        
        func loop() {
            #if BOLT_DEBUG
            print("<->loop for \(request.command)")
            #endif
            // First, we call `read` to read in the next chunk and hop
            // over to `eventLoop` so we can safely write to `accumulatedChunks`
            // without a lock.
            do {
                #if BOLT_DEBUG
                print("-- ask to receive")
                #endif
                let future = try socket.receive(expectedNumberOfBytes: maxChunkSize)
                _ = future?.map{ responseData in
                // future?.whenSuccess { responseData in
                // future?.hop(to: eventLoop).map { responseData in

                // future?.whenSuccess { responseData in
                // future?.hop(to: eventLoop).map { responseData in
                    // Next, we just append the chunk to the accumulation

                    #if BOLT_DEBUG
                    print("-- append response")
                    #endif
                    accumulatedData.append(contentsOf: responseData)

                    if responseData.count < 2 {
                        print("Error, got too little data back")
                        #if BOLT_DEBUG
                        print(request)
                        print(request.command)
                        print(request.items)
                        #endif
                        loop()
                        return
                    }

                    // chunk terminated by 0x00 0x00
                    if (responseData[responseData.count - 1] == 0 && responseData[responseData.count - 2] == 0) == false {
                        print("chunk not terminated as expected")
                        loop()
                        return
                    }
                    
                    let unchunkedResponsesAsBytes = try? Response.unchunk(accumulatedData)

                    var responses = [Response]()
                    var success = true

                    #if BOLT_DEBUG
                    print("-- success response, so process")
                    #endif
                    for responseBytes in unchunkedResponsesAsBytes ?? [] {
                        if let response = try? Response.unpack(responseBytes) {
                            responses.append(response)

                            if let error = response.asError() {
                                print("Error! \(error)")
                                promise.fail(error)
                                return
                            }

                            if response.category != .record {
                                #if BOLT_DEBUG
                                print("Get metadata")
                                #endif
                                self.parseMeta(response.items)
                            }

                            success = success && response.category != .failure
                        } else {
                            print("Error: failed to parse response")
                            return
                        }
                    }

                    // Get more if not ending in a summary
                    if success == true && responses.count > 1 && responses.last!.category == .record {
                        #if BOLT_DEBUG
                        print("-- must loop again")
                        #endif
                        loop()
                        return
                    }

                    #if BOLT_DEBUG
                    print("-- promise succeeds")
                    // print(String(describing: promise))
                    #endif
                    promise.succeed(responses)
                        
                }.cascadeFailure(to: promise) // if anything goes wrong, we fail the whole thing.

            } catch {
                promise.fail(error)
            }
            
        }

        future.whenComplete { result in
            switch result {
            case .failure(let error):
                print(String(describing: error))
            case .success(_):
                loop()
            }
        }
        
        return promise.futureResult
    }

}
