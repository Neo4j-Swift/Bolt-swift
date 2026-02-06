# Bolt-Swift Development Notes

## Testing Requirements

### Target Neo4j Versions
Tests must pass against all of the following Neo4j versions:
- Neo4j 3.5 (legacy)
- Neo4j 4.4 (LTS)
- Neo4j 5.26
- Neo4j 2025.12.1 (latest)
- Neo4j Aura (cloud)

### Test Platforms
- **Linux** (via Docker Swift container)
- **macOS** (native)

### TLS Testing
For each local Neo4j version, test both:
- Unencrypted connections (port 7687)
- TLS-encrypted connections (with self-signed certificates)

### Docker Test Environment

**Neo4j Containers:**
- graphgopher-neo4j: Unencrypted (macOS: localhost:7687, Docker: graphgopher-neo4j:7687)
- neo4j-tls: TLS-enabled (macOS: localhost:7691, Docker: neo4j-tls:7687)

**Swift Linux Container:**
```bash
# Create Swift container on the same network as Neo4j
docker run -d --name swift-linux \
  --network neo4j-tls-docker_default \
  -v /path/to/Neo4j:/workspace/Neo4j \
  swift:6.0 tail -f /dev/null

# Connect to Neo4j network if needed
docker network connect neo4j-tls-docker_default graphgopher-neo4j
```

### Running Tests

**Linux (Docker):**
```bash
# Run all unit tests (skip legacy sync socket tests)
docker exec -w /workspace/Neo4j/Bolt-swift \
  -e NEO4J_HOSTNAME=graphgopher-neo4j \
  -e NEO4J_PASSWORD=j4neo \
  swift-linux swift test --enable-test-discovery \
  --skip "UnencryptedSocketTests" --skip "EncryptedSocketTests"

# Run async integration tests only
docker exec -w /workspace/Neo4j/Bolt-swift \
  -e NEO4J_HOSTNAME=graphgopher-neo4j \
  -e NEO4J_PASSWORD=j4neo \
  swift-linux swift test --enable-test-discovery --filter "AsyncSocketTests"
```

**macOS:**
```bash
# Run all tests
swift test

# Run async integration tests
swift test --filter "AsyncSocketTests"

# Run TLS tests (requires neo4j-tls container)
swift test --filter "EncryptedSocketTests"
```

### Test Configuration

Tests support environment variable overrides:
- `NEO4J_HOSTNAME`: Override hostname (required for Docker)
- `NEO4J_PORT`: Override port
- `NEO4J_USERNAME`: Override username
- `NEO4J_PASSWORD`: Override password

Or edit `Tests/BoltTests/BoltSwiftTestConfig.json`:
```json
{
    "username": "neo4j",
    "password": "j4neo",
    "hostname": "localhost",
    "port": 7687,
    "hostUsesSelfSignedCertificate": false
}
```

### TLS Testing (macOS only)

TLS tests use Network.framework on macOS. The neo4j-tls Docker container provides a TLS-enabled Neo4j on port 7691.

Certificate setup is in `/path/to/neo4j-tls-docker/certificates/`:
- `public.crt`: PEM certificate
- `public.der`: DER certificate for macOS Security framework
- `private.key`: Private key

The certificate must have `extendedKeyUsage = serverAuth` for macOS to accept it.

## Bolt Protocol Versions

The library supports:
- Bolt 3 (Neo4j 3.5+)
- Bolt 4.0-4.4 (Neo4j 4.0-4.4)
- Bolt 5.0-5.6 (Neo4j 5.x)

Handshake proposes versions with ranges for better negotiation.

### Authentication Flow by Version

| Bolt Version | Auth in HELLO | Separate LOGON | LOGOFF Support |
|--------------|---------------|----------------|----------------|
| 3.0 - 5.0    | Yes           | No             | No             |
| 5.1+         | No            | Yes (required) | Yes            |

**Key difference for Bolt 5.1+:**
- HELLO message contains only `user_agent` and optional `routing` context (no auth)
- Authentication must be sent via separate LOGON message (signature 0x6A)
- Re-authentication is supported via LOGOFF (signature 0x6B) then LOGON

### Notification Filtering (Bolt 5.2+)
- `notifications_minimum_severity`: Minimum notification level
- `notifications_disabled_categories`: List of disabled notification categories

## Known Issues

*No current known issues.*

## Build Commands

```bash
# Build
swift build

# Test all (macOS)
swift test

# Test specific suite
swift test --filter "AsyncSocketTests"

# Linux: Run all tests
docker exec -w /workspace/Neo4j/Bolt-swift \
  -e NEO4J_HOSTNAME=graphgopher-neo4j \
  -e NEO4J_PASSWORD=j4neo \
  swift-linux swift test --enable-test-discovery \
  --skip "UnencryptedSocketTests" --skip "EncryptedSocketTests"
```
