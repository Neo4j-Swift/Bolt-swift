import Foundation
import PackStream
import NIO
import NIOTransportServices

#if os(Linux)
import CNIOBoringSSL
import NIOSSL
import NIOTLS
#else
import Network
import Security
import CommonCrypto
#endif

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

public class EncryptedSocket: UnencryptedSocket {

    public lazy var certificateValidator: CertificateValidatorProtocol = UnsecureCertificateValidator(hostname: self.hostname, port: UInt(self.port))

    #if os(Linux)
    override func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> (Bootstrap) {

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let trustRoot: NIOSSLTrustRoots = .default
        var cert: [NIOSSLCertificateSource] = []
        if let certFile = try? NIOSSLCertificate(file: "/tmp/server.der", format: .der) {
            cert.append(NIOSSLCertificateSource.certificate(certFile))
        }

        var tlsConfiguration = TLSConfiguration.forClient(trustRoots: trustRoot, certificateChain: cert, privateKey: nil)
        tlsConfiguration.certificateVerification = .noHostnameVerification
        let sslContext = try! NIOSSLContext(configuration: tlsConfiguration)

        let verificationCallback: NIOSSLVerificationCallback = { verificationResult, certificate in

            let publicKey = (try? certificate.extractPublicKey().toSPKIBytes().toString()) ?? "No public key found"

            var didTrust: Bool = verificationResult == .certificateVerified
            if !didTrust && self.certificateValidator.shouldTrustCertificate(withSHA1: publicKey) {
                didTrust = true
            }

            if didTrust {
                self.certificateValidator.didTrustCertificate(withSHA1: publicKey)
                return .certificateVerified
            }

            return .failed
        }

        let openSslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: self.hostname, verificationCallback: verificationCallback)
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                self.channel = channel
                return channel.pipeline.addHandler(openSslHandler ).flatMap {
                    channel.pipeline.addHandler(dataHandler)
                }
            }

        return bootstrap
    }
    #else
    override func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> (Bootstrap) {

        let group = NIOTSEventLoopGroup()

        return NIOTSConnectionBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                self.channel = channel
                return channel.pipeline.addHandler(dataHandler)
            }
            .tlsConfig(validator: self.certificateValidator)
    }
    #endif
}

#if os(Linux)
#else
extension NIOTSConnectionBootstrap {

    func tlsConfig(validator: CertificateValidatorProtocol) -> NIOTSConnectionBootstrap {
        let options = NWProtocolTLS.Options()
        let verifyQueue = DispatchQueue(label: "verifyQueue")
        let verifyBlock: sec_protocol_verify_t = { (metadata, trust, verifyCompleteCB) in
            let actualTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if(validator.trustedCertificates.count > 0) {
                SecTrustSetAnchorCertificates(actualTrust, validator.trustedCertificates as CFArray)
            }
            SecTrustSetPolicies(actualTrust, SecPolicyCreateSSL(true, nil))

            // only available starting with macOS 10.15 & iOS 13
            // let serverName = sec_protocol_metadata_get_server_name(metadata)

            SecTrustEvaluateAsyncWithError(actualTrust, verifyQueue) { (trust, result, error) -> Void in
            // SecTrustEvaluateAsync(actualTrust, verifyQueue) { (trust, result, error) in

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

                guard let sha1 = optionalSha1, sha1 != "" else {
                    verifyCompleteCB(false)
                    return
                }

                // switch result {
                // case .proceed, .unspecified:@
                if result {
                    validator.didTrustCertificate(withSHA1: sha1)
                    verifyCompleteCB(true)
                // default:
                } else {
                    if(!validator.shouldTrustCertificate(withSHA1: sha1)) {
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
        return self.tlsOptions(.init()) // To remove TLS (unencrypted), just return self
    }
}
#endif
