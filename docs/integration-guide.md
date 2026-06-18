# SICLient Integration Guide

This guide describes how to integrate SICLientCore into a host application, lab harness, or the included SwiftUI console on macOS Tahoe.

**Related:** [user-guide.md](user-guide.md) (CLI/GUI usage) · [deployment-guide.md](deployment-guide.md) (install and configure)

## Quick Start (library)

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

Every public type in `SICLientCore` includes doc comments and file headers explaining IMS terminology — read `CallService.swift` and `RegistrationFSM.swift` first.

## Quick Start (CLI)

```bash
swift run siclient --profile profiles/lab-volte-01.json --dry-run
swift run siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:callee@ims.example --call-duration 5 --hold --dtmf 5
```

## Quick Start (GUI)

```bash
swift run siclient-gui
```

1. Enter path to `profiles/lab-volte-01.json` and click **Load profile**
2. **Register** → place a call, hold/resume, DTMF, SMS, or emergency call
3. Activity log appears in the detail pane

For automated testing without a display, use `ClientViewModel` injection (see `Tests/SICLientGUITests/`).

## Platform Adapters

Replace stubs with real implementations:

| Adapter | Responsibility |
|---|---|
| `SimAdapter` | IMPI/IMPU and IMS-AKA (`akaChallenge`) |
| `NetworkAdapter` | P-CSCF discovery (static, PCO, DHCP, DNS SRV) |
| `BearerAdapter` | Dedicated QCI=1 bearer request/release |
| `AccessInfoAdapter` | PANI / RAT for P-Access-Network-Info |

Use `SimAdapterFactory` to select `LabSimAdapter` vs `KeychainSimAdapter` (`SICLIENT_KEYCHAIN_ACCOUNT` env var).

Use `MutableStubNetworkAdapter` and `MutableStubAccessInfoAdapter` in tests to simulate RAT handover.

## Network Resilience

When the host detects IP or RAT change:

```swift
try await service.handleNetworkPathChange()
```

Registration loss (403/408 during re-register) triggers `terminateAllCalls` — active dialogs receive BYE.

Automatic recovery after failed re-register uses exponential backoff up to `resilience.network_recovery_timeout_sec`.

## Transport

`TransportFactory.make` returns:

- UDP for default lab profiles
- `TLSTransport` when profile `security.mechanism` is `tls`
- `FallbackSIPTransport` when the profile lists both `udp` and `tcp` — large SIP messages (> `resilience.mtu_bytes`) fall back to TCP

Keep-alive mode:

- **UDP:** double-CRLF
- **TCP/TLS:** SIP OPTIONS

Wrap with `RecordingSIPTransport` + `PcapExporter` to capture signaling for Wireshark.

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

## Phase 5 Features

### Emergency call

```bash
swift run siclient --profile profiles/lab-volte-01.json --emergency-call tel:112
```

```swift
let emergencyContext = try await service.registerEmergency()
let session = try await service.placeEmergencyCall(registration: emergencyContext)
```

### SMS over IMS

```bash
swift run siclient --profile profiles/lab-volte-01.json --send-sms tel:+15551212 "hello"
```

Enable `services.sms.use_3gpp_payload` for RP-DATA binary body.

### Call forwarding (XCAP)

```bash
swift run siclient --profile profiles/lab-volte-01.json --set-call-forwarding tel:+15559876
swift run siclient --profile profiles/lab-volte-01.json --fetch-call-forwarding
```

### EVS premium profile

Use `profiles/lab-volte-evs-premium.json` with `codecs.audio: ["EVS", "AMR-WB", "AMR"]`.

### eSRVCC / STIR-SHAK

Enable in profile `services.handover`. STIR-SHAK adds an `Identity` header on MO INVITE; eSRVCC hooks fire via `beginESRVCCHandover()` / `completeESRVCCHandover()` during an active call.

## Phase 6 Features

| Feature | Integration |
|---|---|
| AUTS resync | Automatic on sync failure from `LabSimAdapter`; `DigestCredentials.auts` on re-REGISTER |
| TLS pinning | `security.tls.pinned_cert_sha256` in profile |
| PCO/DHCP P-CSCF | `pcscf.mode: "pco"` or env `SICLIENT_PCO_PCSCF` |
| Concurrent calls | Second `placeCall` auto-holds first; `heldSession()` API |
| Profile hot-reload | `ProfileManager.reload()` |
| Key zeroization | `SecureMemory` after AKA operations |

## Error Handling

SIP responses are mapped via `SIPErrorMapper`:

| Code | Action |
|---|---|
| 401 | Re-authenticate |
| 403 | Stop; may trigger call teardown on re-register |
| 408 / 503 | Retry with backoff |
| 481 / 487 | Dialog cleanup |

Registration retries honor `resilience.max_registration_retries`.

## Performance Targets (NFR)

| Metric | Target |
|---|---|
| Registration (loopback/lab) | < 2 s |
| MO call setup (registered) | < 3 s |

Measured in `PerformanceTests` against mock IMS.

## Testing

```bash
swift test                              # 122 tests (core + GUI)
swift test --filter FeatureCoverage     # broad feature matrix
swift test --filter SICLientGUITests    # GUI ViewModel + CLI smoke
./Tests/gui/run-gui-smoke.sh            # GUI build verification
./Tests/sipp/run-acceptance.sh          # full acceptance suite
```

See `docs/api-reference.md` for the full public API surface.
