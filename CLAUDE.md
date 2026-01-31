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
Neo4j containers are on the `neo4j_default` network:
- neo4j-3.5: 172.18.0.2:7687 (macOS: localhost:7687)
- neo4j-4.4: 172.18.0.3:7687 (macOS: localhost:7688)
- neo4j-5.26: 172.18.0.4:7687 (macOS: localhost:7689)
- neo4j-2025: 172.18.0.5:7687 (macOS: localhost:7690)

Swift container is on the same network for Linux testing.

### Running Tests

**Linux (Docker):**
```bash
docker exec -w /workspace/Neo4j/Bolt-swift swift swift test --enable-test-discovery --filter "AsyncSocketTests"
```

**macOS:**
```bash
swift test --filter "AsyncSocketTests"
```

### Test Configuration
Edit `Tests/BoltTests/BoltSwiftTestConfig.json` to point to the target Neo4j instance:
```json
{
    "username": "neo4j",
    "password": "j4neo",
    "hostname": "172.18.0.3",  // or "localhost" for macOS
    "port": 7687,
    "hostUsesSelfSignedCertificate": false
}
```

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

# Test all
swift test

# Test specific suite
swift test --filter "AsyncSocketTests"

# Linux test with discovery
docker exec -w /workspace/Neo4j/Bolt-swift swift swift test --enable-test-discovery
```
