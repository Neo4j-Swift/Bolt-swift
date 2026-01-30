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
        let tsGroup = NIOTSEventLoopGroup()

        return NIOTSConnectionBootstrap(group: tsGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(dataHandler)
            }
            .tlsConfig(validator: self.certificateValidator)
    }
    #endif
}

// MARK: - NIOTSConnectionBootstrap TLS Extension

#if !os(Linux)
extension NIOTSConnectionBootstrap {
    func tlsConfig(validator: CertificateValidatorProtocol) -> NIOTSConnectionBootstrap {
        let options = NWProtocolTLS.Options()
        let verifyQueue = DispatchQueue(label: "bolt.tls.verify")

        let verifyBlock: sec_protocol_verify_t = { metadata, trust, verifyCompleteCB in
            let actualTrust = sec_trust_copy_ref(trust).takeRetainedValue()

            if !validator.trustedCertificates.isEmpty {
                SecTrustSetAnchorCertificates(actualTrust, validator.trustedCertificates as CFArray)
            }

            SecTrustSetPolicies(actualTrust, SecPolicyCreateSSL(true, nil))

            SecTrustEvaluateAsync(actualTrust, verifyQueue) { trust, result in
                var optionalSha1: String?
                let count = SecTrustGetCertificateCount(trust)

                if count >= 1 {
                    for index in 0..<count {
                        if let cert = SecTrustGetCertificateAtIndex(trust, index) {
                            let certData = SecCertificateCopyData(cert) as Data
                            optionalSha1 = certData.sha1()
                            break
                        }
                    }
                } else {
                    verifyCompleteCB(false)
                    return
                }

                guard let sha1 = optionalSha1, !sha1.isEmpty else {
                    verifyCompleteCB(false)
                    return
                }

                switch result {
                case .proceed, .unspecified:
                    validator.didTrustCertificate(withSHA1: sha1)
                    verifyCompleteCB(true)
                default:
                    if !validator.shouldTrustCertificate(withSHA1: sha1) {
                        verifyCompleteCB(false)
                    } else {
                        validator.didTrustCertificate(withSHA1: sha1)
                        verifyCompleteCB(true)
                    }
                }
            }
        }

        sec_protocol_options_set_verify_block(options.securityProtocolOptions, verifyBlock, verifyQueue)
        return self.tlsOptions(options)
    }

    func tlsConfigDefault() -> NIOTSConnectionBootstrap {
        return self.tlsOptions(.init())
    }
}
#endif
