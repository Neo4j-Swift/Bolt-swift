# Bolt-swift
The Bolt network protocol is a network protocol designed for high-performance access to graph databases. Bolt is a connection-oriented protocol, using a compact binary encoding over TCP or web sockets for higher throughput and lower latency.

The reference implementation can be found [here](https://github.com/neo4j-contrib/boltkit). This codebase is the Swift implementation, and is used by [Theo, the Swift Neo4j driver](https://github.com/Neo4j-Swift/Neo4j-Swift).

## Requirements

* macOS 14+ / iOS 17+ / tvOS 17+ / watchOS 10+ / Linux
* Swift 6.0+

## Connection
The implementation supports both SSL-encrypted and plain-text connections, built on [SwiftNIO 2](https://github.com/apple/swift-nio). SSL connections can be both have a regular chain of trust, be given an explicit certificate to trust, or be untrusted. Further more, you can implement your own trust behaviour on top.

## Tests

Note, tests are destructive to the data in the database under test, so run them on a database created especially for running the tests

## Getting started

### Swift Package Manager
Add the following to your dependencies array in Package.swift:
```swift
.package(url: "https://github.com/Neo4j-Swift/Bolt-swift.git", from: "6.0.0"),
```
and you can now do a
```bash
swift build
```
