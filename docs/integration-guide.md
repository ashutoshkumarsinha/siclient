# SICLient Integration Guide

This guide describes how to integrate SICLientCore into a host application or lab harness on macOS Tahoe.

## Quick Start

```swift
import SICLientCore

let profile = try ProfileLoader.load(fromPath: "profiles/lab-volte-01.json")
let platform = try PlatformContext.stubbed(profile: profile)
let pcscf = try platform.network.discoverPCSCF(profile: profile)
let transport = TransportFactory.make(endpoint: pcscf, profile: profile)
let logger = Logger(correlationID: CorrelationID(prefix: "app"))

let service = CallService(
    profile: profile,
    platform: platform,
    transport: transport,
    logger: logger
)

try await service.register()
let session = try await service.placeCall(to: "sip:callee@ims.example")
try await service.hangUp()
try await service.deregister()
```

## Platform Adapters

Replace stubs with real implementations:

| Adapter | Responsibility |
|---|---|
| `SimAdapter` | IMPI/IMPU and IMS-AKA (`akaChallenge`) |
| `NetworkAdapter` | P-CSCF discovery, local IP, DNS |
| `BearerAdapter` | Dedicated QCI=1 bearer request/release |
| `AccessInfoAdapter` | PANI / RAT for P-Access-Network-Info |

Use `MutableStubNetworkAdapter` and `MutableStubAccessInfoAdapter` in tests to simulate RAT handover.

## Network Resilience

When the host detects IP or RAT change, notify the client:

```swift
try await service.handleNetworkPathChange()
```

This forces re-registration when the access path or local IP changes. Automatic recovery after failed re-register uses exponential backoff up to `resilience.network_recovery_timeout_sec`.

## Transport

`TransportFactory.make` returns:

- UDP for default lab profiles
- `FallbackSIPTransport` when the profile lists both `udp` and `tcp` — large SIP messages (> `resilience.mtu_bytes`) and send failures fall back to TCP

Keep-alive mode is chosen automatically:

- **UDP:** double-CRLF
- **TCP/TLS:** SIP OPTIONS

## Media

Configure the profile `media` block:

```json
{
  "media": {
    "rtp_transport": "udp",
    "local_rtp_port": 40000,
    "enable_audio_io": false,
    "enable_video": false,
    "use_ffmpeg_codec": false
  }
}
```

Pass `enableMedia: false` to `CallService` for signaling-only tests.

## CLI Reference

```bash
swift run siclient --profile profiles/lab-volte-01.json --dry-run
swift run siclient --profile profiles/lab-volte-01.json --deregister
swift run siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:user@ims.example --call-duration 5 --hold --dtmf 5
```

## Lab Acceptance

```bash
chmod +x Tests/sipp/run-acceptance.sh
./Tests/sipp/run-acceptance.sh
```

## Error Handling

SIP responses are mapped via `SIPErrorMapper`:

| Code | Action |
|---|---|
| 401 | Re-authenticate |
| 403 | Stop |
| 408 / 503 | Retry with backoff |
| 481 / 487 | Dialog cleanup |

Registration retries honor `resilience.max_registration_retries`.

## Performance Targets (NFR)

| Metric | Target |
|---|---|
| Registration (loopback/lab) | < 2 s |
| MO call setup (registered) | < 3 s |

Measured in `PerformanceTests` against mock IMS.
