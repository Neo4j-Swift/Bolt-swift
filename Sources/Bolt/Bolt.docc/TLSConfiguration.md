# Configuring TLS/SSL

Secure your Neo4j connections with proper TLS configuration.

## Overview

The Bolt library supports TLS-encrypted connections to Neo4j databases. This guide covers the various certificate validation options and how to configure them.

### Certificate Validation Options

The library provides several built-in certificate validators:

#### Trust System Certificates (Default)

Uses the system's trusted root certificates:

```swift
let settings = ConnectionSettings(
    host: "neo4j.example.com",
    port: 7687,
    username: "neo4j",
    password: "secret",
    encrypted: true
    // Uses system certificates by default
)
```

#### Trust Server Certificate

Trusts the server's certificate after initial connection (similar to SSH):

```swift
import Bolt

let validator = TrustServerCertificateValidator()

let settings = ConnectionSettings(
    host: "localhost",
    port: 7687,
    username: "neo4j",
    password: "password",
    encrypted: true,
    certificateValidator: validator
)
```

#### Allow All Certificates (Development Only)

Accepts any certificate without validation. **Use only for development:**

```swift
import Bolt

// WARNING: Insecure - for development only!
let validator = AllowAllCertificateValidator()

let settings = ConnectionSettings(
    host: "localhost",
    port: 7687,
    username: "neo4j",
    password: "password",
    encrypted: true,
    certificateValidator: validator
)
```

### Custom Certificate Validation

Implement ``CertificateValidatorProtocol`` for custom validation logic:

```swift
import Bolt

class CustomCertificateValidator: CertificateValidatorProtocol {
    func validate(
        certificates: [SecCertificate],
        host: String
    ) -> Bool {
        // Your custom validation logic
        return true
    }
}
```

### Unencrypted Connections

For local development or trusted networks, you can disable encryption:

```swift
let settings = ConnectionSettings(
    host: "localhost",
    port: 7687,
    username: "neo4j",
    password: "password",
    encrypted: false  // No TLS
)
```

## Topics

### Certificate Validators

- ``CertificateValidatorProtocol``
- ``AllowAllCertificateValidator``
- ``TrustServerCertificateValidator``

### Configuration

- ``SSLConfiguration``
