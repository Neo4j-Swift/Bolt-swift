import Foundation
import PackStream
import NIOCore
import NIOPosix
import NIOTransportServices

#if os(Linux)
import NIOSSL
#else
import Network
import Security
import CommonCrypto
#endif

// MARK: - Data SHA1 Extension

extension Data {
    func sha1() -> String {
        #if os(Linux)
        var copy = self
        return SHA1.hexString(from: &copy) ?? "Undefined"
        #else
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(self.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
        #endif
    }
}

// MARK: - Encrypted Socket

/// TLS-encrypted Bolt socket implementation
public class EncryptedSocket: UnencryptedSocket {
    public lazy var certificateValidator: CertificateValidatorProtocol = UnsecureCertificateValidator(
        hostname: self.hostname,
        port: UInt(self.port)
    )

    #if os(Linux)
    override func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> Bootstrap {
        let sslGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let trustRoot: NIOSSLTrustRoots = .default
        var cert: [NIOSSLCertificateSource] = []
        if let certFile = try? NIOSSLCertificate(file: "/tmp/server.der", format: .der) {
            cert.append(NIOSSLCertificateSource.certificate(certFile))
        }

        var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
        tlsConfiguration.trustRoots = trustRoot
        tlsConfiguration.certificateChain = cert
        tlsConfiguration.certificateVerification = .noHostnameVerification

        let sslContext = try! NIOSSLContext(configuration: tlsConfiguration)

        let verificationCallback: NIOSSLVerificationCallback = { [weak self] verificationResult, certificate in
            guard let self = self else { return .failed }

            let publicKey = (try? certificate.extractPublicKey().toSPKIBytes().toString()) ?? "No public key found"

            var didTrust = verificationResult == .certificateVerified
            if !didTrust && self.certificateValidator.shouldTrustCertificate(withSHA1: publicKey) {
                didTrust = true
            }

            if didTrust {
                self.certificateValidator.didTrustCertificate(withSHA1: publicKey)
                return .certificateVerified
            }

            return .failed
        }

        let openSslHandler = try! NIOSSLClientHandler(
            context: sslContext,
            serverHostname: self.hostname,
            verificationCallback: verificationCallback
        )

        return ClientBootstrap(group: sslGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { [weak self] channel in
                guard let self = self else {
                    return channel.eventLoop.makeSucceededVoidFuture()
                }
                return channel.pipeline.addHandler(openSslHandler).flatMap {
                    channel.pipeline.addHandler(dataHandler)
                }
            }
    }

    #else
    override func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> Bootstrap {
        let tsGroup = NIOTSEventLoopGroup(loopCount: 1, defaultQoS: .utility)

        #if BOLT_DEBUG
        print("EncryptedSocket: Setting up TLS bootstrap for \(self.hostname):\(self.port)")
        print("EncryptedSocket: Trusted certificates count: \(self.certificateValidator.trustedCertificates.count)")
        #endif

        return NIOTSConnectionBootstrap(group: tsGroup)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([dataHandler], position: .last)
            }
            .tlsConfig(validator: self.certificateValidator)
    }
    #endif
}

// MARK: - NIOTSConnectionBootstrap TLS Extension

#if !os(Linux)

/// Dispatch queue used for TLS certificate verification (following Hummingbird pattern)
private let tlsDispatchQueue = DispatchQueue(label: "bolt.tls.verify")

extension NIOTSConnectionBootstrap {
    func tlsConfig(validator: CertificateValidatorProtocol) -> NIOTSConnectionBootstrap {
        let options = NWProtocolTLS.Options()

        // Set SNI (Server Name Indication) for the hostname
        // This is required for cloud services like Neo4j Aura
        sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, validator.hostname)

        #if BOLT_DEBUG
        print("tlsConfig: hostname=\(validator.hostname), trustedCertificates.count=\(validator.trustedCertificates.count)")
        #endif

        // Only set up a custom verification block if we have custom trusted certificates
        // Following Hummingbird's pattern: for standard system CAs, don't override verification
        if !validator.trustedCertificates.isEmpty {
            #if BOLT_DEBUG
            print("tlsConfig: Setting up custom verification block for self-signed certificate")
            #endif

            sec_protocol_options_set_verify_block(
                options.securityProtocolOptions,
                { _, sec_trust, sec_protocol_verify_complete in
                    #if BOLT_DEBUG
                    print("tlsConfig: Verification block called")
                    #endif

                    let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()

                    // Set the custom certificates as anchors
                    SecTrustSetAnchorCertificates(trust, validator.trustedCertificates as CFArray)
                    // For self-signed certificates, we need to trust ONLY our anchors (not system CAs)
                    SecTrustSetAnchorCertificatesOnly(trust, true)

                    SecTrustEvaluateAsyncWithError(trust, tlsDispatchQueue) { _, result, error in
                        #if BOLT_DEBUG
                        print("tlsConfig: SecTrustEvaluateAsyncWithError result=\(result), error=\(String(describing: error))")
                        #endif

                        if let error = error {
                            print("TLS trust evaluation failed: \(error.localizedDescription)")
                        }

                        // Get certificate SHA1 for validator callback
                        if let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                           let firstCert = certChain.first {
                            let certData = SecCertificateCopyData(firstCert) as Data
                            let sha1 = certData.sha1()

                            #if BOLT_DEBUG
                            print("tlsConfig: Certificate SHA1: \(sha1)")
                            #endif

                            if result {
                                validator.didTrustCertificate(withSHA1: sha1)
                            }
                        }
                        sec_protocol_verify_complete(result)
                    }
                },
                tlsDispatchQueue
            )
        } else {
            #if BOLT_DEBUG
            print("tlsConfig: No trusted certificates, using default verification")
            #endif
        }

        return self.tlsOptions(options)
    }

    func tlsConfigDefault() -> NIOTSConnectionBootstrap {
        return self.tlsOptions(.init())
    }
}
#endif
