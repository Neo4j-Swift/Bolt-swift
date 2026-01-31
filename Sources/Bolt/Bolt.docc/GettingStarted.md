# Getting Started with Bolt

Learn how to establish connections and communicate with Neo4j using the Bolt protocol.

## Overview

The Bolt library provides low-level protocol support for communicating with Neo4j databases. For most applications, you should use the higher-level [Theo](https://github.com/Neo4j-Swift/Neo4j-Swift) client library instead.

### Creating a Connection

To connect to a Neo4j database, create a ``Connection`` with appropriate settings:

```swift
import Bolt

// Connection settings
let settings = ConnectionSettings(
    host: "localhost",
    port: 7687,
    username: "neo4j",
    password: "password",
    encrypted: true
)

// Create connection
let connection = Connection(settings: settings)

// Connect asynchronously
try connection.connect(timeout: 5000) { error in
    if let error = error {
        print("Connection failed: \(error)")
        return
    }
    print("Connected successfully!")
}
```

### Connection Settings

The ``ConnectionSettings`` class configures how the connection is established:

```swift
let settings = ConnectionSettings(
    host: "neo4j.example.com",
    port: 7687,
    username: "neo4j",
    password: "secret",
    encrypted: true,
    certificateValidator: TrustServerCertificateValidator()
)
```

### Sending Requests

Use the ``Request`` class to send Bolt protocol messages:

```swift
// Create a RUN request for a Cypher query
let request = Request.run(
    query: "MATCH (n:Person) RETURN n.name AS name",
    parameters: [:]
)

// Send the request
connection.request(request) { response in
    switch response {
    case .success(let records):
        for record in records {
            print(record)
        }
    case .failure(let error):
        print("Query failed: \(error)")
    }
}
```

### Handling Responses

Responses from Neo4j come in several forms:

- **SUCCESS**: Operation completed successfully with metadata
- **RECORD**: A data record from a query result
- **FAILURE**: An error occurred

```swift
connection.request(request) { response in
    // Process each response message
}
```

## Topics

### Core Types

- ``Connection``
- ``ConnectionSettings``
- ``Request``
- ``Response``
