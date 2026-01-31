# ``Bolt``

A Swift implementation of the Neo4j Bolt protocol for database communication.

## Overview

Bolt is a connection-oriented protocol used to communicate with Neo4j databases. This library provides a low-level Swift implementation that handles:

- Connection establishment and version negotiation
- TLS/SSL encrypted connections
- Message framing and chunking
- Request/response handling
- Authentication

### Supported Bolt Versions

This implementation supports Bolt protocol versions:
- Bolt 5.4
- Bolt 5.3
- Bolt 5.2
- Bolt 5.1
- Bolt 5.0
- Bolt 4.4

### Key Components

The library is organized around several core components:

- **Connection**: Manages the lifecycle of a database connection
- **Request/Response**: Handles message serialization and deserialization
- **Socket**: Abstraction layer supporting both encrypted and unencrypted transport
- **SSL Configuration**: Flexible TLS configuration with certificate validation

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:TLSConfiguration>

### Connection Management

- ``Connection``
- ``ConnectionSettings``
- ``BoltVersion``

### Protocol Messages

- ``Request``
- ``Response``
- ``BoltMessageSignature``

### Networking

- ``SocketProtocol``
- ``EncryptedSocket``
- ``UnencryptedSocket``

### Security

- ``SSLConfiguration``
- ``CertificateValidatorProtocol``
- ``AllowAllCertificateValidator``
- ``TrustServerCertificateValidator``
